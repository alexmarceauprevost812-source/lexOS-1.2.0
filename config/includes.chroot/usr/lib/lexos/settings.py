#!/usr/bin/env python3
"""
LexOS — Paramètres : une seule fenêtre, une barre latérale, tous les réglages.

Même patron que Cartes LexOS (cartes.py) : une fenêtre Qt (PySide6) qui
affiche une page web servie par un petit serveur HTTP local. La page est
l'interface ; les actions réelles passent par une API locale (/api/…) que
le serveur exécute côté Python.

Pourquoi une API HTTP plutôt que QWebChannel : aucune dépendance de plus
(http.server est dans la bibliothèque standard, déjà utilisé par cartes.py),
et le pont est une LISTE BLANCHE — la page ne peut demander que les actions
définies ici, jamais une commande arbitraire.

Le serveur n'écoute que 127.0.0.1, sur un port libre tiré au lancement.
"""
import functools
import http.server
import json
import mimetypes
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

APP_NAME = "Paramètres LexOS"
BASE_DIR = Path(os.environ.get("LEXOS_SETTINGS_DIR", "/usr/share/lexos/settings"))
WEB_DIR = BASE_DIR / "web"

#  Racines réglables — MÊME PRINCIPE QUE LEXOS_RACINE DANS gpu-garde. En
#  usage réel ces variables n'existent pas et tout pointe au vrai endroit.
#  Elles ne servent qu'au banc d'essai : il donne à ce fichier une fausse
#  machine (fausse batterie, faux /etc) et vérifie que chaque section lit
#  et affiche l'état SANS avoir besoin de deux ordinateurs différents.
PSU_DIR = Path(os.environ.get("LEXOS_PSU", "/sys/class/power_supply"))
BL_DIR = Path(os.environ.get("LEXOS_BL", "/sys/class/backlight"))
ETC_DIR = Path(os.environ.get("LEXOS_ETC", "/etc"))
DMI_DIR = Path(os.environ.get("LEXOS_DMI", "/sys/class/dmi/id"))

#  ALEX : « fais en sorte que tout se mette à jour au fur et à mesure en
#  cliquant sur mise à jour ». Vérifier/Tout mettre à jour ouvraient un
#  terminal détaché et la page des Paramètres n'en savait plus rien ensuite
#  — les boutons restaient dans leur état de départ que le geste ait réussi,
#  échoué, ou tourne encore. MAJ_ETAT_DIR est où on laisse une trace de ce
#  terminal (début, puis fin + code de sortie) pour que la page puisse
#  SAVOIR, en la relisant, au lieu de deviner. Même principe d'emplacement
#  que lexos-capture (XDG_RUNTIME_DIR, avec /tmp en repli).
#
#  DEUX SEGMENTS (« lexos », puis « maj »), PAS UN NOM À TRAIT D'UNION.
#  verifier-parametres.sh lit ce fichier à la recherche des outils appelés
#  — tout ce qui ressemble à un nom de programme LexOS avec un trait
#  d'union — et vérifie qu'ils existent dans config/includes.chroot/usr/bin.
#  Écrit d'un seul tenant, ce dossier se faisait passer pour un outil
#  manquant et mettait le contrôle 16 au rouge, pour un chemin qui n'est
#  pas un programme. Le contrôle a raison d'être strict : c'est à ce
#  chemin-ci de ne pas se déguiser en commande.
MAJ_ETAT_DIR = Path(os.environ.get("LEXOS_MAJ_ETAT_DIR")
                     or os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                                     "lexos", "maj"))


# =============================================================================
#  Actions — la liste blanche.
#  Chaque entrée : nom -> fonction(arg) -> dict sérialisable en JSON.
#  Les arguments venant de la page sont validés contre des ensembles fermés :
#  jamais interpolés dans un shell.
# =============================================================================


#  LE MODE D'APPARENCE, POUR LA PAGE.
#  lexos-theme-gen écrit « sombre » ou « clair » dans ~/.config/lexos/mode
#  depuis toujours. Avant ce correctif, personne ne le lisait côté panneau :
#  « lexos theme clair » repeignait les fenêtres GTK en crème et laissait les
#  trois panneaux web NOIRS, en négatif du reste du bureau.
#  On le passe donc en ?mode=… — pas de nouveau point d'entrée, pas de requête
#  supplémentaire, et l'attribut est posé avant le premier rendu.
def _mode_apparence() -> str:
    try:
        base = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
        valeur = (Path(base) / "lexos" / "mode").read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError, ValueError):
        #  PAS SEULEMENT OSError. Un fichier « mode » ecrit dans un autre
        #  encodage leve UnicodeDecodeError, qui n'est pas une OSError : le
        #  panneau mourait alors AVANT d'ouvrir sa fenetre, pour un fichier de
        #  six octets. Un reglage d'apparence illisible doit faire retomber sur
        #  le mode sombre, jamais empecher les Parametres de s'ouvrir.
        return "sombre"
    #  Tout ce qui n'est pas explicitement « clair » reste sombre : un fichier
    #  vide, tronqué ou écrit par une version future ne doit pas blanchir
    #  l'écran d'un coup.
    return "clair" if valeur == "clair" else "sombre"

def _run(argv, *, detach=False):
    """Lance une commande. detach=True pour les fenêtres graphiques."""
    if shutil.which(argv[0]) is None:
        return {"ok": False, "erreur": f"Outil absent : {argv[0]}"}
    if detach:
        subprocess.Popen(argv, start_new_session=True,
                         stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"ok": True}
    #  ═══ stdin FERMÉE, ET CE N'EST PAS UN DÉTAIL D'HYGIÈNE ═══
    #  capture_output ne redirige que la sortie : l'entrée, elle, est HÉRITÉE.
    #  Si ce serveur a été lancé depuis un terminal — ce qui arrive à chaque
    #  mise au point — tout ce qu'il lance voit ce terminal. Un outil qui
    #  demande un mot de passe (sudo) le demanderait alors sur une fenêtre que
    #  personne ne regarde, et le bouton resterait figé jusqu'au délai de
    #  120 s. Avec DEVNULL, aucun enfant ne peut lire quoi que ce soit : celui
    #  qui a besoin d'un mot de passe doit passer par pkexec, qui a une vraie
    #  fenêtre. C'est aussi ce qui rend le choix de lexos-perf (« y a-t-il un
    #  terminal ? ») juste dans les deux sens.
    r = subprocess.run(argv, capture_output=True, text=True, timeout=120,
                       stdin=subprocess.DEVNULL)
    sortie = (r.stdout or r.stderr).strip()[-4000:]
    if r.returncode == 0:
        return {"ok": True, "sortie": sortie}
    #  « erreur » EN PLUS DE « sortie », ET C'EST TOUT LE PROBLÈME QU'ON RÉPARE.
    #  La page n'affiche un motif que si la réponse porte la clé « erreur » :
    #  partout ailleurs elle retombe sur « Échec : commande refusée ». Une
    #  commande qui échouait pour une raison précise — outil absent, droits
    #  manquants, argument refusé — la disait dans sa sortie, et cette sortie
    #  n'arrivait jamais à l'écran. On voyait un bouton qui « ne marche pas »,
    #  sans le moindre indice, et on cherchait du côté du bouton.
    motif = sortie.splitlines()[-1].strip() if sortie else ""
    if not motif:
        motif = f"« {argv[0]} » a échoué (code {r.returncode})"
    return {"ok": False, "erreur": motif, "sortie": sortie}


#  ═══ LE MOT DE PASSE D'ADMINISTRATEUR, ET LE SILENCE QUI TUE LES BOUTONS ═══
#  ALEX, sur son vieil ordinateur : « les boutons dans les paramètres ne
#  fonctionnaient pas ».
#
#  « pkexec » NE DESSINE PAS LA FENÊTRE DU MOT DE PASSE. Il la demande à un
#  « agent d'authentification » qui doit tourner dans la session. polkitd, le
#  démon, ne suffit pas : c'est l'agent qui parle à l'humain. Sans agent,
#  pkexec échoue tout de suite — pas de fenêtre, pas de message, rien dans la
#  page. Le bouton « ne fait rien », et on va chercher du côté du bouton.
#
#  Le dépôt croyait cet agent garanti : optional-packages/15-essentiel.list
#  affirmait qu'il arrivait « par les Recommends de xfce4-session ». Vérifié,
#  c'est faux — ces Recommends ne nomment aucun agent (dbus, logind, un
#  économiseur d'écran, upower, xfdesktop4, xfwm4). Trois candidats sont
#  maintenant nommés dans la liste, et /usr/lib/lexos/polkit-agent les
#  démarre ; il reste que sur une machine INSTALLÉE avant ce correctif, il n'y
#  en a aucun.
#
#  Alors on cesse de faire semblant : quand aucun agent ne tourne, on ne lance
#  PAS pkexec pour qu'il échoue en silence. On rend un motif, que la page
#  affiche.
_AGENTS_POLKIT = ("polkit-gnome-au", "polkit-mate-aut", "lxpolkit",
                  "lxqt-policykit-")


def _agent_polkit():
    """Un agent d'authentification tourne-t-il dans cette session ?

    « pgrep -x » et JAMAIS « pgrep -f » : avec -f, le motif cherché apparaît
    dans la ligne de commande du pgrep lui-même, qui se reconnaît alors et
    répond toujours oui. Le dépôt s'est fait prendre trois fois (lexos-share,
    lexos-crt). Les noms ci-dessus sont tronqués à quinze caractères parce
    que c'est ainsi que le noyau les stocke (« lxqt-policykit- » : tiret
    final compris, troncature exacte de lxqt-policykit-agent). Et « -u » se
    restreint à NOTRE session : sans lui, l'agent d'un AUTRE utilisateur
    connecté (changement d'utilisateur LightDM, session invitée) ferait
    croire à tort qu'on a un agent ici. On ne cherche plus
    « polkit-agent-he » : ce n'est pas un agent, c'est le mouchard setuid
    qu'un agent lance le temps de vérifier un mot de passe — jamais présent
    au moment où on pose la question."""
    if shutil.which("pgrep") is None:
        return False
    uid = str(os.getuid())
    for nom in _AGENTS_POLKIT:
        try:
            if subprocess.run(["pgrep", "-x", "-u", uid, nom],
                              capture_output=True,
                              timeout=5).returncode == 0:
                return True
        except (OSError, subprocess.SubprocessError):
            continue
    return False


def _run_admin(argv):
    """Lance argv avec les droits d'administration, ou dit pourquoi c'est
    impossible. Ne rend jamais un succès qu'on n'a pas obtenu."""
    if os.geteuid() == 0:
        return _run(argv)
    if shutil.which("pkexec") is None:
        return {"ok": False,
                "erreur": "pkexec est absent : impossible de demander les "
                          "droits d'administration depuis une fenêtre."}
    if not _agent_polkit():
        return {"ok": False,
                "erreur": "Aucune fenêtre de mot de passe n'est disponible "
                          "sur cette session (agent polkit absent). "
                          "Installe-le : sudo apt install lxpolkit, "
                          "puis rouvre la session."}
    return _run(["pkexec"] + argv)


def _terminal(titre, commande):
    """Ouvre un outil en ligne de commande dans un terminal, comme le faisait
    l'ancien routeur bash — même forme d'appel que les .desktop du hook 0400
    (xfce4-terminal --hold -e "commande; bash"). `commande` est une chaîne
    fixe définie ICI, jamais construite depuis la page ; elle part telle
    quelle comme UN SEUL élément d'argv (pas de ré-interprétation shell côté
    Python : subprocess.Popen reçoit une liste, jamais shell=True)."""
    return _run(["xfce4-terminal", f"--title={titre}", "--hold", "-e",
                 f"{commande}; bash"], detach=True)


def _terminal_suivi(titre, commande, cle):
    """Comme _terminal(), mais laisse une trace de FIN — un fichier posé une
    fois « commande » terminée, avec son code de sortie dedans. C'est ce qui
    permet à _maj_progres(cle) de savoir si ça tourne encore sans lire dans
    la fenêtre du terminal, qui vit dans un processus séparé qu'on ne
    contrôle plus une fois « detach=True » posé.

    On enveloppe « commande » plutôt que de la remplacer : ce que
    l'utilisateur voit dans le terminal ne change pas d'un caractère — la
    ligne « echo … > … » n'apparaît qu'après, quand tout est déjà fait."""
    MAJ_ETAT_DIR.mkdir(parents=True, exist_ok=True)
    debut = MAJ_ETAT_DIR / f"{cle}.debut"
    fin = MAJ_ETAT_DIR / f"{cle}.fin"
    fin.unlink(missing_ok=True)
    debut.write_text(str(time.time()), encoding="utf-8")
    enveloppe = f"{commande}; echo $? > {shlex.quote(str(fin))}; bash"
    return _run(["xfce4-terminal", f"--title={titre}", "--hold", "-e", enveloppe],
                detach=True)


def _maj_progres(cle):
    """L'état d'une action de mise à jour lancée par _terminal_suivi() :
    None si elle n'a jamais tourné, {"en_cours": True} tant qu'elle tourne,
    {"en_cours": False, "ok": …} une fois le fichier de fin posé."""
    debut = MAJ_ETAT_DIR / f"{cle}.debut"
    fin = MAJ_ETAT_DIR / f"{cle}.fin"
    if not debut.exists():
        return None
    if not fin.exists():
        return {"en_cours": True}
    try:
        code = int(fin.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        #  Un fichier de fin illisible ou vide veut dire qu'on ne SAIT PAS —
        #  pas que ça a réussi. Un « ok » inventé serait le même mensonge
        #  que le « {"ok": True} » d'act_bt_chercher(), corrigé plus haut.
        return {"en_cours": False, "ok": None}
    return {"en_cours": False, "ok": code == 0}


def _xfce(module):
    """Ouvre le bon panneau de réglages XFCE.

    CE QUI ÉTAIT CASSÉ, ET POURQUOI PERSONNE NE LE VOYAIT.
    Cette fonction lançait « xfce4-settings-manager -s <module> ». L'option
    « -s » n'existe pas : xfce4-settings-manager refusait et mourait aussitôt.
    Comme l'appel est en detach=True (on ne lit pas le code de retour d'une
    fenêtre graphique, elle vit sa vie), l'échec était TOTALEMENT SILENCIEUX.
    Neuf sections des Paramètres avaient donc un bouton qui ne faisait rien,
    sans le moindre message : son, apparence, bureau, multi-tâches, souris,
    supports amovibles, tablette, accessibilité, clavier.

    XFCE ne s'ouvre pas par module : chaque panneau est un PROGRAMME à part
    (xfce4-appearance-settings, xfce4-mouse-settings…). On les nomme donc
    directement, et on garde des solutions de rechange : si le programme
    précis manque, on ouvre le gestionnaire de réglages complet plutôt que
    de ne rien faire. Un bouton doit toujours mener quelque part."""
    for argv in module if isinstance(module, list) else [[module]]:
        if shutil.which(argv[0]):
            return _run(argv, detach=True)
    #  Rien de précis n'est installé : le gestionnaire général vaut mieux que
    #  le silence — l'utilisateur trouvera son réglage à la main.
    if shutil.which("xfce4-settings-manager"):
        return _run(["xfce4-settings-manager"], detach=True)
    return {"ok": False, "erreur": "Aucun outil de réglages XFCE installé"}


#  ═══ CINQ PROFILS, PAS QUATRE ═══
#  « vif » manquait ici, et NULLE PART AILLEURS : lexos-perf le reconnaît
#  (normalize, label, load_profile, detect_profile le suggère même aux
#  portables de 8 Go), la page l'affiche dans sa rangée de boutons et lui
#  donne 7 000 tr/min sur le compte-tours. Seul ce garde-fou l'ignorait —
#  alors le bouton partait, la réponse revenait « profil inconnu », et le
#  seul profil que la machine d'Alex se voit RECOMMANDER était le seul qu'on
#  refusait de lui appliquer.
#
#  La liste doit rester la même que celle de normalize() dans lexos-perf ;
#  tests/test_lexos_perf_vif.sh compare les deux et rougit si elles divergent.
PERFS = {"petit", "medium", "vif", "performant", "max"}
THEMES = {"sombre", "clair"}
ACCENTS = {"orange", "orange-rouge", "bleu", "rouge", "vert", "gris",
           "violet", "neon"}
#  LES POLICES D'ÉCRITURE. Trois familles génériques, puis DOUZE écritures à
#  la main embarquées par LexOS (licence OFL, dans
#  /usr/share/fonts/truetype/lexos, chacune avec son fichier de licence).
#
#  Pourquoi douze plutôt qu'une : Alex a repéré une écriture qui lui plaisait
#  sans savoir la nommer, et deviner à sa place gaspillait son temps comme le
#  mien. Il les a maintenant toutes sous les yeux, sur SA machine, à sa taille
#  et sur son fond — c'est là qu'on juge une police, pas sur une capture.
#
#  Cette liste est la SEULE source de vérité côté machine : le nom qui arrive
#  de la page est refusé s'il n'y est pas. Elle doit rester alignée avec
#  POLICES dans app.js (l'affichage) et cmd_police dans /usr/bin/lexos (le
#  terminal) — les trois nomment les mêmes clés.
POLICES = {
    "defaut", "classique", "mono",
    "manuscrite", "bulle", "carnet", "ronde", "crayon", "plume",
    "marqueur", "architecte", "fleur", "cursive", "tableau", "craie",
}
DOCKS = {"droite", "gauche", "bas", "haut"}
#  ═══ LE DOCK N'A QU'UNE SEULE VÉRITÉ, ET C'EST gsettings ═══
#  Ces deux constantes sont la COPIE de ce que « lexos dock » (cmd_dock,
#  usr/bin/lexos) écrit. Une copie se met à mentir dès qu'on touche l'original
#  sans elle : tests/test_lexos_dock.sh compare les deux chaînes caractère par
#  caractère et rougit si elles s'écartent.
#
#  Pourquoi une copie plutôt que d'appeler « lexos dock » sans argument : cette
#  commande écrit une PHRASE pour un humain (« Position du dock : droite
#  (défaut) »), sur deux lignes, avec des couleurs. Analyser une phrase pour en
#  tirer une donnée, c'est se rendre dépendant de sa formulation — et LexOS la
#  reformule souvent.
DOCK_SCHEMA = "net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"
DOCK_POSITIONS = {"right": "droite", "left": "gauche",
                  "bottom": "bas", "top": "haut"}
CADRAGES = {"remplir", "ajuster", "etirer", "centrer", "mosaique"}
#  PAS DE CLÉ « defaut » : depuis le crochet 0300, wallpaper.png EST un lien
#  symbolique vers wallpaper-demon.png (les deux noms doivent rester la même
#  image pour toujours). realpath() les rend donc indiscernables dans
#  _fond_etat() ci-dessous ; avec les deux clés présentes, c'est TOUJOURS la
#  première insérée qui gagnait — « demon » ne pouvait alors jamais s'allumer
#  dans la galerie. Une seule clé pour une seule image réelle : « demon ».
FONDS = {
    "secu":    "/usr/share/backgrounds/lexos/wallpaper-secu.png",
    "demon":   "/usr/share/backgrounds/lexos/wallpaper-demon.png",
    "keyart":  "/usr/share/backgrounds/lexos/wallpaper-keyart.png",
    #  « Nomad » : le bureau de la démo web, demandé par Alex sur capture —
    #  logo ASCII orange, filet, TI·LEX·AL, 2.0.0 NOMAD. Le crochet 0300 le
    #  rend en trois tailles depuis branding/wallpaper-nomad.svg.
    "nomad":   "/usr/share/backgrounds/lexos/wallpaper-nomad.png",
    #  Les deux images envoyées par Alex. En .jpg et pas en .png : ce sont des
    #  photos-affiches, pas des SVG rendus — un PNG pèserait cinq fois plus
    #  pour la même image. Le hook 0300 les met au format 1920 × 1080 à la
    #  construction (le portrait centré sur du noir, la bannière rognée de
    #  200 px en haut) ; ici on ne nomme QUE le résultat.
    "mascotte": "/usr/share/backgrounds/lexos/wallpaper-mascotte.jpg",
    "tilexal":  "/usr/share/backgrounds/lexos/wallpaper-tilexal.jpg",
}
LANGUES = {
    "fr_CA.UTF-8", "fr_FR.UTF-8", "en_US.UTF-8", "en_CA.UTF-8", "en_GB.UTF-8",
    "es_ES.UTF-8", "es_MX.UTF-8", "de_DE.UTF-8", "it_IT.UTF-8", "pt_BR.UTF-8",
    "ru_RU.UTF-8", "zh_CN.UTF-8", "ja_JP.UTF-8", "ko_KR.UTF-8", "ar_SA.UTF-8",
}


def act_ouvrir(arg):
    """Ouvre l'outil complet d'une section — reprise exacte de l'ancien
    routeur bash (hook 0450)."""
    outils = {
        "wifi":       lambda: _terminal("Réseau — LexOS", "lexos net status; echo; lexos vpn"),
        "reseau":     lambda: _terminal("Réseau — LexOS", "lexos net status; echo; lexos vpn"),
        "bluetooth":  lambda: _terminal("Bluetooth — LexOS", "lexos bt scan"),
        "ecrans":     lambda: _run(["lexos-display", "gui"], detach=True),
        #  « xfce4-mixer » a été RETIRÉ de Debian (il dépendait de
        #  GStreamer 0.10) : « apt-get download xfce4-mixer » ne le trouve
        #  plus du tout. Le garder en repli donnait l'illusion d'un filet
        #  qui ne pouvait jamais se déployer. Le vrai filet est celui de
        #  _xfce() : à défaut de pavucontrol, le gestionnaire général.
        "son":        lambda: _xfce([["pavucontrol"]]),
        "energie":    lambda: _terminal("Énergie — LexOS", "lexos perf status; echo; lexos lumiere"),
        "usb":        lambda: _terminal("USB — LexOS", "lexos usb; echo; echo 'Formater un support : lexos format'"),
        "mac":        lambda: _terminal("Mac (Apple) — LexOS", "lexos mac"),
        "apparence":  lambda: _xfce([["xfce4-appearance-settings"]]),
        "bureau":     lambda: _xfce([["xfdesktop-settings"]]),
        "multitaches": lambda: _xfce([["xfwm4-workspace-settings"], ["xfwm4-settings"]]),
        #  ═══ « exo-preferred-applications » N'EXISTE PLUS ═══
        #  ALEX : « regarde bien pour que tous les boutons et les fenêtres
        #  ouvrent fluidement. » Celui-ci n'ouvrait rien du tout, et le
        #  bouton « Applications par défaut » non plus (même cible).
        #
        #  VÉRIFIÉ SUR LES VRAIS PAQUETS, pas deviné : exo-utils ne livre que
        #  exo-open, exo-desktop-item-edit et exo-helper — plus de
        #  « preferred-applications ». XFCE a déplacé cette fenêtre dans
        #  xfce4-settings, où le fichier .desktop s'intitule très exactement
        #  « Default Applications » et lance « xfce4-mime-settings ».
        #
        #  On passe par _xfce() plutôt que _run() : il essaie chaque nom à
        #  son tour et, si aucun n'est là, ouvre le gestionnaire général
        #  plutôt que de ne rien faire. C'est la règle que cette fonction
        #  s'était déjà donnée — « un bouton doit toujours mener quelque
        #  part » — et que ces deux entrées-ci ne suivaient pas.
        #  CETTE ENTRÉE OUVRAIT LE DIALOGUE DES TYPES DE FICHIERS, c'est-à-dire
        #  exactement ce qu'ouvre « Applications par défaut ». La section
        #  « Applications » parle maintenant d'installer et de retirer des
        #  logiciels : c'est la logithèque qu'elle doit ouvrir.
        "applications": lambda: _terminal("Logithèque LexOS", "lexos logitheque"),
        #  ALEX : « quand on télécharge, l'application soit déjà installée au
        #  lieu de passer par le terminal ». C'est lexos-ouvrir qui le fait,
        #  et c'est lui que le double-clic appelle. Ici, sans argument, il
        #  ouvre le sélecteur de fichiers sur le dossier des téléchargements —
        #  donc PAS de _terminal() : le sujet même de cette entrée est de ne
        #  plus passer par le terminal.
        "fichier-telecharge": lambda: _run(["lexos-ouvrir"], detach=True),
        "notifications": lambda: _run(["xfce4-notifyd-config"], detach=True),
        "recherche":  lambda: _run(["xfce4-appfinder", "--collapsed"], detach=True),
        #  Le bouton rouge de la barre ouvre la même fenêtre. Elle est ici
        #  aussi parce qu'un geste du système doit être atteignable depuis
        #  les Paramètres — sinon il n'existe qu'à un seul endroit, et le
        #  jour où ce bouton bouge, plus personne ne le trouve.
        "session":    lambda: _run(["lexos-session"], detach=True),
        #  Le terminal a son propre jour/nuit, indépendant du bureau.
        #  On l'ouvre DANS un terminal : la commande montre l'état
        #  courant et les quatre modes, ce qui n'aurait aucun sens
        #  dans une fenêtre qui se ferme aussitôt.
        "terminal":   lambda: _terminal("Terminal — jour / nuit", "lexos terminal"),
        "partage":    lambda: _run(["lexos-share", "devices"], detach=True),
        "souris":     lambda: _xfce([["xfce4-mouse-settings"]]),
        "couleurs":   lambda: _run(["gcm-viewer"], detach=True),
        "imprimantes": lambda: _run(["system-config-printer"], detach=True),
        "amovibles":  lambda: _xfce([["thunar-volman-settings"]]),
        #  L'audit du site l'a nommé : « xfce4-wacom-settings » n'existe pas
        #  dans Debian — XFCE n'a pas de panneau wacom. Le repli ouvrait le
        #  gestionnaire général, qui n'en a pas non plus : un bouton qui mène
        #  quelque part, mais pas au bon endroit. Le vrai outil est xsetwacom
        #  (livré par 56-reglages), et il parle en terminal.
        "tablette":   lambda: _terminal(
            "Tablette graphique — LexOS",
            "xsetwacom list devices; echo; "
            "echo 'Aucune ligne au-dessus = aucune tablette branchée.'; echo; "
            "echo 'Régler : man xsetwacom — ex. : xsetwacom set \"<nom>\" Rotate half'"),
        "confidentialite": lambda: _terminal("Confidentialité et sécurité — LexOS",
                                             "lexos net status; echo; lexos secure"),
        "maj":        lambda: _terminal("Mises à jour — LexOS", "lexos doctor"),
        "accessibilite": lambda: _xfce([["xfce4-accessibility-settings"]]),
        #  CETTE ENTRÉE AFFICHAIT UNE LISTE INVENTÉE. Elle imprimait « lex —
        #  Principal, administrateur » et « invite — Invité », deux comptes
        #  écrits en dur ici : pas lus, pas vérifiés, pas forcément existants.
        #  Sur la machine d'Alex, le compte ne s'appelle ni « lex » ni
        #  « invite ». Un écran qui ment est pire qu'un écran vide — on ne
        #  sait même pas qu'il faut chercher ailleurs.
        #  lexos-utilisateurs, lui, LIT les comptes : nom complet, droits,
        #  dernière connexion, état du mot de passe.
        "utilisateurs": lambda: _terminal("Utilisateurs — LexOS",
                                          "lexos utilisateurs"),
        "clavier":    lambda: _xfce([["xfce4-keyboard-settings"]]),
        "datetime":   lambda: _terminal("Date et heure — LexOS", "timedatectl"),
        #  Même fenêtre, même correctif (voir « applications » ci-dessus).
        "defaut":     lambda: _xfce([["xfce4-mime-settings"],
                                     ["exo-preferred-applications"]]),
        "distant":    lambda: _terminal("Bureau à distance — LexOS", "lexos distant"),
        "comptes":    lambda: _terminal("Comptes en ligne — LexOS", "lexos comptes"),
        "bienetre":   lambda: _terminal("Bien-être numérique — LexOS", "lexos bienetre"),
        "apropos":    lambda: _run(["lexos-welcome", "--about"], detach=True),
        #  Le moteur de scan matériel. Il avait sa fenêtre et son lanceur,
        #  mais AUCUN chemin depuis ici : deux piles côte à côte qui ne se
        #  parlaient pas. Le contrôle 16 l'a nommé — c'est cette ligne qui
        #  le branche.
        "boost":      lambda: _run(["lexos-boost"], detach=True),
        #  LexOS Diagnostic — le panneau en direct (matériel/médecin/disques).
        #  Même histoire que Boost juste au-dessus : il avait son icône, son
        #  .desktop et sa branche dans le dispatcheur, mais aucun chemin
        #  depuis ici. Le contrôle 16 l'a nommé.
        "diagnostic": lambda: _run(["lexos-diagnostic"], detach=True),
        #  Étiqueter les dossiers : l'outil PARLE (il liste ce qu'il a fait,
        #  ou dit pourquoi il n'a rien fait). Le lancer détaché donnerait un
        #  bouton qui a l'air de ne rien faire — le défaut le plus répété de
        #  ce dépôt. Il passe donc par un terminal, comme le coffre privé.
        "etiquettes": lambda: _terminal("Étiqueter les dossiers — LexOS",
                                        "lexos etiquette --maison"),
        #  Ce qui est sur le dock, en une commande. Épingler se fait au clic
        #  droit sur l'application ; ici on ne fait que MONTRER, et c'est
        #  volontaire : une liste qu'on peut lire vaut mieux qu'un deuxième
        #  endroit où épingler, qui finirait par diverger du premier.
        "dock-epingles": lambda: _terminal("Applications sur le dock — LexOS",
                                           "lexos epingler --liste"),
        #  Le coffre parle en TERMINAL (menu, questions, mot de passe) : le
        #  lancer détaché ferait un bouton qui ne fait rien — vérifié dans son
        #  routeur, « gui » n'existe pas, l'entrée par défaut est « menu ».
        "prive":      lambda: _terminal("Fichiers privés — LexOS", "lexos prive"),
    }
    fn = outils.get(arg)
    if fn is None:
        return {"ok": False, "erreur": f"Section inconnue : {arg}"}
    return fn()


def act_avion(arg):
    if arg not in {"toggle", "on", "off"}:
        return {"ok": False, "erreur": "avion : toggle|on|off"}
    return _run(["lexos-net", "avion", arg])


#  ═══ POURQUOI _run ET NON _run_admin, ALORS QUE ÇA DEMANDE ROOT ═══
#  Un profil a DEUX moitiés. La moitié système — gouverneur du processeur,
#  sysctl, ordonnanceur d'entrées-sorties, zram, services — exige root. La
#  moitié session — compositing, effets CRT, zoom du dock, vignettes — est
#  faite de réglages de LA session de l'utilisateur, écrits dans SON xfconf.
#
#  Passer tout lexos-perf par _run_admin() reviendrait à appliquer la seconde
#  moitié dans la session de ROOT, c'est-à-dire nulle part : le dock d'Alex ne
#  bougerait pas, la composition resterait allumée, et la page annoncerait un
#  succès complet. C'est pourquoi l'élévation n'est PAS ici mais dans
#  lexos-perf, qui se rappelle lui-même pour la seule moitié système à travers
#  pkexec (règle org.lexos.perf.policy) ou sudo selon qu'il y a un terminal.
#
#  CE QU'ON GAGNE À LE LAISSER LÀ-BAS : « lexos-perf vif » tapé au terminal
#  suit exactement le même chemin que le bouton. Une seule orchestration, pas
#  deux à garder d'accord.
def act_perf(arg):
    if arg not in PERFS:
        return {"ok": False, "erreur": "profil inconnu"}
    r = _run(["lexos-perf", arg])
    #  Code 1 = « la moitié session est passée, la moitié système a été
    #  refusée ». lexos-perf écrit alors son motif sur la SORTIE STANDARD,
    #  que _run remonte dans « erreur » — la page a donc déjà de quoi le dire.
    #  On n'ajoute une phrase que dans le cas où l'on connaît une cause plus
    #  précise que lui : aucun agent d'authentification dans la session, et
    #  donc aucune fenêtre de mot de passe possible. Lui ne peut pas le
    #  savoir ; nous, si.
    #  ON NE DEVINE PAS : on reconnaît la phrase que lexos-perf écrit dans ce
    #  cas précis. Sans ce filtre, un profil refusé pour une TOUTE autre raison
    #  — outil absent, /etc/lexos non inscriptible — aurait reçu le message du
    #  mot de passe, et l'utilisateur serait parti chercher un agent polkit
    #  pour un problème qui n'en est pas un. Le banc vérifie que les deux
    #  phrases se correspondent encore.
    if (not r.get("ok")
            and "plan système refusé" in (r.get("erreur") or "")
            and os.geteuid() != 0 and not _agent_polkit()):
        r["erreur"] = ("Le profil est appliqué à la session, mais la moitié "
                       "système demande le mot de passe administrateur et "
                       "aucune fenêtre de mot de passe n'existe sur cette "
                       "session (agent polkit absent). Installe-le : "
                       "sudo apt install lxpolkit, puis rouvre la session.")
    return r


def act_lumiere(arg):
    try:
        n = int(arg)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "luminosité : un nombre 5-100"}
    n = max(5, min(100, n))
    return _run(["lexos-brightness", str(n)])


def act_theme(arg):
    if arg not in THEMES:
        return {"ok": False, "erreur": "thème : sombre|clair"}
    return _run(["lexos", "theme", arg])


def act_accent(arg):
    if arg not in ACCENTS:
        return {"ok": False, "erreur": "accent inconnu"}
    return _run(["lexos", "accent", arg])


def act_police(arg):
    if arg not in POLICES:
        return {"ok": False, "erreur": "police inconnue"}
    return _run(["lexos", "police", arg])


def act_dock(arg):
    if arg not in DOCKS:
        return {"ok": False, "erreur": "position : droite|gauche|bas|haut"}
    return _run(["lexos", "dock", arg])


def act_fond(arg):
    chemin = FONDS.get(arg)
    if chemin is None:
        return {"ok": False, "erreur": "fond inconnu"}
    if not Path(chemin).exists():
        return {"ok": False, "erreur": f"Image absente : {chemin}"}
    return _run(["lexos", "wallpaper", chemin, "remplir"])


#  Les scènes animées sont LUES SUR LE DISQUE, jamais recopiées dans une liste.
#  L'aide du terminal annonçait « ciel » alors que le fichier s'appelle
#  « etoiles » : la commande copiée de la documentation échouait mot pour mot.
#  Une liste écrite à la main finit toujours par mentir ; celle-ci ne peut pas.
#  ═══ LES FONDS ANIMÉS ONT ÉTÉ RETIRÉS ═══
#  ALEX : « on perd toutes les applications du bureau quand on met un effet
#  animé ; les icônes restent seulement avec un fond d'écran fixe. »
#
#  LA CAUSE, ET POURQUOI ELLE N'A PAS ÉTÉ RÉPARÉE. Le moteur posait sa
#  fenêtre dans le calque _NET_WM_WINDOW_TYPE_DESKTOP — celui de xfdesktop,
#  qui dessine les icônes. xfwm4 garantit que ce calque reste sous les
#  fenêtres normales, mais PAS l'ordre relatif de deux fenêtres DANS ce
#  calque. Notre fond pouvait donc passer devant les icônes, et rien dans le
#  code n'était « cassé » pour autant. Deux correctifs ont été tentés (faire
#  remonter xfdesktop par xdotool, puis par ses deux champs WM_CLASS) : les
#  deux ont échoué chez Alex, et aucune des machines de construction n'a de
#  serveur X pour éprouver le troisième. Deviner une fois de plus aurait
#  autant de chances de retomber à côté.
#
#  On retire donc la fonctionnalité plutôt que de livrer un bureau dont les
#  icônes disparaissent. Le fond VIDÉO est parti avec, pour la même raison :
#  son outil partageait le défaut mot pour mot, et son propre en-tête le
#  disait déjà. Tout le code reste dans l'historique git.


def act_fond_capture(arg):
    """Capture l'écran et en fait le fond d'écran — les deux outils existaient
    déjà mais rien ne les reliait, il fallait retenir le chemin du fichier."""
    mode = arg if arg in ("plein", "zone") else "plein"
    if shutil.which("lexos-capture") is None:
        return {"ok": False, "erreur": "lexos-capture absent"}
    return _run(["lexos-capture", "fond", mode], detach=True)


#  ═══ LES IMAGES DE L'UTILISATEUR, ÉNUMÉRÉES POUR LA PAGE ═══
#  Alex : « fais que les images qu'on télécharge, on peut les utiliser comme
#  fond d'écran aussi ». Le bouton « Une image à moi… » ouvrait un sélecteur
#  AVEUGLE : il fallait se rappeler du nom du fichier. La page montre
#  désormais les images de l'utilisateur en vignettes — et un clic les pose.
#
#  MÊMES DOSSIERS QUE lexos-fond-ecran, dans le même ordre. Deux listes qui
#  divergent, c'est une image proposée ici et introuvable là — le genre
#  d'écart qui fait dire « ça marche une fois sur deux ».
FONDS_PERSO_DIRS = ("Images", "Téléchargements", "Downloads", "Fonds d'écran")
FONDS_PERSO_EXT = {".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp", ".svg"}
FONDS_PERSO_MAX = 24
#  PLAFOND DE TAILLE. La vignette fait 96x56 px, et le pont n'a pas de quoi
#  redimensionner (Pillow n'est pas garanti) : il sert donc le fichier tel
#  quel. Sans plafond, ouvrir la section chargerait en mémoire, jusqu'à 24
#  fois en parallèle, des fichiers de n'importe quelle taille — et le nom
#  comme le contenu d'un téléchargement sont dictés par le site d'en face,
#  pas par l'utilisateur. 40 Mio laisse passer toutes les photos d'appareil
#  et tous les fonds d'écran 4K réels, et arrête le reste.
FONDS_PERSO_POIDS_MAX = 40 * 1024 * 1024


def _fonds_perso():
    """Les images des dossiers personnels, les plus récentes d'abord.

    Bornée à FONDS_PERSO_MAX : la page est une rangée de vignettes, pas un
    gestionnaire de fichiers — au-delà, le bouton « Une image à moi… » ouvre
    le vrai sélecteur. Le tri par date de modification met en tête ce qu'on
    vient de télécharger : c'est précisément l'image qu'on vient chercher.

    UN NIVEAU DE SOUS-DOSSIERS EN PLUS — ALEX : « quand on prend une
    capture d'écran, j'aimerais qu'on la retrouve où sont les images [...]
    on voit pas ça [dans la galerie], j'aimerais qu'on voie les images de
    capture d'écran à la place ». lexos-capture écrit dans
    ~/Images/Captures (voir ce script) : un SOUS-dossier d'« Images », que
    ce simple iterdir() ne voyait jamais. lexos-fond-ecran (le même
    ratissage, en bash) descend déjà à « find -maxdepth 2 » — les deux
    listes avaient divergé, exactement le piège que le commentaire de
    FONDS_PERSO_DIRS met en garde contre plus haut. On aligne : chaque
    dossier ET ses sous-dossiers immédiats, jamais plus profond (une
    galerie qui plonge sans fond n'est plus une galerie).
    """
    vus, images = set(), []

    def ajoute(dossier):
        for f in dossier.iterdir():
            if f.is_file() and f.suffix.lower() in FONDS_PERSO_EXT:
                try:
                    st = f.stat()
                    #  Un fichier trop lourd n'est pas un fond d'écran :
                    #  on ne le propose pas plutôt que d'afficher une
                    #  vignette qui ne chargera jamais.
                    if st.st_size > FONDS_PERSO_POIDS_MAX:
                        continue
                    images.append((st.st_mtime, str(f)))
                except OSError:
                    continue

    for nom in FONDS_PERSO_DIRS:
        d = Path.home() / nom
        try:
            reel = d.resolve()
            if not d.is_dir() or reel in vus:
                continue
            vus.add(reel)
            ajoute(d)
            for sous in d.iterdir():
                if not sous.is_dir():
                    continue
                try:
                    sreel = sous.resolve()
                    if sreel in vus:
                        continue
                    vus.add(sreel)
                    ajoute(sous)
                except OSError:
                    continue
        except OSError:
            continue
    images.sort(reverse=True)
    return [c for _, c in images[:FONDS_PERSO_MAX]]


#  ═══ QUEL FOND EST POSÉ ? — ALEX : « POUR CHANGER DE COULEUR SUR LE BOUTON
#      SÉLECTIONNÉ, POUR QU'IL CHANGE DE COULEUR » ═══
#  Les cinq fonds intégrés et les vignettes de « Mes images » étaient les
#  SEULS choix de toute la page à ne jamais montrer lequel était le choix
#  courant : leurs boutons étaient écrits en dur « class="btn ghost" », sans
#  la moindre condition. Partout ailleurs le dépôt le fait — le thème,
#  l'accent, la police, le dock, la définition d'écran, le profil de
#  performance portent tous « class="btn ${x ? 'sel' : 'ghost'}" ».
#
#  ET CE N'ÉTAIT PAS UN OUBLI D'UNE LIGNE : rien dans etat() ne DISAIT quel
#  fond est posé. Il n'y avait rien à comparer. Voilà la clé qui manquait.
def _fond_actuel():
    """Le chemin de l'image posée sur le bureau, tel que XFCE le connaît.

    On lit la même propriété que lexos-fond-ecran (fond_actuel(), ligne 90) :
    la PREMIÈRE propriété du canal xfce4-desktop qui finit par « last-image ».
    Une machine à deux écrans en a plusieurs, toutes égales quand le fond a
    été posé par LexOS — qui les écrit toutes.

    Rend "" quand on ne peut pas savoir : sans serveur X, sans xfconf-query,
    ou quand aucune propriété n'existe encore. Ne JAMAIS rendre un chemin
    inventé : une vignette mise en évidence à tort est pire que pas de
    vignette en évidence du tout."""
    if shutil.which("xfconf-query") is None:
        return ""
    try:
        r = subprocess.run(["xfconf-query", "-c", "xfce4-desktop", "-l"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    if r.returncode != 0:
        return ""
    prop = next((l.strip() for l in r.stdout.splitlines()
                 if l.strip().endswith("/last-image")), "")
    if not prop:
        return ""
    try:
        v = subprocess.run(["xfconf-query", "-c", "xfce4-desktop", "-p", prop],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    return v.stdout.strip() if v.returncode == 0 else ""


def _fond_etat(perso=None):
    """Ce que la page a besoin de savoir pour mettre le bon bouton en couleur.

    · « chemin » : ce qui est posé, ou "" si on ne sait pas ;
    · « cle »    : la clé de FONDS (defaut, secu, demon, keyart, nomad) si
                   c'est l'un des cinq intégrés, sinon "" ;
    · « i »      : l'indice dans la galerie « Mes images » si c'en est une,
                   sinon None.

    « perso » est passé par etat() pour ne pas relire deux fois le disque —
    la liste vient d'être calculée juste au-dessus."""
    chemin = _fond_actuel()
    vide = {"chemin": "", "cle": "", "i": None}
    if not chemin:
        return vide
    #  On compare des chemins RÉSOLUS : /usr/share/backgrounds/lexos/x.png et
    #  un lien symbolique vers lui sont le même fond, et le dépôt en pose
    #  justement (le fond officiel est un lien, hook 0300).
    def reel(c):
        try:
            return os.path.realpath(c)
        except OSError:
            return c
    r_chemin = reel(chemin)
    cle = next((k for k, v in FONDS.items() if reel(v) == r_chemin), "")
    idx = None
    if perso is None:
        perso = _fonds_perso()
    for i, c in enumerate(perso):
        if reel(c) == r_chemin:
            idx = i
            break
    return {"chemin": chemin, "cle": cle, "i": idx}


def act_fond_fichier(arg):
    """Applique une image de la galerie — désignée par son INDICE, jamais par
    un chemin.

    La page n'est pas une source de confiance : tout ce qui s'exécute passe
    par la liste blanche, comme le dit l'en-tête d'ACTIONS. Elle ne connaît
    d'ailleurs même pas les chemins — l'état ne lui donne que {indice, nom}.
    On ré-énumère ici et l'indice ne sait désigner que ce que la galerie
    propose déjà. Un chemin libre accepté ici, c'est la page qui peut faire
    lire n'importe quel fichier au bureau.

    L'énumération est REFAITE entre l'affichage et le clic : si une image a
    été téléchargée entre-temps, les indices ont glissé d'un cran. On vérifie
    donc aussi le NOM quand la page l'envoie — au pire on refuse, et le
    prochain rendu remet tout d'aplomb. Refuser vaut mieux que poser la
    mauvaise photo.
    """
    if isinstance(arg, dict):
        i, nom = arg.get("i", -1), arg.get("nom", "")
    else:
        i, nom = arg, ""
    try:
        i = int(i)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "indice invalide"}
    fonds = _fonds_perso()
    if not (0 <= i < len(fonds)):
        return {"ok": False, "erreur": "image inconnue — pas dans la galerie"}
    chemin = fonds[i]
    if nom and Path(chemin).name != nom:
        return {"ok": False, "erreur":
                "la galerie a changé depuis l'affichage — rouvre la section"}
    #  « ajuster » : l'image ENTIÈRE sur fond noir — « fais les images sur un
    #  fond noir avec les images ». Une photo de téléphone est verticale ;
    #  « remplir » n'en montrait que la bande du milieu.
    return _run(["lexos", "wallpaper", chemin, "ajuster"])


def act_fond_ouvrir(arg):
    """Ouvre l'image de la galerie EN GRAND, dans un vrai visionneur — pas
    seulement la vignette 96x56 de la page. Alex : « ouvrir directement
    image sur une fenetre pour voir image en plus gros [...] avoir le
    mettre sur une autre application » — une fenêtre séparée, pas un
    agrandissement dans la page elle-même.

    MÊME VALIDATION QUE act_fond_fichier, et pour la même raison : l'indice
    est REVALIDÉ contre une ré-énumération, jamais un chemin fourni par la
    page — voir son commentaire.

    ristretto est déjà le visionneur par défaut de LexOS pour image/png et
    image/jpeg (hook 0400) : on ouvre CELUI-LÀ, pas un outil nouveau.
    xdg-open en repli si ristretto manquait un jour (il est dans la liste
    OPTIONNELLE des paquets, jamais garanti).
    """
    if isinstance(arg, dict):
        i, nom = arg.get("i", -1), arg.get("nom", "")
    else:
        i, nom = arg, ""
    try:
        i = int(i)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "indice invalide"}
    fonds = _fonds_perso()
    if not (0 <= i < len(fonds)):
        return {"ok": False, "erreur": "image inconnue — pas dans la galerie"}
    chemin = fonds[i]
    if nom and Path(chemin).name != nom:
        return {"ok": False, "erreur":
                "la galerie a changé depuis l'affichage — rouvre la section"}
    if shutil.which("ristretto"):
        return _run(["ristretto", chemin], detach=True)
    if shutil.which("xdg-open"):
        return _run(["xdg-open", chemin], detach=True)
    return {"ok": False, "erreur": "aucun visionneur d'images installé (ristretto)"}


def act_fond_perso(arg):
    """Ouvre un sélecteur de fichier (zenity) puis applique l'image choisie.
    Le chemin vient du sélecteur local, pas de la page."""
    if shutil.which("zenity") is None:
        return {"ok": False, "erreur": "zenity absent"}
    r = subprocess.run(
        ["zenity", "--file-selection", "--title=Choisir un fond d'écran",
         "--file-filter=Images | *.jpg *.jpeg *.png *.webp *.avif *.bmp *.tif *.tiff *.gif"],
        capture_output=True, text=True, timeout=600)
    chemin = r.stdout.strip()
    if r.returncode != 0 or not chemin:
        return {"ok": False, "erreur": "Aucun fichier choisi"}
    #  « ajuster » par défaut : l'image entière sur fond noir (la demande
    #  d'Alex), au lieu d'une photo verticale recadrée à la bande du milieu.
    cadrage = arg if arg in CADRAGES else "ajuster"
    return _run(["lexos", "wallpaper", chemin, cadrage])


def act_langue(arg):
    if arg not in LANGUES:
        return {"ok": False, "erreur": "langue inconnue"}
    return _run(["lexos", "lang", arg])


def act_capture(arg):
    modes = {"photo": ["lexos-capture"], "zone": ["lexos-capture", "zone"],
             "fenetre": ["lexos-capture", "fenetre"]}
    argv = modes.get(arg)
    if argv is None:
        return {"ok": False, "erreur": "capture : photo|zone|fenetre"}
    return _run(argv, detach=True)


# =============================================================================
#  Les actions qui CHANGENT quelque chose pour de vrai.
#
#  Règle de la maison, sans exception : l'argument venu de la page est
#  comparé à un ensemble FERMÉ avant d'être utilisé. Jamais de chaîne
#  interpolée dans une commande, jamais de shell=True. La page ne peut donc
#  demander que ce qui est prévu ici — pas une commande de son choix.
# =============================================================================

def act_wifi(arg):
    """Allume ou éteint la radio Wi-Fi."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _wifi_etat()["radio"] == "enabled" else "on"
    return _run(["nmcli", "radio", "wifi", arg])


def act_wifi_auto(arg):
    """Connexion automatique aux réseaux ouverts — l'outil manquant.

    ALEX, PHOTO DES DEUX PAGES CÔTE À CÔTE : « il manque des outils, regarde
    la 2e image — la 2e image a plus d'outils sur le mode wi-fi ». La démo
    avait cette bascule, l'ISO ne l'avait pas, alors que c'est justement du
    côté de l'ISO qu'elle fait quelque chose de réel : lexos-net-autoconnect
    et son minuteur existent depuis longtemps, mais on ne pouvait les allumer
    qu'en ligne de commande.

    POURQUOI PKEXEC, ET POURQUOI « --confirme ». Le fichier d'état vit dans
    /etc : il faut les droits d'administration. « lexos net auto on » pose
    normalement une question sur le terminal (taper OUI) — depuis une fenêtre
    graphique il n'y a pas de terminal pour répondre, et le programme
    resterait bloqué. Le panneau pose donc la MÊME question dans une boîte de
    dialogue, puis passe « --confirme » pour dire qu'elle a été posée. On ne
    supprime pas l'avertissement : on le déplace là où l'utilisateur est.
    """
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _wifi_auto_lu() else "on"
    outil = shutil.which("lexos-net") or "/usr/bin/lexos-net"
    if not os.path.exists(outil):
        return {"ok": False, "erreur": "lexos-net introuvable"}
    argv = [outil, "auto", arg, "--confirme"]
    return _run_admin(argv)


def act_son_muet(arg):
    """Coupe ou rétablit le son."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    valeur = {"on": "1", "off": "0", "toggle": "toggle"}[arg]
    return _run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", valeur])


def act_son_volume(arg):
    """Règle le volume. Le curseur envoie un nombre : on le BORNE à 0-100
    avant de le transmettre. Sans cette borne, un « 400 » venu de la page
    monterait le gain bien au-delà du niveau du matériel — de la distorsion,
    et de quoi abîmer un haut-parleur."""
    if arg in ("moins", "plus"):
        return _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@",
                     "-5%" if arg == "moins" else "+5%"])
    try:
        n = int(arg)
    except (TypeError, ValueError):
        return {"ok": False, "erreur": "valeur inattendue"}
    n = max(0, min(100, n))
    return _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{n}%"])


def act_notif(arg):
    """Ne pas déranger."""
    if arg != "silence":
        return {"ok": False, "erreur": "valeur inattendue"}
    actuel = _notif_etat()["silence"]
    return _run(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb",
                 "-n", "-t", "bool", "-s", "false" if actuel else "true"])


def act_amovibles(arg):
    """Ce que LexOS fait quand on branche quelque chose. Le nom du réglage
    est cherché dans la table VOLMAN : la page ne peut pas désigner une clé
    xfconf de son choix."""
    if arg not in VOLMAN:
        return {"ok": False, "erreur": "valeur inattendue"}
    actuel = _amovibles_etat()[arg]
    return _run(["xfconf-query", "-c", "thunar-volman", "-p", VOLMAN[arg],
                 "-n", "-t", "bool", "-s", "false" if actuel else "true"])


def act_access(arg):
    """Deux réglages d'accessibilité qui se règlent sans redémarrer :
    le curseur large et le contraste élevé."""
    if arg == "curseur":
        grand = _access_etat()["curseurLarge"]
        return _run(["xfconf-query", "-c", "xsettings", "-p", "/Gtk/CursorThemeSize",
                     "-n", "-t", "int", "-s", "24" if grand else "48"])
    if arg == "contraste":
        fort = _access_etat()["contraste"]
        #  On revient au thème de LexOS plutôt qu'à un thème GTK quelconque :
        #  c'est celui que le reste du bureau attend.
        return _run(["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName",
                     "-n", "-t", "string",
                     "-s", "Adwaita-dark" if fort else "HighContrast"])
    if arg in ("orca", "onboard"):
        outil = {"orca": ["orca"], "onboard": ["onboard"]}[arg]
        return _run(outil, detach=True)
    return {"ok": False, "erreur": "valeur inattendue"}


def act_securite(arg):
    """Les outils d'autodéfense s'ouvrent dans un terminal : ils demandent
    tous les droits d'administration et posent des questions. Les lancer en
    silence derrière un interrupteur cacherait justement ce qu'il faut lire."""
    outils = {
        "pare-feu":  ("Pare-feu — LexOS", "lexos secure firewall"),
        "antivirus": ("Antivirus — LexOS", "lexos secure scan"),
        "rootkit":   ("Anti-rootkit — LexOS", "sudo rkhunter --check --sk"),
        "etat":      ("Sécurité — LexOS", "lexos secure"),
    }
    if arg not in outils:
        return {"ok": False, "erreur": "valeur inattendue"}
    return _terminal(*outils[arg])


def act_maj(arg):
    """Mises à jour. Tout passe par un terminal : une mise à jour pose des
    questions, prend du temps, et il faut pouvoir lire ce qui se passe.

    _terminal_suivi() (pas _terminal()) : ALEX voulait que la page se mette
    à jour au fur et à mesure en cliquant sur « Mises à jour » — avant, un
    clic ouvrait le terminal et la page n'en savait plus rien, boutons figés
    que ce soit fini, raté, ou encore en train de tourner. « arg » sert AUSSI
    de clé de suivi : les trois gestes ont chacun leur propre fichier de fin,
    donc lancer « Vérifier » puis « Tout mettre à jour » n'écrase pas le
    suivi de l'un avec celui de l'autre."""
    outils = {
        "verifier":  ("Mises à jour — LexOS", "lexos doctor"),
        "tout":      ("Mise à jour — LexOS", "lexos upgrade"),
        "firmware":  ("Micrologiciel — LexOS", "lexos firmware"),
    }
    if arg not in outils:
        return {"ok": False, "erreur": "valeur inattendue"}
    titre, commande = outils[arg]
    return _terminal_suivi(titre, commande, arg)


def act_usb(arg):
    """Les trois gestes de la démo, en vrai. « ejecter:/dev/sdb » démonte
    proprement ; le chemin est VÉRIFIÉ contre la liste des appareils
    réellement amovibles, jamais pris au mot. Sans ce contrôle, la page
    pourrait demander d'éjecter le disque système."""
    quoi, _, cible = str(arg).partition(":")
    if quoi == "vide-memoire":
        return _terminal("Vide mémoire — LexOS", "lexos vide-memoire")
    if quoi == "terminal":
        return _terminal("Terminal de l'appareil — LexOS", "lexos usb terminal")
    if quoi == "formater":
        return _terminal("Formater un support — LexOS", "lexos format")
    if quoi == "ejecter":
        connus = {a["dev"] for a in _usb_etat()}
        if cible not in connus:
            return {"ok": False, "erreur": "Appareil inconnu ou non amovible"}
        return _run(["udisksctl", "power-off", "-b", cible])
    return {"ok": False, "erreur": "valeur inattendue"}


def act_crt(arg):
    """Les effets de fenêtres « téléviseur 1980 » — « on », « off », « toggle ».

    CE QUI A CHANGÉ SOUS CETTE ACTION. Les effets étaient rendus par COMPIZ,
    retiré de Debian trixie : lexos-wm ne le trouvait plus et se repliait sur
    xfwm4, qui n'a AUCUNE animation. L'interrupteur de cette page a donc
    passé plusieurs images à ne rien commander — ALEX : « l'effet d'animation
    n'est pas là quand je ferme des fenêtres ». C'est picom qui fait le
    travail maintenant, piloté par lexos-crt.

    ON REFUSE D'ALLUMER CE QUI NE PEUT PAS MARCHER, avec le motif exact.
    Sans ce refus, le clic partirait, l'outil dirait « picom est trop ancien »
    dans une sortie que personne ne lit, et l'interrupteur reviendrait tout
    seul à sa place — le geste le plus déroutant qu'une page puisse offrir.
    """
    if not shutil.which("lexos-crt"):
        return {"ok": False, "erreur": "lexos-crt introuvable"}
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    e = _crt_etat()
    if arg == "toggle":
        arg = "off" if e.get("voulu") == "on" else "on"
    if arg == "on":
        if not e.get("picom"):
            return {"ok": False,
                    "erreur": "picom n'est pas installé : « lexos install picom »"}
        v, mini = e.get("picom_version", 0), e.get("picom_min", 12)
        if v and v < mini:
            return {"ok": False,
                    "erreur": "picom v%s est trop ancien : les animations "
                              "arrivent à la v%s" % (v, mini)}
        if not e.get("accel3d"):
            return {"ok": False,
                    "erreur": "pas d'accélération 3D réelle sur cette machine : "
                              "les effets resteraient saccadés"}
    return _run(["lexos-crt", arg])


def act_barre_cachee(arg):
    """Cacher ou montrer la barre du haut."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _barre_cachee() else "on"
    return _run(["xfconf-query", "-c", "xfce4-panel",
                 "-p", "/panels/panel-1/autohide-behavior",
                 "-n", "-t", "int", "-s", "1" if arg == "on" else "0"])


def act_bureaux(arg):
    """Ajouter ou enlever un bureau virtuel. Bornes : 1 au moins, 5 au plus —
    les mêmes que la démo, et que les raccourcis Super+1 … Super+5."""
    if arg not in ("plus", "moins"):
        return {"ok": False, "erreur": "valeur inattendue"}
    nb = _bureaux_etat()["nb"]
    nouveau = nb + 1 if arg == "plus" else nb - 1
    if nouveau < 1:
        return {"ok": False, "erreur": "Il faut garder au moins un bureau"}
    if nouveau > 5:
        return {"ok": False, "erreur": "5 bureaux au maximum"}
    return _run(["xfconf-query", "-c", "xfwm4", "-p", "/general/workspace_count",
                 "-n", "-t", "int", "-s", str(nouveau)])


def act_horloge(arg):
    """Régler l'horloge de la barre : 12/24 h, secondes, jour de la semaine.

    On ne compose plus la chaîne de format ici. C'est lexos-heure qui la
    construit, à partir de trois réponses par oui ou par non — et lui seul.
    Avant, cette fonction écrivait une chaîne « %H h %M » dans xfconf pendant
    que le script en aurait écrit une autre : deux endroits qui décident du
    même affichage finissent toujours par ne plus dire la même chose. Ici, la
    page pose une question, le script répond.

    Les trois clés et les deux valeurs sont des ensembles FERMÉS, vérifiés des
    deux côtés : rien de ce qui vient de la page ne sert à bâtir une commande.
    """
    if arg not in ("12h", "24h", "secondes", "jour"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if not shutil.which("lexos-heure"):
        return {"ok": False, "erreur": "lexos-heure absent"}

    etat_h = _heure_etat()
    if arg == "12h":
        cle, valeur = "h12", "oui"
    elif arg == "24h":
        cle, valeur = "h12", "non"
    elif arg == "secondes":
        cle, valeur = "secondes", "non" if etat_h["secondes"] else "oui"
    else:
        cle, valeur = "jour", "non" if etat_h["jour"] else "oui"
    return _run(["lexos-heure", "--regle", cle, valeur])


def act_fuseau_auto(arg):
    """Le fuseau horaire d'après la position.

    CE QU'ON NE FAIT PAS : deviner la position par l'adresse IP dans le dos
    de l'utilisateur. LexOS a déjà une position — celle que « lexos cartes »
    ou « lexos meteo » ont enregistrée parce qu'on la lui a DONNÉE. C'est
    celle-là qu'on utilise, et s'il n'y en a pas, on le dit au lieu
    d'interroger un service."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    return _run(["lexos-datetime", "fuseau-auto", arg])


#  LES TREIZE PROVINCES ET TERRITOIRES DU CANADA, EN FUSEAUX IANA. MÊME
#  LISTE que LIEUX_CANADA dans lexos-datetime — les deux doivent rester
#  d'accord, sinon un fuseau proposé ici et refusé là-bas (ou l'inverse)
#  serait un bouton qui ment. Chaque zone a été vérifiée pour de vrai
#  (Python, zoneinfo), jamais copiée de mémoire. La Saskatchewan, le
#  Yukon, les Territoires du Nord-Ouest et le Nunavut ont chacun leur
#  propre fuseau IANA (voir le commentaire de LIEUX_CANADA pour le
#  pourquoi) ; le Nouveau-Brunswick et l'Île-du-Prince-Édouard partagent
#  celui des Maritimes au chiffre près.
FUSEAUX_CANADA = {
    "America/Vancouver":  "Colombie-Britannique (Vancouver)",
    "America/Whitehorse": "Yukon (Whitehorse)",
    "America/Edmonton":   "Alberta (Edmonton)",
    "America/Yellowknife": "Territoires du Nord-Ouest (Yellowknife)",
    "America/Regina":     "Saskatchewan (Regina)",
    "America/Winnipeg":   "Manitoba (Winnipeg)",
    "America/Iqaluit":    "Nunavut (Iqaluit)",
    "America/Toronto":    "Ontario (Toronto)",
    "America/Montreal":   "Québec (Montréal)",
    "America/Halifax":    "Maritimes (Halifax)",
    "America/St_Johns":   "Terre-Neuve (St. John's)",
}


def act_fuseau(arg):
    """Change le fuseau horaire pour de vrai — pas seulement celui que suit
    la ville de la météo (act_fuseau_auto). « arg » est validé contre
    FUSEAUX_CANADA, un ensemble FERMÉ : jamais une chaîne de la page
    interpolée telle quelle dans une commande qui touche à l'horloge du
    système.

    pkexec, même schéma que act_heure_auto() : changer le fuseau demande
    les droits d'administration, et on veut la fenêtre de mot de passe
    habituelle plutôt qu'un échec muet."""
    if arg not in FUSEAUX_CANADA:
        return {"ok": False, "erreur": "valeur inattendue"}
    return _run_admin(["timedatectl", "set-timezone", arg])


def act_autocollant(arg):
    """Poser un personnage sur le fond d'écran, ou tout enlever. Les noms
    forment un ensemble fermé — le shell ne voit jamais la valeur brute."""
    if arg not in ("rock", "salut", "prevost", "enlever"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "enlever":
        return _run(["lexos-fond-ecran", "autocollant", "enlever"])
    return _run(["lexos-fond-ecran", "autocollant", "poser", arg])


def _geste_autocollant_etat():
    """Le geste « C + appui long » est-il armé, et peut-il l'être ?

    ABSENT = ALLUMÉ. Le fichier n'existe pas sur une session neuve, et le
    veilleur démarre quand même : c'est une fonction qu'on offre, pas qu'on
    fait demander. L'interrupteur sert à l'ÉTEINDRE — un geste qui capture une
    touche doit pouvoir se couper sans ouvrir un terminal.

    « xlib » n'est pas décoratif : sans python3-xlib le veilleur s'arrête
    aussitôt en le disant dans son journal, et personne ne lit un journal
    qu'on ne sait pas chercher. La page le dit à la place.
    """
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        actif = (conf / "geste-autocollant").read_text().strip() != "off"
    except OSError:
        actif = True
    try:
        import importlib.util
        xlib = importlib.util.find_spec("Xlib") is not None
    except Exception:
        xlib = False
    return {
        "actif": actif,
        "xlib": xlib,
        "veilleur": bool(shutil.which("lexos-sticker")),
    }


def _intro_etat():
    """La vidéo d'ouverture de session : quel réglage, et le son.

    ═══ POURQUOI LA PAGE DOIT SAVOIR SI mpv EST LÀ ═══
    mpv vit dans 20-desktop.list, une liste OPTIONNELLE que le hook 0250
    pose en tolérant l'échec. Sans lui, lexos-intro sort en silence — c'est
    voulu, une session ne se bloque pas pour une vidéo. Mais quelqu'un qui
    choisit « complète » et ne voit jamais rien mérite mieux qu'un réglage
    qui ment : la page le dit.
    """
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"

    def lu(nom, defaut, permis):
        try:
            v = (conf / nom).read_text().strip()
        except OSError:
            return defaut
        return v if v in permis else defaut

    marque = Path("/usr/share/lexos/branding")
    return {
        #  « courte » au départ : 3,5 s partagées avec le chargement du
        #  bureau, contre 10 s pour la complète.
        "choix": lu("intro-video", "courte", ("courte", "complete", "aucune")),
        #  ═══ LE SON EST COUPÉ AU DÉPART ═══
        #  Un son à chaque ouverture de session est une décision de vie, pas
        #  un détail : le jour où on ouvre son portable dans une salle
        #  d'attente, on s'en souvient. L'option existe, elle n'est pas
        #  allumée d'office.
        "son": lu("intro-son", "off", ("on", "off")) == "on",
        "mpv": bool(shutil.which("mpv")),
        #  ═══ LES NOMS SONT CEUX DES FICHIERS JOUÉS, PAS DE LA SOURCE ═══
        #  branding/apres-connexion.mp4 est le CARRÉ déposé par Alex : une
        #  source de construction, effacée du chroot une fois le 1920 × 1080
        #  fabriqué. Regarder ce nom-là dirait « la vidéo est là » sur une
        #  ISO construite sans ffmpeg, où rien n'est jouable. On regarde donc
        #  exactement les deux fichiers que lexos-intro ouvre.
        "fichiers": (marque / "apres-connexion-16-9-courte.mp4").exists()
                    and (marque / "apres-connexion-16-9.mp4").exists(),
    }


def act_intro(arg):
    """Choisir la vidéo d'ouverture, ou allumer son son.

    « courte » · « complete » · « aucune » pour la vidéo ; « son » bascule
    le son. Rien d'autre n'est accepté : ce qui s'écrit dans le fichier est
    relu par lexos-intro à chaque ouverture de session.
    """
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    if arg == "son":
        nouveau = "off" if _intro_etat()["son"] else "on"
        cible, valeur = "intro-son", nouveau
    elif arg in ("courte", "complete", "aucune"):
        cible, valeur = "intro-video", arg
    else:
        return {"ok": False, "erreur": "valeur inattendue"}
    try:
        conf.mkdir(parents=True, exist_ok=True)
        (conf / cible).write_text(valeur + "\n", encoding="utf-8")
    except OSError as err:
        return {"ok": False, "erreur": "réglage non enregistré : %s" % err}
    return {"ok": True}


def act_geste_autocollant(arg):
    """Armer ou désarmer le geste « C + appui long » sur une image.

    ON ÉCRIT LE FICHIER **AVANT** D'AGIR SUR LE VEILLEUR, et l'ordre compte :
    le veilleur relit ce fichier une fois par seconde et s'arrête tout seul
    quand il vaut « off ». Si on le tuait d'abord, un veilleur relancé entre
    les deux (par une autre session, par un autostart) repartirait sur
    l'ancien état.

    L'ARRÊT NE PASSE PAS PAR pkill : on écrit « off » et on laisse le veilleur
    sortir de lui-même, parce que c'est LUI qui sait lever ses captures de
    touche. Un veilleur tué en plein vol laisserait « c » inutilisable dans le
    gestionnaire de fichiers jusqu'à la fin de la session — la panne qu'on ne
    retrouve jamais. Il a bien un gestionnaire de SIGTERM, mais on ne s'en sert
    que comme filet, pas comme moyen normal.
    """
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    etat = _geste_autocollant_etat()
    if arg == "toggle":
        arg = "off" if etat["actif"] else "on"
    if arg == "on" and not etat["xlib"]:
        return {"ok": False,
                "erreur": "python3-xlib n'est pas installé — le geste ne peut pas s'armer"}

    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        conf.mkdir(parents=True, exist_ok=True)
        (conf / "geste-autocollant").write_text(arg + "\n", encoding="utf-8")
    except OSError as err:
        return {"ok": False, "erreur": "réglage non enregistré : %s" % err}

    if arg == "on":
        #  Relancer tout de suite : sans ça, allumer l'interrupteur ne ferait
        #  effet qu'à la session suivante, et l'utilisateur essaierait le geste
        #  en vain juste après l'avoir demandé.
        return _run(["/usr/lib/lexos/geste-autocollant"], detach=True)
    return {"ok": True}


def act_coin(arg):
    """Le coin haut-gauche ouvre la vue d'ensemble, comme sous Ubuntu."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _apercu_etat()["coin"] else "on"
    return _run(["lexos-apercu", "coin", arg])


def act_super_apercu(arg):
    """La touche Super seule ouvre la vue d'ensemble. Super+1…5 continuent
    d'aller aux bureaux : c'est xcape qui fait la différence."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _apercu_etat()["super"] else "on"
    return _run(["lexos-apercu", "super", arg])


def act_apercu(arg):
    """Ouvre la vue d'ensemble tout de suite — le bouton « Voir mes bureaux ».
    detach : c'est une fenêtre, elle vit sa vie."""
    return _run(["lexos-apercu", "ouvrir"], detach=True)


def act_bureau_va(arg):
    """Aller à un bureau donné. Le numéro est borné, jamais interpolé."""
    if not str(arg).isdigit():
        return {"ok": False, "erreur": "valeur inattendue"}
    n = max(0, min(4, int(arg)))
    return _run(["wmctrl", "-s", str(n)])


def act_bluetooth(arg):
    """Allume ou éteint la radio Bluetooth."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        actuel = _bluetooth_etat()
        if actuel is None:
            return {"ok": False, "erreur": "Aucun contrôleur Bluetooth"}
        arg = "off" if actuel else "on"
    return _run(["bluetoothctl", "power", arg])


def act_energie_dim_batterie(arg):
    """Abaisser ou non la luminosité quand le secteur est débranché."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    actif = _energie_etat()["dimBat"]
    if arg == "toggle":
        arg = "off" if actif else "on"
    niveau = "40" if arg == "on" else "100"
    return _run(["xfconf-query", "-c", "xfce4-power-manager",
                 "-p", "/xfce4-power-manager/brightness-on-battery",
                 "-n", "-t", "int", "-s", niveau])


def act_energie_delai(arg):
    """« ecranOff:10 » ou « veille:30 » — en minutes, 0 pour jamais.
    Le nom du réglage est cherché dans une table FERMÉE : la page ne peut pas
    désigner une clé xfconf de son choix."""
    cles = {"ecranOff": ("blank-on-ac", "blank-on-battery"),
            "veille": ("inactivity-on-ac", "inactivity-on-battery")}
    quoi, _, valeur = str(arg).partition(":")
    if quoi not in cles or not valeur.isdigit():
        return {"ok": False, "erreur": "valeur inattendue"}
    minutes = max(0, min(600, int(valeur)))
    dernier = {"ok": False, "erreur": "xfconf-query absent"}
    for prop in cles[quoi]:
        dernier = _run(["xfconf-query", "-c", "xfce4-power-manager",
                        "-p", f"/xfce4-power-manager/{prop}",
                        "-n", "-t", "int", "-s", str(minutes)])
    return dernier


def act_ecran_definition(arg):
    """Changer la définition d'un écran.

    L'argument arrive de la page sous la forme « SORTIE|DÉFINITION ». Les
    deux moitiés sont vérifiées contre ce que la MACHINE déclare — la liste
    des sorties branchées et, pour celle qu'on vise, la liste de ses
    définitions. Une définition qu'un écran ne sait pas afficher donne un
    écran noir ; c'est la seule erreur de ce panneau qui laisse quelqu'un
    incapable de revenir en arrière, alors elle ne doit pas être possible."""
    if not isinstance(arg, str) or arg.count("|") != 1:
        return {"ok": False, "erreur": "valeur inattendue"}
    sortie, definition = arg.split("|", 1)
    for e in _ecrans_etat():
        if e["nom"] == sortie and definition in e["modes"]:
            return _run(["xrandr", "--output", sortie, "--mode", definition])
    return {"ok": False, "erreur": "définition inconnue pour cet écran"}


def act_echelle(arg):
    """La taille du texte et des éléments. Voir _echelle_etat pour le choix
    de Xft/DPI plutôt que d'un agrandissement d'image."""
    if arg not in ECHELLES:
        return {"ok": False, "erreur": "valeur inattendue"}
    return _run(["xfconf-query", "-c", "xsettings", "-p", "/Xft/DPI",
                 "-n", "-t", "int", "-s", str(ECHELLES[arg])])


def act_wifi_connecter(arg):
    """Se connecter à un réseau Wi-Fi.

    LE NOM DU RÉSEAU EST VÉRIFIÉ CONTRE CE QUE LA MACHINE VOIT VRAIMENT, pas
    seulement contre un motif : on ne se connecte qu'à un réseau qui figure
    dans le balayage en cours. C'est la même discipline que pour les sorties
    audio et les définitions d'écran — un ensemble fermé, construit par la
    machine, jamais par la page.

    Le mot de passe, lui, ne peut pas être vérifié contre quoi que ce soit :
    c'est un secret. Il n'est donc JAMAIS écrit dans un journal, jamais
    renvoyé à la page, et il part dans une LISTE d'arguments — subprocess ne
    voit pas de shell, donc aucun caractère ne peut devenir une commande.
    """
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    ssid = str(arg.get("ssid", "")).strip()
    mot = str(arg.get("mot_de_passe", ""))
    if not ssid:
        return {"ok": False, "erreur": "il faut choisir un réseau"}
    if not shutil.which("nmcli"):
        return {"ok": False, "erreur": "nmcli absent"}

    connus = {r["ssid"] for r in _wifi_reseaux()}
    if ssid not in connus:
        return {"ok": False,
                "erreur": "ce réseau n'est plus à portée — relance la recherche"}
    if len(mot) > 128:
        return {"ok": False, "erreur": "mot de passe trop long"}

    argv = ["nmcli", "device", "wifi", "connect", ssid]
    if mot:
        argv += ["password", mot]
    try:
        #  45 s : une association Wi-Fi plus un bail DHCP prennent parfois
        #  vingt secondes sur une borne encombrée. Trop court, on annoncerait
        #  un échec à une connexion en train de réussir.
        r = subprocess.run(argv, capture_output=True, text=True, timeout=45)
    except subprocess.TimeoutExpired:
        return {"ok": False, "erreur": "la connexion n'a pas abouti à temps"}
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    if r.returncode == 0:
        return {"ok": True}

    #  LE MESSAGE D'ERREUR EST NETTOYÉ AVANT D'ÊTRE MONTRÉ. nmcli répète
    #  parfois la commande complète dans sa plainte — mot de passe compris.
    detail = (r.stderr or r.stdout or "").strip()
    if mot and mot in detail:
        detail = detail.replace(mot, "••••••")
    bas = detail.lower()
    if "secrets were required" in bas or "802-11-wireless-security" in bas \
            or "invalid password" in bas:
        detail = "Mot de passe refusé."
    return {"ok": False, "erreur": detail[:300] or "connexion refusée"}


def act_wifi_deconnecter(arg):
    """Se déconnecter du réseau Wi-Fi actif.

    ALEX, PHOTO À L'APPUI : « quand je suis connecté sur le wi-fi, il dit
    pas de déconnecter une fois connecté — là je suis connecté à BELL507
    mais il dit pas déconnecter ». La page montrait bien « connecté » sur la
    ligne du réseau actif, mais RIEN à cliquer : pour se déconnecter il
    fallait passer par le terminal. Le Bluetooth, dans la même fenêtre, a
    son bouton « Déconnecter » depuis toujours (act_bt_deconnecter) — deux
    poids, deux mesures dans une seule page.

    AUCUN NOM NE VIENT DE LA PAGE, ET C'EST VOULU. Se déconnecter, c'est
    « coupe la connexion Wi-Fi EN COURS » : la machine sait déjà laquelle,
    par « nmcli device status » (voir _wifi_etat). On ne prend donc aucun
    argument — ni SSID, ni nom d'appareil. Rien de ce que la page envoie ne
    peut désigner une AUTRE connexion (le câble, un VPN), parce que la page
    n'envoie rien du tout. C'est plus fort que valider une chaîne.

    L'appareil est trouvé exactement comme dans « lexos net disconnect » —
    le premier appareil de type « wifi » à l'état « connected ».
    """
    if not shutil.which("nmcli"):
        return {"ok": False, "erreur": "nmcli absent"}
    appareil = ""
    for ligne in _sortie(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE",
                          "device", "status"]).splitlines():
        champs = _terse(ligne)
        if len(champs) >= 3 and champs[1] == "wifi" and champs[2] == "connected":
            appareil = champs[0]
            break
    if not appareil:
        return {"ok": False, "erreur": "aucune connexion Wi-Fi active"}
    try:
        #  20 s : couper est bien plus rapide qu'associer (pas de DHCP à
        #  attendre), mais NetworkManager peut prendre son temps à ranger
        #  la connexion. Court, mais pas au point d'annoncer un échec sur
        #  une déconnexion en train de réussir.
        r = subprocess.run(["nmcli", "device", "disconnect", appareil],
                           capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return {"ok": False, "erreur": "la déconnexion n'a pas abouti à temps"}
    except (subprocess.SubprocessError, OSError) as e:
        return {"ok": False, "erreur": str(e)}
    if r.returncode == 0:
        return {"ok": True}
    detail = (r.stderr or r.stdout or "").strip()
    return {"ok": False, "erreur": detail[:300] or "déconnexion refusée"}


def act_bt_connecter(arg):
    """Se connecter à un appareil Bluetooth — ou l'appairer s'il est nouveau.

    L'ADRESSE EST VÉRIFIÉE CONTRE CE QUE LE CONTRÔLEUR A VU, comme le SSID
    Wi-Fi contre le balayage : un ensemble fermé construit par la machine.
    Pour un appareil déjà appairé, « connect » suffit. Pour un nouveau, il
    faut « pair » d'abord — une barre de son n'a pas d'écran pour afficher un
    code, le trust+pair direct est exactement ce que fait l'appairage simple.
    """
    adresse = str(arg or "").strip().upper()
    if not shutil.which("bluetoothctl"):
        return {"ok": False, "erreur": "bluetoothctl absent"}
    connus = {d["adresse"].upper(): d for d in _bluetooth_appareils()}
    if adresse not in connus:
        return {"ok": False, "erreur": "appareil inconnu — relance la recherche"}
    d = connus[adresse]
    if not d["appaire"]:
        r = subprocess.run(["bluetoothctl", "pair", adresse],
                           capture_output=True, text=True, timeout=45)
        if r.returncode != 0:
            return {"ok": False,
                    "erreur": "l'appairage a échoué — mets l'appareil en mode "
                              "appairage et réessaie"}
        subprocess.run(["bluetoothctl", "trust", adresse],
                       capture_output=True, text=True, timeout=15)
    r = subprocess.run(["bluetoothctl", "connect", adresse],
                       capture_output=True, text=True, timeout=45)
    if r.returncode == 0:
        return {"ok": True}
    return {"ok": False, "erreur": (r.stderr or r.stdout or "connexion refusée").strip()[:200]}


def act_bt_deconnecter(arg):
    """Couper la connexion, sans désappairer : l'appareil reste connu."""
    adresse = str(arg or "").strip().upper()
    if not shutil.which("bluetoothctl"):
        return {"ok": False, "erreur": "bluetoothctl absent"}
    connus = {d["adresse"].upper() for d in _bluetooth_appareils()}
    if adresse not in connus:
        return {"ok": False, "erreur": "appareil inconnu"}
    return _run(["bluetoothctl", "disconnect", adresse])


def act_bt_chercher(arg):
    """Balayer pendant douze secondes, puis rendre la main.

    « bluetoothctl scan on » ne se termine JAMAIS tout seul : c'est un
    processus qui écoute. Lancé tel quel depuis le pont, il resterait pendu
    et la page attendrait sans fin. « --timeout 12 » borne l'écoute : douze
    secondes suffisent à une barre de son en mode appairage pour se montrer,
    et la main revient toujours.

    « ALEX, IL NE TROUVE RIEN ». Ce que ce code faisait jusqu'ici : lancer
    bluetoothctl, IGNORER son code de sortie, et répondre {"ok": True} dans
    tous les cas où le processus n'a pas planté au sens Python du terme.
    Un contrôleur éteint, un « scan on » refusé (« org.bluez.Error.InProgress »,
    « NotReady »…) — tout ça se terminait aussi par {"ok": True}, et
    « Recherche terminée » s'affichait pendant qu'aucune recherche n'avait eu
    lieu. La page ne trouvait rien, et rien ne disait pourquoi.
    Corrigé sur le même modèle que _run() : on regarde le code de retour ET
    ce que bluetoothctl a dit sur sa sortie, pour rendre une vraie erreur au
    lieu d'un succès qui n'en était pas un.
    """
    del arg
    if not shutil.which("bluetoothctl"):
        return {"ok": False, "erreur": "bluetoothctl absent"}
    try:
        r = subprocess.run(["bluetoothctl", "--timeout", "12", "scan", "on"],
                            capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired:
        return {"ok": False,
                "erreur": "bluetoothctl n'a pas rendu la main — contrôleur bloqué"}
    except OSError as e:
        return {"ok": False, "erreur": str(e)}
    if r.returncode != 0:
        sortie = (r.stdout or r.stderr or "").strip()
        motif = sortie.splitlines()[-1].strip() if sortie else ""
        if not motif:
            motif = f"bluetoothctl a échoué (code {r.returncode})"
        return {"ok": False, "erreur": motif}
    return {"ok": True}


def act_wifi_rechercher(arg):
    """Relancer un balayage, à la demande.

    Séparé de l'affichage exprès : ouvrir la fenêtre ne doit pas déclencher
    une recherche complète — elle coupe brièvement la connexion en cours et
    prend trois secondes. Quand on cherche un réseau qui vient d'apparaître,
    en revanche, on veut pouvoir le demander.
    """
    del arg
    if not shutil.which("nmcli"):
        return {"ok": False, "erreur": "nmcli absent"}
    return _run(["nmcli", "device", "wifi", "rescan"], timeout=30)


def act_distant_partage(arg):
    """Démarrer ou arrêter le partage de cet écran.

    LE DÉMARRAGE PASSE PAR UN TERMINAL, ET C'EST VOULU. lexos-distant DEMANDE
    un mot de passe — il n'y en a pas par défaut, jamais. Le lancer en tâche
    de fond laisserait la question sans personne pour y répondre, et le
    partage ne démarrerait pas, sans dire pourquoi. L'arrêt, lui, ne demande
    rien : il peut partir directement."""
    if arg not in ("on", "off"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if not shutil.which("lexos-distant"):
        return {"ok": False, "erreur": "lexos-distant absent"}
    if arg == "off":
        return _run(["lexos-distant", "arreter"])
    return _terminal("Partager cet écran — LexOS", "lexos distant partager")


def act_distant_vers(arg):
    """Se connecter à une autre machine.

    L'adresse vient de la page, donc elle est vérifiée AVANT tout usage : on
    n'accepte que ce qui ressemble à une adresse — lettres, chiffres, points,
    tirets, deux-points pour le port, arobase pour « compte@machine ». Rien
    d'autre ne passe, et de toute façon subprocess reçoit une liste : même
    une adresse tordue ne peut pas devenir une commande.

    Le protocole est un ensemble fermé ; « auto » laisse lexos-distant
    deviner RDP ou VNC d'après le port, ce qu'il sait déjà faire."""
    if not isinstance(arg, dict):
        return {"ok": False, "erreur": "requête invalide"}
    protocole = arg.get("protocole", "auto")
    adresse = str(arg.get("adresse", "")).strip()
    if protocole not in ("auto", "rdp", "vnc", "ssh"):
        return {"ok": False, "erreur": "protocole inattendu"}
    if not adresse or len(adresse) > 120:
        return {"ok": False, "erreur": "il faut une adresse"}
    if not all(c.isalnum() or c in ".-:@_[]" for c in adresse):
        return {"ok": False, "erreur": "adresse invalide"}

    if protocole == "ssh":
        #  SSH est un terminal : il lui faut une fenêtre, et il demandera
        #  peut-être un mot de passe.
        return _terminal(f"SSH — {adresse}", f"lexos distant ssh {adresse}")
    commande = "vers" if protocole == "auto" else protocole
    return _run(["lexos-distant", commande, adresse], detach=True)


def act_capture_format(arg):
    """PNG (sans perte, le texte reste net) ou JPEG (plus léger)."""
    if arg not in ("png", "jpeg"):
        return {"ok": False, "erreur": "valeur inattendue"}
    return _run(["lexos-capture", "format", arg])


def act_son_sortie(arg):
    """Envoyer le son vers une autre sortie — les haut-parleurs, le casque,
    la télé en HDMI, ou une enceinte Bluetooth.

    LA VALIDATION, ET POURQUOI ELLE EST FAITE AINSI. Le nom vient de la page,
    donc on ne lui fait pas confiance. Mais on ne peut pas non plus le
    comparer à une liste écrite d'avance : les sorties dépendent de la
    machine et de ce qui est branché À CET INSTANT. L'ensemble fermé est
    donc celui que la machine déclare elle-même, relu au moment du clic —
    un nom absent de cette liste est refusé, et rien ne part vers un shell.

    Les flux DÉJÀ EN COURS sont déplacés eux aussi : sans ça, la musique
    continuerait sur les haut-parleurs pendant que le réglage annonce le
    cinéma maison. Personne ne comprendrait, et on aurait raison."""
    connues = {s["nom"] for s in _sorties_audio()}
    if arg not in connues:
        return {"ok": False, "erreur": "sortie inconnue"}

    r = _run(["pactl", "set-default-sink", arg])
    if not r.get("ok"):
        return r

    #  Déplacer ce qui joue déjà. Un flux qui refuse n'est pas une panne :
    #  certains (les bips système) meurent avant qu'on les rattrape.
    for ligne in _sortie(["pactl", "list", "short", "sink-inputs"]).splitlines():
        champs = ligne.split("\t")
        if champs and champs[0].isdigit():
            _run(["pactl", "move-sink-input", champs[0], arg])
    return {"ok": True}


def act_souris(arg):
    """Bascule un réglage du pavé tactile (tape-pour-cliquer, défilement
    naturel). Le chemin xfconf est reconstruit ICI depuis l'état lu, jamais
    reçu de la page — sinon la page pourrait écrire n'importe quelle clé."""
    if arg not in ("tape", "inverse"):
        return {"ok": False, "erreur": "valeur inattendue"}
    s = _souris_etat()
    if not s["pave"]:
        return {"ok": False, "erreur": "Aucun pavé tactile détecté"}
    cle = {"tape": "libinput_Tapping_Enabled",
           "inverse": "libinput_Natural_Scrolling_Enabled"}[arg]
    nouveau = "false" if s[arg] else "true"
    return _run(["xfconf-query", "-c", "pointers",
                 "-p", f"{s['pave']}/Properties/{cle}",
                 "-n", "-t", "bool", "-s", nouveau])


def act_heure_auto(arg):
    """Synchronisation automatique de l'heure (NTP)."""
    if arg not in ("on", "off", "toggle"):
        return {"ok": False, "erreur": "valeur inattendue"}
    if arg == "toggle":
        arg = "off" if _heure_etat()["auto"] else "on"
    #  _run_admin plutôt que pkexec en direct : quand aucun agent
    #  d'authentification ne tourne, pkexec échoue SANS FENÊTRE ET SANS
    #  MESSAGE, et le bouton paraît mort. Le motif est rendu à la page.
    return _run_admin(["timedatectl", "set-ntp", arg])


def _clavier_cle_connue(cle):
    """La clé est-elle dans le catalogue que lexos-clavier publie ?

    CE QUE CE CONTRÔLE FAIT, ET CE QU'IL NE FAIT PAS — parce que la première
    version de ce commentaire se vantait de trop. Il n'empêche AUCUNE
    injection : _run() reçoit une LISTE d'arguments, il n'y a pas de shell,
    et « ; rm -rf / » ne serait jamais qu'un nom de disposition farfelu passé
    à lexos-clavier, qui le refuserait. Dire l'inverse aurait fait croire à
    une protection qui vit ailleurs.

    Ce qu'il fait vraiment : refuser au niveau des Paramètres, avec un motif
    QUI NOMME LE CATALOGUE, plutôt que de lancer un programme pour rien et de
    renvoyer son message à lui. La page peut alors dire à l'utilisateur que
    la disposition n'existe pas, ce qui est l'information utile.
    """
    e = _clavier_etat()
    return any(c.get("cle") == cle for c in e.get("catalogue", []))


def _clavier_bascule_connue(cle):
    e = _clavier_etat()
    return any(b.get("cle") == cle for b in e.get("bascules", []))


def _defaut_choix_connu(categorie, appli):
    """Cette application est-elle proposée pour cette catégorie ?

    Ce qu'il fait, et ce qu'il ne fait pas : il n'empêche aucune injection —
    _run() reçoit une liste d'arguments, il n'y a pas de shell. Il refuse au
    niveau des Paramètres, avec un motif qui nomme la catégorie, plutôt que
    de lancer un programme pour rien.
    """
    for c in _defaut_etat().get("categories", []):
        if c.get("cle") != categorie:
            continue
        return any(x.get("id") == appli for x in c.get("choix", []))
    return False


def act_defaut(arg):
    """Choisir l'application par défaut d'une catégorie — « categorie:appli »."""
    if not shutil.which("lexos-defaut"):
        return {"ok": False, "erreur": "lexos-defaut introuvable"}
    categorie, _, appli = (arg or "").partition(":")
    if not categorie or not appli:
        return {"ok": False, "erreur": "il faut une catégorie et une application"}
    if not _defaut_choix_connu(categorie, appli):
        return {"ok": False,
                "erreur": "« %s » n'est pas proposée pour « %s »" % (appli, categorie)}
    return _run(["lexos-defaut", categorie, appli])


def _recherche_etat():
    """De quoi la recherche dispose sur cette machine.

    LA PAGE DISAIT : « LexOS n'indexe pas le disque en tâche de fond ». C'est
    vrai — plocate n'est pas livré — mais elle s'arrêtait là, sans dire ce qui
    en découle : la recherche par NOM lit cet index et ne fonctionne donc pas
    tant que plocate n'est pas installé, alors que la recherche par CONTENU
    marche tout de suite. Deux recherches, deux états, et un seul mot pour les
    deux.
    """
    vide = {"plocate": False, "index": False, "index_jours": -1,
            "catfish": False, "max": 0, "dispo": False}
    if not shutil.which("lexos-recherche"):
        return vide
    try:
        r = subprocess.run(["lexos-recherche", "--json"],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if "plocate" not in d:
        return vide
    d["dispo"] = True
    return d


#  Les recherches qui n'attendent aucun mot : le titre de la fenêtre, et les
#  arguments de lexos-recherche. Une table plutôt qu'une cascade de « if » —
#  ce que la page peut demander se lit d'un coup d'œil.
_RECHERCHE_SANS_MOT = {
    "gros":     ("Les plus gros fichiers — LexOS", ["gros"]),
    "recent":   ("Fichiers récents — LexOS", ["recent"]),
    "doublons": ("Fichiers en double — LexOS", ["doublons"]),
    "index":    ("Reconstruire l'index — LexOS", None),
}


def act_recherche(arg):
    """Chercher — « nom:<mot> », « contenu:<mot> », « gros: », « recent: »,
    « doublons: », « index: », « fenetre: ».

    POURQUOI UN TERMINAL PLUTÔT QUE LA PAGE. Une recherche rend des dizaines
    de lignes de chemins, qu'on veut pouvoir relire, copier et faire défiler.
    Les recopier dans un panneau de réglages serait refaire un terminal en
    moins bien. La page sert à LANCER la bonne commande sans avoir à la
    connaître — c'est le travail d'une page de réglages, pas d'un afficheur.

    Le mot cherché est du texte libre : il entre dans une chaîne qu'un shell
    redécoupe, donc il est cité par shlex.quote. On refuse d'abord ce qui ne
    peut rien donner : un mot vide, ou plus long qu'une ligne.
    """
    if not shutil.which("lexos-recherche"):
        return {"ok": False, "erreur": "lexos-recherche introuvable"}
    e = _recherche_etat()
    quoi, _, mot = (arg or "").partition(":")

    if quoi in ("nom", "contenu", "fenetre"):
        mot = mot.strip()
        if not mot and quoi != "fenetre":
            return {"ok": False, "erreur": "il faut un mot à chercher"}
        if len(mot) > 200:
            return {"ok": False, "erreur": "ce mot est trop long"}
        if quoi == "nom" and not e.get("plocate"):
            return {"ok": False,
                    "erreur": "la recherche par nom lit l'index de plocate, "
                              "qui n'est pas installé : « lexos install plocate »"}
        if quoi == "nom" and not e.get("index"):
            return {"ok": False,
                    "erreur": "l'index n'a jamais été construit — « Reconstruire l'index » d'abord"}
        if quoi == "fenetre":
            if not e.get("catfish"):
                return {"ok": False,
                        "erreur": "catfish n'est pas installé : « lexos install catfish »"}
            return _run(["lexos-recherche", "fenetre"] + ([mot] if mot else []),
                        detach=True)
        return _terminal("Recherche — LexOS",
                         "lexos-recherche %s %s" % (quoi, shlex.quote(mot)))

    if quoi in _RECHERCHE_SANS_MOT:
        titre, args = _RECHERCHE_SANS_MOT[quoi]
        if quoi == "index":
            #  updatedb parcourt tout le disque et écrit dans /var/lib : c'est
            #  le seul geste de cette page qui demande les droits
            #  d'administrateur, et lexos-recherche ne s'élève pas de lui-même.
            if not e.get("plocate"):
                return {"ok": False,
                        "erreur": "plocate n'est pas installé : « lexos install plocate »"}
            return _terminal(titre, "sudo lexos-recherche index")
        return _terminal(titre, "lexos-recherche " + " ".join(args))

    return {"ok": False, "erreur": "geste inattendu"}


def act_comptes(arg):
    """Les comptes en ligne — « monter:<nom> », « demonter:<nom> »,
    « ajouter:<service> », « retirer:<nom> ».

    DEUX GESTES AGISSENT TOUT DE SUITE, DEUX PASSENT PAR UN TERMINAL, et ce
    n'est pas arbitraire : monter et démonter ne posent aucune question, alors
    qu'« ajouter » lance « rclone config », qui interroge et ouvre le
    navigateur pour l'autorisation, et que « retirer » exige une confirmation.
    Ces deux-là n'ont nulle part où poser leur question dans une page web.

    Les noms viennent de ce que l'outil publie — un compte qui existe, un
    service du catalogue — parce que deux d'entre eux entrent dans une
    commande de terminal, c'est-à-dire dans une chaîne qu'un shell redécoupe.
    Ils y sont cités par shlex.quote en plus.
    """
    if not shutil.which("lexos-comptes"):
        return {"ok": False, "erreur": "lexos-comptes introuvable"}
    e = _comptes_etat()
    if not e.get("dispo"):
        return {"ok": False, "erreur": "lexos-comptes n'a pas répondu"}
    quoi, _, valeur = (arg or "").partition(":")
    comptes = {c.get("nom"): c for c in e.get("comptes", [])}

    if quoi == "ajouter":
        if not e.get("rclone"):
            return {"ok": False,
                    "erreur": "rclone n'est pas installé : « lexos install rclone »"}
        if valeur not in [x.get("cle") for x in e.get("services", [])]:
            return {"ok": False, "erreur": "« %s » n'est pas un service connu" % valeur}
        return _terminal("Relier un compte — LexOS",
                         "lexos-comptes ajouter %s" % shlex.quote(valeur))

    if valeur not in comptes:
        return {"ok": False, "erreur": "« %s » n'est pas un compte relié" % valeur}
    if quoi == "monter":
        if comptes[valeur].get("monte"):
            return {"ok": False, "erreur": "« %s » est déjà ouvert" % valeur}
        return _run(["lexos-comptes", "monter", valeur])
    if quoi == "demonter":
        if not comptes[valeur].get("monte"):
            return {"ok": False, "erreur": "« %s » n'est pas ouvert" % valeur}
        return _run(["lexos-comptes", "demonter", valeur])
    if quoi == "retirer":
        return _terminal("Retirer un compte — LexOS",
                         "lexos-comptes retirer %s" % shlex.quote(valeur))
    return {"ok": False, "erreur": "geste inattendu"}


def act_bienetre(arg):
    """Le bien-être numérique — « compteur:on|off », « limite:<min>|off »,
    « pauses:on|off », « nuit:on|off », « oublier: ».

    Rien ici ne demande les droits d'administrateur : lexos-bienetre n'écrit
    que dans le dossier de la personne connectée, et démarre ou arrête des
    programmes de sa propre session. La page agit donc directement.

    ON REFUSE D'ALLUMER CE QUI N'EST PAS LÀ, avec un motif que la page peut
    montrer : workrave et redshift ne sont pas livrés avec LexOS. Sans ce
    refus, le clic partirait, l'outil dirait « n'est pas installé » dans une
    sortie que personne ne lit, et l'interrupteur reviendrait tout seul à sa
    place — le geste le plus déroutant qui soit.
    """
    if not shutil.which("lexos-bienetre"):
        return {"ok": False, "erreur": "lexos-bienetre introuvable"}
    quoi, _, valeur = (arg or "").partition(":")
    e = _bienetre_etat()
    if quoi == "compteur":
        if valeur not in ("on", "off"):
            return {"ok": False, "erreur": "il faut « on » ou « off »"}
        return _run(["lexos-bienetre", "demarrer" if valeur == "on" else "arreter"])
    if quoi == "limite":
        if valeur == "off":
            return _run(["lexos-bienetre", "limite", "off"])
        if not valeur.isdigit() or not (1 <= int(valeur) <= 1440):
            return {"ok": False,
                    "erreur": "la limite est un nombre de minutes entre 1 et 1440, ou « off »"}
        return _run(["lexos-bienetre", "limite", valeur])
    if quoi in ("pauses", "nuit"):
        if valeur not in ("on", "off"):
            return {"ok": False, "erreur": "il faut « on » ou « off »"}
        installe = e.get("pauses_installe" if quoi == "pauses" else "nuit_installe")
        if valeur == "on" and not installe:
            programme = "workrave" if quoi == "pauses" else "redshift"
            return {"ok": False,
                    "erreur": "%s n'est pas installé : « lexos install %s »"
                              % (programme, programme)}
        return _run(["lexos-bienetre", quoi, valeur])
    if quoi == "oublier":
        #  ═══ CELUI-CI PASSE PAR UN TERMINAL, ET IL LE FAUT ═══
        #  « lexos-bienetre oublier » demande de TAPER le mot « effacer »
        #  avant de supprimer quoi que ce soit. Lancé sans terminal, ce
        #  « read » échoue, la réponse reste vide, l'outil répond « Annulé. »
        #  — et rend 0. Le moteur aurait donc annoncé « ok », la page aurait
        #  affiché « Historique effacé », et rien n'aurait été effacé. Un
        #  succès annoncé pour une action qui n'a pas eu lieu est pire que
        #  l'échec : on ne recommence pas.
        return _terminal("Effacer l'historique — LexOS", "lexos-bienetre oublier")
    return {"ok": False, "erreur": "geste inattendu"}


def act_terminal(arg):
    """Le mode du terminal — « mode:<jour|nuit|auto|suivre> » ou « horaire:HH:MM-HH:MM ».

    ICI, PAS DE TERMINAL À OUVRIR : lexos-terminal n'écrit que dans le dossier
    de configuration de la personne connectée, il ne demande aucun droit
    d'administrateur. La page agit donc directement, et le changement est
    instantané — les fenêtres déjà ouvertes se repeignent.

    L'HEURE EST VÉRIFIÉE ICI AUSSI, et pas seulement par l'outil : la page
    doit pouvoir dire « ce n'est pas une heure » plutôt que d'afficher le
    message brut d'un programme.
    """
    if not shutil.which("lexos-terminal"):
        return {"ok": False, "erreur": "lexos-terminal introuvable"}
    quoi, _, valeur = (arg or "").partition(":")
    if quoi == "mode":
        if valeur not in ("jour", "nuit", "auto", "suivre"):
            return {"ok": False, "erreur": "mode inattendu"}
        return _run(["lexos-terminal", valeur])
    if quoi == "horaire":
        debut, _, fin = valeur.partition("-")
        for h in (debut, fin):
            if not re.fullmatch(r"([01][0-9]|2[0-3]):[0-5][0-9]", h or ""):
                return {"ok": False,
                        "erreur": "il faut deux heures au format HH:MM (00:00 à 23:59)"}
        if debut == fin:
            return {"ok": False,
                    "erreur": "le début et la fin du jour ne peuvent pas être la même heure"}
        return _run(["lexos-terminal", "horaire", debut, fin])
    return {"ok": False, "erreur": "geste inattendu"}


def act_partage(arg):
    """Changer le nom de la machine — « nom:<nouveau> ».

    Comme pour les comptes, le geste ouvre un TERMINAL : changer le nom touche
    à /etc/hostname ET à /etc/hosts, il faut les droits d'administrateur, et
    lexos-share ne s'élève pas de lui-même. La commande est écrite en toutes
    lettres sous les yeux de qui tape son mot de passe.

    La règle du nom est celle que l'outil publie (RFC 1123) : on ne la recopie
    pas ici. On refuse AVANT d'ouvrir la fenêtre — un terminal qui s'ouvre
    pour mourir aussitôt ressemble à une panne.
    """
    e = _partage_etat()
    if not e.get("dispo"):
        return {"ok": False,
                "erreur": ("lexos-share n'a pas répondu"
                           if shutil.which("lexos-share")
                           else "lexos-share introuvable")}
    quoi, _, valeur = (arg or "").partition(":")
    if quoi != "nom":
        return {"ok": False, "erreur": "geste inattendu"}
    if not valeur:
        return {"ok": False, "erreur": "il faut un nom de machine"}
    regex = e.get("nom_regex") or ""
    #  re.fullmatch, pas re.match : en Python « $ » accepte un retour à la
    #  ligne final, et « poste\n » se retrouverait cité dans la commande.
    if not regex or not re.fullmatch(regex, valeur):
        return {"ok": False,
                "erreur": "nom de machine invalide : lettres, chiffres et "
                          "« - » seulement, 63 caractères au plus, et pas de "
                          "« - » au début ni à la fin"}
    if valeur == e.get("nom"):
        return {"ok": False, "erreur": "la machine s'appelle déjà « %s »" % valeur}
    return _terminal("Nom de la machine — LexOS",
                     "sudo lexos-share nom %s" % shlex.quote(valeur))


#  LES GESTES SUR LES COMPTES, ET LA COMMANDE QUE CHACUN LANCE.
#  Écrits ici une fois, plutôt qu'en cascade de « if » : la table dit d'un
#  coup d'œil ce que la page peut demander, et rien d'autre ne peut passer.
#  La valeur est le titre de la fenêtre et les arguments de lexos-utilisateurs
#  — « {} » sera remplacé par le nom du compte, cité.
_UTIL_GESTES = {
    "motdepasse":    ("Mot de passe — LexOS",      ["motdepasse"]),
    "admin-on":      ("Droits d'administrateur — LexOS", ["admin", "{}", "on"]),
    "admin-off":     ("Droits d'administrateur — LexOS", ["admin", "{}", "off"]),
    "verrouiller":   ("Verrouiller un compte — LexOS",   ["verrouiller"]),
    "deverrouiller": ("Déverrouiller un compte — LexOS", ["deverrouiller"]),
    "supprimer":     ("Supprimer un compte — LexOS",     ["supprimer"]),
}


def act_utilisateur(arg):
    """Agir sur un compte — « geste:nom ».

    TOUT CE QUI TOUCHE AUX COMPTES PASSE PAR UN TERMINAL, ET C'EST VOULU.
    Ces gestes demandent les droits d'administrateur, et lexos-utilisateurs
    ne s'élève JAMAIS de lui-même : « un outil qui s'élève tout seul habitue à
    taper son mot de passe sans lire ce qui va s'exécuter » (son propre
    commentaire). La page ouvre donc un terminal où la commande est écrite en
    toutes lettres, et où la personne tape son mot de passe en la voyant.

    C'est aussi la seule façon qui marche : adduser pose des questions,
    passwd lit un mot de passe qui ne s'affiche pas, et « supprimer » fait
    RECOPIER le nom du compte avant d'effacer. Rien de tout cela ne peut se
    faire dans une fenêtre qui n'a pas de clavier.

    CE QUI EST VÉRIFIÉ ICI, ET POURQUOI ICI. La commande part dans une chaîne
    que xfce4-terminal découpe comme un shell — ce n'est PAS le cas de _run(),
    qui reçoit une liste. Un nom de compte venu de la page ne peut donc pas y
    entrer sans contrôle. Deux verrous, dans cet ordre :
      1. le nom doit être un compte QUI EXISTE, tel que l'outil le publie
         (ou, pour « ajouter », respecter la règle d'adduser qu'il publie) ;
      2. il est cité par shlex.quote avant d'entrer dans la commande.
    Le premier suffirait ; le second existe parce qu'une liste de comptes est
    un ensemble qui peut grandir, et qu'on ne veut pas que la sûreté de cette
    ligne dépende de ce qui a le droit de s'appeler un compte.
    """
    e = _utilisateurs_etat()
    if not e.get("dispo"):
        #  DEUX PANNES DIFFÉRENTES, DEUX MESSAGES. « Introuvable » quand
        #  l'outil n'est pas là ; « n'a pas répondu » quand il est là mais
        #  que sa sortie est inutilisable. Dire « introuvable » d'un
        #  programme installé envoie chercher au mauvais endroit.
        return {"ok": False,
                "erreur": ("lexos-utilisateurs n'a pas répondu"
                           if shutil.which("lexos-utilisateurs")
                           else "lexos-utilisateurs introuvable")}
    geste, _, reste = (arg or "").partition(":")
    comptes = {c.get("nom"): c for c in e.get("comptes", [])}

    #  ═══ CRÉER UN COMPTE ═══ le seul nom qui ne doit PAS déjà exister.
    if geste == "ajouter":
        regex = e.get("nom_regex") or ""
        if not reste:
            return {"ok": False, "erreur": "il faut un nom de compte"}
        if reste in comptes:
            return {"ok": False, "erreur": "« %s » existe déjà" % reste}
        #  La règle est celle d'adduser, publiée par l'outil : on ne la
        #  recopie pas ici. Sans elle, on n'ouvre pas de terminal du tout —
        #  un terminal qui s'ouvre pour mourir aussitôt ressemble à une panne.
        #  re.fullmatch, PAS re.match. En Python, « $ » accepte un retour à
        #  la ligne final : « marie\n » passe re.match(« ^…$ ») et se
        #  retrouverait cité dans la commande du terminal. fullmatch exige
        #  que TOUTE la chaîne soit consommée, retour à la ligne compris.
        if not regex or not re.fullmatch(regex, reste):
            return {"ok": False,
                    "erreur": "nom de compte invalide : minuscules, chiffres, "
                              "« - » et « _ », en commençant par une lettre"}
        return _terminal("Créer un compte — LexOS",
                         "sudo lexos-utilisateurs ajouter %s" % shlex.quote(reste))

    #  ═══ LA CONNEXION AUTOMATIQUE ═══ « off » n'est pas un compte.
    if geste == "auto":
        if reste != "off" and reste not in comptes:
            return {"ok": False, "erreur": "« %s » n'est pas un compte de cette machine" % reste}
        if not e.get("lightdm"):
            return {"ok": False,
                    "erreur": "LightDM n'est pas installé : la connexion "
                              "automatique ne se règle que pour lui"}
        return _terminal("Connexion automatique — LexOS",
                         "sudo lexos-utilisateurs auto-connexion %s" % shlex.quote(reste))

    #  ═══ LE NOM AFFICHÉ ═══ deux morceaux : le compte, puis le texte libre.
    if geste == "nom-complet":
        nom, _, plein = reste.partition(":")
        if nom not in comptes:
            return {"ok": False, "erreur": "« %s » n'est pas un compte de cette machine" % nom}
        if not plein.strip():
            return {"ok": False, "erreur": "il faut un nom à afficher"}
        #  On ne rejoue PAS ici la règle du champ GECOS (ni virgule, ni
        #  deux-points, ni signe égal) : elle vit dans lexos-utilisateurs, qui
        #  la dira dans le terminal, sous les yeux de la personne. La citer
        #  ici en ferait une deuxième copie, à tenir à jour pour rien.
        return _terminal("Nom affiché — LexOS",
                         "sudo lexos-utilisateurs nom-complet %s %s"
                         % (shlex.quote(nom), shlex.quote(plein.strip())))

    #  ═══ LES GESTES SUR UN COMPTE EXISTANT ═══
    if geste not in _UTIL_GESTES:
        return {"ok": False, "erreur": "geste inattendu"}
    if reste not in comptes:
        return {"ok": False, "erreur": "« %s » n'est pas un compte de cette machine" % reste}

    #  DEUX REFUS QUI ÉVITENT UN TERMINAL POUR RIEN. lexos-utilisateurs
    #  refuse déjà ces deux-là — c'est sa seule interdiction dure — mais il le
    #  fait APRÈS avoir ouvert une fenêtre et demandé un mot de passe. Le
    #  dire tout de suite est plus honnête, et la page peut l'afficher.
    dernier_admin = comptes[reste].get("admin") and e.get("nb_admins", 0) <= 1
    if geste in ("admin-off", "supprimer", "verrouiller") and dernier_admin:
        return {"ok": False,
                "erreur": "« %s » est le seul administrateur : sans lui, cette "
                          "machine ne peut plus être administrée depuis le bureau" % reste}
    if geste == "supprimer" and comptes[reste].get("moi"):
        return {"ok": False,
                "erreur": "« %s » est le compte ouvert en ce moment : on ne "
                          "supprime pas la branche sur laquelle on est assis" % reste}

    titre, gabarit = _UTIL_GESTES[geste]
    args = [a.replace("{}", reste) if a == "{}" else a for a in gabarit]
    if "{}" not in gabarit:
        args = args + [reste]
    return _terminal(titre, "sudo lexos-utilisateurs "
                     + " ".join(shlex.quote(a) for a in args))


def act_clavier(arg):
    """Changer la disposition du clavier — « quoi:clé ».

    Quatre gestes, tous rendus par lexos-clavier :
      dabord:<clé>   la mettre en premier, c'est-à-dire celle du démarrage
      ajouter:<clé>  en ajouter une deuxième (quatre au maximum, limite de X)
      retirer:<clé>  en enlever une
      bascule:<clé>  quelles touches passent de l'une à l'autre
    """
    if not shutil.which("lexos-clavier"):
        return {"ok": False, "erreur": "lexos-clavier introuvable"}
    quoi, _, cle = (arg or "").partition(":")
    if quoi not in ("dabord", "ajouter", "retirer", "bascule"):
        return {"ok": False, "erreur": "geste inattendu"}
    if not cle:
        return {"ok": False, "erreur": "aucune disposition donnée"}
    verifie = _clavier_bascule_connue if quoi == "bascule" else _clavier_cle_connue
    if not verifie(cle):
        return {"ok": False, "erreur": "« %s » n'est pas dans le catalogue" % cle}
    return _run(["lexos-clavier", quoi, cle])


ACTIONS = {
    "ouvrir": act_ouvrir,
    "clavier": act_clavier,
    "defaut-appli": act_defaut,
    "utilisateur": act_utilisateur,
    "partage-nom": act_partage,
    "terminal-mode": act_terminal,
    "bienetre": act_bienetre,
    "comptes": act_comptes,
    "recherche": act_recherche,
    "wifi-radio": act_wifi,
    "wifi-auto": act_wifi_auto,
    "son-muet": act_son_muet,
    "son-volume": act_son_volume,
    "son-sortie": act_son_sortie,
    "ecran-definition": act_ecran_definition,
    "echelle": act_echelle,
    "bt-connecter": act_bt_connecter,
    "bt-deconnecter": act_bt_deconnecter,
    "bt-chercher": act_bt_chercher,
    "wifi-connecter": act_wifi_connecter,
    "wifi-deconnecter": act_wifi_deconnecter,
    "wifi-rechercher": act_wifi_rechercher,
    "distant-partage": act_distant_partage,
    "distant-vers": act_distant_vers,
    "capture-format": act_capture_format,
    "souris": act_souris,
    "bluetooth-radio": act_bluetooth,
    "crt": act_crt,
    "usb": act_usb,
    "amovibles": act_amovibles,
    "notif": act_notif,
    "access": act_access,
    "securite": act_securite,
    "maj": act_maj,
    "barre-cachee": act_barre_cachee,
    "bureaux": act_bureaux,
    "horloge": act_horloge,
    "fuseau-auto": act_fuseau_auto,
    "fuseau": act_fuseau,
    "autocollant": act_autocollant,
    "coin": act_coin,
    "intro": act_intro,
    "geste-autocollant": act_geste_autocollant,
    "super_apercu": act_super_apercu,
    "apercu": act_apercu,
    "bureau-va": act_bureau_va,
    "energie-dim-batterie": act_energie_dim_batterie,
    "energie-delai": act_energie_delai,
    "heure-auto": act_heure_auto,
    "avion": act_avion,
    "perf": act_perf,
    "lumiere": act_lumiere,
    "theme": act_theme,
    "accent": act_accent,
    "police": act_police,
    "dock": act_dock,
    "fond": act_fond,
    "fond-perso": act_fond_perso,
    "fond-fichier": act_fond_fichier,
    "fond-ouvrir": act_fond_ouvrir,
    "fond-capture": act_fond_capture,
    "langue": act_langue,
    "capture": act_capture,
}


# =============================================================================
#  État — ce que la page affiche au chargement.
# =============================================================================

def _sortie(argv, *, timeout=10):
    #  Le délai par défaut suffit à tout ce qui lit la machine ; le balayage
    #  Wi-Fi, lui, peut prendre plus de dix secondes sur une borne encombrée —
    #  d'où le paramètre.
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


# =============================================================================
#  Lire l'état RÉEL de la machine.
#
#  Pourquoi ces fonctions existent : les sections des Paramètres n'étaient que
#  des boutons « ouvrir l'outil complet ». On voyait la liste des réglages,
#  jamais leur VALEUR — impossible de savoir si le Wi-Fi était allumé sans
#  ouvrir un terminal. Un panneau de réglages qui ne dit pas l'état des choses
#  n'est pas un panneau de réglages, c'est un menu de raccourcis.
#
#  Chacune de ces fonctions ne fait que LIRE, ne lève jamais, et renvoie une
#  valeur neutre quand l'outil manque : une machine sans batterie ou sans
#  pactl ne doit pas casser la page, juste afficher moins de choses.
# =============================================================================

def _wifi_auto_lu():
    """La connexion automatique aux réseaux ouverts est-elle activée ?

    Une seule vérité : le fichier que lexos-net écrit et que
    lexos-net-autoconnect relit avant de faire quoi que ce soit. Le panneau
    ne tient pas son propre compte — c'est comme ça qu'on se retrouve avec un
    interrupteur qui dit « allumé » et un service qui ne fait rien.
    """
    try:
        with open("/etc/lexos/wifi-auto-open", encoding="utf-8") as f:
            return f.read().strip() == "on"
    except OSError:
        return False


def _wifi_etat():
    """Radio Wi-Fi allumée ? réseau connecté ? force du signal ?"""
    if not shutil.which("nmcli"):
        return {"radio": "absent", "reseau": "", "signal": 0,
                "auto": _wifi_auto_lu(), "internet": "absent"}
    #  « -t » (terse) donne des mots-clés fixes, jamais traduits — la sortie
    #  normale de nmcli suit la langue du système (fr_CA sur LexOS).
    radio = _sortie(["nmcli", "-t", "radio", "wifi"]) or "absent"
    #  PHOTO D'ALEX : « il dit que je ne suis pas connecté, mais je le suis ».
    #  LE RÉSEAU CONNECTÉ VIENT DE L'ÉTAT DE L'APPAREIL (« device status »),
    #  PAS D'UN BALAYAGE DE BORNES (« device wifi ») comme avant. Un balayage
    #  est un instantané des bornes VUES, pas de la connexion ACTIVE — les
    #  deux peuvent diverger (balayage pas encore relancé depuis la vraie
    #  connexion, borne provisoirement absente du dernier passage…), et
    #  c'est cette différence qui affichait « Aucun » alors que
    #  networkmanager, lui, savait très bien qu'il était connecté. « device
    #  status » répond exactement à la question posée : CET appareil, est-il
    #  connecté, à quoi ? Pas de rapport avec le bogue du split() nu plus
    #  bas dans _wifi_reseaux() (un SSID avec « : » dedans) — deux bogues
    #  différents sur deux commandes différentes, réglés chacun à sa place.
    reseau, signal = "", 0
    for ligne in _sortie(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION",
                          "device", "status"]).splitlines():
        champs = _terse(ligne)
        if len(champs) >= 4 and champs[1] == "wifi" and champs[2] == "connected":
            reseau = champs[3]
            break
    #  Le signal ne vient QUE du balayage — l'état de l'appareil ne le
    #  connaît pas. On cherche la borne du même nom dans le dernier
    #  balayage ; à défaut (pas encore vue), 0 plutôt qu'un chiffre inventé.
    if reseau:
        for ligne in _sortie(["nmcli", "-t", "-f", "SSID,SIGNAL",
                              "device", "wifi"]).splitlines():
            champs = _terse(ligne)
            if len(champs) >= 2 and champs[0] == reseau:
                signal = int(champs[1]) if champs[1].isdigit() else 0
                break
    #  « connectivity » distingue les deux pannes qu'on confond toujours :
    #  « full » = on passe ; « limited » ou « portal » = on est CONNECTÉ mais
    #  rien ne passe (portail d'hôtel, box sans internet) ; « none » = pas de
    #  réseau du tout. C'est cette différence que dit la couleur du
    #  pictogramme dans la colonne de gauche — vert, orange, rouge.
    internet = _sortie(["nmcli", "-t", "networking", "connectivity"]) or "unknown"
    return {"radio": radio, "reseau": reseau, "signal": signal,
            "auto": _wifi_auto_lu(), "internet": internet,
            "reseaux": _wifi_reseaux(reseau) if radio == "enabled" else []}


def _terse(ligne):
    """Découper une ligne « nmcli -t », en respectant ses échappements.

    IL FAUT VRAIMENT CE BOUT DE CODE. nmcli sépare ses champs par « : » et
    échappe donc en « \\: » les deux-points qui se trouvent DANS une valeur.
    Un simple split(":") coupe alors « Chez Léa : 5G » en deux et affiche un
    réseau qui n'existe pas — pendant que le vrai reste introuvable.
    """
    champs, courant, echappe = [], "", False
    for c in ligne:
        if echappe:
            courant += c
            echappe = False
        elif c == "\\":
            echappe = True
        elif c == ":":
            champs.append(courant)
            courant = ""
        else:
            courant += c
    champs.append(courant)
    return champs


def _wifi_reseaux(connecte=""):
    """Les réseaux à portée, du plus fort au plus faible.

    « connecte » EST LE NOM DU RÉSEAU RÉELLEMENT CONNECTÉ, tel que
    _wifi_etat() vient de l'établir. Voir plus bas pourquoi cette fonction ne
    le déduit plus elle-même.

    CE QUI MANQUAIT. Le panneau savait dire « connecté » ou « aucun », et
    rien d'autre : sans réseau, il fallait deviner qu'un bouton ouvrait un
    autre outil. Or au premier démarrage il n'y a JAMAIS de réseau — et sans
    réseau, ni météo, ni catalogue, ni mises à jour. C'est le premier geste
    qu'on fait sur une machine neuve, et c'était le seul qu'on ne pouvait pas
    faire ici.

    « --rescan auto » laisse nmcli décider : il ne relance une recherche que
    si son cache est vieux. Forcer un balayage à chaque ouverture de fenêtre
    coûterait trois secondes et couperait brièvement la connexion en cours.
    """
    if not shutil.which("nmcli"):
        return []
    lignes = _sortie(["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY",
                      "device", "wifi", "list", "--rescan", "auto"],
                     timeout=25)
    par_nom = {}
    for ligne in lignes.splitlines():
        ch = _terse(ligne)
        if len(ch) < 4:
            continue
        actif, ssid, signal, securite = ch[0], ch[1], ch[2], ch[3]
        #  Un réseau caché n'a pas de nom à afficher : on ne peut ni le
        #  montrer ni s'y connecter d'un clic. Il reste joignable par
        #  « lexos wifi », qui sait demander le nom.
        if not ssid:
            continue
        #  ═══ CE RÉSEAU EST-IL LE RÉSEAU CONNECTÉ ? ═══
        #  ALEX : « une fois connecté à un réseau internet, il n'affiche pas
        #  pour se déconnecter. » Le bouton Déconnecter EXISTE : la page le
        #  dessine dès que la ligne est marquée active. Elle ne l'était
        #  jamais.
        #
        #  LE MÊME CORRECTIF AVAIT DÉJÀ ÉTÉ FAIT — À MOITIÉ. Le haut de la
        #  page disait autrefois « aucun réseau » alors qu'Alex était
        #  connecté ; _wifi_etat() a été réparé en lisant « device status »
        #  (l'état de l'APPAREIL) au lieu du balayage des bornes. La leçon
        #  était écrite noir sur blanc dans son commentaire : un balayage est
        #  un instantané des bornes VUES, pas de la connexion ACTIVE.
        #
        #  Cette fonction-ci, elle, est restée sur le balayage : elle jugeait
        #  « connecté » sur le champ ACTIVE de « device wifi list ». D'où la
        #  photo d'Alex — le haut de la page affiche « Réseau connecté :
        #  BELL507 », et trois centimètres plus bas la même borne propose
        #  « Se connecter ». Deux réponses contradictoires dans une seule
        #  fenêtre, parce que deux sources différentes.
        #
        #  On prend donc la MÊME source de vérité que le haut de la page : le
        #  nom du réseau connecté, établi par « device status ». Le champ
        #  ACTIVE reste en second recours — s'il dit vrai, tant mieux ; s'il
        #  se tait (le cas d'Alex), le nom tranche. Deux signaux valent mieux
        #  qu'un quand l'un a déjà prouvé qu'il pouvait manquer.
        est_actif = (bool(connecte) and ssid == connecte) or actif == "yes"
        force = int(signal) if signal.isdigit() else 0
        #  Une borne peut émettre en 2,4 GHz ET en 5 GHz sous le même nom :
        #  deux lignes, un seul réseau aux yeux de celui qui regarde. On garde
        #  la plus forte.
        ancien = par_nom.get(ssid)
        if ancien is None or force > ancien["signal"]:
            par_nom[ssid] = {"ssid": ssid, "signal": force,
                             "protege": bool(securite.strip()),
                             "securite": securite.strip(),
                             "actif": est_actif}
        elif est_actif:
            ancien["actif"] = True
    return sorted(par_nom.values(),
                  key=lambda r: (not r["actif"], -r["signal"]))


def _son_etat():
    """Volume en pour-cent et sourdine, via PipeWire/PulseAudio."""
    if not shutil.which("pactl"):
        return {"volume": -1, "muet": False}
    volume = -1
    sortie = _sortie(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
    for morceau in sortie.replace("/", " ").split():
        if morceau.endswith("%") and morceau[:-1].isdigit():
            volume = int(morceau[:-1])
            break
    muet = _sortie(["pactl", "get-sink-mute", "@DEFAULT_SINK@"]).endswith("yes")
    return {"volume": volume, "muet": muet, "casque": _casque_branche(),
            "sorties": _sorties_audio()}


def _sorties_audio():
    """Toutes les sorties audio de la machine, et laquelle reçoit le son.

    POURQUOI CETTE LISTE MANQUAIT, ET CE QUE ÇA COÛTAIT. Le panneau montrait
    le volume et la sourdine — mais jamais OÙ le son sortait. Alex a un
    cinéma maison : sans cette liste, aucun moyen de lui envoyer le son
    depuis LexOS, ni d'en revenir. Il fallait ouvrir le mélangeur PulseAudio,
    donc savoir qu'il existe.

    Un haut-parleur Bluetooth appairé APPARAÎT ICI TOUT SEUL : PipeWire en
    fait une sortie comme une autre dès qu'il est connecté. C'est pour ça
    qu'on ne traite pas le sans-fil à part — ce serait une deuxième liste qui
    finirait par ne plus dire la même chose que celle-ci.

    Le NOM technique (« alsa_output.pci-0000_00_1f.3.analog-stereo ») ne va
    pas à l'écran : on montre la description que donne le pilote (« Haut-
    parleurs », « LG Sound Bar »). Mais c'est le nom technique qui sert à
    basculer — et il est vérifié contre CETTE liste avant tout usage."""
    if not shutil.which("pactl"):
        return []
    defaut = _sortie(["pactl", "get-default-sink"]).strip()
    sorties = []
    #  « short » donne une ligne par sortie, colonnes séparées par tabulation :
    #  index, nom, pilote, format, état. On veut la deuxième.
    for ligne in _sortie(["pactl", "list", "short", "sinks"]).splitlines():
        champs = ligne.split("\t")
        if len(champs) >= 2 and champs[1]:
            sorties.append({"nom": champs[1], "titre": champs[1], "actif": champs[1] == defaut})

    #  La description lisible vit dans la sortie longue. On la récupère en
    #  deuxième passe plutôt que de tout analyser d'un bloc : si ce format
    #  change un jour, on perd les jolis noms, pas la liste.
    nom_courant = ""
    for ligne in _sortie(["pactl", "list", "sinks"]).splitlines():
        depouillee = ligne.strip()
        if depouillee.startswith("Name:"):
            nom_courant = depouillee.split(":", 1)[1].strip()
        elif depouillee.startswith("Description:") and nom_courant:
            desc = depouillee.split(":", 1)[1].strip()
            for sortie in sorties:
                if sortie["nom"] == nom_courant and desc:
                    sortie["titre"] = desc
            nom_courant = ""
    return sorties


def _batterie_etat():
    """Charge et source d'alimentation. Une tour n'a pas de batterie : on
    renvoie alors -1, et la page n'affiche simplement pas la ligne."""
    niveau, secteur = -1, True
    base = PSU_DIR
    try:
        for d in sorted(base.glob("BAT*")):
            try:
                niveau = int((d / "capacity").read_text().strip())
                break
            except (OSError, ValueError):
                continue
        for d in sorted(base.glob("A*")):          # ADP*, AC*
            try:
                secteur = (d / "online").read_text().strip() == "1"
                break
            except OSError:
                continue
    except OSError:
        pass
    return {"niveau": niveau, "secteur": secteur}


def _ecrans_probleme():
    """Pourquoi la liste des écrans est vide — quand elle l'est.

    LA PANNE SIGNATURE DE CE PROJET, DANS SA FORME LA PLUS PURE.
    _ecrans_etat() rendait une liste vide sans un mot quand xrandr manquait.
    La fenêtre s'ouvrait, la section Écrans s'affichait, et elle était vide :
    pas d'erreur, pas d'explication, l'air de dire « tu n'as aucun écran » —
    sur une machine à quatre écrans allumés.

    Promouvoir le paquet (fait : x11-xserver-utils est passé en obligatoire)
    règle le cas d'aujourd'hui. Faire PARLER le code règle tous les autres :
    une session Wayland, un xrandr retiré à la main, une machine sans serveur
    graphique. Une section vide qui explique pourquoi vaut infiniment mieux
    qu'une section vide.

    Rend une chaîne vide quand tout va bien — l'appelant n'affiche alors rien.
    """
    if os.environ.get("XDG_SESSION_TYPE") == "wayland":
        return ("Session Wayland : xrandr ne sait pas lire ses écrans. "
                "LexOS ouvre XFCE en X11 — vérifie la session choisie à la connexion.")
    if not shutil.which("xrandr"):
        return ("L'outil qui lit les écrans (xrandr) n'est pas installé : "
                "impossible de lister les écrans. Paquet : x11-xserver-utils.")
    if not os.environ.get("DISPLAY"):
        return ("Aucune session graphique ouverte (DISPLAY est vide) : "
                "xrandr n'a pas d'écran à interroger.")
    return ""


def _ecrans_etat():
    """Les sorties vidéo BRANCHÉES, avec leur définition courante."""
    ecrans = []
    if not shutil.which("xrandr"):
        return ecrans
    for ligne in _sortie(["xrandr", "--query"]).splitlines():
        if " connected" not in ligne:
            continue
        mots = ligne.split()
        nom = mots[0]
        definition = ""
        for m in mots:
            #  « 1920x1080+0+0 » — la géométrie active, s'il y en a une.
            if "x" in m and "+" in m and m[0].isdigit():
                definition = m.split("+")[0]
                break
        ecrans.append({"nom": nom, "definition": definition,
                       "principal": "primary" in mots, "modes": []})

    #  LES DÉFINITIONS POSSIBLES, écran par écran. Elles ne s'inventent pas :
    #  chaque dalle a sa liste, et proposer une définition qu'un écran ne sait
    #  pas afficher donne un écran noir — la panne la plus effrayante qui soit
    #  pour qui ne sait pas que Ctrl+Alt+F2 existe. On lit donc CE QUE
    #  L'ÉCRAN DÉCLARE, et rien d'autre.
    #
    #  Dans « xrandr --query », les définitions d'une sortie sont les lignes
    #  INDENTÉES qui la suivent, jusqu'à la sortie suivante.
    courant = None
    for ligne in _sortie(["xrandr", "--query"]).splitlines():
        if ligne and not ligne[0].isspace():
            mots = ligne.split()
            courant = mots[0] if (" connected" in ligne) else None
            continue
        if courant is None:
            continue
        mots = ligne.split()
        if mots and "x" in mots[0] and mots[0][0].isdigit():
            for e in ecrans:
                if e["nom"] == courant and mots[0] not in e["modes"]:
                    e["modes"].append(mots[0])
    return ecrans


#  Les tailles d'affichage proposées. 96 points par pouce est la valeur de
#  référence de X11 — « 100 % » n'est donc pas un chiffre rond arbitraire,
#  c'est cette référence. Ensemble FERMÉ : la page ne peut pas en demander
#  d'autre.
ECHELLES = {"100": 96, "125": 120, "150": 144, "175": 168, "200": 192}


def _image_etat():
    """Les deux autres « qualités d'image » : celle des captures d'écran et
    celle du fond animé. Chacune vit dans son propre outil — on ne fait que
    lire le même fichier que lui, pour que les Paramètres et le terminal ne
    puissent pas se contredire."""
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        capture = (conf / "capture-format").read_text().strip()
    except OSError:
        capture = "png"
    if capture not in ("png", "jpeg"):
        capture = "png"
    #  Il y avait ici une « qualité du fond animé » : elle ne réglait que le
    #  décodage du fond vidéo, retiré avec les fonds animés. Un réglage qui
    #  ne pilote plus rien est un bouton qui ment — on l'enlève aussi.
    return {"capture": capture}


def _echelle_etat():
    """La taille du texte et des éléments, en pourcentage.

    POURQUOI Xft/DPI ET PAS « xrandr --scale ». Les deux agrandissent, mais
    pas de la même façon : xrandr redimensionne l'IMAGE une fois dessinée —
    tout devient flou, y compris le texte. Xft/DPI dit aux applications de
    dessiner plus grand dès le départ : le texte reste net. Sur une dalle
    d'ordinateur portable, c'est toute la différence entre « lisible » et
    « pâteux ».

    XFCE range ça dans les XSettings, donc xfsettingsd l'applique à chaud."""
    v = _xfconf_lire("xsettings", "/Xft/DPI")
    try:
        dpi = int(v)
    except (TypeError, ValueError):
        dpi = 96
    #  On rend le pourcentage le PLUS PROCHE : une machine réglée à la main
    #  sur 110 doit s'afficher comme « 100 % » plutôt que comme rien du tout.
    proche = min(ECHELLES.items(), key=lambda kv: abs(kv[1] - dpi))
    return {"pourcent": proche[0], "dpi": dpi}


def _souris_etat():
    """Réglages du pavé tactile, lus dans xfconf (là où XFCE les garde)."""
    def prop(chemin, defaut=False):
        if not shutil.which("xfconf-query"):
            return defaut
        v = _sortie(["xfconf-query", "-c", "pointers", "-p", chemin])
        return v == "true" if v in ("true", "false") else defaut

    #  Le nom du périphérique fait partie du chemin xfconf et varie d'une
    #  machine à l'autre : on cherche le premier qui ressemble à un pavé.
    pave = ""
    if shutil.which("xfconf-query"):
        for p in _sortie(["xfconf-query", "-c", "pointers", "-l"]).splitlines():
            bas = p.lower()
            if "touchpad" in bas or "synaptics" in bas or "trackpad" in bas:
                pave = "/" + p.strip("/").split("/")[0]
                break
    if not pave:
        return {"pave": "", "tape": False, "inverse": False}
    return {"pave": pave,
            "tape": prop(f"{pave}/Properties/libinput_Tapping_Enabled"),
            "inverse": prop(f"{pave}/Properties/libinput_Natural_Scrolling_Enabled")}


def _bluetooth_etat():
    """La radio Bluetooth est-elle allumée ? « Powered: yes » dans la sortie
    de bluetoothctl. Renvoie None quand la machine n'a pas de Bluetooth du
    tout — la page n'affiche alors pas l'interrupteur plutôt que d'en montrer
    un qui ne servirait à rien."""
    if not shutil.which("bluetoothctl"):
        return None
    sortie = _sortie(["bluetoothctl", "show"])
    if not sortie:
        return None
    for ligne in sortie.splitlines():
        if ligne.strip().startswith("Powered:"):
            return ligne.split(":", 1)[1].strip() == "yes"
    return None


def _bluetooth_complet():
    allume = _bluetooth_etat()
    return {"radio": allume,
            "appareils": _bluetooth_appareils() if allume else []}


def _bluetooth_appareils():
    """Les appareils Bluetooth : appairés d'abord, puis ceux qui se montrent.

    CE QUI MANQUAIT, ET POUR LE MÊME CINÉMA MAISON QUE LE SON. Le panneau
    disait « allumé, prêt à appairer » et s'arrêtait là : la barre de son
    d'Alex était introuvable, faute de liste où la voir. « bluetoothctl
    devices » sait pourtant tout — appairés (Paired), connectés (Connected),
    et ce que le dernier balayage a vu passer.

    On lit deux listes : les appairés (toujours), et ce que le contrôleur a
    déjà entendu. On ne DÉCLENCHE pas de balayage ici : « scan on » est un
    processus qui reste ouvert, pas une commande qui rend la main — c'est
    l'action « bt-chercher » qui s'en charge, sur demande.
    """
    if not shutil.which("bluetoothctl"):
        return []
    appareils = {}

    def lire(argv, appaire):
        for ligne in _sortie(argv, timeout=15).splitlines():
            #  « Device AC:BF:71:2E:11:09 LG Sound Bar SN9Y »
            mots = ligne.split(None, 2)
            if len(mots) < 3 or mots[0] != "Device":
                continue
            adresse, nom = mots[1], mots[2].strip()
            #  Sans nom réel, bluetoothctl répète l'adresse avec des tirets :
            #  une ligne pareille n'aide personne à reconnaître son appareil.
            if nom.replace("-", ":").upper() == adresse.upper():
                continue
            d = appareils.setdefault(adresse, {"adresse": adresse, "nom": nom,
                                               "appaire": False,
                                               "connecte": False})
            d["appaire"] = d["appaire"] or appaire

    lire(["bluetoothctl", "devices", "Paired"], True)
    lire(["bluetoothctl", "devices"], False)

    for adresse, d in appareils.items():
        info = _sortie(["bluetoothctl", "info", adresse], timeout=10)
        for ligne in info.splitlines():
            l = ligne.strip()
            if l.startswith("Connected:"):
                d["connecte"] = l.endswith("yes")
            elif l.startswith("Icon:"):
                d["genre"] = l.split(":", 1)[1].strip()

    return sorted(appareils.values(),
                  key=lambda d: (not d["connecte"], not d["appaire"],
                                 d["nom"].lower()))


def _casque_branche():
    """Un casque est-il branché ? On lit le port ACTIF de la sortie audio.
    Sert à l'afficher, pas à le changer : on ne débranche pas un casque en
    logiciel, et un faux interrupteur serait un mensonge."""
    if not shutil.which("pactl"):
        return False
    sortie = _sortie(["pactl", "list", "sinks"]).lower()
    for ligne in sortie.splitlines():
        if ligne.strip().startswith("active port:"):
            return "headphone" in ligne or "headset" in ligne
    return False


def _lumiere_etat():
    """Luminosité du rétroéclairage, en pour-cent. -1 quand la machine n'a pas
    de rétroéclairage pilotable (une tour avec un écran externe, par exemple).

    MÊME PRÉFÉRENCE QUE lexos-brightness, ET CE N'EST PAS UN DÉTAIL. Sur
    beaucoup de portables, /sys/class/backlight/ porte à la fois
    « acpi_videoN » (le firmware) et une interface native du pilote
    graphique (« intel_backlight »…) — et la première, alphabétiquement,
    n'est pas toujours celle qui pilote vraiment l'écran. lexos-brightness
    écrit désormais dans la seconde de préférence ; si ce panneau-ci
    continuait de LIRE la première, la barre afficherait un pourcentage qui
    n'a jamais correspondu à ce que le curseur vient de régler — deux
    sources pour la même valeur, libres de diverger.
    """
    base = BL_DIR
    try:
        candidats = sorted(base.iterdir())
    except OSError:
        return -1

    def lire(d):
        try:
            actuel = int((d / "brightness").read_text().strip())
            maxi = int((d / "max_brightness").read_text().strip())
        except (OSError, ValueError):
            return None
        return round(actuel * 100 / maxi) if maxi > 0 else None

    for d in candidats:
        if d.name.startswith("acpi_video"):
            continue
        v = lire(d)
        if v is not None:
            return v
    for d in candidats:
        v = lire(d)
        if v is not None:
            return v
    return -1


def _xfconf_lire(canal, propriete):
    if not shutil.which("xfconf-query"):
        return ""
    return _sortie(["xfconf-query", "-c", canal, "-p", propriete])


def _energie_etat():
    """Les délais d'extinction et de veille, là où XFCE les garde. Les valeurs
    sont en MINUTES ; 0 veut dire jamais, des deux côtés."""
    c = "xfce4-power-manager"
    def entier(prop, defaut):
        v = _xfconf_lire(c, f"/xfce4-power-manager/{prop}")
        return v if v.isdigit() else str(defaut)

    dim = _xfconf_lire(c, "/xfce4-power-manager/brightness-on-battery")
    return {
        #  « brightness-on-battery » vaut le niveau visé sur batterie ; s'il
        #  est posé et inférieur à 100, c'est que l'abaissement est actif.
        "dimBat": bool(dim.isdigit() and int(dim) < 100),
        "ecranOff": entier("blank-on-ac", 10),
        "veille": entier("inactivity-on-ac", 30),
    }


def _dock_etat():
    """Position du dock, lue LÀ OÙ PLANK LA PREND — c'est-à-dire gsettings.

    ALEX : « le bouton de position du dock reste sur Droite quoi qu'on
    choisisse ». Le dock, lui, se déplaçait bien.

    CETTE FONCTION LISAIT ~/.config/lexos/dock. Ce fichier n'est écrit par
    PERSONNE : vérifié sur tout le dépôt, le chemin n'apparaissait qu'ici.
    « lexos dock » pose la position dans gsettings et nulle part ailleurs. La
    lecture retombait donc toujours sur son repli — « droite » — quel que soit
    le choix. Deux sources de vérité pour un seul réglage, dont une vide.

    Le dépôt avait déjà tranché ce débat pour le Wi-Fi (voir _wifi_auto_lu :
    « une seule vérité : le fichier que lexos-net écrit et que
    lexos-net-autoconnect relit »). On tranche pareil ici, dans le même sens :
    on lit ce qui COMMANDE, on n'ouvre pas un deuxième registre à synchroniser
    à la main.

    ═══ ET ON NE RÉPOND PLUS « DROITE » QUAND ON NE SAIT PAS ═══
    ALEX, DEUXIÈME SIGNALEMENT. Le repli disait « droite » dès que gsettings
    manquait, au motif que c'est le défaut de Plank. C'était encore une
    réponse inventée : « je ne sais pas » devenait « c'est à droite », un
    bouton s'allumait, et l'interface avait l'air de marcher pendant que rien
    ne marchait. Un réglage qui n'affiche rien pousse à chercher ; un réglage
    qui affiche une valeur fausse fait perdre des heures.

    On rend donc None quand la position ne peut pas être lue — gsettings
    absent, Plank pas installé, schéma introuvable, valeur vide. La page
    n'allume alors AUCUN bouton et dit pourquoi en une ligne.
    """
    if shutil.which("gsettings") is None:
        return None
    try:
        r = subprocess.run(["gsettings", "get", DOCK_SCHEMA, "position"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    #  Schéma absent (Plank pas installé) : gsettings sort en erreur.
    if r.returncode != 0:
        return None
    #  gsettings rend la chaîne AVEC ses apostrophes : «'right'».
    brut = r.stdout.strip().strip("'\"")
    if not brut:
        return None
    #  Une valeur PRÉSENTE qu'on ne sait pas traduire est rendue telle quelle :
    #  aucun bouton ne s'allumera, ce qui est honnête, mais la page saura que
    #  la lecture a réussi — ce n'est pas le même cas que « on ne sait pas ».
    return DOCK_POSITIONS.get(brut, brut)


def _libre_etat():
    """Ce qui, dans CETTE machine, n'est pas du logiciel libre.

    La démo affiche la liste des trois exceptions (micrologiciels, Steam,
    pilote Broadcom) comme un texte fixe — elle ne peut pas faire mieux, elle
    n'a pas de machine sous elle. L'ISO, elle, peut REGARDER : « Steam est
    installé » et « Steam pourrait être installé » ne sont pas la même
    phrase, et c'est justement la précision qui donne du poids au reste.

    On ne regarde que la présence, jamais l'usage. Rien n'est envoyé nulle
    part : dpkg et /sys répondent depuis le disque."""
    def paquet(nom):
        #  Toutes les autres sondes de etat() se protègent (which(), except
        #  OSError, timeout=15) ; celle-ci était la seule nue. Sous un PATH
        #  dépouillé (dpkg-query absent), elle levait FileNotFoundError et
        #  faisait tomber tout /api/etat sans réponse.
        try:
            r = subprocess.run(["dpkg-query", "-W", "-f=${db:Status-Status}", nom],
                               capture_output=True, text=True, timeout=15)
        except (subprocess.SubprocessError, OSError):
            return False
        return r.returncode == 0 and r.stdout.strip() == "installed"

    #  Les micrologiciels : on compte les paquets « firmware-* » plutôt que
    #  d'en nommer un, la liste dépendant entièrement du matériel.
    firmwares = []
    try:
        r = subprocess.run(["dpkg-query", "-W", "-f=${binary:Package}\n",
                            "firmware-*"], capture_output=True, text=True,
                           timeout=15)
        firmwares = [l for l in r.stdout.split() if l]
    except (subprocess.SubprocessError, OSError):
        pass

    return {
        "firmwares": len(firmwares),
        "steam": paquet("steam-installer") or paquet("steam"),
        "broadcom": (paquet("broadcom-sta-dkms")
                     or paquet("firmware-brcm80211")),
    }


#  =========================================================================
#  LES LOGICIELS TIERS — ce qui n'est pas du Debian ordinaire, et sa licence
#  =========================================================================
#  POURQUOI CETTE PAGE EXISTE. LexOS dit « 100 % Linux », et c'est vrai. Mais
#  « libre » et « gratuit » ne sont pas la même chose, et une distribution qui
#  se réclame du libre doit pouvoir montrer SA propre liste d'exceptions
#  plutôt que de la laisser deviner. Trois catégories, nommées :
#
#    · libre        — on peut lire le code, le modifier, le redistribuer ;
#    · propriétaire — on peut s'en servir, c'est tout ;
#    · pas livré    — LexOS ne le distribue pas ; il est téléchargé chez son
#                     éditeur si TU le demandes, et la licence est la sienne.
#
#  Et surtout : la page REGARDE la machine. « Steam est installé » et « Steam
#  pourrait être installé » ne sont pas la même phrase — c'est la même règle
#  que le panneau « 100 % Linux » juste au-dessus. Une liste écrite d'avance
#  finirait par mentir dès la première version où un paquet change de nom.
TIERS = [
    #  (clé, nom, licence, libre, origine, à quoi ça sert)
    ("nvidia-driver-cuda", "Pilote NVIDIA", "NVIDIA Proprietary", False,
     "Debian non-free",
     "Fait marcher les cartes NVIDIA récentes. Il doit être DANS l'ISO : il "
     "ne s'installe pas après coup sur une machine qui n'affiche rien."),
    ("__firmwares", "Micrologiciels", "variées, souvent non libres", False,
     "Debian non-free-firmware",
     "Les petits programmes que réclament le Wi-Fi, le Bluetooth et certaines "
     "cartes graphiques pour démarrer. Sans eux, pas de réseau sans fil."),
    ("steam-installer", "Steam", "Valve Proprietary", False, "Debian non-free",
     "La boutique de jeux de Valve. Installée seulement dans la partie jeux."),
    ("llama.cpp", "llama.cpp", "MIT", True, "Debian trixie-backports",
     "Le moteur d'IA locale. Vrai libre, et il ne dépend de personne."),
    ("gocryptfs", "gocryptfs", "MIT", True, "Debian main",
     "Le coffre des Fichiers privés : il chiffre chaque fichier séparément."),
    ("wine", "Wine", "LGPL-2.1+", True, "Debian main",
     "Fait tourner des programmes Windows. Beaucoup croient qu'il réclame une "
     "copie de Windows : c'est faux — Wine Is Not an Emulator, c'est une "
     "réécriture libre, à partir de zéro."),
    ("flatpak", "Flatpak", "LGPL-2.1+", True, "Debian main",
     "La Logithèque. Le système est libre ; chaque application qu'on y "
     "installe garde SA licence à elle."),
    ("remmina", "Remmina", "GPL-2+", True, "Debian main",
     "La visionneuse du bureau à distance (RDP, VNC)."),
    ("x11vnc", "x11vnc", "GPL-2", True, "Debian main",
     "Le serveur qui laisse voir cet écran depuis ailleurs."),
    ("python3-pyside6.qtwidgets", "Qt / PySide6", "LGPL-3", True, "Debian main",
     "Les fenêtres de LexOS : Paramètres, Cartes, IA locale, Fichiers privés."),
]

#  Ceux-là ne sont PAS dans l'image. Ils arrivent après, chez leur éditeur, et
#  seulement si on le demande. On les nomme quand même : ce que LexOS
#  n'installe pas fait partie de ce qu'il faut savoir.
TIERS_ABSENTS = [
    ("claude", "Claude Code", "Anthropic, propriétaire", False,
     "npm, après l'installation sur le disque",
     "L'assistant de programmation d'Anthropic. Il tourne dans le nuage : "
     "compte et connexion requis. Il n'est plus mis dans l'ISO — la version "
     "y vieillirait."),
    ("ollama", "Ollama", "MIT", True, "script officiel ollama.com",
     "La couche pratique par-dessus llama.cpp. Libre, mais pas empaquetée "
     "par Debian : c'est pour ça qu'elle n'est pas dans l'image."),
    ("google-chrome-stable", "Google Chrome", "Google, propriétaire", False,
     "dépôt Google",
     "Installé seulement si tu tapes « lexos chrome ». Firefox, lui, est "
     "livré et libre."),
    ("__modeles", "Les modèles d'IA", "au cas par cas", False,
     "Hugging Face / Ollama, si tu en télécharges un",
     "Aucun ne voyage dans l'ISO. Beaucoup ont des poids ouverts sans être "
     "libres — le panneau IA locale affiche la licence avant de télécharger."),
]


def _tiers_etat():
    """Chaque composant, avec sa licence et s'il est VRAIMENT là."""
    def installe(cle):
        if cle == "__firmwares":
            return _libre_etat()["firmwares"] > 0
        if cle == "__modeles":
            #  Un modèle, ça se voit au disque, pas au dpkg.
            for base in (Path("/var/lib/lexos-ia/modeles"),
                         Path.home() / ".local/share/lexos-ia/modeles",
                         Path.home() / ".ollama/models"):
                try:
                    if base.exists() and any(base.iterdir()):
                        return True
                except OSError:
                    pass
            return False
        if shutil.which(cle):
            return True
        try:
            r = subprocess.run(["dpkg-query", "-W", "-f=${db:Status-Status}", cle],
                               capture_output=True, text=True, timeout=15)
            return r.returncode == 0 and r.stdout.strip() == "installed"
        except (subprocess.SubprocessError, OSError):
            return False

    def ligne(t, livre):
        cle, nom, licence, libre, origine, role = t
        return {"nom": nom, "licence": licence, "libre": libre,
                "origine": origine, "role": role, "livre": livre,
                "present": installe(cle)}

    dedans = [ligne(t, True) for t in TIERS]
    dehors = [ligne(t, False) for t in TIERS_ABSENTS]
    return {
        "livres": dedans,
        "absents": dehors,
        "libres": sum(1 for x in dedans if x["libre"]),
        "proprietaires": sum(1 for x in dedans if not x["libre"] and x["present"]),
    }


def _apercu_etat():
    """La vue d'ensemble des bureaux : par quoi elle s'ouvre, et par quoi on
    la déclenche.

    « moteur » n'est pas décoratif : sans xfdashboard on retombe sur la liste
    des fenêtres de xfdesktop, qui montre les mêmes bureaux mais pas en
    vignettes. La page le dit plutôt que de laisser croire à la vue de la
    démo. Et « super » ne peut s'allumer que si xcape est là — lui seul sait
    distinguer une touche Super relâchée seule d'un Super+1."""
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"

    def drapeau(nom):
        try:
            return (conf / nom).read_text().strip() == "on"
        except OSError:
            return False

    if shutil.which("xfdashboard"):
        moteur = "xfdashboard"
    elif shutil.which("xfdesktop"):
        moteur = "xfdesktop"
    else:
        moteur = ""
    return {
        "moteur": moteur,
        "coin": drapeau("coin-actif"),
        "geste": _geste_autocollant_etat(),
        "super": drapeau("super-apercu"),
        "xcape": bool(shutil.which("xcape")),
    }


def _barre_cachee():
    """La barre du haut se cache-t-elle toute seule ? XFCE range ça dans
    autohide-behavior : 0 = toujours visible, 1 = intelligent, 2 = toujours
    cachée. On considère « cachée » dès que ce n'est plus 0."""
    v = _xfconf_lire("xfce4-panel", "/panels/panel-1/autohide-behavior")
    return v.isdigit() and int(v) != 0


def _bureaux_etat():
    """Combien de bureaux virtuels, où l'on est, et combien de fenêtres sur
    chacun. wmctrl répond aux trois — c'est lui qui parle au gestionnaire de
    fenêtres, pas une supposition."""
    nb = _xfconf_lire("xfwm4", "/general/workspace_count")
    nb = int(nb) if nb.isdigit() else 0
    courant, fenetres = 0, []
    if shutil.which("wmctrl"):
        for ligne in _sortie(["wmctrl", "-d"]).splitlines():
            champs = ligne.split()
            if len(champs) >= 2 and champs[1] == "*":
                courant = int(champs[0]) if champs[0].isdigit() else 0
        if not nb:
            nb = len(_sortie(["wmctrl", "-d"]).splitlines())
        #  Une fenêtre par ligne, son bureau en deuxième colonne.
        compte = {}
        for ligne in _sortie(["wmctrl", "-l"]).splitlines():
            champs = ligne.split()
            if len(champs) >= 2 and champs[1].lstrip("-").isdigit():
                d = int(champs[1])
                if d >= 0:
                    compte[d] = compte.get(d, 0) + 1
        fenetres = [compte.get(i, 0) for i in range(max(nb, 1))]
    return {"nb": max(nb, 1), "courant": courant, "fenetres": fenetres}


def _usb_etat():
    """Les supports AMOVIBLES branchés — clés, disques externes, cartes.
    lsblk répond en JSON, ce qui évite d'avoir à découper du texte aligné qui
    change de forme d'une version à l'autre.

    On ne liste QUE l'amovible (RM=1) ou l'USB (TRAN=usb) : le disque système
    n'a rien à faire dans une liste où le bouton d'à côté s'appelle
    « Formater ». C'est le genre de confusion qui coûte des données."""
    if not shutil.which("lsblk"):
        return []
    brut = _sortie(["lsblk", "-J", "-b", "-o",
                    "NAME,SIZE,LABEL,RM,TYPE,TRAN,MOUNTPOINT,MODEL"])
    try:
        arbre = json.loads(brut).get("blockdevices", [])
    except (ValueError, AttributeError):
        return []

    def taille(octets):
        try:
            o = int(octets)
        except (TypeError, ValueError):
            return ""
        for unite, seuil in (("To", 1e12), ("Go", 1e9), ("Mo", 1e6)):
            if o >= seuil:
                n = o / seuil
                return f"{n:.0f} {unite}" if n >= 10 else f"{n:.1f} {unite}"
        return f"{o} o"

    appareils = []
    for d in arbre:
        amovible = d.get("rm") in (True, 1, "1") or d.get("tran") == "usb"
        if not amovible or d.get("type") != "disk":
            continue
        #  Le nom montré : l'étiquette d'une partition si elle en a une, sinon
        #  le modèle, sinon le nom brut. C'est ce qui est écrit sur la clé.
        nom = (d.get("model") or d.get("name") or "").strip()
        monte = ""
        for part in d.get("children") or []:
            if part.get("label"):
                nom = part["label"].strip()
            if part.get("mountpoint"):
                monte = part["mountpoint"]
        #  Une clé (petite) ou un disque externe (gros) : l'icône change.
        try:
            gros = int(d.get("size") or 0) >= 256 * 10**9
        except (TypeError, ValueError):
            gros = False
        appareils.append({"nom": nom or d.get("name", ""),
                          "dev": "/dev/" + d.get("name", ""),
                          "taille": taille(d.get("size")),
                          "monte": monte, "disque": gros})
    return appareils


def _service_actif(nom):
    """Un service systemd tourne-t-il ? Renvoie None s'il n'est même pas
    installé — « éteint » et « absent » ne veulent pas dire la même chose,
    et la page doit pouvoir le dire."""
    if not shutil.which("systemctl"):
        return None
    etat_unite = _sortie(["systemctl", "is-enabled", nom])
    if not etat_unite or "not-found" in etat_unite:
        return None
    return _sortie(["systemctl", "is-active", nom]) == "active"


def _securite_etat():
    """L'état réel de l'autodéfense. Chaque entrée vaut True (en marche),
    False (installé mais arrêté) ou None (pas installé) — trois états, parce
    que « le pare-feu est éteint » et « il n'y a pas de pare-feu » appellent
    des gestes différents."""
    #  ufw status demande les droits root ; sans eux on lit le fichier de
    #  configuration, qui dit la même chose et se lit sans privilège.
    feu = None
    if shutil.which("ufw"):
        feu = False
        try:
            for ligne in Path(ETC_DIR / "ufw/ufw.conf").read_text().splitlines():
                if ligne.strip().startswith("ENABLED="):
                    feu = ligne.split("=", 1)[1].strip().lower() == "yes"
        except OSError:
            pass
    #  Le disque est-il chiffré ? Un périphérique de type « crypt » suffit.
    chiffre = False
    if shutil.which("lsblk"):
        chiffre = "crypt" in _sortie(["lsblk", "-o", "TYPE", "-n"]).split()
    return {
        "pareFeu": feu,
        "chiffre": chiffre,
        "antivirus": _service_actif("clamav-freshclam.service"),
        "intrusion": _service_actif("fail2ban.service"),
        "rootkit": bool(shutil.which("rkhunter") or shutil.which("chkrootkit")),
        "apparmor": _service_actif("apparmor.service"),
    }


VOLMAN = {
    "ouvrir":  "/autobrowse/enabled",
    "photos":  "/autophoto/enabled",
    "musique": "/autoplay-audio-cds/enabled",
    "monter":  "/automount-media/enabled",
}


def _amovibles_etat():
    """Ce que LexOS fait quand on branche quelque chose. thunar-volman garde
    ces réglages dans xfconf ; on lit les vrais, pas des valeurs supposées."""
    return {cle: _xfconf_lire("thunar-volman", prop) == "true"
            for cle, prop in VOLMAN.items()}


def _access_etat():
    """Accessibilité : ce qui est réglable, et ce qui est installé.
    La taille du curseur est un nombre ; au-delà de 32 on parle de « curseur
    large » — c'est le seuil où la différence se voit vraiment."""
    taille = _xfconf_lire("xsettings", "/Gtk/CursorThemeSize")
    theme = _xfconf_lire("xsettings", "/Net/ThemeName").lower()
    return {
        "contraste": "highcontrast" in theme.replace("-", "").replace(" ", ""),
        "curseurLarge": taille.isdigit() and int(taille) >= 32,
        "orca": bool(shutil.which("orca")),
        "onboard": bool(shutil.which("onboard")),
    }


def _maj_etat():
    """Mises à jour automatiques, et micrologiciel. On lit la configuration
    d'unattended-upgrades telle qu'elle est sur la machine."""
    secu, tout = False, False
    for f in (ETC_DIR / "apt/apt.conf.d/20auto-upgrades",
              ETC_DIR / "apt/apt.conf.d/50unattended-upgrades"):
        try:
            texte = Path(f).read_text()
        except OSError:
            continue
        for ligne in texte.splitlines():
            l = ligne.strip()
            if l.startswith("//") or l.startswith("#"):
                continue
            if "Unattended-Upgrade" in l and '"1"' in l:
                secu = True
            if "Update-Package-Lists" in l and '"1"' in l:
                secu = secu or True
    #  « Tout mettre à jour » = la ligne des dépôts autres que sécurité est
    #  décommentée dans 50unattended-upgrades.
    try:
        for ligne in Path(ETC_DIR / "apt/apt.conf.d/50unattended-upgrades").read_text().splitlines():
            l = ligne.strip()
            if l.startswith('"') and "-updates" in l and not l.startswith("//"):
                tout = True
    except OSError:
        pass
    return {
        "secu": secu, "tout": tout, "fwupd": bool(shutil.which("fwupdmgr")),
        #  Ce que _terminal_suivi() a laissé derrière lui pour chaque geste —
        #  None si jamais lancé cette session, sinon en_cours/ok. C'est CE
        #  DICT que la page relit à chaque rafraîchissement pour savoir si
        #  elle doit encore attendre.
        "progres": {cle: _maj_progres(cle) for cle in ("verifier", "tout", "firmware")},
    }


def _utilisateurs_etat():
    """Les comptes de la machine — demandés à lexos-utilisateurs.

    CE QUE CETTE FONCTION FAISAIT, ET POURQUOI C'ÉTAIT FAUX. Elle lisait
    /etc/passwd et /etc/group elle-même, avec sa PROPRE définition de
    « administrateur » : appartenir à sudo, wheel OU adm. Or « adm » ne donne
    que la lecture des journaux. Quelqu'un qui n'est que dans « adm »
    s'affichait « administrateur » dans les Paramètres alors qu'il ne peut
    pas lancer un seul sudo — et lexos-utilisateurs, lui, ne le comptait pas
    comme administrateur. Deux définitions du même mot dans le même système,
    et c'est la fausse qu'on montrait à l'écran.

    Elle filtrait aussi les comptes autrement (UID < 65000 et un shell qui
    n'est pas nologin, là où l'outil dit UID >= 1000 et pas « nobody ») :
    deux listes de comptes possibles, pour la même machine.

    Une seule source, donc, et c'est l'outil — comme pour lexos-clavier,
    lexos-defaut et lexos-distant.
    """
    vide = {"comptes": [], "auto": "", "nb_admins": 0, "groupe_admin": "sudo",
            "root": False, "lightdm": False, "nom_regex": "", "dispo": False}
    if not shutil.which("lexos-utilisateurs"):
        return vide
    try:
        r = subprocess.run(["lexos-utilisateurs", "--json"],
                           capture_output=True, text=True, timeout=30)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if not isinstance(d.get("comptes"), list):
        return vide
    d["dispo"] = True
    return d


def _imprimantes_etat():
    """Les imprimantes connues de CUPS, et laquelle est par défaut."""
    if not shutil.which("lpstat"):
        return {"dispo": False, "liste": []}
    defaut = ""
    sortie = _sortie(["lpstat", "-d"])
    if ":" in sortie:
        defaut = sortie.split(":", 1)[1].strip()
    liste = []
    for ligne in _sortie(["lpstat", "-p"]).splitlines():
        mots = ligne.split()
        if len(mots) >= 2 and mots[0] == "printer":
            nom = mots[1]
            liste.append({"nom": nom,
                          "etat": "prête" if "idle" in ligne else "occupée",
                          "defaut": nom == defaut})
    return {"dispo": True, "liste": liste}


def _clavier_etat():
    """Le clavier, tel que lexos-clavier le voit.

    ALEX : « dans les paramètres de clavier, une fois installé, on n'est pas
    capable de changer de clavier », puis « faire en sorte qu'on puisse
    avoir tous les paramètres de clavier ».

    CETTE SECTION NE SAVAIT QUE LIRE. Elle appelait « setxkbmap -query »,
    affichait les dispositions, et pour changer quoi que ce soit renvoyait
    au dialogue de XFCE — lequel s'ouvre TOUT GRISÉ tant que « Utiliser les
    réglages système » est actif, ce qui est son défaut (vérifié dans le
    GtkBuilder du binaire : xkb_use_system_default_switch, active=True).
    Deux impasses, et rien pour le dire.

    ON DEMANDE À lexos-clavier PLUTÔT QUE DE REFAIRE SON TRAVAIL. Il porte
    déjà le catalogue des vingt dispositions, les six bascules, et il sait
    appliquer ET conserver. Relire setxkbmap de notre côté ferait deux
    copies de la même logique, qui finiraient par ne plus dire la même
    chose — exactement le raisonnement tenu pour lexos-distant plus bas.
    """
    vide = {"dispositions": [], "courante": "", "actives": [],
            "catalogue": [], "bascules": [], "bascule": "", "max": 4,
            "x_applique": ""}
    if not shutil.which("lexos-clavier"):
        return vide
    try:
        r = subprocess.run(["lexos-clavier", "--json"],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    actives = d.get("actives", [])
    return {
        #  « dispositions » et « courante » restent servis : la page les
        #  affichait déjà sous ces noms, et un renommage silencieux aurait
        #  vidé l'écran sans qu'une seule erreur ne le dise.
        "dispositions": [a.get("cle", "") for a in actives],
        "courante": actives[0].get("cle", "") if actives else "",
        "actives": actives,
        "catalogue": d.get("catalogue", []),
        "bascules": d.get("bascules", []),
        "bascule": d.get("bascule", ""),
        "max": d.get("max", 4),
        "x_applique": d.get("x_applique", ""),
    }


def _distant_etat():
    """Le bureau à distance, tel que lexos-distant le voit.

    ON LUI DEMANDE PLUTÔT QUE DE REFAIRE SON TRAVAIL. Ce panneau se
    contentait de « serveur actif / arrêté » — alors que lexos-distant sait
    déjà quelle adresse donner, sur quel port, et quels outils sont là.
    Relire « ip addr » et « pgrep » de notre côté aurait fait deux copies de
    la même logique, qui auraient fini par ne plus dire la même chose. On
    consomme donc sa sortie « --json ».
    """
    vide = {"outil": "", "actif": False, "adresses": [], "ports": "",
            "remmina": False, "ssh": False}
    if not shutil.which("lexos-distant"):
        return vide
    try:
        r = subprocess.run(["lexos-distant", "--json"],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    return {
        "outil": d.get("outil", ""),
        "actif": bool(d.get("partage")),
        "adresses": d.get("adresses", []),
        "ports": d.get("ports", ""),
        "remmina": bool(d.get("remmina")),
        "ssh": bool(d.get("ssh")),
    }


def _reseau_etat():
    """Le filaire : branché ou non, et avec quelle adresse. Une question
    simple qu'aucune section ne savait répondre."""
    if not shutil.which("nmcli"):
        return {"filaire": None, "ip": ""}
    filaire, ip = None, ""
    for ligne in _sortie(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE",
                          "device"]).splitlines():
        champs = ligne.split(":")
        if len(champs) >= 3 and champs[1] == "ethernet":
            filaire = champs[2] == "connected"
            if filaire:
                sortie = _sortie(["nmcli", "-t", "-f", "IP4.ADDRESS",
                                  "device", "show", champs[0]])
                for l in sortie.splitlines():
                    if ":" in l:
                        ip = l.split(":", 1)[1].split("/")[0]
                        break
            break
    return {"filaire": filaire, "ip": ip}


def _defaut_etat():
    """Quel logiciel ouvre quoi — et lesquels pourraient le faire.

    ALEX : « le contenu comme Ubuntu », « commence par applications par
    défaut ». La page LISAIT le fichier d'associations et affichait cinq
    lignes sans rien à cliquer ; pour changer quoi que ce soit, elle passait
    la main à l'outil de XFCE.

    ON DEMANDE À lexos-defaut PLUTÔT QUE DE REFAIRE SON TRAVAIL. Il porte
    déjà les dix catégories, leurs types MIME, la lecture des .desktop et la
    liste des applications capables d'ouvrir chaque type. La version
    précédente de cette fonction relisait mimeapps.list à la main avec sa
    propre table de cinq types — deux sources pour la même question, qui
    auraient fini par ne plus dire la même chose. Même raisonnement que pour
    lexos-clavier et lexos-distant.

    UBUNTU EN OFFRE SIX, ON EN GARDE DIX. On ne retire pas des réglages pour
    « faire comme » : le lecteur audio, l'éditeur de texte, le gestionnaire
    de fichiers, les archives et le terminal n'existent pas dans la page
    d'Ubuntu, et les enlever d'ici n'aiderait personne.
    """
    vide = {"navigateur": "", "assoc": {}, "categories": []}
    if not shutil.which("lexos-defaut"):
        return vide
    try:
        r = subprocess.run(["lexos-defaut", "--json"],
                           capture_output=True, text=True, timeout=30)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    cats = d.get("categories", [])

    #  « navigateur » et « assoc » restent servis sous leurs anciens noms :
    #  d'autres endroits de la page les lisent, et un renommage silencieux
    #  aurait vidé l'écran sans qu'une seule erreur ne le dise.
    ancien = {"texte": "texte", "images": "image", "pdf": "pdf",
              "audio": "musique", "video": "video"}
    assoc, nav = {}, ""
    for c in cats:
        courant = (c.get("courant") or "").replace(".desktop", "")
        if c.get("cle") == "navigateur":
            nav = courant
        elif c.get("cle") in ancien and courant:
            assoc[ancien[c["cle"]]] = courant
    return {"navigateur": nav, "assoc": assoc, "categories": cats}


def _couleurs_etat():
    """Les écrans connus de colord, et s'ils ont un profil de couleur."""
    if not shutil.which("colormgr"):
        return {"dispo": False, "ecrans": []}
    ecrans, courant = [], None
    for ligne in _sortie(["colormgr", "get-devices"]).splitlines():
        l = ligne.strip()
        if l.startswith("Model:"):
            courant = {"nom": l.split(":", 1)[1].strip(), "profil": ""}
            ecrans.append(courant)
        elif courant is not None and l.startswith("Default Profile:"):
            courant["profil"] = l.split(":", 1)[1].strip()
    return {"dispo": True, "ecrans": ecrans}


def _tablette_etat():
    """Une tablette graphique est-elle branchée ? xsetwacom la voit quand le
    pilote est chargé ; sinon on cherche dans les périphériques d'entrée."""
    if shutil.which("xsetwacom"):
        lignes = [l for l in _sortie(["xsetwacom", "--list", "devices"]).splitlines() if l.strip()]
        if lignes:
            return {"branchee": True,
                    "noms": [l.split("id:")[0].strip() for l in lignes]}
    return {"branchee": False, "noms": []}


def _notif_etat():
    """Ne pas déranger, et combien de temps une notification reste à l'écran."""
    c = "xfce4-notifyd"
    dnd = _xfconf_lire(c, "/do-not-disturb")
    duree = _xfconf_lire(c, "/expire-timeout")
    return {"silence": dnd == "true",
            "duree": duree if duree.isdigit() else ""}


def _mac_etat():
    """Cette machine est-elle un Mac ? Le fabricant est écrit dans le DMI par
    le BIOS ; c'est la source que tous les outils lisent."""
    try:
        vendeur = (DMI_DIR / "sys_vendor").read_text().strip()
        modele = (DMI_DIR / "product_name").read_text().strip()
    except OSError:
        return {"apple": False, "modele": ""}
    return {"apple": "apple" in vendeur.lower(), "modele": modele}


def _crt_etat():
    """Les effets de fenêtres « téléviseur 1980 » — demandés à lexos-crt.

    ALEX : « l'effet d'animation n'est pas là quand je ferme des fenêtres ».
    Il avait raison, et ce n'était pas un réglage de travers : l'effet était
    configuré pour COMPIZ, retiré de Debian trixie. lexos-wm se repliait donc
    sur xfwm4, qui n'a aucune animation d'ouverture ni de fermeture.

    CE QUE CETTE PAGE DOIT POUVOIR DIRE : non pas « allumé / éteint », mais
    POURQUOI c'est éteint quand ça l'est — picom absent, picom trop ancien,
    ou pas d'accélération 3D. Un interrupteur qui revient tout seul à sa place
    sans un mot est le geste le plus déroutant qu'une page puisse offrir.
    """
    vide = {"voulu": "off", "tourne": False, "picom": False,
            "picom_version": 0, "picom_min": 12, "accel3d": False,
            "script": False, "dispo": False}
    if not shutil.which("lexos-crt"):
        return vide
    try:
        r = subprocess.run(["lexos-crt", "--json"],
                           capture_output=True, text=True, timeout=20)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if "voulu" not in d:
        return vide
    d["dispo"] = True
    return d


def _terminal_etat():
    """Le terminal de jour et le terminal de nuit, tels que lexos-terminal les
    voit.

    LA PAGE N'AVAIT AUCUN ÉTAT : elle listait quatre commandes à taper. Elle ne
    disait donc ni ce qui est choisi, ni ce qui s'applique en ce moment — et
    ces deux-là diffèrent dès qu'on est en « auto » ou en « suivre ». C'est
    précisément l'écart entre les deux qui explique ce qu'on a sous les yeux.
    """
    vide = {"mode": "", "effectif": "", "bureau": "", "debut": "", "fin": "",
            "minuterie": False, "dispo": False}
    if not shutil.which("lexos-terminal"):
        return vide
    try:
        r = subprocess.run(["lexos-terminal", "--json"],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if not d.get("mode"):
        return vide
    d["dispo"] = True
    return d


def _partage_etat():
    """Le partage, tel que lexos-share le voit.

    CETTE FONCTION NE SAVAIT QU'UNE CHOSE : si le serveur tourne. La page
    n'avait donc qu'une ligne à afficher — « actif » ou « au repos » — là où
    Ubuntu met le NOM DE L'ORDINATEUR en haut de sa page « Partage », et pour
    une bonne raison : ce nom n'a d'usage que vu d'ailleurs. C'est lui que le
    téléphone affiche dans sa liste d'appareils.

    Elle cherchait aussi « share-server.py » avec pgrep -f, qui compare la
    ligne de commande entière : n'importe quelle commande mentionnant ce nom
    faisait dire « partage actif ». lexos-share cherche maintenant le chemin
    complet, et c'est lui qu'on interroge.
    """
    vide = {"actif": False, "nom": "", "nom_regex": "", "recus": "",
            "minutes": 0, "kde": False, "bt": False, "qr": False,
            "ssh_serveur": False, "dispo": False}
    if not shutil.which("lexos-share"):
        return vide
    try:
        r = subprocess.run(["lexos-share", "--json"],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if "nom" not in d:
        return vide
    d["dispo"] = True
    return d


def _comptes_etat():
    """Les comptes en ligne — demandés à lexos-comptes.

    CE QUE CETTE FONCTION FAISAIT. Elle appelait « rclone listremotes »
    elle-même. Elle savait donc quels comptes sont CONFIGURÉS, et rien de
    plus — surtout pas lesquels sont MONTÉS, c'est-à-dire lesquels sont
    réellement là, dans Fichiers, en ce moment. C'est pourtant toute la
    différence pour qui cherche ses documents.

    Et elle ignorait le catalogue des services. La page ne pouvait donc pas
    proposer d'en relier un : il fallait passer par le terminal ne serait-ce
    que pour apprendre les noms acceptés. Ce catalogue vit dans lexos-comptes,
    avec le type rclone exact de chaque service — celui qui fait la différence
    entre une commande qui marche et un « unknown remote type ». Le recopier
    ici aurait donné deux listes destinées à diverger.
    """
    vide = {"rclone": False, "gvfs": False, "nuage": "", "comptes": [],
            "services": [], "dispo": False,
            #  Ancien nom, encore lu ailleurs dans la page.
            "liens": [], "goa": False}
    if not shutil.which("lexos-comptes"):
        return vide
    try:
        r = subprocess.run(["lexos-comptes", "--json"],
                           capture_output=True, text=True, timeout=20)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if not isinstance(d.get("services"), list):
        return vide
    d["dispo"] = True
    d["liens"] = [{"nom": c.get("nom", ""), "par": "rclone"}
                  for c in d.get("comptes", [])]
    d["goa"] = bool(d.get("gvfs"))
    return d

def _bienetre_etat():
    """Temps d'écran, limite, pauses, lumière du soir — demandés à l'outil.

    DEUX CORRECTIONS SUCCESSIVES, ET LA SECONDE EST CELLE-CI.
    La première version lisait ~/.config/lexos/ecran-aujourdhui, un fichier
    que personne n'écrit : la section affichait éternellement « pas de
    relevé ». La deuxième lisait le bon dossier, mais à la main — donc une
    deuxième copie du format de lexos-bienetre, qui aurait fini par ne plus
    dire la même chose. On demande maintenant à l'outil, comme pour le
    clavier, les applications par défaut et les comptes.

    ET ELLE NE SAVAIT QUE DEUX CHOSES : les minutes du jour, et si le
    compteur tourne. Ni la limite, ni la semaine, ni l'état réel de workrave
    et de redshift — d'où une page sans un seul réglage.

    TROIS DISTINCTIONS À GARDER : « zéro minute » n'est pas « le compteur est
    arrêté » ; « workrave n'est pas installé » n'est pas « les rappels sont
    arrêtés » ; une limite de zéro n'est pas une limite atteinte.
    """
    vide = {"tourne": False, "minutes": 0, "limite": 0,
            "pauses_installe": False, "pauses_actif": False,
            "nuit_installe": False, "nuit_actif": False,
            "semaine": [], "total_semaine": 0, "dispo": False,
            #  Anciens noms, encore lus ailleurs dans la page.
            "pauses": False, "soir": False}
    if not shutil.which("lexos-bienetre"):
        return vide
    try:
        r = subprocess.run(["lexos-bienetre", "--json"],
                           capture_output=True, text=True, timeout=20)
        d = json.loads(r.stdout or "{}")
    except (subprocess.SubprocessError, OSError, ValueError):
        return vide
    if "minutes" not in d:
        return vide
    d["dispo"] = True
    d["pauses"] = bool(d.get("pauses_installe"))
    d["soir"] = bool(d.get("nuit_installe"))
    return d

def _heure_etat():
    """Fuseau et synchronisation automatique, via timedatectl."""
    if not shutil.which("timedatectl"):
        return {"fuseau": "", "auto": False}
    fuseau, auto = "", False
    for ligne in _sortie(["timedatectl", "show"]).splitlines():
        if ligne.startswith("Timezone="):
            fuseau = ligne.split("=", 1)[1]
        elif ligne.startswith("NTP="):
            auto = ligne.split("=", 1)[1] == "yes"
    #  Ce que l'horloge de la barre affiche VRAIMENT. La démo propose
    #  « 24 h / 12 h », « secondes » et « jour de la semaine » ; côté XFCE ces
    #  trois réglages ne sont qu'UN seul : la chaîne de format du greffon
    #  horloge. On la lit et on la décompose, plutôt que de garder trois
    #  drapeaux à part qui finiraient par mentir sur ce qui est affiché.
    #  L'HORLOGE EST MAINTENANT UNE TUILE LEXOS (lexos-heure), et plus le
    #  greffon horloge de XFCE : il fallait ça pour qu'un clic sur l'heure
    #  ouvre le volet des notifications, ce que le greffon d'origine ne
    #  savait pas faire. Son format vit donc dans ~/.config/lexos/horloge et
    #  non dans une propriété xfconf accrochée au NUMÉRO du greffon — ajouter
    #  une tuile à la barre renumérote ces propriétés, et le réglage aurait
    #  fini par s'appliquer à autre chose.
    horloge = {"H12": "non", "SECONDES": "non", "JOUR": "oui"}
    if shutil.which("lexos-heure"):
        for ligne in _sortie(["lexos-heure", "--etat"]).splitlines():
            if "=" in ligne:
                cle, _, valeur = ligne.partition("=")
                if cle in horloge:
                    horloge[cle] = valeur.strip()
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"
    try:
        fuseau_auto = (conf / "fuseau-auto").read_text().strip() == "on"
    except OSError:
        fuseau_auto = False
    #  « Fuseau automatique » n'est proposable que si un lieu est connu — et
    #  le seul lieu que LexOS connaisse est celui qu'on lui a donné pour la
    #  météo. Sans ça, l'interrupteur promettrait une devinette qu'on refuse
    #  de faire (voir lexos-datetime : jamais de géolocalisation par IP).
    lieu_connu = False
    try:
        contenu = (conf / "meteo.conf").read_text()
        lieu_connu = "LEXOS_METEO_LAT=" in contenu and "LEXOS_METEO_LON=" in contenu
    except OSError:
        pass
    return {
        "fuseau": fuseau,
        "auto": auto,
        "fuseau_auto": fuseau_auto,
        "lieu_connu": lieu_connu,
        "maintenant": _sortie(["date", "+%A %d %B %Y, %H:%M:%S"]),
        "h12": horloge["H12"] == "oui",
        "secondes": horloge["SECONDES"] == "oui",
        "jour": horloge["JOUR"] == "oui",
    }


def etat():
    conf = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "lexos"

    def fichier(nom, defaut):
        try:
            return (conf / nom).read_text().strip() or defaut
        except OSError:
            return defaut

    #  Même règle que avion_state() dans lexos-net : « -t » (terse) donne des
    #  mots-clés fixes, jamais traduits — contrairement à la sortie normale de
    #  nmcli, qui suit la langue du système (fr_CA par défaut sur LexOS).
    avion = "off"
    if shutil.which("nmcli"):
        wifi = _sortie(["nmcli", "-t", "radio", "wifi"]) or "?"
        wwan = _sortie(["nmcli", "-t", "radio", "wwan"]) or "?"
        if wifi == "disabled" and wwan in ("disabled", "missing"):
            avion = "on"

    version = ""
    try:
        for ligne in Path(ETC_DIR / "os-release").read_text().splitlines():
            if ligne.startswith("PRETTY_NAME="):
                version = ligne.split("=", 1)[1].strip('"')
                break
    except OSError:
        pass

    try:
        perf = Path(ETC_DIR / "lexos/performance").read_text().strip() or "medium"
    except OSError:
        perf = "medium"

    #  Un seul ratissage du disque, pour DEUX clés. _fonds_perso() n'a pas de
    #  cache : l'appeler deux fois (une par clé, comme avant) double le coût
    #  à chaque rafraîchissement ET peut faire correspondre chaque clé à un
    #  instantané différent si le dossier surveillé change entre les deux
    #  appels (justement ~/Téléchargements) — l'indice mis en évidence
    #  désignerait alors la mauvaise vignette.
    perso = _fonds_perso()

    return {
        "perf": perf,
        "theme": fichier("mode", "sombre"),
        "accent": fichier("accent", "orange"),
        "police": fichier("police", "defaut"),
        "avion": avion,
        "hote": socket.gethostname(),
        "version": version or "LexOS 2.0.0 « Nomad »",
        "noyau": _sortie(["uname", "-r"]),
        "libre": _libre_etat(),
        "tiers": _tiers_etat(),
        #  L'état réel du matériel, pour que les sections montrent des
        #  VALEURS et pas seulement des boutons.
        "wifi": _wifi_etat(),
        "son": _son_etat(),
        "batterie": _batterie_etat(),
        "ecrans": _ecrans_etat(),
        #  La galerie du fond d'écran : index + nom seulement. Le CHEMIN reste
        #  côté machine — la page applique par indice (fond-fichier revalide),
        #  et les vignettes passent par /api/fond-vignette, jamais par un
        #  chemin que la page choisirait.
        "fonds_perso": [{"i": i, "nom": Path(c).name}
                        for i, c in enumerate(perso)],
        #  ALEX : « pour changer de couleur sur le bouton sélectionné ». Sans
        #  cette clé, la page n'avait RIEN à comparer : les cinq fonds
        #  intégrés et les vignettes de la galerie étaient les seuls choix de
        #  toute l'interface à ne pas montrer lequel était posé.
        "fond": _fond_etat(perso),
        #  Vide n'est pas une réponse. Quand la liste ci-dessus l'est, celle-ci
        #  dit POURQUOI — et la page peut enfin l'écrire au lieu de laisser
        #  croire qu'aucun écran n'est branché.
        "ecrans_probleme": _ecrans_probleme(),
        "echelle": _echelle_etat(),
        "image": _image_etat(),
        "souris": _souris_etat(),
        "heure": _heure_etat(),
        "lumiere": _lumiere_etat(),
        "energie": _energie_etat(),
        "bluetooth": _bluetooth_complet(),
        "dock": _dock_etat(),
        "intro": _intro_etat(),
        "barreCachee": _barre_cachee(),
        "bureaux": _bureaux_etat(),
        "apercu": _apercu_etat(),
        "usb": _usb_etat(),
        "securite": _securite_etat(),
        "amovibles": _amovibles_etat(),
        "access": _access_etat(),
        "maj": _maj_etat(),
        "utilisateurs": _utilisateurs_etat(),
        "imprimantes": _imprimantes_etat(),
        "clavier": _clavier_etat(),
        "distant": _distant_etat(),
        "reseau": _reseau_etat(),
        "defaut": _defaut_etat(),
        "couleurs": _couleurs_etat(),
        "tablette": _tablette_etat(),
        "notif": _notif_etat(),
        "mac": _mac_etat(),
        "partage": _partage_etat(),
        "terminal": _terminal_etat(),
        "crt": _crt_etat(),
        "recherche": _recherche_etat(),
        "comptes": _comptes_etat(),
        "bienetre": _bienetre_etat(),
        "langue": _sortie(["sh", "-c", "printf %s \"${LANG:-}\""]) or os.environ.get("LANG", ""),
    }


# =============================================================================
#  Serveur : fichiers statiques + API.
# =============================================================================

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path == "/api/etat":
            return self._json(200, etat())
        #  ═══ LES VIGNETTES DE LA GALERIE ═══
        #  La page ne demande JAMAIS un chemin — seulement un indice, revalidé
        #  contre une énumération fraîche. Servir un chemin venu de la page,
        #  c'est la laisser lire n'importe quel fichier du compte ; un indice
        #  ne sait désigner que ce que la galerie propose déjà.
        if self.path.startswith("/api/fond-vignette"):
            from urllib.parse import parse_qs, urlparse
            try:
                i = int(parse_qs(urlparse(self.path).query).get("i", ["-1"])[0])
            except ValueError:
                i = -1
            fonds = _fonds_perso()
            if not (0 <= i < len(fonds)):
                return self._json(404, {"ok": False, "erreur": "vignette inconnue"})
            chemin = Path(fonds[i])
            genre = mimetypes.guess_type(str(chemin))[0] or "application/octet-stream"
            try:
                #  Le plafond est REVÉRIFIÉ ici, et pas seulement à
                #  l'énumération : le fichier a pu grossir entre les deux (un
                #  téléchargement encore en cours, par exemple).
                if chemin.stat().st_size > FONDS_PERSO_POIDS_MAX:
                    return self._json(413, {"ok": False, "erreur": "image trop lourde"})
                corps = chemin.read_bytes()
            except OSError:
                return self._json(404, {"ok": False, "erreur": "fichier illisible"})
            self.send_response(200)
            self.send_header("Content-Type", genre)
            self.send_header("Content-Length", str(len(corps)))
            #  L'image peut changer sur le disque ; la galerie se réénumère à
            #  chaque état. Un cache court évite juste de relire à chaque rendu.
            self.send_header("Cache-Control", "max-age=30")
            self.end_headers()
            self.wfile.write(corps)
            return None
        return super().do_GET()

    def do_POST(self):
        if not self.path.startswith("/api/action"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            requete = json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self._json(400, {"ok": False, "erreur": "requête invalide"})
        action = ACTIONS.get(requete.get("action", ""))
        if action is None:
            return self._json(400, {"ok": False, "erreur": "action inconnue"})
        try:
            return self._json(200, action(requete.get("arg")))
        except subprocess.TimeoutExpired:
            return self._json(200, {"ok": False, "erreur": "délai dépassé"})
        except Exception as e:  # la fenêtre doit survivre à un outil qui casse
            return self._json(200, {"ok": False, "erreur": str(e)})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main():
    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    mimetypes.add_type("text/javascript", ".js")
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("image/svg+xml", ".svg")

    section = ""
    if len(sys.argv) > 1 and sys.argv[1].replace("-", "").isalnum():
        section = sys.argv[1]

    port = _port_libre()
    handler = functools.partial(Handler, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-settings-http").start()

    url = f"http://127.0.0.1:{port}/index.html?mode={_mode_apparence()}"
    if section:
        url += f"#{section}"

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)

    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)

    #  La fenêtre s'ouvrait à 980 x 700, quel que soit l'écran. Sur le
    #  ThinkPad (1366 x 768), 700 pixels de haut coupaient la barre latérale
    #  au milieu : Alex voyait la liste s'arrêter à « Partage » et pensait
    #  qu'il manquait des sections. Les 32 sections sont bien là et la barre
    #  défile — mais une fenêtre qui n'utilise pas l'écran donne l'impression
    #  contraire.
    #
    #  Ubuntu ouvre ses Paramètres à la taille de l'écran disponible. On fait
    #  pareil : on prend ce que le bureau laisse (barre du haut et dock
    #  déduits, c'est ce que renvoie availableGeometry), sans jamais dépasser
    #  une largeur confortable en lecture ni descendre sous une taille
    #  utilisable.
    ecran = app.primaryScreen()
    if ecran is not None:
        dispo = ecran.availableGeometry()
        largeur = max(900, min(1180, int(dispo.width() * 0.92)))
        hauteur = max(600, min(900, int(dispo.height() * 0.94)))
        fenetre.resize(largeur, hauteur)
        #  Centrer : sur un petit écran, une fenêtre presque aussi grande que
        #  le bureau posée en haut à gauche déborde à droite et en bas.
        fenetre.move(
            dispo.x() + (dispo.width() - largeur) // 2,
            dispo.y() + (dispo.height() - hauteur) // 2,
        )
    else:
        fenetre.resize(980, 700)
    icone = "/usr/share/icons/hicolor/128x128/apps/lexos-reglages.png"
    if Path(icone).exists():
        fenetre.setWindowIcon(QIcon(icone))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)
    vue.load(QUrl(url))
    fenetre.show()

    code = app.exec()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
