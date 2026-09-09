#!/usr/bin/env python3
# =============================================================================
#  telechargements.py — savoir qu'un téléchargement a commencé, et où il en est
# =============================================================================
#  ═══ POURQUOI SURVEILLER UN DOSSIER PLUTÔT QU'ÉCOUTER LE NAVIGATEUR ═══
#  Firefox et Chrome ne préviennent pas le système : il n'y a aucun signal à
#  écouter. La seule voie qui marche pour TOUS les programmes — navigateur,
#  gestionnaire de téléchargement, wget lancé à la main — est de regarder le
#  dossier Téléchargements : un fichier qui apparaît, un fichier qui grossit.
#
#  ═══ Gio.FileMonitor, ET PAS inotifywait ═══
#  Vérifié dans le dépôt : rien n'utilise inotify aujourd'hui, et
#  inotify-tools n'est dans aucune liste. python3-gi, lui, est déjà installé
#  sans condition (lexos-boost.list.chroot) et donne Gio.FileMonitor, qui fait
#  exactement ce travail. Pas de nouvelle dépendance.
#
#  ═══ CE PROGRAMME N'A AUCUNE INTERFACE, ET C'EST VOULU ═══
#  C'est la brique du dessous. Elle écrit une ligne JSON par événement sur la
#  sortie standard ; la pastille viendra la lire. Si cette brique n'est pas
#  fiable, le reste ne sert à rien — alors on la fait tourner seule d'abord.
#
#      {"ev":"debut",  "id":…, "nom":…, "total":…|null}
#      {"ev":"avance", "id":…, "recu":…, "total":…|null, "pourcent":…|null}
#      {"ev":"fini",   "id":…, "nom":…, "taille":…}
#      {"ev":"annule", "id":…, "nom":…}
#
#  ═══ LE PIÈGE DU POURCENTAGE — ET COMMENT ON SAIT VRAIMENT LA TAILLE ═══
#  Les navigateurs écrivent d'abord un fichier temporaire (.part, .crdownload).
#  On voit sa taille grossir, mais la taille FINALE n'est pas dans le nom, et
#  le serveur ne l'annonce pas toujours.
#
#  Il y a pourtant un cas où on la connaît, et il se MESURE : quand le
#  navigateur PRÉALLOUE le fichier. Le fichier a alors tout de suite sa taille
#  finale (st_size), mais les blocs réellement écrits sur le disque
#  (st_blocks × 512) sont bien moindres et montent au fil du téléchargement.
#  On distingue donc :
#
#    · st_size stable ET blocs qui montent  -> PRÉALLOUÉ. total = st_size,
#      avancement = blocs / total. Le pourcentage est réel.
#    · st_size qui monte                    -> taille finale INCONNUE. On
#      annonce les octets reçus, et « pourcent » vaut null.
#
#  ON N'INVENTE JAMAIS DE POURCENTAGE. Un anneau qui ment est pire qu'un
#  anneau qui tourne sans fin.
# =============================================================================
import json
import os
import sys
import time

from gi.repository import Gio, GLib

#  Les extensions que les navigateurs donnent à leur fichier en cours. Le
#  fichier final, lui, n'a pas de suffixe : c'est le renommage qui dit « fini ».
EN_COURS = (".part", ".crdownload", ".download", ".partial", ".opdownload")

#  Un fichier qui n'a pas bougé depuis ce délai est considéré abandonné.
#  Ni trop court (une pause réseau n'est pas un abandon), ni trop long
#  (une pastille qui reste après un « Annuler » est un bogue visible).
ABANDON_S = float(os.environ.get("LEXOS_DL_ABANDON", "20"))

#  Cadence d'échantillonnage. 250 ms suffit pour un anneau fluide et ne coûte
#  rien : on ne lit que des métadonnées, jamais le contenu.
PAS_MS = int(os.environ.get("LEXOS_DL_PAS_MS", "250"))


def dire(**kw):
    """Une ligne JSON par événement, vidée tout de suite.

    Sans le flush, la pastille ne verrait rien tant que le tampon n'est pas
    plein — c'est-à-dire jamais, pour un flux d'événements aussi petit.
    """
    sys.stdout.write(json.dumps(kw, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def dossier_telechargements():
    """Le dossier à surveiller, dans l'ordre de ce qui est fiable.

    Trois écritures, parce qu'aucune n'est garantie : la variable du banc,
    puis XDG (quand user-dirs est configuré), puis les deux noms usuels — le
    français des ISO fr_CA et l'anglais d'une session créée avant que les
    dossiers soient traduits.
    """
    seam = os.environ.get("LEXOS_DL_DIR")
    if seam:
        return seam
    d = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
    if d and os.path.isdir(d) and d != os.path.expanduser("~"):
        return d
    for nom in ("Téléchargements", "Downloads"):
        p = os.path.join(os.path.expanduser("~"), nom)
        if os.path.isdir(p):
            return p
    return None


class Suivi:
    """Ce qu'on sait d'un fichier en cours d'écriture."""

    __slots__ = ("chemin", "ident", "recu", "total", "prealloue",
                 "taille_vue", "stable", "vu_a", "annonce")

    def __init__(self, chemin, ident):
        self.chemin = chemin
        self.ident = ident
        self.recu = 0
        self.total = None
        self.prealloue = False
        self.taille_vue = None
        self.stable = 0
        self.vu_a = time.monotonic()
        self.annonce = False


def nom_visible(chemin):
    """Le nom sans le suffixe de travail — c'est celui que la personne attend."""
    base = os.path.basename(chemin)
    for suf in EN_COURS:
        if base.endswith(suf):
            return base[: -len(suf)]
    return base


class Veille:
    def __init__(self, dossier):
        self.dossier = dossier
        self.suivis = {}
        self.prochain_id = 1
        self.connus = set()

    # --- ce que le disque dit d'un fichier ---------------------------------
    def mesurer(self, chemin):
        try:
            st = os.stat(chemin)
        except OSError:
            return None
        #  st_blocks compte des blocs de 512 octets, TOUJOURS — c'est la
        #  définition POSIX, pas la taille de bloc du système de fichiers.
        return st.st_size, st.st_blocks * 512

    def demarrer(self, chemin):
        if chemin in self.suivis:
            return
        s = Suivi(chemin, self.prochain_id)
        self.prochain_id += 1
        self.suivis[chemin] = s
        m = self.mesurer(chemin)
        if m:
            s.taille_vue = m[0]
        dire(ev="debut", id=s.ident, nom=nom_visible(chemin), total=None)
        s.annonce = True

    def avancer(self, s):
        m = self.mesurer(s.chemin)
        if m is None:
            return
        taille, ecrits = m

        #  ═══ LA DÉTECTION DU PRÉALLOUÉ ═══
        #  La taille ne bouge plus alors que les blocs montent : le fichier a
        #  été réservé à sa taille finale. Il faut DEUX échantillons stables
        #  avant de le croire — sinon un fichier simplement lent passerait
        #  pour préalloué à la première mesure, et on afficherait un
        #  pourcentage faux dès la première seconde.
        if s.taille_vue is not None and taille == s.taille_vue:
            s.stable += 1
        else:
            s.stable = 0
        s.taille_vue = taille

        if not s.prealloue and s.stable >= 2 and 0 < ecrits < taille:
            s.prealloue = True
            s.total = taille

        if s.prealloue:
            s.recu = min(ecrits, s.total)
            pc = round(100.0 * s.recu / s.total, 1) if s.total else None
        else:
            #  ═══ « min », ET CE N'EST PAS DE LA PRUDENCE DÉCORATIVE ═══
            #  Un fichier préalloué a sa taille finale DÈS LA PREMIÈRE
            #  mesure, mais il faut deux échantillons pour s'en assurer.
            #  Sans ce min, la première ligne annonçait « 4 Mo reçus » pour
            #  un fichier vide de 4 Mo — mesuré — puis le pourcentage
            #  retombait à 12,5 %. La pastille aurait donc reculé.
            #  Pour un fichier qui grossit vraiment, les blocs alloués sont
            #  ≥ la taille : le min rend alors la taille, comme avant.
            s.recu = min(ecrits, taille) if ecrits else taille
            pc = None

        dire(ev="avance", id=s.ident, recu=s.recu, total=s.total, pourcent=pc)
        s.vu_a = time.monotonic()

    def finir(self, chemin, final=None):
        s = self.suivis.pop(chemin, None)
        if not s:
            return
        cible = final or chemin
        m = self.mesurer(cible)
        dire(ev="fini", id=s.ident, nom=nom_visible(cible),
             taille=(m[0] if m else s.recu))

    def annuler(self, chemin):
        s = self.suivis.pop(chemin, None)
        if s:
            dire(ev="annule", id=s.ident, nom=nom_visible(chemin))

    # --- le battement ------------------------------------------------------
    def battement(self):
        for chemin, s in list(self.suivis.items()):
            if not os.path.exists(chemin):
                #  Le fichier a disparu sans renommage : annulé.
                self.annuler(chemin)
                continue
            self.avancer(s)
            if time.monotonic() - s.vu_a > ABANDON_S:
                self.annuler(chemin)
        return True

    # --- ce que Gio nous raconte -------------------------------------------
    def evenement(self, _mon, fichier, autre, typ):
        chemin = fichier.get_path()
        if not chemin:
            return
        base = os.path.basename(chemin)
        if base.startswith("."):
            return          # fichiers cachés : jamais un téléchargement visible

        temporaire = base.endswith(EN_COURS)

        if typ in (Gio.FileMonitorEvent.CREATED,
                   Gio.FileMonitorEvent.CHANGED):
            if temporaire:
                self.demarrer(chemin)
            elif typ == Gio.FileMonitorEvent.CREATED and chemin not in self.connus:
                #  Un fichier qui apparaît DÉJÀ à son nom final : c'est un
                #  téléchargement qui n'est pas passé par un temporaire (wget,
                #  curl, certains gestionnaires). On le suit pareil.
                self.connus.add(chemin)
                self.demarrer(chemin)

        elif typ == Gio.FileMonitorEvent.RENAMED:
            #  Le renommage du temporaire vers le nom final EST le signal de
            #  fin : c'est le seul moment où le navigateur dit « c'est bon ».
            cible = autre.get_path() if autre else None
            if chemin in self.suivis:
                self.finir(chemin, final=cible)

        elif typ in (Gio.FileMonitorEvent.DELETED,
                     Gio.FileMonitorEvent.MOVED_OUT):
            if chemin in self.suivis:
                self.annuler(chemin)

        elif typ == Gio.FileMonitorEvent.CHANGES_DONE_HINT:
            if chemin in self.suivis and not temporaire:
                self.finir(chemin)


def main():
    dossier = dossier_telechargements()
    if not dossier:
        dire(ev="erreur", motif="aucun dossier Téléchargements")
        return 0
    if not os.path.isdir(dossier):
        dire(ev="erreur", motif="dossier introuvable", dossier=dossier)
        return 0

    veille = Veille(dossier)
    f = Gio.File.new_for_path(dossier)
    try:
        mon = f.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
    except GLib.Error as e:
        dire(ev="erreur", motif="surveillance impossible", detail=str(e))
        return 0
    mon.connect("changed", veille.evenement)

    #  ═══ LE BATTEMENT EST INDISPENSABLE, PAS UN CONFORT ═══
    #  FileMonitor prévient qu'un fichier a changé, pas de combien. Et sur
    #  certains systèmes de fichiers il regroupe les changements : un gros
    #  téléchargement peut n'émettre qu'un événement par seconde. C'est donc
    #  le battement qui donne l'avancement régulier, et lui aussi qui repère
    #  l'abandon — un fichier qui ne bouge plus n'émet, par définition, aucun
    #  événement.
    GLib.timeout_add(PAS_MS, veille.battement)

    dire(ev="veille", dossier=dossier)
    boucle = GLib.MainLoop()
    try:
        boucle.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
