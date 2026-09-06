#!/usr/bin/env python3
"""
LexOS — la fenêtre « Partager ».

CE QU'ELLE REMPLACE, ET POURQUOI.
« lexos share qr » affichait son QR dans une fenêtre yad : un dialogue GTK
générique, l'image en haut, le texte en balises Pango. Alex, photo de l'ISO 72 :
« la page pour partager, elle est pas pareille ». Elle ne pouvait pas l'être —
yad ne prend pas le thème LexOS, et son bouton reste le bouton du thème GTK
courant. On passe donc au même patron que tous les autres panneaux : une page
web locale dans une fenêtre Qt (voir settings.py, volet.py, cartes.py).

CE QU'ELLE NE FAIT PAS. Elle ne démarre PAS le serveur de partage et ne
choisit PAS les fichiers : c'est lexos-share qui fait déjà les deux, et qui
sait déjà arrêter le serveur au bon moment. Elle reçoit l'adresse toute faite
et se contente de l'AFFICHER. Refaire ce travail ici aurait donné deux
chemins qui démarrent des serveurs, deux façons de les arrêter, et un jour un
serveur oublié en train de servir le dossier personnel sur le réseau.

COMMENT ELLE S'ARRÊTE. Elle se ferme d'elle-même à la fin du délai, ou quand
on clique « Fermer le partage ». lexos-share attend la première des deux fins
(« wait -n ») et tue le serveur derrière — le comportement qu'il avait déjà
avec la fenêtre yad, sans rien changer à cette mécanique.

LA SÉCURITÉ, comme dans le reste de LexOS : la page ne peut demander que les
actions de la liste ACTIONS, la liste est fermée, et subprocess reçoit
toujours une LISTE d'arguments, jamais une chaîne passée à un shell.
"""
import argparse
import base64
import functools
import http.server
import json
import mimetypes
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.request
import time
from pathlib import Path

BASE_DIR = Path(os.environ.get("LEXOS_PARTAGE_DIR", "/usr/share/lexos/partage"))
WEB_DIR = BASE_DIR / "web"

#  LA LISTE EST FERMÉE. Un nom qui n'est pas ici ne fait rien, et le serveur
#  répond 400 sans regarder plus loin. C'est la même règle que dans volet.py.
ACTIONS = {"fermer", "ouvrir-recus"}

ETAT = {}
FERMER = threading.Event()


# =============================================================================
#  Le QR
# =============================================================================
def qr_data_uri(url):
    """Rend le QR en PNG et le renvoie en data:URI, ou None.

    POURQUOI UN PNG ET NON UN QR EN CARACTÈRES. Un QR dessiné avec des blocs
    de texte n'a pas des modules carrés : ça dépend de la police et de
    l'interligne du terminal. L'appareil photo du téléphone peut refuser de
    le lire — le genre de défaut qui marche chez celui qui l'a écrit et pas
    chez l'autre.

    -m 2 : la « zone calme » autour du code. Elle fait partie de la norme ;
    la rogner pour gagner de la place casse la lecture.
    """
    if not shutil.which("qrencode"):
        return None
    try:
        png = subprocess.run(
            ["qrencode", "-t", "PNG", "-s", "8", "-m", "2", "-l", "M", "-o", "-", url],
            capture_output=True, timeout=10, check=True,
        ).stdout
    except (subprocess.SubprocessError, OSError):
        return None
    if not png:
        return None
    return "data:image/png;base64," + base64.b64encode(png).decode("ascii")


# =============================================================================
#  Les fichiers
# =============================================================================
def taille_lisible(n):
    for unite in ("o", "Ko", "Mo", "Go", "To"):
        if n < 1024 or unite == "To":
            if unite == "o":
                return f"{n} o"
            return f"{n:.1f} {unite}".replace(".", ",")
        n /= 1024.0
    return f"{n} o"


def decris(chemins):
    out = []
    for c in chemins:
        p = Path(c)
        try:
            out.append({"nom": p.name, "taille": taille_lisible(p.stat().st_size)})
        except OSError:
            #  Un fichier disparu entre le lancement et l'affichage n'est pas
            #  une raison de ne rien montrer du tout.
            out.append({"nom": p.name, "taille": "—"})
    return out


def moyens():
    """Les autres façons d'envoyer, avec leur état RÉEL.

    On regarde si l'outil est là ET s'il répond, plutôt que d'afficher un
    bouton qui promet quelque chose qui n'existe pas sur cette machine.
    """
    liste = []

    nom, pret = "Aucun appareil apparié", False
    if shutil.which("kdeconnect-cli"):
        try:
            sortie = subprocess.run(
                ["kdeconnect-cli", "--list-available", "--id-name-only"],
                capture_output=True, text=True, timeout=4,
            ).stdout.strip()
            if sortie:
                premier = sortie.splitlines()[0].split(None, 1)
                nom = premier[1] if len(premier) > 1 else premier[0]
                pret = True
        except (subprocess.SubprocessError, OSError):
            pass
        liste.append({"nom": "KDE Connect", "detail": nom,
                      "etat": "Joignable" if pret else "Rien en vue", "pret": pret})
    else:
        liste.append({"nom": "KDE Connect", "detail": "Pas installé",
                      "etat": "Absent", "pret": False})

    allume = False
    if shutil.which("bluetoothctl"):
        try:
            s = subprocess.run(["bluetoothctl", "show"], capture_output=True,
                               text=True, timeout=4).stdout
            allume = "Powered: yes" in s
        except (subprocess.SubprocessError, OSError):
            pass
    liste.append({"nom": "Bluetooth", "detail": "Sans Wi-Fi, mais plus lent",
                  "etat": "Allumé" if allume else "Éteint", "pret": allume})
    return liste


# =============================================================================
#  L'AUTO-VÉRIFICATION — pour que l'outil se teste lui-même
# =============================================================================
#  ALEX : « on n'est pas capable de partager réellement, même quand je scanne
#  le code QR ». Le serveur allait bien, le QR aussi, le jeton aussi. Il n'y
#  avait AUCUN moyen, depuis la fenêtre, de savoir ce qui coinçait — et donc
#  aucun moyen de savoir où chercher. Un outil qui ne peut pas dire pourquoi
#  il ne marche pas fait perdre plus de temps que le défaut lui-même.
#
#  TROIS QUESTIONS, ET CE QUE CHACUNE PROUVE VRAIMENT. C'est le point
#  important : aucune ne prouve tout, et il faut le dire plutôt que d'annoncer
#  « Prêt » sur une demi-mesure.
#
#    1. Le serveur répond-il sur l'ADRESSE DU RÉSEAU, et pas sur 127.0.0.1 ?
#       Prouve que la prise est ouverte sur la bonne interface et que le jeton
#       est bon. Ne prouve PAS que le pare-feu laisse passer : du trafic vers
#       sa propre adresse passe par la boucle locale, qu'ufw autorise par
#       défaut. C'est justement pourquoi la question 2 existe.
#
#    2. ufw est-il actif, et notre port ouvert ? C'est LA cause la plus
#       probable, et la seule des trois qu'on sache réparer.
#       On ne demande PAS ce diagnostic à root : « ufw status » l'exige, et
#       réclamer un mot de passe pour AFFICHER une ligne d'état serait
#       insupportable. lexos-share, lui, connaît déjà la réponse — il vient de
#       poser la question avant d'ouvrir le port — et nous la passe.
#
#    3. Sommes-nous seulement sur un réseau ? Sans adresse IPv4 autre que la
#       boucle locale, il n'y a personne à joindre. Aucun programme ne peut
#       savoir si LE TÉLÉPHONE est sur le même Wi-Fi ; on nomme donc la piste
#       plutôt que de prétendre l'avoir écartée — beaucoup de routeurs, et
#       presque tous les réseaux « invité », interdisent à deux appareils de
#       se parler.
def diagnostic(url, pare_feu):
    """Rend {niveau, texte, detail} — trois états, jamais un quatrième."""
    hote, port = "", ""
    try:
        reste = url.split("://", 1)[1]
        hote_port = reste.split("/", 1)[0]
        hote, _, port = hote_port.partition(":")
    except (IndexError, ValueError):
        pass

    #  3. Une adresse sur le réseau, ou rien.
    if not hote or hote.startswith("127.") or hote == "localhost":
        return {"niveau": "reseau",
                "texte": "Le téléphone doit être sur le même Wi-Fi",
                "detail": "Cette machine n'a pas d'adresse sur un réseau local."}

    #  2. Le pare-feu, tel que lexos-share l'a trouvé AVANT d'ouvrir.
    if pare_feu == "ferme":
        return {"niveau": "pare-feu",
                "texte": "Pare-feu à ouvrir",
                "detail": f"ufw refuse les entrées : sudo ufw allow {port}/tcp"}

    #  1. Le serveur répond-il, pour de vrai, sur l'adresse du réseau ?
    #     Un délai court : la fenêtre ne doit pas rester grise pendant qu'on
    #     interroge une prise qui ne répondra jamais.
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            joignable = 200 <= r.status < 400
    except urllib.error.HTTPError:
        #  Une réponse d'erreur EST une réponse : la prise est ouverte et
        #  quelque chose écoute. C'est tout ce que cette question demande.
        joignable = True
    except (urllib.error.URLError, OSError, ValueError):
        joignable = False

    if not joignable:
        return {"niveau": "reseau",
                "texte": "Le téléphone doit être sur le même Wi-Fi",
                "detail": f"Rien ne répond sur {hote}:{port} depuis cette machine."}

    return {"niveau": "pret",
            "texte": "Prêt",
            "detail": "Beaucoup de routeurs isolent les appareils entre eux ; "
                      "si la page ne s'ouvre pas, essaie un autre réseau que "
                      "le réseau « invité »."}


# =============================================================================
#  Le petit serveur qui sert la page — 127.0.0.1 SEULEMENT
# =============================================================================
#  À NE PAS CONFONDRE AVEC LE SERVEUR DE PARTAGE. Celui-là (share-server.py)
#  écoute sur le réseau pour que le téléphone l'atteigne. CELUI-CI n'écoute
#  que sur la boucle locale : il sert l'interface, pas les fichiers, et il n'a
#  aucune raison d'être joignable depuis l'extérieur de la machine.
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # pas de journal : la fenêtre n'est pas un serveur web

    def _json(self, code, obj):
        corps = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        if self.path.split("?")[0] == "/api/etat":
            e = dict(ETAT)
            reste = int(e.pop("_fin") - time.time())
            e.pop("_pare_feu", None)
            e["secondes"] = max(0, reste)
            #  ═══ LES APPAREILS PROCHES NE SONT PLUS DANS L'ÉTAT ═══
            #  moyens() lance kdeconnect-cli et bluetoothctl, chacun avec son
            #  délai de quatre secondes. C'était payé à CHAQUE ouverture de la
            #  fenêtre, pour deux rangées qu'Alex ne voulait plus voir. La
            #  liste est maintenant derrière son bouton, sur /api/appareils :
            #  on ne paie que si on la demande.
            e["diagnostic"] = diagnostic(e.get("url", ""), ETAT.get("_pare_feu", "inconnu"))
            return self._json(200, e)
        if self.path.split("?")[0] == "/api/appareils":
            return self._json(200, {"moyens": moyens()})
        return super().do_GET()

    def do_POST(self):
        if self.path.split("?")[0] != "/api/action":
            return self._json(404, {"erreur": "inconnu"})
        try:
            n = int(self.headers.get("Content-Length", 0))
            if n > 4096:
                return self._json(400, {"erreur": "trop long"})
            demande = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, OSError):
            return self._json(400, {"erreur": "illisible"})

        quoi = demande.get("action")
        if quoi not in ACTIONS:
            return self._json(400, {"erreur": "action refusée"})

        if quoi == "fermer":
            FERMER.set()
        elif quoi == "ouvrir-recus":
            dossier = ETAT.get("recus", "")
            if dossier and shutil.which("xdg-open"):
                try:
                    subprocess.Popen(["xdg-open", dossier],
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
                except OSError:
                    pass
        return self._json(200, {"ok": True})


#  LE MODE D'APPARENCE, POUR LA PAGE.
#  lexos-theme-gen écrit « sombre » ou « clair » dans ~/.config/lexos/mode.
#  On le passe en ?mode=… — pas de nouveau point d'entrée, pas de requête
#  supplémentaire, et l'attribut est posé avant le premier rendu. Sans ça,
#  « lexos theme clair » laisserait cette fenêtre noire au milieu d'un bureau
#  crème. Même fonction, au mot près, que settings.py et volet.py.
def mode_apparence():
    try:
        base = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
        valeur = (Path(base) / "lexos" / "mode").read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError, ValueError):
        #  PAS SEULEMENT OSError : un fichier « mode » écrit dans un autre
        #  encodage lève UnicodeDecodeError, qui n'en est pas une. Un réglage
        #  d'apparence illisible doit faire retomber sur le sombre, jamais
        #  empêcher la fenêtre de s'ouvrir.
        return "sombre"
    #  Tout ce qui n'est pas explicitement « clair » reste sombre : un fichier
    #  vide ou tronqué ne doit pas blanchir l'écran d'un coup.
    return "clair" if valeur == "clair" else "sombre"


def port_libre():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


# =============================================================================
def main():
    ap = argparse.ArgumentParser(description="Fenêtre de partage LexOS")
    ap.add_argument("--url", required=True, help="adresse déjà servie par share-server")
    ap.add_argument("--recus", required=True, help="dossier de réception")
    ap.add_argument("--minutes", type=float, default=15.0)
    #  Ce que lexos-share a trouvé en interrogeant ufw AVANT d'ouvrir le port.
    #  On ne le redemande pas ici : « ufw status » exige root, et réclamer un
    #  mot de passe pour afficher une ligne d'état serait insupportable.
    ap.add_argument("--pare-feu", default="inconnu",
                    choices=("absent", "inactif", "ouvert", "ferme", "inconnu"))
    ap.add_argument("fichiers", nargs="*")
    a = ap.parse_args()

    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        return 1

    ETAT.update({
        "url": a.url,
        "recus": a.recus,
        "qr": qr_data_uri(a.url),
        "fichiers": decris(a.fichiers),
        "_fin": time.time() + a.minutes * 60,
        "_pare_feu": getattr(a, "pare_feu", "inconnu"),
    })

    mimetypes.add_type("text/javascript", ".js")
    port = port_libre()
    serveur = http.server.ThreadingHTTPServer(
        ("127.0.0.1", port), functools.partial(Handler, directory=str(WEB_DIR)))
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-partage-http").start()

    from PySide6.QtCore import QUrl, QTimer
    from PySide6.QtWidgets import QApplication
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName("Partager")
    app.setDesktopFileName("lexos-share")

    vue = QWebEngineView()
    vue.setWindowTitle("Partager — LexOS")
    vue.resize(620, 660)
    vue.load(QUrl(f"http://127.0.0.1:{port}/index.html?mode={mode_apparence()}"))
    vue.show()

    #  Deux façons de finir, et elles se rejoignent ici : le bouton de la page
    #  (FERMER) et l'écoulement du délai. lexos-share attend la mort de cette
    #  fenêtre pour arrêter le serveur de partage.
    def veille():
        if FERMER.is_set() or time.time() >= ETAT["_fin"]:
            app.quit()

    t = QTimer()
    t.timeout.connect(veille)
    t.start(500)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
