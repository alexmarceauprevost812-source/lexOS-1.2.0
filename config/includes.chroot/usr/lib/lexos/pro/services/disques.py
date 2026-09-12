"""Volumes montés — lus dans /proc/mounts, mesurés avec statvfs.

AUCUNE ÉCRITURE ICI. Pas de formatage, pas de partitionnement, pas de
montage privilégié : la consigne l'interdit, et ce module n'a même pas de
fonction pour le faire. Un module sans le verbe ne peut pas commettre
l'action par accident.

Le filtre des systèmes de fichiers virtuels n'est pas cosmétique : sans
lui, la page afficherait quarante lignes de cgroup et de tmpfs, et le
disque réel serait noyé au milieu.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

from . import execution

#  Systèmes de fichiers qui ne représentent pas un espace de stockage.
_VIRTUELS = {
    "proc", "sysfs", "devtmpfs", "devpts", "cgroup", "cgroup2", "pstore",
    "bpf", "securityfs", "debugfs", "tracefs", "configfs", "fusectl",
    "hugetlbfs", "mqueue", "autofs", "binfmt_misc", "efivarfs", "ramfs",
    "rpc_pipefs", "nsfs", "squashfs", "overlay", "fuse.portal",
    "fuse.gvfsd-fuse", "tmpfs",
}


@dataclass
class Volume:
    peripherique: str
    point: str
    systeme: str
    options: str = ""
    total: int = 0
    libre: int = 0
    utilise: int = 0
    pourcent: float = 0.0
    mesure: bool = False
    raison: str = ""

    @property
    def lecture_seule(self) -> bool:
        return "ro" in self.options.split(",")


def _demonter_octal(chemin: str) -> str:
    """/proc/mounts encode l'espace en \\040. Sans ce décodage, un dossier
    « Mes documents » s'afficherait « Mes\\040documents » et ne s'ouvrirait
    pas."""
    resultat = []
    i = 0
    while i < len(chemin):
        if chemin[i] == "\\" and i + 3 < len(chemin) and chemin[i + 1:i + 4].isdigit():
            try:
                resultat.append(chr(int(chemin[i + 1:i + 4], 8)))
                i += 4
                continue
            except ValueError:
                pass
        resultat.append(chemin[i])
        i += 1
    return "".join(resultat)


def volumes(*, tout: bool = False) -> list:
    """Les volumes montés. `tout=True` inclut les systèmes virtuels."""
    r = execution.lire_fichier("/proc/mounts")
    if not r.ok:
        return []
    vus = set()
    sortie = []
    for ligne in r.sortie.splitlines():
        champs = ligne.split()
        if len(champs) < 4:
            continue
        peripherique, point, systeme, options = (
            _demonter_octal(champs[0]), _demonter_octal(champs[1]),
            champs[2], champs[3])
        if not tout and systeme in _VIRTUELS:
            continue
        #  Un même périphérique monté deux fois (bind) n'apparaît qu'une.
        cle = (peripherique, point)
        if cle in vus:
            continue
        vus.add(cle)
        v = Volume(peripherique, point, systeme, options)
        try:
            st = os.statvfs(point)
        except (PermissionError, OSError) as e:
            v.raison = f"Taille non mesurable : {e.strerror or e}"
            sortie.append(v)
            continue
        taille = st.f_frsize or st.f_bsize
        v.total = st.f_blocks * taille
        #  f_bavail (dispo pour l'utilisateur) et non f_bfree (dispo pour
        #  root) : afficher f_bfree promettrait une place que l'utilisateur
        #  ne peut pas prendre — les 5 % réservés d'ext4.
        v.libre = st.f_bavail * taille
        v.utilise = max(0, v.total - st.f_bfree * taille)
        v.pourcent = (v.utilise / v.total * 100.0) if v.total else 0.0
        v.mesure = v.total > 0
        if not v.mesure:
            v.raison = "Volume de taille nulle (pseudo-système de fichiers)."
        sortie.append(v)
    sortie.sort(key=lambda x: (x.point != "/", x.point))
    return sortie


def volume_racine():
    for v in volumes():
        if v.point == "/":
            return v
    return None
