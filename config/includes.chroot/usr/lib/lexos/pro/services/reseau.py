"""Interfaces, adresses et connectivité — en lecture seule.

AUCUNE ANALYSE INTRUSIVE. Pas de balayage de ports sur d'autres machines,
pas de capture. On lit /sys et, si NetworkManager est là, on lui pose des
questions sur SES propres connexions. Les secrets Wi-Fi ne sont jamais lus
ni stockés : la page ouvre les réglages natifs pour ça.
"""
from __future__ import annotations

import os
import socket
from dataclasses import dataclass, field

from . import capacites, execution


@dataclass
class Interface:
    nom: str
    etat: str = "inconnu"
    type_: str = ""
    mac: str = ""
    adresses: list = field(default_factory=list)
    boucle: bool = False


def _lire(chemin: str, defaut: str = "") -> str:
    r = execution.lire_fichier(chemin)
    return r.sortie.strip() if r.ok else defaut


def _type_interface(nom: str) -> str:
    if nom == "lo":
        return "boucle locale"
    if os.path.isdir(f"/sys/class/net/{nom}/wireless") or nom.startswith("wl"):
        return "sans fil"
    if os.path.isdir(f"/sys/class/net/{nom}/bridge"):
        return "pont"
    if nom.startswith(("en", "eth")):
        return "filaire"
    if nom.startswith(("docker", "veth", "br-", "virbr")):
        return "virtuelle"
    if nom.startswith(("tun", "tap", "wg")):
        return "tunnel"
    return "autre"


def _adresses_par_interface() -> dict:
    """socket.getaddrinfo ne dit pas à quelle interface appartient une
    adresse. On passe donc par `ip -o addr`, et à défaut on n'invente rien."""
    par_nom = {}
    if not execution.outil_present("ip"):
        return par_nom
    r = execution.lancer(["ip", "-o", "addr", "show"])
    if not r.ok:
        return par_nom
    for ligne in r.lignes():
        champs = ligne.split()
        if len(champs) < 4:
            continue
        nom = champs[1]
        famille = champs[2]
        adresse = champs[3]
        if famille in ("inet", "inet6"):
            par_nom.setdefault(nom, []).append(
                {"famille": "IPv4" if famille == "inet" else "IPv6",
                 "adresse": adresse})
    return par_nom


def interfaces() -> list:
    base = "/sys/class/net"
    try:
        noms = sorted(os.listdir(base))
    except OSError:
        return []
    adresses = _adresses_par_interface()
    sortie = []
    for nom in noms:
        i = Interface(nom=nom)
        i.etat = _lire(f"{base}/{nom}/operstate", "inconnu")
        i.mac = _lire(f"{base}/{nom}/address")
        i.type_ = _type_interface(nom)
        i.boucle = nom == "lo"
        i.adresses = adresses.get(nom, [])
        sortie.append(i)
    sortie.sort(key=lambda x: (x.boucle, x.type_ == "virtuelle", x.nom))
    return sortie


def passerelle() -> dict:
    """La route par défaut, si on peut la lire."""
    if execution.outil_present("ip"):
        r = execution.lancer(["ip", "route", "show", "default"])
        if r.ok and r.sortie:
            champs = r.sortie.split()
            if "via" in champs:
                return {"trouve": True,
                        "adresse": champs[champs.index("via") + 1],
                        "interface": champs[champs.index("dev") + 1]
                        if "dev" in champs else ""}
        if r.ok:
            return {"trouve": False,
                    "raison": "Aucune route par défaut : cette machine n'a "
                              "pas de chemin vers l'extérieur."}
        return {"trouve": False, "raison": r.erreur}
    return {"trouve": False,
            "raison": "L'outil « ip » n'est pas installé : la route par "
                      "défaut ne peut pas être lue."}


def connectivite(*, delai: float = 2.0) -> dict:
    """Y a-t-il un chemin vers l'extérieur ?

    On ouvre une connexion TCP vers un résolveur public et on la ferme
    aussitôt. Ce n'est PAS une analyse : une seule adresse, un seul port,
    aucune donnée envoyée. Et on distingue les trois cas — joignable, DNS
    qui répond mais pas de route, rien du tout — parce que « pas
    d'internet » ne dit pas où est la panne.
    """
    gest = capacites.reseau_gestionnaire()
    if gest["present"] and gest["outil"] == "nmcli":
        r = execution.lancer(["nmcli", "-t", "-f", "STATE", "general"],
                             delai=delai + 2)
        if r.ok and r.sortie:
            etat = r.sortie.strip().splitlines()[0]
            return {"mesure": True, "source": "NetworkManager", "etat": etat,
                    "connecte": etat.startswith("connect")}
    try:
        s = socket.create_connection(("9.9.9.9", 53), timeout=delai)
        s.close()
        return {"mesure": True, "source": "connexion TCP 9.9.9.9:53",
                "etat": "connecté", "connecte": True}
    except socket.timeout:
        return {"mesure": True, "source": "connexion TCP 9.9.9.9:53",
                "etat": f"aucune réponse en {delai:g} s", "connecte": False}
    except OSError as e:
        return {"mesure": True, "source": "connexion TCP 9.9.9.9:53",
                "etat": f"injoignable ({e.strerror or e})", "connecte": False}


def connexion_active() -> dict:
    """La connexion NetworkManager en cours, si NM est là."""
    gest = capacites.reseau_gestionnaire()
    if not (gest["present"] and gest["outil"] == "nmcli"):
        return {"trouve": False,
                "raison": gest.get("raison") or
                "NetworkManager n'est pas disponible sur ce système."}
    r = execution.lancer(
        ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show",
         "--active"])
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    liste = []
    for ligne in r.lignes():
        parts = ligne.split(":")
        if len(parts) >= 3:
            liste.append({"nom": parts[0], "type": parts[1],
                          "peripherique": parts[2]})
    if not liste:
        return {"trouve": False,
                "raison": "NetworkManager ne signale aucune connexion active."}
    return {"trouve": True, "connexions": liste}
