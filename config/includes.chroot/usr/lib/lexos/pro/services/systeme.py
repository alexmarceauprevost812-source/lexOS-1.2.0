"""Processeur, mémoire, noyau, machine — mesurés, jamais supposés.

Toutes les mesures viennent de /proc, qui est lisible par tout le monde et
ne coûte pas un processus. Quand un fichier manque, la fonction rend None
ET un motif : l'appelant affiche « Indisponible — <motif> ».

LE PIÈGE DU POURCENTAGE PROCESSEUR. /proc/stat ne donne pas un
pourcentage : il donne des COMPTEURS cumulés depuis le démarrage. Le
pourcentage est la DIFFÉRENCE entre deux lectures. Une première lecture
seule ne peut donc rien dire — et c'est pour ça que MesureCPU rend None au
premier appel au lieu d'un chiffre qui serait la moyenne depuis l'allumage
de la machine, c'est-à-dire un chiffre faux qu'on croirait vrai.
"""
from __future__ import annotations

import os
import platform
import socket
from dataclasses import dataclass

from . import capacites, execution


@dataclass
class Mesure:
    """Une valeur, ou l'absence de valeur AVEC sa raison."""
    valeur: float | None = None
    raison: str = ""
    detail: str = ""

    @property
    def disponible(self) -> bool:
        return self.valeur is not None


class MesureCPU:
    """Occupation du processeur entre deux appels successifs.

    Garde l'état précédent. Le premier appel rend une Mesure indisponible :
    il n'y a rien à comparer, et le dire est plus honnête que de rendre la
    moyenne depuis le démarrage.
    """

    def __init__(self):
        self._precedent = None

    @staticmethod
    def _lire():
        r = execution.lire_fichier("/proc/stat")
        if not r.ok:
            return None, r.erreur
        for ligne in r.sortie.splitlines():
            if ligne.startswith("cpu "):
                champs = ligne.split()[1:]
                try:
                    nombres = [int(x) for x in champs]
                except ValueError:
                    return None, "/proc/stat : ligne « cpu » illisible."
                if len(nombres) < 4:
                    return None, "/proc/stat : ligne « cpu » trop courte."
                total = sum(nombres)
                #  idle + iowait : le temps où le processeur n'a rien fait.
                inactif = nombres[3] + (nombres[4] if len(nombres) > 4 else 0)
                return (total, inactif), ""
        return None, "/proc/stat ne contient pas de ligne « cpu »."

    def pourcent(self) -> Mesure:
        actuel, motif = self._lire()
        if actuel is None:
            return Mesure(raison=motif)
        if self._precedent is None:
            self._precedent = actuel
            return Mesure(raison="Première mesure — il faut deux lectures "
                                 "de /proc/stat pour calculer un pourcentage.")
        d_total = actuel[0] - self._precedent[0]
        d_inactif = actuel[1] - self._precedent[1]
        self._precedent = actuel
        if d_total <= 0:
            return Mesure(raison="Aucun temps écoulé entre deux lectures.")
        occupe = (d_total - d_inactif) / d_total * 100.0
        return Mesure(valeur=max(0.0, min(100.0, occupe)))


def memoire() -> dict:
    """/proc/meminfo. On utilise MemAvailable, pas MemFree.

    MemFree ignore le cache, que le noyau rend dès qu'on en a besoin :
    s'en servir afficherait une machine « pleine » alors qu'elle va très
    bien. MemAvailable est l'estimation que le noyau lui-même publie.
    """
    r = execution.lire_fichier("/proc/meminfo")
    if not r.ok:
        return {"disponible": False, "raison": r.erreur}
    champs = {}
    for ligne in r.sortie.splitlines():
        cle, _, reste = ligne.partition(":")
        morceaux = reste.split()
        if morceaux:
            try:
                champs[cle.strip()] = int(morceaux[0]) * 1024
            except ValueError:
                continue
    total = champs.get("MemTotal")
    dispo = champs.get("MemAvailable")
    if total is None:
        return {"disponible": False,
                "raison": "/proc/meminfo ne contient pas MemTotal."}
    if dispo is None:
        return {"disponible": False,
                "raison": "/proc/meminfo ne contient pas MemAvailable "
                          "(noyau antérieur à 3.14)."}
    utilise = max(0, total - dispo)
    return {"disponible": True, "total": total, "libre": dispo,
            "utilise": utilise,
            "pourcent": (utilise / total * 100.0) if total else 0.0,
            "echange_total": champs.get("SwapTotal", 0),
            "echange_libre": champs.get("SwapFree", 0)}


def demarrage() -> Mesure:
    """Temps écoulé depuis le démarrage, en secondes."""
    r = execution.lire_fichier("/proc/uptime")
    if not r.ok:
        return Mesure(raison=r.erreur)
    try:
        return Mesure(valeur=float(r.sortie.split()[0]))
    except (ValueError, IndexError):
        return Mesure(raison="/proc/uptime est illisible.")


def duree_lisible(secondes: float | None) -> str:
    if secondes is None:
        return "Indisponible"
    s = int(secondes)
    j, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m = s // 60
    if j:
        return f"{j} j {h} h {m} min"
    if h:
        return f"{h} h {m} min"
    return f"{m} min"


def charge() -> Mesure:
    """La charge moyenne 1/5/15 minutes — une notion différente du
    pourcentage : c'est un nombre de tâches, pas une fraction."""
    try:
        un, cinq, quinze = os.getloadavg()
    except OSError as e:
        return Mesure(raison=f"Charge moyenne indisponible : {e}")
    return Mesure(valeur=un, detail=f"{un:.2f} / {cinq:.2f} / {quinze:.2f}")


def _modele_processeur() -> tuple:
    r = execution.lire_fichier("/proc/cpuinfo")
    if not r.ok:
        return "", r.erreur
    for ligne in r.sortie.splitlines():
        for cle in ("model name", "Model", "Processor"):
            if ligne.startswith(cle):
                return ligne.partition(":")[2].strip(), ""
    return "", "/proc/cpuinfo ne nomme pas le modèle de processeur."


def coeurs() -> dict:
    logiques = os.cpu_count() or 0
    physiques = None
    r = execution.lire_fichier("/proc/cpuinfo")
    if r.ok:
        paires = set()
        phys = cid = None
        for ligne in r.sortie.splitlines():
            if ligne.startswith("physical id"):
                phys = ligne.partition(":")[2].strip()
            elif ligne.startswith("core id"):
                cid = ligne.partition(":")[2].strip()
                if phys is not None:
                    paires.add((phys, cid))
        if paires:
            physiques = len(paires)
    return {"logiques": logiques, "physiques": physiques}


def infos() -> dict:
    """Tout ce que la page Système affiche. Chaque champ absent porte un
    motif plutôt qu'une chaîne vide."""
    d = capacites.distribution()
    modele, motif_modele = _modele_processeur()
    c = coeurs()
    try:
        machine = socket.gethostname()
    except OSError:
        machine = ""
    return {
        "machine": machine or "Indisponible",
        "distribution": d.libelle(),
        "distribution_id": d.id or "inconnu",
        "distribution_version": d.version or "inconnue",
        "familles": ", ".join(d.familles) or "aucune déclarée",
        "lexos": capacites.est_lexos(),
        "noyau": platform.release() or "Indisponible",
        "noyau_complet": platform.version() or "",
        "architecture": platform.machine() or "Indisponible",
        "processeur": modele or f"Indisponible — {motif_modele}",
        "coeurs_logiques": c["logiques"] or "Indisponible",
        "coeurs_physiques": c["physiques"] if c["physiques"] else "Indisponible",
        "session": capacites.session(),
        "python": platform.python_version(),
        "utilisateur": os.environ.get("USER") or os.environ.get("LOGNAME") or "",
        "racine": os.geteuid() == 0,
    }


def octets_lisibles(n) -> str:
    """Unités décimales (Go), celles qu'affichent les fabricants et les
    autres outils du bureau. Mélanger Gio et Go dans la même fenêtre est
    une source de confusion sans bénéfice."""
    if n is None:
        return "Indisponible"
    try:
        n = float(n)
    except (TypeError, ValueError):
        return "Indisponible"
    for unite, seuil in (("To", 1e12), ("Go", 1e9), ("Mo", 1e6), ("ko", 1e3)):
        if abs(n) >= seuil:
            return f"{n / seuil:.1f} {unite}".replace(".", ",")
    return f"{int(n)} o"
