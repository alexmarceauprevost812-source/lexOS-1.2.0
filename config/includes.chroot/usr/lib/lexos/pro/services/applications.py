"""Les lanceurs .desktop installés — recherche et lancement.

CE N'EST PAS UN GESTIONNAIRE D'INSTALLATION, et la consigne le demande
explicitement : pour installer ou retirer un logiciel, on ouvre la
logithèque native. Ce module lit des fichiers .desktop et lance ce qui
existe déjà.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from . import capacites, execution


@dataclass
class Lanceur:
    nom: str
    commande: str
    fichier: str
    commentaire: str = ""
    categories: str = ""
    icone: str = ""
    terminal: bool = False


def _dossiers() -> list:
    base = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    dossiers = [Path(d) / "applications" for d in base.split(":") if d]
    maison = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    dossiers.insert(0, Path(maison) / "applications")
    return dossiers


def _lire_desktop(chemin: Path) -> Lanceur | None:
    """Lit la section [Desktop Entry] et rien d'autre.

    On IGNORE les entrées NoDisplay et Hidden : les afficher remplirait la
    liste de morceaux internes que l'utilisateur ne peut pas lancer utilement.
    """
    try:
        texte = chemin.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    dans_section = False
    champs = {}
    for ligne in texte.splitlines():
        ligne = ligne.strip()
        if ligne.startswith("["):
            dans_section = ligne == "[Desktop Entry]"
            continue
        if not dans_section or "=" not in ligne or ligne.startswith("#"):
            continue
        cle, _, val = ligne.partition("=")
        champs.setdefault(cle.strip(), val.strip())
    if champs.get("Type") not in (None, "Application"):
        return None
    if champs.get("NoDisplay", "").lower() == "true":
        return None
    if champs.get("Hidden", "").lower() == "true":
        return None
    nom = champs.get("Name[fr]") or champs.get("Name")
    commande = champs.get("Exec", "")
    if not nom or not commande:
        return None
    return Lanceur(
        nom=nom, commande=commande, fichier=str(chemin),
        commentaire=champs.get("Comment[fr]") or champs.get("Comment", ""),
        categories=champs.get("Categories", ""),
        icone=champs.get("Icon", ""),
        terminal=champs.get("Terminal", "").lower() == "true")


def lanceurs() -> list:
    vus, sortie = set(), []
    for dossier in _dossiers():
        try:
            fichiers = sorted(dossier.glob("*.desktop"))
        except OSError:
            continue
        for f in fichiers:
            if f.name in vus:
                continue       # le dossier maison gagne sur /usr/share
            vus.add(f.name)
            l = _lire_desktop(f)
            if l:
                sortie.append(l)
    sortie.sort(key=lambda x: x.nom.lower())
    return sortie


def lancer(l: Lanceur) -> execution.Resultat:
    """Lance un .desktop par l'outil prévu pour ça.

    gio launch / gtk-launch comprennent les champs %U, %f, les actions et
    le champ Terminal=true. Découper « Exec » à la main les casserait — et
    ce serait aussi la porte ouverte à une réinterprétation shell.
    """
    chemin = l.fichier
    if execution.outil_present("gio"):
        return execution.lancer_detache(["gio", "launch", chemin])
    if execution.outil_present("gtk-launch"):
        return execution.lancer_detache(
            ["gtk-launch", os.path.basename(chemin)])
    return execution.Resultat(
        False, erreur="Ni « gio » ni « gtk-launch » n'est installé : LEXOS "
                      "PRO ne peut pas lancer un fichier .desktop sans "
                      "réinterpréter sa ligne Exec, ce qu'il s'interdit.")


def ouvrir_logitheque() -> execution.Resultat:
    outil = capacites.premier_present(capacites.LOGITHEQUES)
    if outil:
        return execution.lancer_detache([outil])
    return execution.Resultat(
        False, erreur="Aucune logithèque graphique n'a été trouvée "
                      "(gnome-software, plasma-discover, mintinstall…). "
                      "Installez-en une, ou utilisez le gestionnaire de "
                      "paquets en ligne de commande.")
