"""Ce que CETTE machine sait faire — mesuré une fois, partagé partout.

POURQUOI CENTRALISER. Sans ce module, chaque page redécouvrirait de son
côté s'il y a systemd, quel gestionnaire de paquets répond, si la session
est Wayland… avec à chaque fois une chance de se tromper différemment.
Ici, la question est posée UNE fois et la réponse est la même partout.

ET SURTOUT : « Ubuntu » n'est pas « Debian ».
Les deux partagent apt, mais pas leurs noms de paquets, pas leurs dépôts,
pas leur outil graphique de logiciels. La consigne est explicite là-dessus,
et c'est pour ça que `distribution()` rend l'ID **et** la liste ID_LIKE
séparément : une page qui veut « une famille Debian » demande la famille,
une page qui veut « Ubuntu précisément » demande l'ID. On ne confond
jamais les deux dans le même test.
"""
from __future__ import annotations

import functools
import os
import shutil
from dataclasses import dataclass, field

from . import execution


@dataclass
class Distribution:
    id: str = ""
    nom: str = ""
    version: str = ""
    familles: list = field(default_factory=list)   # ID_LIKE, découpé
    source: str = ""

    @property
    def connue(self) -> bool:
        return bool(self.id)

    def est(self, *ids) -> bool:
        """L'identifiant EXACT — « ubuntu » ne répond pas à est('debian')."""
        return self.id in ids

    def dans_famille(self, *ids) -> bool:
        """L'ID ou l'une de ses familles. Ubuntu répond ici à « debian »."""
        return self.id in ids or any(f in ids for f in self.familles)

    def libelle(self) -> str:
        if not self.connue:
            return "Distribution inconnue"
        return self.nom or self.id


def _lire_os_release() -> dict:
    """/etc/os-release, lu comme des données — jamais exécuté."""
    valeurs = {}
    for chemin in ("/etc/os-release", "/usr/lib/os-release"):
        r = execution.lire_fichier(chemin)
        if not r.ok:
            continue
        for ligne in r.sortie.splitlines():
            ligne = ligne.strip()
            if not ligne or ligne.startswith("#") or "=" not in ligne:
                continue
            cle, _, val = ligne.partition("=")
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            valeurs.setdefault(cle.strip(), val)
        valeurs.setdefault("__source__", chemin)
        if valeurs:
            break
    return valeurs


@functools.lru_cache(maxsize=1)
def distribution() -> Distribution:
    v = _lire_os_release()
    if not v:
        return Distribution()
    familles = [x for x in (v.get("ID_LIKE") or "").split() if x]
    return Distribution(
        id=v.get("ID", ""),
        nom=v.get("PRETTY_NAME") or v.get("NAME", ""),
        version=v.get("VERSION_ID", ""),
        familles=familles,
        source=v.get("__source__", ""),
    )


@functools.lru_cache(maxsize=1)
def est_lexos() -> bool:
    """LexOS se reconnaît à son ID ou à son dossier de configuration."""
    d = distribution()
    return d.est("lexos") or os.path.isdir("/etc/lexos")


# --- Session graphique -------------------------------------------------------
@functools.lru_cache(maxsize=1)
def session() -> dict:
    """Wayland, X11, ou aucune — et on le dit franchement.

    XDG_SESSION_TYPE est la réponse de systemd-logind ; WAYLAND_DISPLAY et
    DISPLAY sont les preuves directes. On préfère la preuve directe, parce
    que XDG_SESSION_TYPE vaut « tty » dans plus d'un cas où un serveur
    graphique tourne quand même.
    """
    wayland = bool(os.environ.get("WAYLAND_DISPLAY"))
    x11 = bool(os.environ.get("DISPLAY"))
    if wayland:
        type_ = "wayland"
    elif x11:
        type_ = "x11"
    else:
        type_ = os.environ.get("XDG_SESSION_TYPE") or "aucune"
    return {
        "type": type_,
        "bureau": os.environ.get("XDG_CURRENT_DESKTOP") or "",
        "gestionnaire": os.environ.get("DESKTOP_SESSION") or "",
        "graphique": wayland or x11,
    }


def bureau_est(*noms) -> bool:
    """XDG_CURRENT_DESKTOP peut valoir « ubuntu:GNOME » : on découpe."""
    brut = (session().get("bureau") or "").lower()
    morceaux = {m.strip() for m in brut.replace(";", ":").split(":") if m.strip()}
    return any(n.lower() in morceaux for n in noms)


# --- Outils : on ne cherche qu'une fois -------------------------------------
#  L'ordre de chaque liste est un ordre de PRÉFÉRENCE, pas un hasard.
TERMINAUX = ("lexos-pro-terminal", "xfce4-terminal", "gnome-terminal",
             "konsole", "kitty", "alacritty", "tilix", "mate-terminal",
             "lxterminal", "xterm")
EDITEURS = ("code", "codium", "zed", "subl", "gnome-text-editor", "kate",
            "mousepad", "gedit", "nvim", "vim", "nano")
GESTIONNAIRES_FICHIERS = ("thunar", "nautilus", "dolphin", "nemo", "pcmanfm",
                          "caja")
LOGITHEQUES = ("gnome-software", "plasma-discover", "mintinstall",
               "pamac-manager", "lexos-logitheque")


@functools.lru_cache(maxsize=None)
def premier_present(noms: tuple) -> str:
    for n in noms:
        if shutil.which(n):
            return n
    return ""


@functools.lru_cache(maxsize=None)
def tous_presents(noms: tuple) -> tuple:
    return tuple(n for n in noms if shutil.which(n))


@functools.lru_cache(maxsize=1)
def gestionnaire_paquets() -> dict:
    """Le mécanisme de mise à jour RÉELLEMENT présent.

    On mesure la présence de l'outil, on ne la déduit pas de la
    distribution : une Debian sans apt existe (image minimale), et un
    système hybride aussi.
    """
    familles = (
        ("apt", ["apt", "apt-get"], "Debian / Ubuntu"),
        ("dnf", ["dnf"], "Fedora / RHEL"),
        ("zypper", ["zypper"], "openSUSE"),
        ("pacman", ["pacman"], "Arch"),
        ("apk", ["apk"], "Alpine"),
        ("xbps", ["xbps-install"], "Void"),
    )
    for nom, outils, famille in familles:
        present = [o for o in outils if shutil.which(o)]
        if present:
            return {"nom": nom, "outils": present, "famille": famille,
                    "trouve": True}
    return {"nom": "", "outils": [], "famille": "",
            "trouve": False,
            "raison": "Aucun gestionnaire de paquets connu n'a été trouvé "
                      "sur le PATH (apt, dnf, zypper, pacman, apk, xbps)."}


@functools.lru_cache(maxsize=1)
def systemd() -> dict:
    """systemd tourne-t-il VRAIMENT, ou l'outil est-il seulement installé ?

    La différence compte : dans un conteneur, systemctl existe souvent sans
    qu'aucun PID 1 systemd ne réponde. Afficher une liste de services vide
    laisserait croire qu'il n'y en a aucun.
    """
    if not shutil.which("systemctl"):
        return {"present": False,
                "raison": "systemctl n'est pas installé sur ce système."}
    if not os.path.isdir("/run/systemd/system"):
        return {"present": False,
                "raison": "systemctl est installé mais systemd n'est pas le "
                          "gestionnaire de services de cette session "
                          "(/run/systemd/system absent)."}
    return {"present": True, "raison": ""}


@functools.lru_cache(maxsize=1)
def audio() -> dict:
    """PipeWire, PulseAudio, ALSA seul — ou rien de mesurable."""
    if shutil.which("wpctl"):
        return {"outil": "wpctl", "pile": "PipeWire (WirePlumber)",
                "present": True}
    if shutil.which("pactl"):
        return {"outil": "pactl", "pile": "PulseAudio ou PipeWire",
                "present": True}
    if shutil.which("amixer"):
        return {"outil": "amixer", "pile": "ALSA", "present": True}
    return {"outil": "", "pile": "", "present": False,
            "raison": "Aucun outil de contrôle du son trouvé "
                      "(wpctl, pactl, amixer)."}


@functools.lru_cache(maxsize=1)
def reseau_gestionnaire() -> dict:
    if shutil.which("nmcli"):
        return {"nom": "NetworkManager", "outil": "nmcli", "present": True}
    if shutil.which("networkctl"):
        return {"nom": "systemd-networkd", "outil": "networkctl",
                "present": True}
    return {"nom": "", "outil": "", "present": False,
            "raison": "Ni nmcli ni networkctl n'est installé : les "
                      "interfaces sont lues directement dans /sys."}


def resume() -> dict:
    """Tout ce qui précède, en un seul objet — pour la page À propos et
    pour l'export de diagnostic."""
    d = distribution()
    return {
        "distribution": {"id": d.id, "nom": d.nom, "version": d.version,
                         "familles": d.familles, "lexos": est_lexos()},
        "session": session(),
        "paquets": gestionnaire_paquets(),
        "systemd": systemd(),
        "audio": audio(),
        "reseau": reseau_gestionnaire(),
        "terminal": premier_present(TERMINAUX),
        "terminaux": list(tous_presents(TERMINAUX)),
        "editeur": premier_present(EDITEURS),
        "editeurs": list(tous_presents(EDITEURS)),
        "fichiers": premier_present(GESTIONNAIRES_FICHIERS),
        "logitheque": premier_present(LOGITHEQUES),
        "outils": {n: bool(shutil.which(n)) for n in
                   ("nvidia-smi", "lspci", "pkexec", "systemctl", "journalctl",
                    "ufw", "firewall-cmd", "ss", "git", "python3",
                    "xdg-open", "gio", "gsettings", "xrandr", "mokutil")},
    }
