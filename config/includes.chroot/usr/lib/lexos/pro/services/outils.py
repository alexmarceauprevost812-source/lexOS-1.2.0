"""Le catalogue des outils — et leur BRANCHEMENT sur le système réel.

D'APRÈS LA PLANCHE D'ALEX, mais ce module n'est pas une planche : chaque
entrée pointe sur quelque chose qui existe, et sait dire ce qui manque
quand ça manque. La consigne d'origine l'écrit noir sur blanc — « ne
transforme pas l'image entière en arrière-plan de faux boutons ».

CINQ GENRES, ET LA DIFFÉRENCE COMPTE :

  · « page »     — une page de LEXOS PRO. Toujours disponible : c'est nous.
  · « dossier »  — un dossier XDG. Disponible s'il existe vraiment sur le
                   disque ; on ne propose pas « Vidéos » à quelqu'un qui
                   n'en a pas.
  · « commande » — une application du système. On essaie une liste de
                   candidats DANS L'ORDRE et on prend le premier installé.
                   Aucun ? La tuile est éteinte, et elle dit lesquels on a
                   cherchés — pas « indisponible » tout court.
  · « terminal » — un outil en ligne de commande, ouvert dans le vrai
                   terminal. Docker et les bases de données n'ont pas de
                   fenêtre ; prétendre le contraire serait un faux bouton.
  · « session »  — éteindre, redémarrer, fermer la session. DEMANDE
                   CONFIRMATION, toujours : ce sont les trois seules
                   actions de cette page qui font perdre du travail.

RIEN N'EST LANCÉ PAR UN SHELL. Comme partout ailleurs dans LEXOS PRO, les
commandes partent en liste d'arguments par services.execution.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from . import capacites, execution, fichiers

PAGE, DOSSIER, COMMANDE, TERMINAL, SESSION = (
    "page", "dossier", "commande", "terminal", "session")


@dataclass
class Outil:
    cle: str
    libelle: str
    icone: str
    categorie: str
    genre: str
    cible: object = None
    description: str = ""
    confirmation: str = ""
    candidats: list = field(default_factory=list)


#  Les cinq rangées de la planche, dans son ordre.
CATALOGUE = [
    # ── Poste de travail ────────────────────────────────────────────────
    Outil("maison", "Dossier personnel", "maison", "Poste de travail",
          DOSSIER, "~", "Vos fichiers, à la racine de votre compte."),
    Outil("fichiers", "Fichiers", "fichiers", "Poste de travail",
          PAGE, "fichiers", "Le gestionnaire de fichiers de LEXOS PRO."),
    Outil("terminal", "Terminal", "terminal", "Poste de travail",
          PAGE, "terminal", "Ouvrir le vrai terminal du système."),
    Outil("navigateur", "Navigateur Web", "navigateur", "Poste de travail",
          PAGE, "navigateur", "Ouvrir une adresse dans le navigateur."),
    Outil("messagerie", "Messagerie", "enveloppe", "Poste de travail",
          COMMANDE, None, "Votre client de courrier électronique.",
          candidats=["thunderbird", "evolution", "geary", "kmail",
                     "claws-mail", "betterbird"]),
    Outil("editeur", "Éditeur de texte", "texte", "Poste de travail",
          COMMANDE, None, "Écrire et modifier du texte.",
          candidats=["mousepad", "gnome-text-editor", "gedit", "kate",
                     "code", "codium", "featherpad"]),
    #  « Centre de logiciels » dépasse la largeur d'une tuile. « Logithèque »
    #  est de toute façon le mot que le reste de LexOS emploie.
    Outil("logitheque", "Logithèque", "sacoche", "Poste de travail",
          COMMANDE, None, "Centre de logiciels : installer et retirer des "
                          "applications.",
          candidats=["lexos-logitheque", "gnome-software",
                     "plasma-discover", "mintinstall"]),
    Outil("parametres", "Paramètres", "parametres", "Poste de travail",
          PAGE, "parametres", "Les dix pages de réglages de LEXOS PRO."),
    Outil("corbeille", "Corbeille", "corbeille", "Poste de travail",
          COMMANDE, None, "Les fichiers mis de côté, encore récupérables.",
          candidats=["gio", "xdg-open"]),

    # ── Matériel et système ─────────────────────────────────────────────
    Outil("systeme", "Système", "systeme", "Matériel et système",
          PAGE, "parametres:systeme", "Machine, distribution, noyau."),
    Outil("reseau", "Réseau", "globe", "Matériel et système",
          PAGE, "parametres:reseau", "Interfaces, adresses, connectivité."),
    Outil("securite", "Sécurité", "securite", "Matériel et système",
          PAGE, "securite", "Pare-feu, Secure Boot, ports en écoute."),
    Outil("disques", "Disques", "disque-dur", "Matériel et système",
          COMMANDE, None, "Volumes, partitions et espace libre.",
          candidats=["lexos-disques", "gnome-disks", "gparted",
                     "partitionmanager"]),
    Outil("peripheriques", "Périphériques", "usb", "Matériel et système",
          COMMANDE, None, "Clés USB, téléphones, appareils branchés.",
          candidats=["lexos-peripheriques", "lexos-usb"]),
    Outil("camera", "Caméra", "camera", "Matériel et système",
          COMMANDE, None, "La webcam de la machine.",
          candidats=["cheese", "guvcview", "snapshot", "kamoso"]),
    Outil("images", "Images", "image", "Matériel et système",
          DOSSIER, "XDG_PICTURES_DIR", "Votre dossier d'images."),
    Outil("videos", "Vidéos", "video", "Matériel et système",
          DOSSIER, "XDG_VIDEOS_DIR", "Votre dossier de vidéos."),
    Outil("musique", "Musique", "audio", "Matériel et système",
          DOSSIER, "XDG_MUSIC_DIR", "Votre dossier de musique."),

    # ── Travail ─────────────────────────────────────────────────────────
    Outil("documents", "Documents", "texte", "Travail",
          DOSSIER, "XDG_DOCUMENTS_DIR", "Votre dossier de documents."),
    Outil("telechargements", "Téléchargements", "telechargement", "Travail",
          DOSSIER, "XDG_DOWNLOAD_DIR", "Ce que vous avez téléchargé."),
    Outil("cloud", "Cloud", "nuage", "Travail",
          COMMANDE, None, "Synchronisation avec un serveur de fichiers.",
          candidats=["nextcloud", "owncloud", "insync", "dropbox",
                     "megasync"]),
    Outil("developpement", "Développement", "developpement", "Travail",
          PAGE, "developpement", "Projets, Git, environnements, tests."),
    Outil("graphisme", "Graphisme", "pinceau", "Travail",
          COMMANDE, None, "Dessin et retouche d'images.",
          candidats=["lexos-studio", "gimp", "krita", "inkscape",
                     "pinta", "drawing"]),
    Outil("multimedia", "Multimédia", "video", "Travail",
          COMMANDE, None, "Lecteur audio et vidéo.",
          candidats=["vlc", "mpv", "celluloid", "totem", "haruna"]),
    Outil("jeux", "Jeux", "manette", "Travail",
          COMMANDE, None, "La ludothèque de la machine.",
          candidats=["lexos-jeux", "lexos-game", "steam", "lutris",
                     "heroic"]),
    Outil("calculatrice", "Calculatrice", "calculatrice", "Travail",
          COMMANDE, None, "Calculs simples et scientifiques.",
          candidats=["galculator", "gnome-calculator", "kcalc",
                     "qalculate-gtk", "xcalc"]),
    Outil("calendrier", "Calendrier", "calendrier", "Travail",
          COMMANDE, None, "Agenda et rendez-vous.",
          candidats=["lexos-volet", "gnome-calendar", "korganizer",
                     "orage", "evolution"]),

    # ── Outils avancés ──────────────────────────────────────────────────
    Outil("archive", "Archive", "archive", "Outils avancés",
          COMMANDE, None, "Ouvrir et créer des archives.",
          candidats=["xarchiver", "file-roller", "ark", "engrampa"]),
    Outil("imprimantes", "Imprimantes", "imprimante", "Outils avancés",
          COMMANDE, None, "Ajouter et gérer les imprimantes.",
          candidats=["system-config-printer", "gnome-control-center"]),
    Outil("aide", "Aide", "bouee", "Outils avancés",
          COMMANDE, None, "L'aide de LexOS, dans un terminal.",
          candidats=["lexos"]),
    Outil("outils_systeme", "Outils système", "cube", "Outils avancés",
          COMMANDE, None, "Diagnostic matériel et santé de la machine.",
          candidats=["lexos-diagnostic", "lexos-materiel", "lexos-medecin"]),
    Outil("virtualisation", "Virtualisation", "virtualisation",
          "Outils avancés", COMMANDE, None,
          "Machines virtuelles.",
          candidats=["virt-manager", "virtualbox", "gnome-boxes",
                     "vmware"]),
    Outil("conteneurs", "Conteneurs", "conteneurs", "Outils avancés",
          TERMINAL, ["docker", "ps", "-a"],
          "L'état des conteneurs, dans un terminal.",
          candidats=["docker", "podman"]),
    Outil("bases", "Bases de données", "base", "Outils avancés",
          COMMANDE, None, "Parcourir une base de données.",
          candidats=["dbeaver", "sqlitebrowser", "pgadmin4", "mysql-workbench"]),
    Outil("outils", "Outils", "cles", "Outils avancés",
          PAGE, "parametres:applications",
          "Toutes les applications installées."),
    Outil("vpn", "VPN", "vpn", "Outils avancés",
          COMMANDE, None, "Réseau privé virtuel.",
          candidats=["lexos-vpn", "nm-connection-editor"]),

    # ── Session ─────────────────────────────────────────────────────────
    Outil("moniteur", "Moniteur système", "performances", "Session",
          PAGE, "parametres:performances",
          "Courbes du processeur et liste des processus."),
    Outil("journaux", "Journaux", "journal", "Session",
          PAGE, "parametres:services",
          "Les journaux des services accessibles."),
    #  « Gestionnaire de mots de passe » ne tient pas sur une tuile et
    #  s'affichait « Gestionnaire de mots…passe ». Le libellé court va sur
    #  la tuile, le nom complet reste dans la description — donc dans
    #  l'infobulle, où il y a la place.
    Outil("motsdepasse", "Mots de passe", "cle", "Session",
          COMMANDE, None, "Gestionnaire de mots de passe : votre coffre.",
          candidats=["lexos-prive", "keepassxc", "seahorse", "bitwarden"]),
    Outil("utilisateurs", "Utilisateurs", "personnes", "Session",
          COMMANDE, None, "Les comptes de la machine.",
          candidats=["lexos-utilisateurs", "gnome-control-center",
                     "users-admin"]),
    Outil("apparence", "Apparence", "apparence", "Session",
          PAGE, "parametres:apparence",
          "Thème, taille du texte, densité, animations."),
    Outil("langues", "Langues", "langues", "Session",
          COMMANDE, None, "Langue du système et disposition du clavier.",
          candidats=["lexos-clavier", "gnome-control-center",
                     "xfce4-keyboard-settings"]),
    Outil("eteindre", "Éteindre", "alimentation", "Session",
          SESSION, "poweroff", "Arrêter complètement la machine.",
          confirmation="Éteindre la machine ?\n\nTout travail non "
                       "enregistré sera perdu."),
    Outil("redemarrer", "Redémarrer", "redemarrer", "Session",
          SESSION, "reboot", "Redémarrer la machine.",
          confirmation="Redémarrer la machine ?\n\nTout travail non "
                       "enregistré sera perdu."),
    Outil("deconnexion", "Déconnexion", "sortie", "Session",
          SESSION, "logout", "Fermer la session et revenir à l'écran "
                             "de connexion.",
          confirmation="Fermer la session ?\n\nLes applications ouvertes "
                       "seront fermées."),
]

CATEGORIES = ["Poste de travail", "Matériel et système", "Travail",
              "Outils avancés", "Session"]

#  Les trois façons d'éteindre, par ordre de préférence. loginctl et
#  systemctl parlent à systemd-logind, qui applique la politique du système
#  (il refusera si un autre utilisateur est connecté, par exemple) — c'est
#  le mécanisme prévu, pas un raccourci.
_SESSION = {
    "poweroff": (["systemctl", "poweroff"], ["loginctl", "poweroff"]),
    "reboot": (["systemctl", "reboot"], ["loginctl", "reboot"]),
    "logout": (["lexos-session", "logout"], ["loginctl", "terminate-user",
                                             str(os.getuid())]),
}


def _dossier_cible(cible: str) -> str:
    """Le chemin d'un dossier XDG, ou vide s'il n'existe pas."""
    if cible == "~":
        return str(Path.home())
    chemin = os.environ.get(cible, "")
    if not chemin:
        for entree in fichiers.dossiers_usuels():
            #  dossiers_usuels() lit déjà user-dirs.dirs ; on s'appuie
            #  dessus plutôt que de relire le fichier une seconde fois.
            attendu = {"XDG_PICTURES_DIR": "Images",
                       "XDG_VIDEOS_DIR": "Vidéos",
                       "XDG_MUSIC_DIR": "Musique",
                       "XDG_DOCUMENTS_DIR": "Documents",
                       "XDG_DOWNLOAD_DIR": "Téléchargements"}.get(cible)
            if attendu and entree["nom"] == attendu:
                chemin = entree["chemin"]
                break
    return chemin if chemin and os.path.isdir(chemin) else ""


def resoudre(outil: Outil) -> dict:
    """Cet outil est-il utilisable ICI, et par quoi exactement ?

    Rend toujours une raison quand ce n'est pas le cas — c'est elle qui
    s'affichera sur la tuile éteinte. « Indisponible » tout court
    n'apprend rien à personne.
    """
    if outil.genre == PAGE:
        return {"disponible": True, "genre": PAGE, "page": outil.cible,
                "detail": "Page de LEXOS PRO"}

    if outil.genre == DOSSIER:
        chemin = _dossier_cible(outil.cible)
        if chemin:
            return {"disponible": True, "genre": DOSSIER, "chemin": chemin,
                    "detail": chemin}
        return {"disponible": False,
                "raison": f"Ce dossier n'existe pas sur ce compte "
                          f"({outil.cible}). Créez-le, ou déclarez-le dans "
                          f"~/.config/user-dirs.dirs."}

    if outil.genre == SESSION:
        for argv in _SESSION.get(outil.cible, ()):
            if execution.outil_present(argv[0]):
                return {"disponible": True, "genre": SESSION, "argv": argv,
                        "detail": " ".join(argv)}
        return {"disponible": False,
                "raison": "Ni systemctl ni loginctl n'est disponible : "
                          "LEXOS PRO ne sait pas arrêter cette machine."}

    #  COMMANDE et TERMINAL : le premier candidat installé gagne.
    trouve = capacites.premier_present(tuple(outil.candidats))
    if not trouve:
        return {"disponible": False,
                "raison": "Aucun de ces programmes n'est installé : "
                          + ", ".join(outil.candidats) + "."}
    if outil.genre == TERMINAL:
        argv = [trouve] + list(outil.cible[1:])
        return {"disponible": True, "genre": TERMINAL, "argv": argv,
                "detail": " ".join(argv)}
    argv = _argv_commande(outil, trouve)
    return {"disponible": True, "genre": COMMANDE, "argv": argv,
            "detail": " ".join(argv)}


def _argv_commande(outil: Outil, programme: str) -> list:
    """Les arguments à passer, quand l'outil choisi en demande.

    gnome-control-center n'ouvre rien d'utile sans sa section ; « gio »
    n'ouvre pas la corbeille sans l'URI. Deviner « le programme sans
    argument fait la bonne chose » donne des boutons qui s'ouvrent sur la
    mauvaise page — ou sur rien.
    """
    sections = {
        "imprimantes": "printers", "utilisateurs": "user-accounts",
        "langues": "region",
    }
    if programme == "gnome-control-center" and outil.cle in sections:
        return [programme, sections[outil.cle]]
    if outil.cle == "corbeille":
        #  « gio open trash:/// » et « xdg-open trash:/// » — deux verbes
        #  différents pour la même chose. La première version de cette
        #  branche fabriquait un argument VIDE au milieu de la liste pour
        #  xdg-open ; un argv avec un trou n'est pas une commande.
        return ([programme, "open", "trash:///"] if programme == "gio"
                else [programme, "trash:///"])
    if outil.cle == "aide":
        return [programme, "aide"]
    if outil.cle == "calendrier" and programme == "lexos-volet":
        return [programme, "agenda"]
    if outil.cle == "vpn" and programme == "nm-connection-editor":
        return [programme]
    return [programme]


def lancer(outil: Outil) -> execution.Resultat:
    """Lance l'outil. Les pages et les dossiers ne passent PAS par ici :
    l'interface les traite elle-même (changer de page, ouvrir Fichiers)."""
    r = resoudre(outil)
    if not r["disponible"]:
        return execution.Resultat(False, erreur=r["raison"])
    if r["genre"] in (COMMANDE, SESSION):
        return execution.lancer_detache(r["argv"])
    if r["genre"] == TERMINAL:
        from . import terminal
        return terminal.ouvrir_commande(r["argv"])
    return execution.Resultat(
        False, erreur=f"Le genre « {r['genre']} » se traite dans "
                      f"l'interface, pas ici.")


def par_categorie() -> dict:
    groupes = {c: [] for c in CATEGORIES}
    for o in CATALOGUE:
        groupes.setdefault(o.categorie, []).append(o)
    return groupes


def etat_general() -> dict:
    """Combien de tuiles sont réellement branchées — pour la zone de statut."""
    dispo = sum(1 for o in CATALOGUE if resoudre(o)["disponible"])
    return {"total": len(CATALOGUE), "disponibles": dispo,
            "manquants": len(CATALOGUE) - dispo}
