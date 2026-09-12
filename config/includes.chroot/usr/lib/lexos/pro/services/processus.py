"""Les processus, lus dans /proc — et rien de plus.

CE QU'ON S'INTERDIT : tuer automatiquement quoi que ce soit, toucher à un
processus qui n'appartient pas à l'utilisateur, envoyer SIGKILL sans
détour. La seule action possible est un SIGTERM — la demande polie d'arrêt
— sur un processus de l'utilisateur, après confirmation à l'écran.

Le pourcentage processeur d'un processus se calcule comme celui de la
machine : par différence entre deux lectures. Un seul relevé ne donnerait
que la moyenne depuis le lancement du processus, ce qui n'est pas ce que
l'on croit lire dans un moniteur.
"""
from __future__ import annotations

import os
import signal
from dataclasses import dataclass

from . import execution

_HORLOGE = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
_PAGE = os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096


@dataclass
class Processus:
    pid: int
    nom: str
    utilisateur_uid: int
    a_nous: bool
    memoire: int = 0
    cpu: float | None = None
    commande: str = ""
    etat: str = ""


class Moniteur:
    """Garde les compteurs précédents pour calculer un vrai pourcentage."""

    def __init__(self):
        self._cpu_precedent = {}
        self._total_precedent = None

    @staticmethod
    def _total_jiffies():
        r = execution.lire_fichier("/proc/stat")
        if not r.ok:
            return None
        for ligne in r.sortie.splitlines():
            if ligne.startswith("cpu "):
                try:
                    return sum(int(x) for x in ligne.split()[1:])
                except ValueError:
                    return None
        return None

    def liste(self) -> list:
        total = self._total_jiffies()
        d_total = None
        if total is not None and self._total_precedent is not None:
            d_total = total - self._total_precedent
        self._total_precedent = total

        nous = os.getuid()
        sortie = []
        nouveaux = {}
        try:
            entrees = os.listdir("/proc")
        except OSError:
            return []
        for e in entrees:
            if not e.isdigit():
                continue
            pid = int(e)
            base = f"/proc/{pid}"
            try:
                uid = os.stat(base).st_uid
            except OSError:
                continue        # le processus est mort entre-temps : normal
            r = execution.lire_fichier(f"{base}/stat", limite=8192)
            if not r.ok:
                continue
            brut = r.sortie
            #  Le nom est entre parenthèses et PEUT CONTENIR DES ESPACES et
            #  des parenthèses. On découpe donc sur la DERNIÈRE « ) », pas
            #  sur les espaces — une erreur classique qui décale tous les
            #  champs suivants pour un processus nommé « (foo bar) ».
            ouvrante = brut.find("(")
            fermante = brut.rfind(")")
            if ouvrante < 0 or fermante < ouvrante:
                continue
            nom = brut[ouvrante + 1:fermante]
            reste = brut[fermante + 2:].split()
            if len(reste) < 22:
                continue
            etat = reste[0]
            try:
                utime, stime = int(reste[11]), int(reste[12])
                rss_pages = int(reste[21])
            except (ValueError, IndexError):
                continue
            jiffies = utime + stime
            nouveaux[pid] = jiffies
            cpu = None
            if d_total and d_total > 0 and pid in self._cpu_precedent:
                delta = jiffies - self._cpu_precedent[pid]
                cpu = max(0.0, min(100.0, delta / d_total * 100.0))
            cmd = ""
            rc = execution.lire_fichier(f"{base}/cmdline", limite=4096)
            if rc.ok:
                cmd = rc.sortie.replace("\x00", " ").strip()
            sortie.append(Processus(
                pid=pid, nom=nom, utilisateur_uid=uid, a_nous=(uid == nous),
                memoire=rss_pages * _PAGE, cpu=cpu, commande=cmd or nom,
                etat=etat))
        self._cpu_precedent = nouveaux
        return sortie

    @property
    def premier_passage(self) -> bool:
        return not self._cpu_precedent


def demander_arret(pid: int) -> execution.Resultat:
    """SIGTERM — une DEMANDE d'arrêt, que le processus peut refuser.

    Jamais SIGKILL : un programme tué net ne sauvegarde rien. Et jamais sur
    un processus qui n'est pas à nous : on vérifie le propriétaire ici, en
    plus de la confirmation demandée à l'écran, parce qu'une garde dans
    l'interface seule se contourne par accident au premier remaniement.
    """
    try:
        uid = os.stat(f"/proc/{pid}").st_uid
    except FileNotFoundError:
        return execution.Resultat(
            False, erreur=f"Le processus {pid} n'existe plus.")
    except OSError as e:
        return execution.Resultat(
            False, erreur=f"Processus {pid} illisible : {e.strerror or e}")
    if uid != os.getuid():
        return execution.Resultat(
            False, erreur=f"Le processus {pid} appartient à un autre "
                          f"utilisateur (uid {uid}). LEXOS PRO ne demande "
                          f"l'arrêt que de vos propres processus.")
    if pid == os.getpid():
        return execution.Resultat(
            False, erreur="Ce processus est LEXOS PRO lui-même.")
    if pid == 1:
        return execution.Resultat(
            False, erreur="Le processus 1 est l'init du système.")
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return execution.Resultat(
            False, erreur=f"Le processus {pid} n'existe plus.")
    except PermissionError:
        return execution.Resultat(
            False, erreur=f"Permission refusée pour arrêter le processus {pid}.")
    except OSError as e:
        return execution.Resultat(False, erreur=str(e))
    return execution.Resultat(
        True, sortie=f"Demande d'arrêt (SIGTERM) envoyée au processus {pid}.")


def temperatures() -> dict:
    """Les capteurs thermiques, UNIQUEMENT s'ils existent.

    Beaucoup de machines n'en exposent aucun, et beaucoup de machines
    virtuelles non plus. Afficher « 42 °C » par défaut serait inventer.
    """
    base = "/sys/class/thermal"
    try:
        entrees = sorted(e for e in os.listdir(base)
                         if e.startswith("thermal_zone"))
    except OSError as e:
        return {"trouve": False,
                "raison": f"{base} illisible ({e.strerror or e}) : aucun "
                          f"capteur thermique accessible."}
    liste = []
    for e in entrees:
        rt = execution.lire_fichier(f"{base}/{e}/temp")
        if not rt.ok:
            continue
        try:
            milli = int(rt.sortie.strip())
        except ValueError:
            continue
        rn = execution.lire_fichier(f"{base}/{e}/type")
        liste.append({"nom": rn.sortie.strip() if rn.ok else e,
                      "celsius": milli / 1000.0})
    if not liste:
        return {"trouve": False,
                "raison": "Aucun capteur thermique exposé par le noyau sur "
                          "cette machine."}
    return {"trouve": True, "capteurs": liste}
