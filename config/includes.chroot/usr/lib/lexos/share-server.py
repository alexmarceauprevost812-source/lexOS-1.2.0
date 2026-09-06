#!/usr/bin/env python3
"""
LexOS — serveur de partage local (envoi et réception de fichiers)

Sert un dossier en HTTP sur le réseau local, avec une page d'accueil sobre :
    · liste des fichiers partagés, téléchargeables d'un clic
    · formulaire d'envoi pour recevoir des fichiers depuis un téléphone

Pensé pour durer quelques minutes, le temps d'un transfert, puis s'arrêter.
Il n'écoute que sur le réseau local et ne demande aucune application côté
téléphone : on scanne le QR code et c'est tout.

Usage :
    share-server.py --dir <dossier> [--port 0] [--recv <dossier>] [--minutes 15]
"""

import argparse
import html
import http.server
import os
import secrets
import socket
import socketserver
import sys
import threading
import time
import urllib.parse

CSS = """
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body {
  margin: 0; padding: 24px 16px 48px;
  background: #000; color: #fff;
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
.wrap { max-width: 640px; margin: 0 auto; }
h1 { font-size: 26px; margin: 0 0 4px; letter-spacing: -.5px; }
h1 span { color: #E8590C; }
.sub { color: #8A8A90; font-size: 14px; margin: 0 0 28px; }
h2 { font-size: 14px; text-transform: uppercase; letter-spacing: 1.5px;
     color: #8A8A90; margin: 32px 0 12px; font-weight: 600; }
ul { list-style: none; padding: 0; margin: 0; }
li { border-bottom: 1px solid #1C1C20; }
li:first-child { border-top: 1px solid #1C1C20; }
a.file {
  display: flex; justify-content: space-between; gap: 12px; align-items: center;
  padding: 14px 4px; color: #fff; text-decoration: none;
}
a.file:hover { background: #0E0E10; }
a.file .name { overflow-wrap: anywhere; }
a.file .size { color: #8A8A90; font-size: 13px; white-space: nowrap; }
form { border: 1px dashed #2A2A30; border-radius: 10px; padding: 20px; }
input[type=file] { width: 100%; color: #B8B8BC; margin-bottom: 14px; }
button {
  background: #E8590C; color: #fff; border: 1px solid #A84007;
  border-radius: 6px; padding: 11px 20px; font-size: 15px; font-weight: 600;
  cursor: pointer; width: 100%;
}
button:hover { background: #FF7A33; }
.msg { background: #0E1A10; border: 1px solid #1F8F4E; color: #2DBF6B;
       border-radius: 8px; padding: 12px 14px; margin-bottom: 20px; font-size: 15px; }
.empty { color: #8A8A90; padding: 14px 4px; }
footer { margin-top: 40px; color: #4A4A50; font-size: 12px; text-align: center; }
"""

PAGE = """<!doctype html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Partage LexOS</title>
<style>{css}</style>
</head><body><div class="wrap">
<h1>Lex<span>OS</span></h1>
<p class="sub">Partage local &middot; {host}</p>
{message}
<h2>Fichiers partagés</h2>
{files}
{upload}
<footer>Ce partage s'arrête tout seul dans {minutes} minutes.</footer>
</div></body></html>
"""

UPLOAD_FORM = """<h2>M'envoyer un fichier</h2>
<form method="post" enctype="multipart/form-data">
  <input type="file" name="fichier" multiple required>
  <button type="submit">Envoyer vers l'ordinateur</button>
</form>
"""


def human(size):
    for unit in ("o", "Kio", "Mio", "Gio"):
        if size < 1024 or unit == "Gio":
            return f"{size:.0f} {unit}" if unit == "o" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} Gio"


class Handler(http.server.SimpleHTTPRequestHandler):
    share_dir = "."
    recv_dir = None
    minutes = 15
    message = ""
    token = ""

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s %s\n" % (self.address_string(), fmt % args))

    # --- Jeton d'accès -------------------------------------------------------
    #  Le serveur écoute sur tout le réseau local : sans jeton, n'importe qui
    #  sur le même wifi (un café, une salle d'attente) lirait les fichiers
    #  partagés et pourrait en déposer. Le jeton vit dans l'adresse encodée
    #  par le QR code : scanner marche toujours, deviner ne marche pas.
    def _strip_token(self):
        """Renvoie le chemin sans le jeton, ou None si le jeton est absent/faux.

        Jeton vide = tout est refusé. Un oubli de configuration doit fermer la
        porte, jamais l'ouvrir : main() en pose toujours un.
        """
        if not self.token:
            return None
        path = urllib.parse.urlparse(self.path).path
        prefix = "/" + self.token
        if path == prefix:
            return "/"
        if path.startswith(prefix + "/"):
            # compare_digest : comparaison à temps constant, pas de fuite par
            # mesure du temps de réponse.
            got = path[1:len(self.token) + 1]
            if secrets.compare_digest(got, self.token):
                return path[len(prefix):]
        return None

    def _deny(self):
        """Répond 404 — ne confirme jamais qu'un partage tourne ici."""
        body = b"404"
        self.send_response(404)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # --- Page d'accueil ------------------------------------------------------
    def render_index(self):
        try:
            names = sorted(
                n for n in os.listdir(self.share_dir)
                if os.path.isfile(os.path.join(self.share_dir, n))
            )
        except OSError:
            names = []

        if names:
            items = []
            for n in names:
                size = os.path.getsize(os.path.join(self.share_dir, n))
                items.append(
                    '<li><a class="file" href="{href}" download>'
                    '<span class="name">{name}</span>'
                    '<span class="size">{size}</span></a></li>'.format(
                        href=urllib.parse.quote(n),
                        name=html.escape(n),
                        size=human(size),
                    )
                )
            files = "<ul>" + "".join(items) + "</ul>"
        else:
            files = '<p class="empty">Aucun fichier partagé pour l\'instant.</p>'

        msg = f'<p class="msg">{html.escape(self.message)}</p>' if self.message else ""
        Handler.message = ""

        body = PAGE.format(
            css=CSS,
            host=html.escape(self.headers.get("Host", "")),
            message=msg,
            files=files,
            upload=UPLOAD_FORM if self.recv_dir else "",
            minutes=self.minutes,
        ).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        inner = self._strip_token()
        if inner is None:
            self._deny()
            return
        if inner in ("/", "/index.html"):
            self.render_index()
            return
        super().do_GET()

    def copyfile(self, source, outputfile):
        # Un téléphone qui annule un téléchargement ferme brutalement la
        # connexion : c'est normal, ça n'a pas à polluer le journal.
        try:
            super().copyfile(source, outputfile)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # --- Réception -----------------------------------------------------------
    #  Parseur multipart maison, en flux. Le module cgi de la bibliothèque
    #  standard aurait fait l'affaire, mais il disparaît en Python 3.13 :
    #  autant ne pas dépendre d'une pièce condamnée.
    #
    #  Toutes les lectures sont bornées par Content-Length. En HTTP/1.1 la
    #  connexion reste ouverte après le corps : lire « jusqu'à EOF » bloquerait
    #  indéfiniment.
    def _read(self, n):
        """Lit n octets au plus, en vidant d'abord le tampon d'avance.

        Après un délimiteur, `_pending` contient déjà des octets lus au réseau —
        typiquement les en-têtes de la partie suivante. Toute lecture doit
        passer par ici : sinon ces octets sont perdus et, dans un envoi
        multiple, tous les fichiers après le premier disparaissent.
        """
        data = b""
        if self._pending:
            data, self._pending = self._pending[:n], self._pending[n:]
            if len(data) >= n:
                return data
        return data + self._raw_read(n - len(data))

    def _raw_read(self, n):
        n = min(n, self._remaining)
        if n <= 0:
            return b""
        data = self.rfile.read(n)
        self._remaining -= len(data)
        return data

    def _readline(self):
        """Une ligne d'en-tête, tampon d'avance compris."""
        idx = self._pending.find(b"\n")
        if idx != -1:
            line, self._pending = self._pending[:idx + 1], self._pending[idx + 1:]
            return line
        line, self._pending = self._pending, b""
        if self._remaining > 0:
            more = self.rfile.readline(min(8192, self._remaining))
            self._remaining -= len(more)
            line += more
        return line

    def _read_part_headers(self):
        headers = {}
        while True:
            line = self._readline()
            if not line or line in (b"\r\n", b"\n"):
                return headers
            name, _, value = line.decode("utf-8", "replace").partition(":")
            if name:
                headers[name.strip().lower()] = value.strip()

    @staticmethod
    def _filename_of(disposition):
        for piece in disposition.split(";"):
            piece = piece.strip()
            if piece.startswith("filename="):
                return piece[9:].strip().strip('"')
        return None

    def _stream_until_boundary(self, delim, out):
        """Recopie la partie courante dans `out` jusqu'au délimiteur.

        Renvoie True si le délimiteur a été trouvé, False si le corps s'est
        terminé avant (envoi tronqué).
        """
        keep = len(delim)
        buf = b""
        while True:
            idx = buf.find(delim)
            if idx != -1:
                if out is not None:
                    out.write(buf[:idx])
                self._pending = buf[idx + keep:]
                return True
            # On garde de quoi reconnaître un délimiteur à cheval sur deux blocs.
            if len(buf) > keep:
                if out is not None:
                    out.write(buf[:-keep])
                buf = buf[-keep:]
            chunk = self._read(1 << 16)
            if not chunk:
                if out is not None and buf:
                    out.write(buf)
                return False
            buf += chunk

    def _unique_path(self, name):
        # Seul le nom de base compte : aucun chemin ne vient du client.
        name = os.path.basename(name).replace("\\", "_").lstrip(".") or "fichier"
        dest = os.path.join(self.recv_dir, name)
        stem, ext = os.path.splitext(dest)
        i = 1
        while os.path.exists(dest):
            dest = f"{stem}-{i}{ext}"
            i += 1
        return dest

    def do_POST(self):
        if self._strip_token() is None:
            self._deny()
            return
        if not self.recv_dir:
            self.send_error(403, "Reception desactivee")
            return

        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype or "boundary=" not in ctype:
            self.send_error(400, "Envoi illisible")
            return

        try:
            self._remaining = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(411, "Content-Length manquant")
            return
        if self._remaining <= 0:
            self.send_error(400, "Corps vide")
            return

        boundary = ctype.split("boundary=", 1)[1].strip().strip('"').encode("utf-8")
        delim = b"\r\n--" + boundary
        self._pending = b""

        first = self._readline()
        if not first.startswith(b"--" + boundary):
            self.send_error(400, "Envoi mal forme")
            return

        saved = []
        while self._remaining > 0 or self._pending:
            headers = self._read_part_headers()
            if not headers:
                break

            name = self._filename_of(headers.get("content-disposition", ""))
            if name:
                dest = self._unique_path(name)
                with open(dest, "wb") as out:
                    found = self._stream_until_boundary(delim, out)
                saved.append(os.path.basename(dest))
                print(f"  reçu : {dest}", flush=True)
            else:
                # Champ de formulaire sans fichier : consommé et oublié.
                found = self._stream_until_boundary(delim, None)

            if not found:
                break

            # Après le délimiteur vient soit "--" (fin), soit CRLF (suite).
            tail = self._read(2)
            if tail.startswith(b"--"):
                break

        Handler.message = (
            "Reçu : " + ", ".join(saved) if saved else "Aucun fichier reçu."
        )
        self.send_response(303)
        self.send_header("Location", "/" + self.token + "/")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def translate_path(self, path):
        # Sert exclusivement depuis le dossier de partage. basename() écrase
        # toute tentative de remontée (« ../../etc/passwd ») ; le jeton, lui,
        # a déjà été vérifié par do_GET avant d'arriver ici.
        path = urllib.parse.urlparse(path).path
        name = os.path.basename(urllib.parse.unquote(path))
        return os.path.join(self.share_dir, name)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def local_ip():
    """Adresse de cette machine sur le réseau local.

    connect() en UDP n'envoie aucun paquet : il se contente de demander au
    noyau quelle interface servirait à joindre cette destination.
    """
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 9))
        addr = s.getsockname()[0]
    except OSError:
        addr = ""
    finally:
        s.close()

    if addr and not addr.startswith("127."):
        return addr

    # Repli : première adresse non-locale trouvée sur la machine.
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            cand = info[4][0]
            if not cand.startswith("127."):
                return cand
    except OSError:
        pass
    return "127.0.0.1"


#  Le port du partage, et ses replis. 45407 est celui qu'Alex avait sur sa
#  photo : il n'a rien de spécial, sinon d'être déjà passé par là et de ne
#  correspondre à aucun service connu. Les deux suivants servent quand la
#  machine partage déjà (deux fenêtres ouvertes en même temps), et le 0 final
#  est le vieux comportement — on préfère un partage qui démarre sur un port
#  imprévisible à un partage qui refuse de démarrer.
PORT_PARTAGE = 45407
PORTS_REPLI = (45408, 45409, 0)


def ouvrir_serveur(port):
    """Ouvre le serveur sur `port`, ou sur le premier repli disponible.

    On n'essaie PAS de deviner si le port est libre avant de s'en servir :
    entre le test et l'ouverture, un autre programme peut le prendre. On
    tente, et on regarde ce que le noyau répond."""
    for essai in (port,) + PORTS_REPLI:
        try:
            return Server(("0.0.0.0", essai), Handler)
        except OSError as e:
            #  EADDRINUSE seulement : une adresse refusée pour une autre
            #  raison (droits, pile réseau absente) ne se répare pas en
            #  changeant de port, et l'essayer trois fois masquerait la
            #  vraie cause derrière le dernier message.
            if e.errno not in (98, 48):      # Linux, BSD
                raise
    raise OSError("aucun port disponible pour le partage")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--recv", default=None)
    #  ═══ UN PORT FIXE, ET C'EST CE QUI DÉBLOQUE LE PARTAGE ═══
    #  ALEX : « on n'est pas capable de partager réellement, même quand je
    #  scanne le code QR ». Le port était tiré au hasard (« --port 0 »,
    #  45407 sur sa photo) — et « lexos secure enable » pose
    #  « ufw default deny incoming ». Le téléphone tapait donc à une porte
    #  murée, et aucune règle de pare-feu posée à la main n'aurait pu suivre
    #  un port qui change à chaque partage.
    #
    #  LA SÉCURITÉ NE VIENT PAS DU PORT, ELLE VIENT DU JETON. C'est déjà écrit
    #  plus haut, à l'endroit où le jeton est tiré : treize caractères
    #  d'os.urandom dans l'adresse. Un port fixe ne donne rien à personne —
    #  sans le jeton, le serveur rend 404 sur tout.
    ap.add_argument("--port", type=int, default=PORT_PARTAGE)
    ap.add_argument("--minutes", type=int, default=15)
    args = ap.parse_args()

    Handler.share_dir = os.path.abspath(args.dir)
    Handler.recv_dir = os.path.abspath(args.recv) if args.recv else None
    Handler.minutes = args.minutes
    # ~13 caractères tirés de os.urandom : deviner l'adresse est hors de portée
    # pendant les quinze minutes où le partage vit.
    Handler.token = secrets.token_urlsafe(10)

    httpd = ouvrir_serveur(args.port)
    port = httpd.server_address[1]
    url = f"http://{local_ip()}:{port}/{Handler.token}/"

    print(url, flush=True)

    def stop_later():
        time.sleep(args.minutes * 60)
        print("  temps écoulé — partage fermé", flush=True)
        httpd.shutdown()

    threading.Thread(target=stop_later, daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
