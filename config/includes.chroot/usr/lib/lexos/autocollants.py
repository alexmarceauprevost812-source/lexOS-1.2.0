# =============================================================================
#  autocollants — la bibliothèque des découpes, lue par tous les panneaux
# =============================================================================
#  UN MODULE, PAS UN PROGRAMME. Il répond à quatre questions et rien d'autre :
#  qu'y a-t-il, à quoi ça ressemble, mets-le dans le presse-papier, et quel est
#  le vrai chemin. Les Paramètres, la Capture et le Volet l'importent au lieu
#  d'écrire chacun leur version — c'est la même leçon que ui.css : la
#  duplication ne revient jamais d'un coup, elle revient une ligne à la fois.
#
#  ═══ LE DOSSIER **EST** LA BIBLIOTHÈQUE ═══
#  Aucune base, aucun index, aucun fichier de métadonnées. ~/Images/Autocollants
#  fait foi. On doit pouvoir y glisser un PNG à la main dans le gestionnaire de
#  fichiers, ou en supprimer un, et que tout reste juste au rafraîchissement
#  suivant. Un index finit toujours par se désynchroniser, et le jour où ça
#  arrive personne ne comprend pourquoi une image « existe mais ne s'affiche
#  pas ».
#
#  ═══ LA PAGE NE CONNAÎT QUE DES INDICES ═══
#  Aucune fonction ne prend un chemin venant de la page. On énumère, on borne
#  l'indice, et on revalide le nom. C'est la règle déjà posée pour la galerie
#  de fonds d'écran dans settings.py — même raison, même forme : une page web
#  locale reste une page web, et un chemin qui la traverse est un chemin qu'on
#  ne contrôle plus.
#
#  ═══ POURQUOI GdkPixbuf ET RIEN D'AUTRE ═══
#  Il vient avec gir1.2-gtk-3.0, qui est en liste STRICTE — donc toujours là.
#  ImageMagick ne l'est pas, et python3-pil non plus : un sélecteur qui
#  n'affiche rien parce qu'un paquet facultatif a manqué serait exactement la
#  panne silencieuse qu'on passe la journée à chercher.
#  Et il sait faire le damier lui-même : composite_color_simple() compose une
#  image transparente sur un échiquier, ce qui est précisément le rendu de
#  GIMP. Sans lui il aurait fallu dessiner le damier à la main.
# =============================================================================
import os
import unicodedata
from pathlib import Path

#  Les extensions acceptées. On reste sur PNG pour ce que NOUS produisons —
#  seul lui garde la transparence — mais on LIT aussi ce qu'Alex y aurait
#  glissé à la main : le dossier est à lui.
EXTENSIONS = (".png", ".webp")

VIGNETTE_H = 200          # px de haut ; la largeur suit le rapport de l'image
DAMIER = 12               # px du carreau, comme GIMP
DAMIER_CLAIR = 0x999999
DAMIER_SOMBRE = 0x666666


def dossier():
    """~/Images/Autocollants — le même que celui de lexos-sticker.

    On ne le crée PAS ici : lister() sur un dossier absent doit rendre une
    liste vide, pas fabriquer un dossier vide dans le dossier personnel de
    quelqu'un qui n'a jamais demandé d'autocollant.
    """
    return Path(os.environ.get("LEXOS_AUTOCOLLANTS",
                               Path.home() / "Images" / "Autocollants"))


def _fichiers():
    """Les autocollants, du plus récent au plus ancien.

    TRI PAR DATE DE MODIFICATION, et c'est le bon choix ici : on vient de
    découper une image, on veut la retrouver EN PREMIER. Un tri alphabétique
    obligerait à chercher.

    Les fichiers cachés sont écartés — .avant-modif/ y range les copies de
    sécurité de Studio+, et elles n'ont rien à faire dans la grille.
    """
    d = dossier()
    try:
        noms = [f for f in d.iterdir()
                if f.is_file()
                and not f.name.startswith(".")
                and f.suffix.lower() in EXTENSIONS]
    except OSError:
        return []
    noms.sort(key=lambda f: (-f.stat().st_mtime, f.name.lower()))
    return noms


def lister():
    """Ce que la page affiche : des indices, des noms, des tailles, des dates.

    Jamais de chemin. La page n'en a pas besoin — elle demande la vignette par
    « ?i=N » et les actions par le même indice.
    """
    out = []
    for i, f in enumerate(_fichiers()):
        try:
            st = f.stat()
        except OSError:
            continue
        out.append({
            "i": i,
            #  NFC : deux fichiers dont le nom s'écrit « é » ou « e+accent »
            #  s'affichent pareil et se comparent faux. On normalise ce qu'on
            #  MONTRE ; le chemin réel, lui, n'est jamais reconstruit d'après
            #  cette chaîne.
            "nom": unicodedata.normalize("NFC", f.name),
            "taille_o": st.st_size,
            "date": int(st.st_mtime),
        })
    return out


def chemin(i, nom=""):
    """Le vrai chemin, revalidé. None si l'indice ne désigne plus rien.

    DEUX GARDES, ET LA SECONDE EST CELLE QU'ON OUBLIE. Borner l'indice ne
    suffit pas : entre l'affichage de la grille et le clic, un fichier a pu
    être supprimé dans le gestionnaire de fichiers, et l'indice 3 désigne
    alors une AUTRE image. On recoupe donc le nom quand la page le fournit,
    et on refuse plutôt que d'agir sur la mauvaise.
    """
    fichiers = _fichiers()
    try:
        i = int(i)
    except (TypeError, ValueError):
        return None
    if not (0 <= i < len(fichiers)):
        return None
    f = fichiers[i]
    if nom and unicodedata.normalize("NFC", f.name) != unicodedata.normalize("NFC", nom):
        return None
    #  Ceinture et bretelles : le chemin résolu doit rester DANS le dossier.
    #  Un lien symbolique posé à la main pointant ailleurs ne doit pas faire
    #  sortir « supprimer » du périmètre.
    try:
        reel = f.resolve()
        if dossier().resolve() not in reel.parents:
            return None
    except OSError:
        return None
    return str(f)


def vignette(i, hauteur=VIGNETTE_H):
    """Les octets PNG d'une miniature, composée sur un DAMIER.

    ═══ POURQUOI LE DAMIER N'EST PAS UNE COQUETTERIE ═══
    Un autocollant à fond transparent affiché tel quel sur le panneau NOIR de
    LexOS a l'air d'une image vide. La moitié de la collection semblerait
    ratée, et la conclusion naturelle serait « la découpe ne marche pas ».
    Le damier gris clair / gris foncé est la convention de tous les éditeurs
    d'image : il dit « ici, c'est transparent » sans un mot.
    """
    p = chemin(i)
    if p is None:
        return None
    try:
        import gi
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf
    except Exception:
        return None
    try:
        px = GdkPixbuf.Pixbuf.new_from_file_at_scale(p, -1, hauteur, True)
        if px is None:
            return None
        if px.get_has_alpha():
            px = px.composite_color_simple(
                px.get_width(), px.get_height(),
                GdkPixbuf.InterpType.BILINEAR, 255,
                DAMIER, DAMIER_CLAIR, DAMIER_SOMBRE)
        ok, octets = px.save_to_bufferv("png", [], [])
        return bytes(octets) if ok else None
    except Exception:
        return None


def copier(i, nom=""):
    """Met l'autocollant dans le presse-papier, transparence conservée.

    ═══ C'EST LE BOUTON QUI COUVRE 90 % DES USAGES ═══
    On n'écrira jamais GIMP, ni Firefox, ni une messagerie. Le seul chemin
    universel vers ces logiciels-là est le presse-papier : un PNG copié avec
    son canal alpha se colle dans n'importe quoi. Les intégrations maison
    (Capture, Volet) sont du confort ; celui-ci est la fonction.

    ═══ UNE LIMITE À CONNAÎTRE, ET ELLE N'EST PAS DE NOUS ═══
    Sous X11, le presse-papier appartient au PROCESSUS qui l'a rempli : si le
    panneau des Paramètres se ferme avant qu'on colle, le contenu disparaît,
    sauf si un gestionnaire de presse-papier tourne. C'est le fonctionnement
    de X11, pas un défaut d'ici — mais c'est la raison pour laquelle on ne
    ferme pas la fenêtre juste après avoir copié.
    """
    p = chemin(i, nom)
    if p is None:
        return False
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import Gtk, Gdk, GdkPixbuf
    except Exception:
        return False
    try:
        px = GdkPixbuf.Pixbuf.new_from_file(p)
        cp = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        cp.set_image(px)
        cp.store()          # demander au gestionnaire de presse-papier, s'il y en a un
        return True
    except Exception:
        return False


def supprimer(i, nom=""):
    """Retire un autocollant. Le chemin est revalidé par chemin()."""
    p = chemin(i, nom)
    if p is None:
        return False
    try:
        os.remove(p)
        return True
    except OSError:
        return False
