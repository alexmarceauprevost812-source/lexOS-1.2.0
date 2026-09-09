#!/usr/bin/env python3
"""LexOS Pro Terminal — le pont local qui rend le terminal RÉEL.

ALEX : « c'est le new terminal officiel de LexOS Pro, pour le terminal
normal je veux que ce soit lui qui le remplace. » Puis, une fois branché
partout : « j'ai beau essayer le terminal LexOS Pro, je suis même pas
capable de lancer claude ».

  ═══ CE QUE CE FICHIER FAISAIT, ET POURQUOI CE N'ÉTAIT PAS SUFFISANT ═══

La première version lançait chaque commande dans un bash JETABLE :
subprocess.run(["bash", "-c", …], stdin=DEVNULL, capture_output=True,
timeout=25). Quatre verrous, dont chacun suffisait à empêcher un programme
interactif de tourner — et surtout AUCUN pseudo-terminal. « isatty() » était
donc faux, et claude, comme tout programme bien élevé, refusait de démarrer.
Une liste (LISTE_TUI) reconnaissait vim, nano, htop, less et man pour
renvoyer un message clair au lieu d'un carnage de codes d'échappement ;
claude n'y était pas, il partait dans le subprocess et se faisait tuer au
bout de 25 secondes. C'est exactement ce qu'ALEX a vu.

  ═══ CE QUE FAIT CE FICHIER MAINTENANT ═══

Un VRAI pseudo-terminal par volet (pty.fork), un shell de connexion qui vit
entre deux commandes, aucun délai, l'entrée branchée, la taille suivie. La
page, elle, tient une vraie grille de caractères avec xterm.js (paquet
Debian node-xterm). vim, nano, htop, less, man, sudo et claude y tournent
comme dans n'importe quel terminal — parce que c'en est un.

Quatre routes, une par sens du tuyau :

  GET  /api/flux?fen=…   la sortie du pty, en flux continu (SSE, base64)
  POST /api/saisie       les frappes, écrites sur le maître du pty
  POST /api/taille       colonnes × lignes (TIOCSWINSZ)
  POST /api/fermer       raccroche le shell et tout ce qu'il a lancé

  ═══ SÉCURITÉ : CE PONT EXÉCUTE N'IMPORTE QUELLE COMMANDE, EXPRÈS ═══

C'est un terminal : accepter d'exécuter ce qu'on tape est tout le produit.
Le risque n'est donc pas « la commande », c'est « qui peut atteindre ce
pont ». Trois verrous, tous nécessaires, sur LES QUATRE ROUTES :

  1. Écoute UNIQUEMENT 127.0.0.1 (comme lexos-settings et lexos-cartes) —
     rien n'est visible depuis le réseau.
  2. Un JETON tiré au hasard à chaque lancement (secrets.token_urlsafe),
     jamais écrit sur le disque, exigé dans l'en-tête « X-Lexos-Jeton » de
     CHAQUE requête. Sans lui : 403, rien n'est exécuté.
  3. L'en-tête « Origin » de la requête, quand le navigateur en pose un,
     doit être exactement http://127.0.0.1:<notre port>.

Pourquoi le jeton ET l'Origine, et pas l'un ou l'autre ? Parce qu'une simple
requête POST (Content-Type: text/plain, sans en-tête personnalisé) part
AVANT que le navigateur ne demande la permission CORS — une page malveillante
ouverte dans un vrai navigateur pourrait donc l'envoyer en aveugle même si
elle ne lira jamais la réponse. Exiger un en-tête personnalisé (le jeton)
change la nature de la requête : le navigateur DOIT alors demander la
permission au serveur avant de l'envoyer pour de vrai (une requête
« préparée », preflight), et notre serveur refuse cette permission à toute
origine autre que la sienne. C'est le jeton qui ferme la porte ; l'Origine
n'est qu'une deuxième serrure.

CE POINT A ÉTÉ MANQUÉ UNE FOIS : à la première écriture des trois routes du
pty, /api/flux ne vérifiait NI l'un NI l'autre — la route qui OUVRE le shell
et déverse tout ce qu'il écrit. Ça n'a pas été vu en relisant le code, mais
en éprouvant les quatre routes contre les trois refus attendus. D'où la
matrice complète dans tests/test_lexos_terminal_pty.sh, jamais un échantillon.
"""
import base64
import fcntl
import functools
import http.server
import json
import os
import pty
import secrets
import shlex
import signal
import socket
import struct
import sys
import termios
import threading
import time
import urllib.parse
from pathlib import Path

APP_NAME = "LexOS Pro Terminal"
WEB_DIR = Path(os.environ.get("LEXOS_TERMINAL_PRO_WEB",
                               "/usr/share/lexos/terminal-pro/web"))
ICON_PATH = Path("/usr/share/icons/hicolor/128x128/apps/lexos-pro-terminal.png")

#  ═══ PIÈCE 1 — UN VRAI PTY, UNE SESSION PAR VOLET ═══
#
#  ALEX : « j'ai beau essayer le terminal LexOS Pro, je suis même pas capable
#  de lancer claude ». Ce n'était pas un bogue : `executer()` ci-dessus lance
#  un bash JETABLE avec stdin=DEVNULL, capture_output=True et un délai de
#  25 s. Trois verrous, dont chacun suffit à empêcher `claude` de tourner —
#  et surtout AUCUN pty, donc `isatty()` est faux et tout programme bien
#  élevé refuse de démarrer en mode interactif.
#
#  Ici, à l'inverse : un pseudo-terminal réel (pty.fork), un shell de
#  connexion qui VIT entre deux commandes, aucun délai, l'entrée branchée.
#  C'est ce que `claude`, `sudo`, `nano`, `htop` et `less` exigent tous.
#
#  ── POURQUOI pty.fork() ET PAS openpty() + subprocess ──────────────────────
#  pty.fork() ne se contente pas d'ouvrir une paire maître/esclave : l'enfant
#  devient CHEF DE SESSION (setsid) et l'esclave devient son TERMINAL DE
#  CONTRÔLE. Sans ce terminal de contrôle il n'y a pas de contrôle de tâches :
#  pas de groupe de processus au premier plan, donc Ctrl+C n'interromprait
#  rien (validation n° 8) et sudo ne trouverait pas de terminal où lire le mot
#  de passe (validation n° 5). openpty() + subprocess.Popen ne donne ça
#  qu'avec start_new_session=True PLUS un TIOCSCTTY à la main ; pty.fork()
#  fait les deux d'un coup et c'est de la bibliothèque standard.
SHELL_DEFAUT = "/bin/bash"

#  Ce que la session garde en mémoire de ce que le pty a déjà écrit. Sert au
#  rattrapage : le flux SSE peut s'attacher quelques millisecondes après le
#  démarrage du shell, et la bannière + la première invite ne doivent pas se
#  perdre. Borné, sinon un `htop` laissé ouvert une nuit remplirait la RAM.
TAMPON_MAX = int(os.environ.get("LEXOS_TERMINAL_PRO_TAMPON", str(256 * 1024)))

#  Un volet = une session. Bornée pour qu'une page en boucle ne puisse pas
#  ouvrir mille shells.
SESSIONS_MAX = int(os.environ.get("LEXOS_TERMINAL_PRO_SESSIONS_MAX", "64"))


class Session:
    """Un shell vivant derrière son pseudo-terminal.

    Un fil de lecture vide le maître en continu dans « tampon » ; les lecteurs
    (le flux SSE) se réveillent sur « cond » et repartent de leur position
    absolue. Le tampon est borné : « perdus » compte les octets déjà jetés,
    pour qu'une position absolue reste juste même après un élagage."""

    def __init__(self, cwd=None, colonnes=80, lignes=24, shell=None,
                 cmd=None):
        self.colonnes = max(2, int(colonnes))
        self.lignes = max(1, int(lignes))
        self.tampon = bytearray()
        self.perdus = 0
        self.fini = False
        self.code = None
        self.cond = threading.Condition()

        depart = cwd if (cwd and os.path.isdir(cwd)) else str(Path.home())
        shell = shell or os.environ.get("SHELL") or SHELL_DEFAUT
        if not os.path.isabs(shell) or not os.access(shell, os.X_OK):
            shell = SHELL_DEFAUT

        #  L'ENVIRONNEMENT EST CONSTRUIT AVANT LE FORK, EXPRÈS. Entre fork()
        #  et exec() dans un programme à plusieurs fils, seul le strict
        #  minimum est sûr : un autre fil peut détenir le verrou du malloc au
        #  moment du fork, et l'enfant qui allouerait se bloquerait pour
        #  toujours. On prépare donc tout ici, et l'enfant ne fait plus que
        #  chdir + signal + execve.
        env = dict(os.environ)
        #  xterm.js annonce xterm-256color : dire autre chose ferait dessiner
        #  les programmes en couleurs pauvres (ou pas du tout).
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LEXOS_TERMINAL"] = "pro"
        #  Ces deux-là appartiennent au pont, pas au shell de l'utilisateur :
        #  les laisser fuiterait le jeton dans l'environnement de CHAQUE
        #  programme lancé (un `env` suffirait à le lire).
        env.pop("LEXOS_TERMINAL_PRO_JETON", None)
        env.pop("LEXOS_TERMINAL_PRO_PORT", None)

        #  argv[0] commençant par « - » : c'est ainsi que login démarre un
        #  SHELL DE CONNEXION. Il lit alors /etc/profile puis ~/.profile —
        #  et c'est ~/.profile qui, sur Debian, source ~/.bashrc. Sans ça,
        #  le PATH de l'utilisateur (~/.local/bin, /usr/local/bin, les
        #  installations de node ou de claude) manquerait, et « claude »
        #  serait « command not found » au lieu de démarrer.
        argv = ["-" + os.path.basename(shell)]
        if cmd:
            argv = [os.path.basename(shell), "-l", "-c", cmd]

        pid, maitre = pty.fork()
        if pid == 0:  # ── l'enfant : le moins de code possible, puis exec ──
            try:
                os.chdir(depart)
            except OSError:
                pass
            #  PYTHON IGNORE SIGPIPE, ET « ignoré » SE TRANSMET À TRAVERS
            #  exec (contrairement à « traité par une fonction », qui est
            #  remis à zéro). Sans cette ligne, tout le shell hérite d'un
            #  SIGPIPE ignoré : « yes | head » ne s'arrête plus jamais, et
            #  la moitié des pipelines se comportent bizarrement. Le même
            #  raisonnement vaut pour SIGINT/SIGQUIT si quelqu'un les avait
            #  ignorés plus haut.
            for sig in (signal.SIGPIPE, signal.SIGINT, signal.SIGQUIT,
                        signal.SIGTERM, signal.SIGHUP, signal.SIGCHLD):
                try:
                    signal.signal(sig, signal.SIG_DFL)
                except (OSError, ValueError):
                    pass
            try:
                os.execve(shell, argv, env)
            except OSError:
                os._exit(127)
        #  ── le parent ──
        self.pid = pid
        self.maitre = maitre
        self.redimensionner(self.colonnes, self.lignes)
        self._fil = threading.Thread(target=self._lire, daemon=True,
                                     name="lexos-pty-%d" % pid)
        self._fil.start()

    # -- lecture -----------------------------------------------------------
    def _lire(self):
        while True:
            try:
                morceau = os.read(self.maitre, 65536)
            except OSError:
                #  Quand le shell meurt, Linux rend EIO sur le maître — ce
                #  n'est pas une panne, c'est la fin normale de la session.
                morceau = b""
            if not morceau:
                break
            with self.cond:
                self.tampon += morceau
                trop = len(self.tampon) - TAMPON_MAX
                if trop > 0:
                    del self.tampon[:trop]
                    self.perdus += trop
                self.cond.notify_all()
        with self.cond:
            self.fini = True
            self.cond.notify_all()
        try:
            self.code = os.waitpid(self.pid, 0)[1]
        except OSError:
            self.code = -1

    @property
    def total(self):
        """Position absolue de la fin du flux, élagage compris."""
        return self.perdus + len(self.tampon)

    def depuis(self, pos, delai):
        """Rend (octets, nouvelle_position, fini). Attend au plus « delai »
        secondes qu'il y ait quelque chose. Une position antérieure à ce qui
        a été élagué est remontée au plus ancien octet encore là — mieux vaut
        un trou qu'un plantage."""
        with self.cond:
            if pos < self.perdus:
                pos = self.perdus
            if pos >= self.total and not self.fini:
                self.cond.wait(delai)
                if pos < self.perdus:
                    pos = self.perdus
            bloc = bytes(self.tampon[pos - self.perdus:])
            return bloc, pos + len(bloc), self.fini

    # -- écriture ----------------------------------------------------------
    def ecrire(self, donnees):
        """Les frappes, telles quelles, sur le maître. Une écriture partielle
        est possible sur un pty (le tampon du noyau est petit) : on boucle."""
        vus = 0
        while vus < len(donnees):
            try:
                vus += os.write(self.maitre, donnees[vus:])
            except BlockingIOError:
                time.sleep(0.005)
            except OSError:
                return False
        return True

    def redimensionner(self, colonnes, lignes):
        """TIOCSWINSZ sur le MAÎTRE.

        MESURÉ, PAS SUPPOSÉ : cet ioctl suffit — le noyau envoie lui-même
        SIGWINCH au groupe de processus AU PREMIER PLAN du terminal. Ajouter
        un kill(-pgid, SIGWINCH) à la main serait pire que redondant : le
        groupe du shell n'est pas forcément celui du premier plan, on
        réveillerait donc le mauvais programme."""
        self.colonnes = max(2, int(colonnes))
        self.lignes = max(1, int(lignes))
        try:
            fcntl.ioctl(self.maitre, termios.TIOCSWINSZ,
                        struct.pack("HHHH", self.lignes, self.colonnes, 0, 0))
            return True
        except OSError:
            return False

    def _pgid(self):
        try:
            return os.getpgid(self.pid)
        except OSError:
            return -1

    def vivante(self):
        if self.fini:
            return False
        try:
            os.kill(self.pid, 0)
            return True
        except OSError:
            return False

    # -- fermeture ---------------------------------------------------------
    def fermer(self):
        """SIGHUP au GROUPE, pas au seul shell.

        Fermer un onglet pendant qu'un `htop` tourne ne doit pas laisser de
        processus orphelin (validation n° 11) : `htop` est un enfant du shell,
        tuer le shell seul le laisserait vivant, rattaché à init. Le signal
        part donc au groupe entier — c'est exactement ce que fait un vrai
        terminal quand sa fenêtre se ferme, d'où le nom du signal
        (« hang up », raccrocher)."""
        #  MESURÉ : un travail lancé depuis le shell interactif — au premier
        #  plan (`htop`) comme en fond (`sleep 300 &`) — reçoit SON PROPRE
        #  groupe de processus, différent de celui du shell. Signaler le seul
        #  groupe du shell ne l'atteint donc PAS directement ; on compte sur
        #  bash pour propager. Alors on frappe les deux : d'abord le groupe
        #  au premier plan du terminal (là où se trouve `htop`), ensuite
        #  celui du shell. Ce que fait un vrai terminal quand sa fenêtre se
        #  ferme, et la raison du nom du signal (« hang up », raccrocher).
        try:
            avant = os.tcgetpgrp(self.maitre)
        except OSError:
            avant = -1
        for cible in (avant, self._pgid()):
            if cible and cible > 0:
                try:
                    os.killpg(cible, signal.SIGHUP)
                except OSError:
                    pass
        try:
            os.kill(self.pid, signal.SIGHUP)
        except OSError:
            pass
        #  Fermer le maître fait aussi arriver EOF/EIO côté esclave : le fil
        #  de lecture sort de sa boucle et la session se marque finie.
        try:
            os.close(self.maitre)
        except OSError:
            pass
        with self.cond:
            self.fini = True
            self.cond.notify_all()


#  Le registre des sessions vivantes, une par volet. La clé est l'identifiant
#  que la page fabrique pour chaque volet (onglet ou division).
SESSIONS = {}
_VERROU_SESSIONS = threading.Lock()


def session_de(fen, creer=False, cwd=None, colonnes=80, lignes=24, cmd=None):
    """Rend la session du volet « fen », en la créant si demandé. Une session
    morte est remplacée, jamais rendue telle quelle."""
    with _VERROU_SESSIONS:
        s = SESSIONS.get(fen)
        if s is not None and not s.vivante():
            SESSIONS.pop(fen, None)
            s = None
        if s is None and creer:
            if len(SESSIONS) >= SESSIONS_MAX:
                raise RuntimeError("trop de sessions ouvertes")
            s = Session(cwd=cwd, colonnes=colonnes, lignes=lignes, cmd=cmd)
            SESSIONS[fen] = s
        return s


def fermer_session(fen):
    with _VERROU_SESSIONS:
        s = SESSIONS.pop(fen, None)
    if s is not None:
        s.fermer()
        return True
    return False


def fermer_toutes():
    with _VERROU_SESSIONS:
        vivantes = list(SESSIONS.values())
        SESSIONS.clear()
    for s in vivantes:
        s.fermer()


#  ═══ LE SERVEUR ═══
class Handler(http.server.SimpleHTTPRequestHandler):
    jeton = ""
    port = 0

    def log_message(self, fmt, *args):
        pass

    def _json(self, code, donnees):
        corps = json.dumps(donnees).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def _origine_valide(self):
        """Absente : un fetch same-origin depuis notre propre page ne pose
        PAS toujours cet en-tête selon le navigateur — on ne bloque donc que
        l'en-tête présent ET faux, jamais son absence pure."""
        o = self.headers.get("Origin", "")
        return o == "" or o == "http://127.0.0.1:%d" % self.port

    def _autorise(self):
        """═══ LES DEUX SERRURES, SUR TOUTES LES ROUTES ═══

        Le modèle de sécurité ne bouge pas d'un pouce avec l'arrivée du pty :
        les trois routes nouvelles (/api/flux, /api/saisie, /api/taille) sont
        exactement aussi exigeantes que /api/exec l'était. Le raisonnement
        derrière — pourquoi le jeton ET l'origine — est écrit en tête de
        fichier ; c'est le jeton qui ferme la porte."""
        if not self._origine_valide():
            self._json(403, {"ok": False, "erreur": "origine refusée"})
            return False
        recu = self.headers.get("X-Lexos-Jeton", "")
        if not (recu and secrets.compare_digest(recu, self.jeton)):
            self._json(403, {"ok": False, "erreur": "jeton absent ou invalide"})
            return False
        return True

    def _corps(self):
        """Le JSON de la requête, ou None (400 déjà envoyé)."""
        try:
            taille = int(self.headers.get("Content-Length", "0"))
            return json.loads(self.rfile.read(taille) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._json(400, {"ok": False, "erreur": "requête invalide"})
            return None

    def do_GET(self):
        chemin, _, requete = self.path.partition("?")
        if chemin == "/api/flux":
            return self._flux(urllib.parse.parse_qs(requete))
        if chemin.startswith("/api/"):
            return self._json(404, {"ok": False, "erreur": "inconnu"})
        return super().do_GET()

    #  ═══ PIÈCE 3 — LE TUYAU, SENS PONT → PAGE ═══
    def _flux(self, params):
        """Sortie du pty en flux continu (text/event-stream).

        POURQUOI DU BASE64 ET PAS LE TEXTE TEL QUEL : ce qui sort d'un pty
        est un flot d'OCTETS, et on le lit par blocs de 64 ko. Un caractère
        accentué (deux octets en UTF-8), un emoji (quatre), ou n'importe
        quel dessin de cadre peut se faire couper EN PLEIN MILIEU par une
        frontière de bloc. Décoder chaque bloc en texte ici produirait des
        « ￼ » à la place — et les recoller correctement demanderait de
        garder un décodeur à état par session. Le base64 transporte les
        octets intacts ; c'est xterm.js, de l'autre côté, qui tient le
        décodeur UTF-8 à état et recolle les morceaux. En prime, le base64
        ne contient jamais de « \n », donc rien ne peut casser le découpage
        en événements SSE."""
        #  LE FLUX EST UNE ROUTE COMME LES AUTRES. Première écriture : cette
        #  vérification manquait — /api/flux créait un shell et déversait sa
        #  sortie à qui la demandait, sans jeton ni origine. Trouvé en
        #  éprouvant les quatre routes contre les trois refus attendus, pas
        #  en relisant le code : les trois routes POST passaient, celle-ci
        #  répondait 200. C'est la route la PLUS sensible des quatre — elle
        #  ouvre le shell et montre tout ce qu'il écrit.
        if not self._autorise():
            return

        def prem(nom, defaut=""):
            v = params.get(nom, [defaut])
            return v[0] if v else defaut

        fen = prem("fen").strip()
        if not fen:
            return self._json(400, {"ok": False, "erreur": "fen manquant"})
        try:
            colonnes = int(prem("colonnes", "80") or 80)
            lignes = int(prem("lignes", "24") or 24)
        except ValueError:
            colonnes, lignes = 80, 24
        #  ON NE CONSOMME LE DÉMARRAGE QUE SI UN SHELL VA VRAIMENT NAÎTRE.
        #  Le consommer sans rien créer — flux rouvert sur une session déjà
        #  là, après un hoquet du tuyau — perdrait pour de bon le
        #  « -e "lexos capture video" » du lanceur : la fenêtre s'ouvrirait
        #  sur une invite nue, sans que rien n'explique pourquoi.
        depart = None if session_de(fen) is not None else _prendre_demarrage()
        try:
            s = session_de(fen, creer=True,
                           cwd=(depart and depart["cwd"]) or prem("cwd") or None,
                           colonnes=colonnes, lignes=lignes,
                           cmd=(depart and depart["cmd"]) or None)
        except Exception as e:  # noqa: BLE001 — la fenêtre doit survivre
            return self._json(500, {"ok": False, "erreur": str(e)})

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        pos = 0
        try:
            while True:
                #  Le réveil au bout d'une seconde n'est pas de l'attente
                #  active : sans lui, un volet fermé par la page ne serait
                #  JAMAIS remarqué — on ne s'en aperçoit qu'en écrivant sur
                #  la prise. Le « : » est un commentaire SSE, ignoré par le
                #  lecteur, et c'est lui qui déclenche l'erreur d'écriture.
                bloc, pos, fini = s.depuis(pos, 1.0)
                if bloc:
                    self.wfile.write(b"data: " +
                                     base64.b64encode(bloc) + b"\n\n")
                elif fini:
                    self.wfile.write(b"event: fin\ndata: {}\n\n")
                    self.wfile.flush()
                    return
                else:
                    self.wfile.write(b": .\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            #  La page a fermé le volet ou s'est rechargée. Le shell, lui,
            #  reste vivant : c'est /api/fermer qui le raccroche, pas la
            #  perte du tuyau — sinon un simple hoquet réseau local tuerait
            #  la session en cours.
            return

    def do_POST(self):
        if self.path in ("/api/saisie", "/api/taille", "/api/fermer"):
            return self._route_pty(self.path)
        return self._json(404, {"ok": False, "erreur": "inconnu"})

    #  ═══ PIÈCE 3 — LE TUYAU, SENS PAGE → PONT ═══
    def _route_pty(self, chemin):
        if not self._autorise():
            return
        requete = self._corps()
        if requete is None:
            return
        fen = str(requete.get("fen", "")).strip()
        if not fen:
            return self._json(400, {"ok": False, "erreur": "fen manquant"})

        if chemin == "/api/fermer":
            return self._json(200, {"ok": True, "ferme": fermer_session(fen)})

        s = session_de(fen)
        if s is None:
            return self._json(404, {"ok": False, "erreur": "session absente"})

        if chemin == "/api/taille":
            try:
                colonnes = int(requete.get("colonnes", 80))
                lignes = int(requete.get("lignes", 24))
            except (TypeError, ValueError):
                return self._json(400, {"ok": False, "erreur": "taille invalide"})
            return self._json(200, {"ok": s.redimensionner(colonnes, lignes)})

        #  /api/saisie — les frappes. Du TEXTE JSON, pas du base64 : ce que
        #  xterm.js remonte est déjà une chaîne (« a », « \x1b[A » pour la
        #  flèche du haut, une ligne entière collée…), et JSON transporte
        #  n'importe quelle chaîne sans dommage. C'est l'inverse du sens
        #  descendant, où l'on manipule des octets bruts découpés au hasard.
        texte = requete.get("texte", "")
        if not isinstance(texte, str):
            return self._json(400, {"ok": False, "erreur": "saisie invalide"})
        return self._json(200, {"ok": s.ecrire(texte.encode("utf-8"))})


def _port_libre():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def demarrer_serveur():
    """Démarre le pont sur un port libre, avec un jeton neuf. Rend
    (serveur, port, jeton) — l'appelant décide de la fenêtre."""
    port = _port_libre()
    jeton = secrets.token_urlsafe(32)
    classe = type("HandlerJeton", (Handler,), {"jeton": jeton, "port": port})
    handler = functools.partial(classe, directory=str(WEB_DIR))
    serveur = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=serveur.serve_forever, daemon=True,
                     name="lexos-terminal-pro-http").start()
    return serveur, port, jeton


#  ═══ CE QUE LA LIGNE DE COMMANDE A DEMANDÉ POUR LE PREMIER VOLET ═══
#  « Ouvrir un terminal ici » de Thunar passe --working-directory ; le pont
#  x-terminal-emulator et les lanceurs du panneau passent -e ou -x. Avant, ces
#  options étaient IGNORÉES (le seul argv du fichier était celui de Qt) : le
#  clic droit de Thunar ouvrait le dossier personnel au lieu du dossier visé,
#  et tout ce qui demandait d'exécuter une commande devait partir vers le
#  Terminal classique.
#
#  UNE SEULE FOIS, POUR LE PREMIER VOLET. Un nouvel onglet ouvert ensuite doit
#  recevoir un shell ordinaire, pas rejouer la commande de départ — d'où le
#  drapeau « consomme », et un verrou parce que deux volets peuvent demander
#  leur flux en même temps.
DEMARRAGE = {"cwd": None, "cmd": None, "consomme": False}
_VERROU_DEMARRAGE = threading.Lock()


def _prendre_demarrage():
    with _VERROU_DEMARRAGE:
        if DEMARRAGE["consomme"]:
            return None
        DEMARRAGE["consomme"] = True
        return {"cwd": DEMARRAGE["cwd"], "cmd": DEMARRAGE["cmd"]}


def lire_arguments(args):
    """Rend (cwd, commande, tenir). Reconnaît les formes de xfce4-terminal ET
    la convention Debian de x-terminal-emulator.

    LA DIFFÉRENCE ENTRE LES DEUX N'EST PAS UN DÉTAIL : xfce4-terminal prend
    « -e "ls -la" » — UN seul argument, une ligne de shell entière ;
    x-terminal-emulator prend « -e ls -la » — la commande PUIS ses arguments,
    déjà découpés. Confondre les deux donne soit un « ls -la » introuvable
    (on cherche un programme dont le nom contient une espace), soit un « -la »
    perdu. On distingue au nombre d'arguments restants, et on RECOLLE avec
    shlex.quote quand il y en a plusieurs : le shell recevra exactement les
    mots qu'on lui a donnés, espaces et guillemets compris."""
    cwd = None
    commande = None
    tenir = False
    i = 0
    while i < len(args):
        a = args[i]
        if a.startswith("--working-directory="):
            cwd = a.split("=", 1)[1]
        elif a == "--working-directory" and i + 1 < len(args):
            i += 1
            cwd = args[i]
        elif a in ("--hold", "-hold", "-H"):
            tenir = True
        elif a in ("-e", "--command", "-x"):
            reste = args[i + 1:]
            if len(reste) == 1:
                commande = reste[0]
            elif reste:
                commande = " ".join(shlex.quote(m) for m in reste)
            i = len(args)
        elif a.startswith("--command="):
            commande = a.split("=", 1)[1]
        i += 1
    return cwd, commande, tenir


def main():
    cwd, commande, tenir = lire_arguments(sys.argv[1:])
    DEMARRAGE["cwd"] = cwd
    if commande:
        #  --hold : la fenêtre reste après la fin de la commande. C'est ce que
        #  le lanceur 11 du panneau attend (« lexos capture video »), sans
        #  quoi le volet se ferme avant qu'on ait pu lire le message.
        DEMARRAGE["cmd"] = (
            commande + "\nprintf '\\n\\033[90m— terminé. Entrée pour fermer.\\033[0m'\nread -r _\n"
            if tenir else commande)

    if not WEB_DIR.exists():
        print(f"Erreur : dossier web/ introuvable ({WEB_DIR})", file=sys.stderr)
        sys.exit(1)

    serveur, port, jeton = demarrer_serveur()
    url = f"http://127.0.0.1:{port}/index.html?port={port}&jeton={jeton}"

    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import QApplication, QMainWindow
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)

    fenetre = QMainWindow()
    fenetre.setWindowTitle(APP_NAME)
    ecran = app.primaryScreen()
    if ecran is not None:
        dispo = ecran.availableGeometry()
        largeur = max(760, min(1280, int(dispo.width() * 0.72)))
        hauteur = max(480, min(860, int(dispo.height() * 0.78)))
        fenetre.resize(largeur, hauteur)
        fenetre.move(dispo.x() + (dispo.width() - largeur) // 2,
                     dispo.y() + (dispo.height() - hauteur) // 2)
    else:
        fenetre.resize(1000, 640)
    if ICON_PATH.exists():
        fenetre.setWindowIcon(QIcon(str(ICON_PATH)))

    vue = QWebEngineView(fenetre)
    fenetre.setCentralWidget(vue)

    #  ═══ LE PRESSE-PAPIER, ET POURQUOI IL FAUT DEUX RÉGLAGES ═══
    #  ALEX : le copier-coller ne fonctionnait pas. Deux causes distinctes ;
    #  celle-ci est côté Qt. QtWebEngine DÉSACTIVE PAR DÉFAUT l'accès de
    #  JavaScript au presse-papier — tant que ces attributs ne sont pas
    #  posés, la page ne peut ni écrire ni lire dedans, quoi qu'elle tente.
    #
    #  LES DEUX SONT NÉCESSAIRES ET NE FONT PAS LA MÊME CHOSE :
    #    · JavascriptCanAccessClipboard autorise l'ÉCRITURE (copier) ;
    #    · JavascriptCanPaste          autorise la LECTURE  (coller).
    #  N'en poser qu'un donne un copier-coller à moitié réparé — le collage
    #  marche mais pas la copie, ou l'inverse — et c'est plus long à
    #  diagnostiquer qu'une panne franche.
    #
    #  AVANT le load : après le chargement, les réglages peuvent ne pas
    #  s'appliquer à la page déjà en cours.
    #
    #  ET SOUS try/except, PARCE QU'UN TERMINAL QUI NE S'OUVRE PAS EST PIRE.
    #  Si une version de PySide6 renomme ou déplace ces attributs, la fenêtre
    #  doit s'ouvrir QUAND MÊME, sans presse-papier. Un presse-papier absent
    #  est un désagrément ; une fenêtre qui refuse de s'ouvrir laisse un
    #  système où l'on ne peut plus rien lancer du tout — c'est la règle
    #  écrite en tête de ce fichier. On journalise l'échec, on ne l'avale pas.
    try:
        from PySide6.QtWebEngineCore import QWebEngineSettings
        reglages = vue.settings()
        reglages.setAttribute(
            QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard, True)
        reglages.setAttribute(
            QWebEngineSettings.WebAttribute.JavascriptCanPaste, True)
    except Exception as e:  # noqa: BLE001 — voir le commentaire ci-dessus
        print(f"[lexos-terminal-pro] presse-papier non activé : {e}",
              file=sys.stderr)

    vue.load(QUrl(url))
    fenetre.show()

    code = app.exec()
    #  Raccrocher AVANT de rendre la main : sans ça, fermer la fenêtre
    #  laisserait un shell (et tout ce qu'il a lancé) vivant en fond, sans
    #  plus aucun terminal pour l'atteindre.
    fermer_toutes()
    serveur.shutdown()
    sys.exit(code)


if __name__ == "__main__":
    main()
