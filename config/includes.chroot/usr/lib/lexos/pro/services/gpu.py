"""Carte graphique, pilote et écrans — constat seulement.

CE MODULE N'INSTALLE RIEN. Pas de pilote, pas de modification de GRUB, du
Secure Boot ou des modules du noyau. La consigne l'interdit explicitement,
et l'expérience de ce dépôt le confirme : un écran noir sur une RTX 50 se
répare en connaissance de cause, pas par une application qui devine.

nvidia-smi mérite son propre délai : sur un pilote à moitié chargé il peut
rester bloqué de longues secondes. Sans délai maximal, la page se figerait.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

from . import capacites, execution

#  nvidia-smi peut être lent quand le module vient d'être chargé.
DELAI_NVIDIA = 6.0


@dataclass
class Carte:
    description: str
    fournisseur: str = ""
    pilote: str = ""
    identifiant: str = ""


def _pilote_du_peripherique(adresse: str) -> str:
    """Le pilote réellement lié à la carte, lu dans /sys — pas deviné."""
    lien = f"/sys/bus/pci/devices/0000:{adresse}/driver"
    try:
        return os.path.basename(os.path.realpath(lien)) if os.path.exists(lien) else ""
    except OSError:
        return ""


def cartes() -> dict:
    """Les contrôleurs graphiques vus par lspci."""
    if not execution.outil_present("lspci"):
        return {"trouve": False,
                "raison": "L'outil « lspci » n'est pas installé "
                          "(paquet pciutils) : les cartes graphiques ne "
                          "peuvent pas être énumérées."}
    r = execution.lancer(["lspci", "-nn"])
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    liste = []
    for ligne in r.lignes():
        bas = ligne.lower()
        if "vga compatible controller" not in bas and "3d controller" not in bas \
                and "display controller" not in bas:
            continue
        adresse = ligne.split()[0]
        description = ligne.partition(":")[2]
        description = description.partition(":")[2].strip() or ligne
        fournisseur = ""
        for nom in ("NVIDIA", "AMD", "Intel", "ATI"):
            if nom.lower() in bas:
                fournisseur = nom
                break
        liste.append(Carte(description=description, fournisseur=fournisseur,
                           pilote=_pilote_du_peripherique(adresse) or
                           "aucun pilote lié",
                           identifiant=adresse))
    if not liste:
        return {"trouve": False,
                "raison": "lspci n'a signalé aucun contrôleur graphique."}
    return {"trouve": True, "cartes": liste}


def nvidia() -> dict:
    """nvidia-smi, avec délai maximal et gestion de TOUS ses refus.

    Trois cas distincts, et les confondre serait trompeur :
      · l'outil n'est pas installé (pas de pilote propriétaire) ;
      · l'outil est là mais le module n'est pas chargé (il le dit lui-même,
        et c'est le symptôme de l'écran noir) ;
      · l'outil répond : on lit ses champs.
    """
    if not execution.outil_present("nvidia-smi"):
        return {"trouve": False,
                "raison": "nvidia-smi n'est pas installé : soit la machine "
                          "n'a pas de carte NVIDIA, soit le pilote "
                          "propriétaire n'est pas en place."}
    champs = ("name", "driver_version", "memory.total", "memory.used",
              "temperature.gpu", "utilization.gpu")
    r = execution.lancer(
        ["nvidia-smi", f"--query-gpu={','.join(champs)}",
         "--format=csv,noheader,nounits"], delai=DELAI_NVIDIA)
    if not r.ok:
        return {"trouve": False,
                "raison": f"nvidia-smi a répondu par une erreur : {r.erreur}"}
    cartes_nv = []
    for ligne in r.lignes():
        valeurs = [v.strip() for v in ligne.split(",")]
        if len(valeurs) < len(champs):
            continue
        cartes_nv.append(dict(zip(champs, valeurs)))
    if not cartes_nv:
        return {"trouve": False,
                "raison": "nvidia-smi n'a rendu aucune ligne exploitable."}
    return {"trouve": True, "cartes": cartes_nv}


def ecrans() -> dict:
    """Les écrans détectables. Wayland et X11 ne répondent pas pareil.

    Sous Wayland, xrandr ne voit que ce que XWayland expose — souvent un
    seul écran virtuel. On le DIT au lieu de présenter sa réponse comme la
    vérité du matériel.
    """
    s = capacites.session()
    if s["type"] == "x11" and execution.outil_present("xrandr"):
        r = execution.lancer(["xrandr", "--query"])
        if r.ok:
            liste = []
            for ligne in r.lignes():
                if " connected" in ligne:
                    liste.append(ligne.split(" connected")[0].strip()
                                 + " — " + ligne.split("connected", 1)[1].strip())
            if liste:
                return {"trouve": True, "ecrans": liste, "source": "xrandr (X11)"}
            return {"trouve": False,
                    "raison": "xrandr n'a signalé aucun écran connecté."}
        return {"trouve": False, "raison": r.erreur}

    #  Repli universel : le noyau expose l'état des connecteurs DRM.
    base = "/sys/class/drm"
    try:
        entrees = sorted(os.listdir(base))
    except OSError as e:
        return {"trouve": False,
                "raison": f"{base} illisible ({e.strerror or e}) : les "
                          f"écrans ne peuvent pas être énumérés."}
    liste = []
    for e in entrees:
        chemin = f"{base}/{e}/status"
        r = execution.lire_fichier(chemin)
        if r.ok and r.sortie.strip() == "connected":
            liste.append(e.split("-", 1)[-1] if "-" in e else e)
    if not liste:
        return {"trouve": False,
                "raison": "Aucun connecteur DRM n'est marqué « connected »."}
    note = ""
    if s["type"] == "wayland":
        note = ("Session Wayland : les réglages de résolution et de mise à "
                "l'échelle appartiennent au bureau, pas à cette application.")
    return {"trouve": True, "ecrans": liste, "source": "/sys/class/drm (noyau)",
            "note": note}


def rendu_opengl() -> dict:
    """Le rendu est-il matériel ou logiciel ?

    llvmpipe / softpipe / swrast sont du rendu LOGICIEL : la carte n'est pas
    utilisée. C'est la distinction que lexos-crt fait déjà dans ce dépôt
    avant de lancer un compositeur, et elle vaut la peine d'être affichée.
    """
    if not execution.outil_present("glxinfo"):
        return {"trouve": False,
                "raison": "glxinfo n'est pas installé (paquet mesa-utils) : "
                          "le type de rendu ne peut pas être vérifié."}
    if not capacites.session()["graphique"]:
        return {"trouve": False,
                "raison": "Aucune session graphique : glxinfo n'a pas "
                          "d'affichage où se connecter."}
    r = execution.lancer(["glxinfo", "-B"], delai=10.0)
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    moteur = ""
    for ligne in r.lignes():
        if "OpenGL renderer string" in ligne:
            moteur = ligne.partition(":")[2].strip()
            break
    if not moteur:
        return {"trouve": False,
                "raison": "glxinfo n'a pas rendu de « OpenGL renderer string »."}
    logiciel = any(m in moteur.lower()
                   for m in ("llvmpipe", "softpipe", "swrast"))
    return {"trouve": True, "moteur": moteur, "materiel": not logiciel}
