"""Mises à jour — on DIT ce qu'on sait, et depuis quand.

LA DISTINCTION QUI COMPTE : des données LOCALES (le cache d'apt, qui peut
dater de trois semaines) ne sont pas une VÉRIFICATION à jour. Les
confondre ferait dire « système à jour » à une machine qui ne s'est pas
connectée depuis un mois.

ET ON NE LANCE RIEN. Pas de mise à niveau majeure, pas de suppression de
paquets, pas de redémarrage. On ouvre l'outil natif.
"""
from __future__ import annotations

import os
import time

from . import capacites, execution


def mecanisme() -> dict:
    g = capacites.gestionnaire_paquets()
    if not g["trouve"]:
        return {"trouve": False, "raison": g["raison"]}
    d = capacites.distribution()
    return {"trouve": True, "nom": g["nom"], "famille": g["famille"],
            "distribution": d.libelle(),
            #  On nomme la distribution EXACTE : « une famille Debian » ne
            #  suffit pas à choisir un dépôt ou un outil graphique.
            "note": f"Paquets gérés par « {g['nom']} » sur "
                    f"{d.libelle() or 'une distribution inconnue'}."}


def _age_cache_apt() -> dict:
    for chemin in ("/var/lib/apt/periodic/update-success-stamp",
                   "/var/cache/apt/pkgcache.bin",
                   "/var/lib/apt/lists"):
        try:
            horodatage = os.path.getmtime(chemin)
        except OSError:
            continue
        secondes = max(0, time.time() - horodatage)
        return {"trouve": True, "secondes": secondes, "source": chemin}
    return {"trouve": False,
            "raison": "Aucune trace de la dernière mise à jour de la liste "
                      "des paquets n'a été trouvée."}


def etat_local() -> dict:
    """Ce que le cache LOCAL sait — sans aucun accès réseau.

    Volontairement sans réseau : interroger les dépôts prend du temps,
    demande parfois des droits, et surtout ce n'est pas à une application
    de bureau de le décider toute seule au démarrage.
    """
    g = capacites.gestionnaire_paquets()
    if not g["trouve"]:
        return {"trouve": False, "raison": g["raison"]}
    if g["nom"] == "apt":
        age = _age_cache_apt()
        if not execution.outil_present("apt-get"):
            return {"trouve": False,
                    "raison": "apt-get est absent : le nombre de mises à "
                              "jour en attente ne peut pas être calculé."}
        #  --just-print n'installe RIEN : il simule et rend la liste.
        r = execution.lancer(
            ["apt-get", "--just-print", "upgrade"], delai=25.0,
            env_sup={"DEBIAN_FRONTEND": "noninteractive", "LC_ALL": "C"})
        if not r.ok:
            return {"trouve": False, "raison": r.erreur, "age": age}
        paquets = [l.split()[1] for l in r.lignes()
                   if l.startswith("Inst ") and len(l.split()) > 1]
        return {"trouve": True, "nombre": len(paquets),
                "paquets": paquets[:200], "age": age,
                "verification": "locale"}
    return {"trouve": False,
            "raison": f"LEXOS PRO ne sait pas encore compter les mises à "
                      f"jour en attente avec « {g['nom']} ». Utilisez "
                      f"l'outil natif ci-dessous.",
            "age": {"trouve": False}}


def age_lisible(secondes: float | None) -> str:
    if secondes is None:
        return "Indisponible"
    j = int(secondes // 86400)
    if j >= 1:
        return f"il y a {j} jour{'s' if j > 1 else ''}"
    h = int(secondes // 3600)
    if h >= 1:
        return f"il y a {h} h"
    return "il y a moins d'une heure"


OUTILS_NATIFS = ("gnome-software", "plasma-discover", "mintupdate",
                 "update-manager", "pamac-manager")


def ouvrir_outil_natif() -> execution.Resultat:
    for outil in OUTILS_NATIFS:
        if execution.outil_present(outil):
            return execution.lancer_detache([outil])
    return execution.Resultat(
        False, erreur="Aucun outil graphique de mise à jour n'a été trouvé "
                      "(update-manager, gnome-software, plasma-discover…).")
