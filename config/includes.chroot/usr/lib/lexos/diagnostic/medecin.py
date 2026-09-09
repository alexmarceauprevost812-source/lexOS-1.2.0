"""LexOS Médecin — bilan de santé de la machine INSTALLÉE.

C'est le pendant de verifier.sh (lexos-avant-de-construire.md), mais après
coup : verifier.sh regarde le dépôt avant de construire une ISO ; lexos-medecin
regarde la machine sous vos pieds, une fois installée. Même esprit : ne rien
laisser un trou silencieux, tout mettre en un rapport qu'on peut coller
quand quelqu'un écrit « ça marche pas ».

Plutôt que de faire vivre ici une liste figée des ~63 outils lexos-*
(qui se périmerait au premier outil ajouté), le contrôle des outils se
fait par DÉCOUVERTE : on regarde ce qui existe réellement sous /usr/bin
sur CETTE machine, exactement comme le fait le script bash de
lexos-carte-des-trous.md :

    for f in config/includes.chroot/usr/bin/lexos-*; do
      o=$(basename "$f"); s=${o#lexos-}
      grep -q "^[[:space:]]*$s)" config/includes.chroot/usr/bin/lexos \
        || echo "PAS DANS LE case : $o"
    done

— la même logique, rejouée en direct sur la machine plutôt que sur le dépôt.
"""
from __future__ import annotations

import datetime as _dt
import os
import re
from pathlib import Path

import moteur
from utils import executable_present, executer, lire_version_lexos

#  ═══ LES RACINES SONT DÉTOURNABLES, POUR QUE CE MODULE SOIT ÉPROUVABLE ═══
#  Un diagnostic qui lit /usr/bin et ~/.config ne se teste qu'en changeant de
#  machine. Le banc monte donc un faux système dans un dossier temporaire.
#  Vides de sens en production : les valeurs par défaut sont les vraies.
RACINE = Path(os.environ.get("LEXOS_MEDECIN_RACINE", "/"))
MAISON = Path(os.environ.get("LEXOS_MEDECIN_MAISON", str(Path.home())))

CHEMIN_DISPATCHEUR = RACINE / "usr/bin/lexos"
DOSSIER_BIN = RACINE / "usr/bin"
DOSSIER_LANCEURS = RACINE / "usr/share/applications"
SEUIL_DISQUE_ALERTE = 90  # pourcentage


def _outils_lexos_installes() -> list:
    """Les outils que quelqu'un peut vouloir atteindre — pas les rouages.

    ═══ « *.wrapper » N'EST PAS UN OUTIL, C'EST UN PONT ═══
    Un fichier « .wrapper » est la convention Debian pour l'aiguillage
    d'update-alternatives : « x-terminal-emulator » pointe dessus, et son seul
    travail est de traduire des arguments avant de passer la main. Personne
    ne le tape jamais par son nom, il n'a pas de page de réglages, et aucun
    lanceur ne le désigne — par construction.

    Le compter parmi les outils faisait dire au médecin, à l'écran de
    quelqu'un qui cherche une panne : « lexos-pro-terminal.wrapper :
    joignable par AUCUN chemin ». C'est faux et ça envoie chercher un
    problème là où il n'y en a pas — exactement ce qu'un outil de diagnostic
    ne doit jamais faire. Le contrôle 16 (verifier-parametres.sh) écarte les
    ponts pour la même raison ; les deux inventaires disent maintenant la
    même chose."""
    if not DOSSIER_BIN.is_dir():
        return []
    return sorted(p.name for p in DOSSIER_BIN.glob("lexos-*")
                  if p.is_file() and p.suffix != ".wrapper")


def _texte_dispatcheur():
    if CHEMIN_DISPATCHEUR.is_file():
        try:
            return CHEMIN_DISPATCHEUR.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return None
    return None


# =============================================================================
#  « Est-il joignable ? » — et non « est-il dans le case ? »
# =============================================================================
#  ═══ LE DÉFAUT QU'ON RÉPARE ICI, ET IL ÉTAIT DOUBLE ═══
#  ALEX : « lexos-medecin rapporte 73 problèmes qui n'existent pas ».
#
#  1. L'EXPRESSION NE LISAIT PAS LE case. Elle cherchait « ^\s*capture\) »,
#     donc un nom SUIVI D'UNE PARENTHÈSE. Or le dispatcheur écrit
#     « capture|capture-ecran) », « net|reseau) », « musique|music) » : le nom
#     est suivi d'un « | ». Tout outil ayant un synonyme était déclaré absent.
#     Mesuré sur les 80 outils du dépôt : 7 vus, 73 « problèmes ».
#
#     ET UNE EXPRESSION QUI GÈRE LES ALTERNATIVES NE SUFFIT PAS NON PLUS.
#     La forme proposée — « (?:[a-z0-9_|-]*\|)?NOM(?:\|[a-z0-9_|-]*)? » —
#     monte à 50 vus, mais bute sur les alias ACCENTUÉS, qui sont partout
#     dans ce dispatcheur : « medecin|médecin|doc) », « materiel|matériel| »,
#     « session|arret|arrêt| ». On ne devine donc pas la forme : ON LIT LES
#     ÉTIQUETTES du case et on regarde si le nom est l'une d'elles. 67 vus.
#
#  2. ET SURTOUT, LA QUESTION N'ÉTAIT PAS LA BONNE. Un outil est branché s'il
#     est JOIGNABLE — par n'importe quel chemin. Dix outils ne sont dans aucun
#     case et c'est VOULU : lexos-firstrun part à l'ouverture de session,
#     lexos-usb-notify par une règle udev, lexos-update-check par une
#     minuterie systemd. Les annoncer « absents du dispatcheur » est vrai,
#     inutile, et noie les vrais défauts.
#
#  On cherche donc dans TOUTES les portes d'entrée, et on RAPPORTE PAR
#  LAQUELLE l'outil est atteint. Un outil n'est un problème que s'il n'est
#  joignable NULLE PART.
def _etiquettes_du_case(texte) -> set:
    """Les étiquettes du « case » du dispatcheur, lues et non devinées."""
    etiquettes = set()
    if not texte:
        return etiquettes
    for ligne in texte.split("\n"):
        if ligne.lstrip().startswith("#"):
            continue
        m = re.match(r"^\s*\(?([^)(]+)\)\s*(?:#.*)?$|^\s*\(?([^)(]+)\)\s+", ligne)
        if not m:
            continue
        for e in (m.group(1) or m.group(2)).split("|"):
            e = e.strip().strip("\"'")
            if e:
                etiquettes.add(e)
    return etiquettes


def _sources_joignabilite() -> list:
    """(libellé, fichiers) pour chaque porte d'entrée possible.

    L'ordre compte : c'est celui du rapport, du plus courant au plus rare.
    """
    def fichiers(*motifs):
        out = []
        for m in motifs:
            base, _, motif = m.rpartition("/")
            for racine in (RACINE, MAISON):
                d = (racine / base) if base else racine
                if d.is_dir():
                    out.extend(f for f in d.glob(motif) if f.is_file())
        return out

    return [
        ("un lanceur du menu", fichiers("usr/share/applications/*.desktop")),
        ("le démarrage de session", fichiers("etc/xdg/autostart/*.desktop",
                                             ".config/autostart/*.desktop")),
        ("un service systemd", fichiers("usr/lib/systemd/system/*",
                                        "etc/systemd/system/*")),
        ("une règle udev", fichiers("etc/udev/rules.d/*",
                                    "usr/lib/udev/rules.d/*",
                                    "lib/udev/rules.d/*")),
        ("les réglages XFCE", fichiers(
            ".config/xfce4/xfconf/xfce-perchannel-xml/*.xml",
            "etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/*.xml")),
        ("le dock", fichiers(".config/plank/dock1/launchers/*",
                             "etc/skel/.config/plank/dock1/launchers/*")),
        ("un autre outil LexOS", fichiers("usr/bin/lexos*",
                                          "usr/lib/lexos/*")),
    ]


def _contexte_joignabilite() -> dict:
    texte = _texte_dispatcheur()
    #  On lit chaque source UNE fois : 80 outils × des centaines de fichiers
    #  relus à chaque tour, c'est un bilan qui prend une minute.
    sources = []
    for libelle, fichiers in _sources_joignabilite():
        blocs = []
        for f in fichiers:
            try:
                blocs.append((f.name, f.read_text(encoding="utf-8", errors="ignore")))
            except OSError:
                continue
        sources.append((libelle, blocs))
    return {
        "dispatcheur": texte,
        "etiquettes": _etiquettes_du_case(texte),
        #  Commentaires retirés : un outil CITÉ dans une explication n'est pas
        #  appelé pour autant. C'est le piège qui s'est refermé sept fois sur
        #  ce dépôt — un contrôle qui lit de la prose en croyant lire du code.
        "code_dispatcheur": re.sub(r"(?m)^\s*#.*$", "", texte or ""),
        "sources": sources,
    }


def _joignable(nom_outil: str, ctx: dict) -> list:
    """Par quels chemins cet outil est-il atteignable ? (liste, vide = aucun)"""
    chemins = []
    suffixe = nom_outil[len("lexos-"):]
    if suffixe in ctx["etiquettes"]:
        chemins.append("le dispatcheur (lexos %s)" % suffixe)
    elif nom_outil in ctx["code_dispatcheur"]:
        chemins.append("le dispatcheur")
    for libelle, blocs in ctx["sources"]:
        for nom_fichier, texte in blocs:
            #  Un fichier ne se cite pas lui-même : /usr/bin/lexos-truc
            #  contient forcément « lexos-truc ».
            if nom_fichier == nom_outil:
                continue
            if nom_outil in texte:
                chemins.append(libelle)
                break
    return chemins


def _a_un_lanceur(nom_outil: str):
    if not DOSSIER_LANCEURS.is_dir():
        return None
    for fichier in DOSSIER_LANCEURS.glob("*.desktop"):
        try:
            if nom_outil in fichier.read_text(encoding="utf-8", errors="ignore"):
                return True
        except OSError:
            continue
    return False


def verifier_outils() -> dict:
    outils = _outils_lexos_installes()
    ctx = _contexte_joignabilite()

    releve = []
    for nom in outils:
        chemin = DOSSIER_BIN / nom
        par_ou = _joignable(nom, ctx)
        releve.append({
            "nom": nom,
            "executable": os.access(chemin, os.X_OK),
            "joignable_par": par_ou,
            "joignable": bool(par_ou),
            "a_un_lanceur": _a_un_lanceur(nom),
        })

    problemes = [r for r in releve if not r["executable"] or not r["joignable"]]
    return {
        "total": len(releve),
        "outils": releve,
        "problemes": problemes,
        "joignables": sum(1 for r in releve if r["joignable"]),
        "dispatcheur_trouve": ctx["dispatcheur"] is not None,
    }


def verifier_son() -> dict:
    for cmd in (["wpctl", "status"], ["pactl", "info"]):
        if executable_present(cmd[0]):
            sortie = executer(cmd)
            return {"teste_avec": cmd[0], "fonctionne": sortie is not None}
    return {"teste_avec": None, "fonctionne": None}


def verifier_wifi() -> dict:
    if not executable_present("nmcli"):
        return {"disponible": None, "connecte": None}
    radio = executer(["nmcli", "-t", "-f", "WIFI", "g"])
    actif = bool(radio) and radio.strip().lower() in ("enabled", "activé", "active", "oui", "yes")
    sortie = executer(["nmcli", "-t", "-f", "TYPE,STATE", "dev"])
    connecte = False
    if sortie:
        for ligne in sortie.splitlines():
            if ligne.startswith("wifi:") and "connect" in ligne.split(":", 1)[1].lower():
                connecte = True
    return {"disponible": actif, "connecte": connecte}


def verifier_espace_disque(seuil: int = SEUIL_DISQUE_ALERTE) -> list:
    return [d for d in moteur.etat_disques() if d["pourcentage"] >= seuil]


# =============================================================================
#  Le bruit connu du journal — trois familles, trois raisons
# =============================================================================
#  UN COMPTEUR D'ERREURS QUI COMPTE DU BRUIT NE SERT PLUS À RIEN : on
#  s'habitue à voir « 6 erreurs » à chaque bilan, et le jour où il y en a une
#  VRAIE, elle passe inaperçue au milieu. Chaque exclusion ci-dessous est
#  nommée, et vaut pour ce qu'elle est : un refus normal ou une absence
#  assumée, pas une panne.
BRUIT_JOURNAL = (
    #  journalctl écrit lui-même cette ligne quand il n'a rien à montrer.
    "No entries",
    #  ═══ REFUS D'AUTHENTIFICATION, PAS PANNE ═══
    #  Un outil qui tente « sudo -n » sans avoir les droits fait échouer PAM,
    #  qui écrit DEUX lignes à chaque tentative. Ce sont des refus attendus —
    #  le programme retombe sur pkexec ou renonce proprement.
    #  LA VRAIE CORRECTION EST À LA SOURCE, et elle est faite : lexos-mac,
    #  lexos-brightness et lexos-perf ne sondent plus les droits par un
    #  « sudo -n true » jeté avant l'appel réel. Ce filtre reste pour les
    #  refus légitimes qui subsistent — un mot de passe refusé en est un.
    "pam_unix(sudo:auth)",
    "a password is required",
    #  ═══ BLUETOOTH CHERCHE UN CARNET D'ADRESSES QUI N'EXISTE PAS ICI ═══
    #  obexd interroge evolution-source-registry, qui appartient à la suite
    #  GNOME que LexOS n'installe pas. Sans conséquence — le transfert de
    #  fichiers Bluetooth marche — et ça revient à CHAQUE démarrage.
    "obexd",
    "evolution-source-registry",
)


def _bruit_connu(ligne: str) -> bool:
    return any(motif in ligne for motif in BRUIT_JOURNAL)


def verifier_erreurs_journal(nb_lignes: int = 20) -> dict:
    if not executable_present("journalctl"):
        return {"disponible": False, "lignes": [], "nombre": 0}
    sortie = executer(
        ["journalctl", "-p", "err", "-b", "--no-pager", "-n", str(nb_lignes), "-o", "short"],
        timeout=6.0,
    )
    lignes = [
        l for l in (sortie or "").splitlines()
        if l.strip() and not _bruit_connu(l)
    ]
    return {"disponible": True, "lignes": lignes, "nombre": len(lignes)}


def bilan_complet() -> dict:
    return {
        "outils": verifier_outils(),
        "son": verifier_son(),
        "wifi": verifier_wifi(),
        "disques_pleins": verifier_espace_disque(),
        "journal": verifier_erreurs_journal(),
    }


def rapport_texte() -> str:
    """Le rapport en une page, en français, prêt à copier-coller."""
    b = bilan_complet()
    maintenant = _dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    lignes = [
        f"=== Bilan LexOS Médecin — {maintenant} ===",
        f"Version LexOS : {lire_version_lexos()}",
        "",
    ]

    outils = b["outils"]
    if outils["dispatcheur_trouve"]:
        lignes.append(
            f"Outils lexos-* : {outils['total']} trouvés, "
            f"{outils['joignables']} joignables, {len(outils['problemes'])} problème(s).")
        for p in outils["problemes"]:
            raisons = []
            if not p["executable"]:
                raisons.append("pas exécutable")
            if not p["joignable"]:
                #  ═══ DIRE QUELQUE CHOSE D'UTILE ═══
                #  « absent du dispatcheur » était vrai pour dix outils qui
                #  vont très bien : ils partent par udev, par une minuterie ou
                #  à l'ouverture de session. Ce qui compte, et la seule chose
                #  qui mérite qu'on dérange quelqu'un, c'est : PERSONNE ne
                #  peut le lancer.
                raisons.append("joignable par aucun chemin "
                               "(ni dispatcheur, ni menu, ni dock, ni service, "
                               "ni udev, ni raccourci, ni autre outil)")
            lignes.append(f"  - {p['nom']} : {', '.join(raisons)}")
    else:
        lignes.append("Outils lexos-* : /usr/bin/lexos introuvable, vérification impossible.")

    son = b["son"]
    if son["fonctionne"] is None:
        lignes.append("Son : aucun outil de diagnostic (wpctl/pactl) trouvé.")
    else:
        lignes.append(f"Son : {'OK' if son['fonctionne'] else 'NE RÉPOND PAS'} (testé avec {son['teste_avec']})")

    wifi = b["wifi"]
    if wifi["disponible"] is None:
        lignes.append("Wi-Fi : nmcli absent, vérification impossible.")
    else:
        etat = "radio activée" if wifi["disponible"] else "radio désactivée"
        connexion = "connecté" if wifi["connecte"] else "non connecté"
        lignes.append(f"Wi-Fi : {etat}, {connexion}")

    disques = b["disques_pleins"]
    if disques:
        lignes.append(f"Espace disque : {len(disques)} partition(s) au-delà de {SEUIL_DISQUE_ALERTE} % :")
        for d in disques:
            lignes.append(f"  - {d['point_montage']} : {d['pourcentage']} %")
    else:
        lignes.append("Espace disque : toutes les partitions sont sous le seuil d'alerte.")

    journal = b["journal"]
    if journal["disponible"]:
        lignes.append(f"Erreurs journal (démarrage courant) : {journal['nombre']}")
        for l in journal["lignes"][:10]:
            lignes.append(f"  {l}")
    else:
        lignes.append("Erreurs journal : journalctl indisponible.")

    lignes.append("")
    lignes.append("=== Fin du rapport — copiez-collez tel quel pour demander de l'aide ===")
    return "\n".join(lignes)
