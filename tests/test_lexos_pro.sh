#!/usr/bin/env bash
# =============================================================================
#  LEXOS PRO — banc d'essai
# =============================================================================
#  DEUX ÉTAGES, ET ILS NE SE VALENT PAS :
#
#    1. LES SERVICES (pro/services/) — du Python pur, sans Qt. Ils se jouent
#       PARTOUT, y compris sur un coureur de CI sans serveur graphique. C'est
#       là qu'est la substance : lecture du système, détection des capacités,
#       et les quatre cas d'erreur exigés (commande absente, permission
#       refusée, délai dépassé, résultat invalide).
#
#    2. L'INTERFACE (pro/ui/) — demande PySide6. S'il n'est pas là, ce banc
#       ne dit PAS « réussi » : il dit « NON MESURÉ » et nomme ce qui manque.
#       Un banc qui passe au vert parce qu'il n'a rien pu vérifier est pire
#       qu'un banc rouge.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="$RACINE/config/includes.chroot/usr/lib/lexos"
PY="${PYTHON:-python3}"

REUSSIS=0; ECHOUES=0; NON_MESURES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
gris() { printf '  \033[33m➖ NON MESURÉ\033[0m %s\n' "$1"; NON_MESURES=$((NON_MESURES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -d "$SOURCES/pro" ] || { echo "pro/ introuvable sous $SOURCES"; exit 1; }

# =============================================================================
titre "1. Les fichiers se compilent tous"
# =============================================================================
if "$PY" -m compileall -q "$SOURCES/pro" > "$RACINE/.compile.log" 2>&1; then
	ok "les $(find "$SOURCES/pro" -name '*.py' | wc -l) fichiers Python compilent"
else
	non "erreur de compilation :"
	sed 's/^/      /' < "$RACINE/.compile.log"
fi
rm -f "$RACINE/.compile.log"

# =============================================================================
titre "2. Les services — tests unitaires (sans serveur graphique)"
# =============================================================================
SORTIE="$(cd "$RACINE" && PYTHONPATH="$SOURCES" "$PY" -m unittest discover \
	-s tests/pro -p 'test_*.py' 2>&1)"
CODE=$?
printf '%s\n' "$SORTIE" | tail -4 | sed 's/^/      /'
if [ "$CODE" = "0" ]; then
	ok "$(printf '%s' "$SORTIE" | grep -oE 'Ran [0-9]+ tests' | head -1) — tous verts"
else
	non "des tests unitaires échouent (voir ci-dessus)"
fi

# =============================================================================
titre "3. La couche services n'importe JAMAIS Qt"
# =============================================================================
#  C'est ce qui rend l'étage 2 jouable sans écran — et ce qui garde la
#  frontière nette. Un « import PySide6 » qui s'y glisserait rendrait tous
#  les tests ci-dessus impossibles sur un coureur de CI, sans prévenir.
FUITES="$(grep -rn 'PySide6\|QtCore\|QtWidgets' "$SOURCES/pro/services/" \
	"$SOURCES/pro/version.py" 2>/dev/null || true)"
if [ -z "$FUITES" ]; then
	ok "aucun import Qt dans pro/services/ ni dans version.py"
else
	non "Qt a fuité dans la couche services :"
	printf '%s\n' "$FUITES" | sed 's/^/      /'
fi

# =============================================================================
titre "4. Aucun shell=True, et aucune commande construite par concaténation"
# =============================================================================
#  La règle centrale de sécurité de cette application : argv est une LISTE.
#
#  ON ANALYSE L'ARBRE SYNTAXIQUE, PAS LE TEXTE. Un « grep shell=True » se
#  déclenchait sur les trois COMMENTAIRES qui expliquent qu'on ne s'en sert
#  jamais — le piège que ce dépôt s'est déjà pris sept fois. Un contrôle qui
#  rougit sur sa propre justification apprend à ignorer les rouges.
SHELL_VRAI="$("$PY" - "$SOURCES/pro" <<'PYEOF' 2>&1
import ast, pathlib, sys
trouves = []
for f in sorted(pathlib.Path(sys.argv[1]).rglob("*.py")):
    try:
        arbre = ast.parse(f.read_text(encoding="utf-8"))
    except SyntaxError as e:
        trouves.append(f"{f} : illisible ({e})")
        continue
    for n in ast.walk(arbre):
        if isinstance(n, ast.Call):
            for m in n.keywords:
                if m.arg == "shell" and not (
                        isinstance(m.value, ast.Constant)
                        and m.value.value is False):
                    trouves.append(f"{f}:{n.lineno} shell= non-False")
print("\n".join(trouves))
PYEOF
)"
if [ -z "$SHELL_VRAI" ]; then
	ok "aucun appel avec « shell= » ailleurs que False (analyse syntaxique)"
else
	non "shell=True réellement appelé :"
	printf '%s\n' "$SHELL_VRAI" | sed 's/^/      /'
fi

# =============================================================================
titre "5. Tout appel externe passe par le module execution"
# =============================================================================
#  subprocess ne doit apparaître QUE dans execution.py (et dans terminal.py,
#  qui a besoin de passer un environnement — il est nommé explicitement ici
#  pour que l'exception reste visible plutôt que de se diluer).
#  --include='*.py' : sans lui, les .pyc de __pycache__ (compilés à la
#  section 1 de ce banc même) faisaient rougir le contrôle. Le banc se
#  tirait dans le pied avec sa propre étape précédente.
HORS="$(grep -rln --include='*.py' 'subprocess' "$SOURCES/pro/" 2>/dev/null \
	| grep -v '/services/execution.py$' | grep -v '/services/terminal.py$' || true)"
if [ -z "$HORS" ]; then
	ok "subprocess n'est utilisé que dans execution.py et terminal.py"
else
	non "subprocess utilisé hors des deux modules prévus :"
	printf '%s\n' "$HORS" | sed 's/^/      /'
fi

# =============================================================================
titre "6. Le lanceur et le fichier .desktop"
# =============================================================================
LANCEUR="$RACINE/config/includes.chroot/usr/bin/lexos-pro"
DESKTOP="$RACINE/config/includes.chroot/usr/share/applications/lexos-pro.desktop"
[ -x "$LANCEUR" ] && ok "le lanceur existe et est exécutable" \
	|| non "lanceur absent ou non exécutable : $LANCEUR"
[ -f "$DESKTOP" ] && ok "le fichier .desktop existe" \
	|| non "fichier .desktop absent"
grep -qx 'Exec=lexos-pro' "$DESKTOP" 2>/dev/null \
	&& ok "le .desktop appelle bien « lexos-pro »" \
	|| non "la ligne Exec du .desktop ne correspond pas au lanceur"
ICONE="$RACINE/config/includes.chroot/usr/share/icons/hicolor/scalable/apps/lexos-pro.svg"
[ -f "$ICONE" ] \
	&& ok "l'icône déclarée par le .desktop existe réellement" \
	|| non "Icon=lexos-pro est déclaré mais aucune icône n'est livrée"

#  Le lanceur ne doit RIEN installer : c'est la consigne, et c'est une
#  garde structurelle, pas une intention.
if grep -qE '(apt|dnf|pacman|zypper)[[:space:]]+(-y[[:space:]]+)?install' "$LANCEUR" \
   && ! grep -q 'echo' "$LANCEUR"; then
	non "le lanceur semble installer des paquets lui-même"
else
	ok "le lanceur n'installe aucun paquet : il indique la commande à taper"
fi

# =============================================================================
titre "7. Le démarrage graphique"
# =============================================================================
#  TROIS CAS, ET LES CONFONDRE SERAIT MENTIR DANS UN SENS OU DANS L'AUTRE :
#    · PySide6 absent          -> non mesuré ;
#    · PySide6 présent mais INIMPORTABLE (une bibliothèque système manque)
#      -> non mesuré AUSSI, avec la bibliothèque nommée. Ce n'est pas
#         l'application qui est cassée, c'est la machine qui n'a pas de quoi
#         la faire tourner. Le dire « échoué » enverrait chercher un défaut
#         là où il n'y en a pas ;
#    · PySide6 importable      -> on MESURE.
#
#  MESURÉ EN VRAI : sur le coureur de la CI, « import PySide6.QtGui » a
#  rendu « ImportError: libEGL.so.1: cannot open shared object file ».
#  Qt6Gui réclame libEGL, libGL, libxkbcommon, libdbus et quatre autres dès
#  l'import — y compris pour la plateforme offscreen, qui n'affiche rien.
#  La CI les installe désormais ; ici, on explique.
IMPORT="$("$PY" -c 'import PySide6.QtWidgets' 2>&1)"
CODE_IMPORT=$?
if [ "$CODE_IMPORT" != "0" ] && grep -qi 'No module named' <<< "$IMPORT"; then
	gris "PySide6 n'est pas installé pour « $PY » : le démarrage graphique
                n'a PAS été vérifié. Ce n'est ni un succès ni un échec —
                c'est une mesure qui n'a pas eu lieu."
elif [ "$CODE_IMPORT" != "0" ]; then
	gris "PySide6 est installé mais ne s'importe pas sur cette machine :
                $(tail -1 <<< "$IMPORT")
                Une bibliothèque système manque (Qt réclame libEGL, libGL,
                libxkbcommon, libdbus… dès l'import, même sans affichage).
                Le démarrage graphique n'a donc PAS été vérifié."
else
	ESSAI="$(cd "$SOURCES" && QT_QPA_PLATFORM=offscreen \
		LEXOS_PRO_AUTORISER_ROOT=1 "$PY" - <<'PYEOF' 2>&1
import sys
sys.path.insert(0, '.')
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QCoreApplication, QThreadPool
from pro import app as A
from pro.ui import theme
from pro.ui.pages.parametres import SECTIONS

qapp = QApplication(['lexos-pro'])
qapp.setStyleSheet(theme.feuille())
f = A.Fenetre()
f.resize(1280, 720)
f.show()
vues = 0
for cle, libelle, _ in A.MENU:
    f.aller(cle)
    for _ in range(8):
        QCoreApplication.processEvents()
    vues += 1
f.aller('parametres')
for cle, libelle, _, _ in SECTIONS:
    f.page_parametres.aller_par_cle(cle)
    for _ in range(8):
        QCoreApplication.processEvents()
    vues += 1
QThreadPool.globalInstance().waitForDone(25000)
for _ in range(300):
    QCoreApplication.processEvents()
#  ── LES ICÔNES DE TYPES DE FICHIERS ─────────────────────────────
#  UNE ICÔNE VIDE NE SE REMARQUE PAS dans une liste de fichiers : elle
#  ressemble à « type inconnu », qui est un résultat légitime. C'est
#  exactement le genre de défaut qui vit des mois. On compte donc les
#  pixels opaques de chacune.
from pro.ui import theme
TYPES = ["png","jpg","gif","svg","tiff","raw","mp4","mp3","wav","flac",
         "ogg","wma","midi","m4a","doc","docx","xls","xlsx","ppt","pptx",
         "pdf","txt","rtf","md","json","html","css","js","zip","rar",
         "7z","tar","iso","app","deb","exe","sh","py","appimage","snap",
         "flatpak","service"]

#  UN SEUIL DE COUVERTURE, PAS « PLUS DE ZÉRO PIXEL ».
#  La première version comptait « au moins 40 pixels opaques ». Elle
#  n'attrapait qu'une icône ENTIÈREMENT vide — le cas le plus rare. La
#  mutation qui supprimait le CORPS coloré la laissait verte : le symbole
#  et le bandeau suffisaient à passer. Mesuré : une icône entière couvre
#  82-83 % de sa boîte, une icône sans corps 9 à 44 %. Le seuil est à
#  65 %, avec de la marge des deux côtés.
def couverture(nom, dossier=False, t=48):
    im = theme.icone_fichier(nom, t, dossier).pixmap(t, t).toImage()
    points = [(x, y) for y in range(0, t, 2) for x in range(0, t, 2)]
    opaques = sum(1 for x, y in points if im.pixelColor(x, y).alpha() > 0)
    return 100 * opaques // len(points)

SEUIL = 65
vides, sans_famille = [], []
for ext in TYPES:
    if theme.famille_fichier("essai." + ext)[0] == "inconnu":
        sans_famille.append(ext)
    c = couverture("essai." + ext)
    if c < SEUIL:
        vides.append(f"{ext}({c}%)")
#  Le dossier et le type inconnu doivent AUSSI donner une icône : ce sont
#  les deux cas les plus fréquents d'un vrai dossier.
for nom, dossier in (("Mes documents", True), ("sans-extension", False),
                     ("truc.xyzinconnu", False)):
    c = couverture(nom, dossier)
    if c < SEUIL:
        vides.append(f"{nom}({c}%)")
#  Une famille est un couple COULEUR + SYMBOLE. En réutiliser une pour sa
#  seule couleur fait hériter du mauvais symbole — c'est arrivé à .ogg,
#  .wma, .m4a et .rtf, qui portaient une photo ou un cube.
mauvais = []
for ext, attendu in (("ogg", "audio"), ("wma", "audio"), ("m4a", "audio"),
                     ("mp3", "audio"), ("rtf", "texte"), ("txt", "texte"),
                     ("png", "image"), ("pdf", "pdf"), ("zip", "archive"),
                     ("iso", "disque"), ("py", "python"), ("sh", "invite")):
    cle = theme.famille_fichier("x." + ext)[0]
    if theme._FAMILLES.get(cle, ("", ""))[1] != attendu:
        mauvais.append(ext)
#  LE BANDEAU EST CE QUI DISTINGUE .xls DE .xlsx — même famille, même
#  couleur, même symbole : seule l'étiquette les sépare. Le supprimer ne
#  change quasiment pas la COUVERTURE (il est dans le corps), donc le
#  contrôle ci-dessus le laissait passer. Ici on compare deux icônes de
#  même famille : elles DOIVENT différer en grand format.
identiques = []
for a_, b_ in (("xls", "xlsx"), ("doc", "docx"), ("ppt", "pptx"),
               ("tar", "gz"), ("html", "php")):
    if theme.famille_fichier("x." + a_)[0] != theme.famille_fichier("x." + b_)[0]:
        continue          # familles différentes : la couleur suffit déjà
    ia = theme.icone_fichier("x." + a_, 48).pixmap(48, 48).toImage()
    ib = theme.icone_fichier("x." + b_, 48).pixmap(48, 48).toImage()
    if ia == ib:
        identiques.append(f"{a_}/{b_}")
#  ── LA PAGE OUTILS ───────────────────────────────────────────────
#  CHAQUE TUILE FAIT QUELQUE CHOSE, OU DIT POURQUOI NON. On vérifie
#  qu'aucune n'est un faux bouton : toutes ont une infobulle, celles
#  qui sont éteintes portent leur raison, et la grille ne déborde pas
#  horizontalement — défaut mesuré sur capture à 1280x720, où neuf
#  colonnes figées demandaient 1134 px pour 1070 disponibles.
from PySide6.QtWidgets import QToolButton, QScrollArea
from pro.services import outils as _O
f.resize(1280, 720)
f.aller('outils')
for _ in range(30):
    QCoreApplication.processEvents()
QThreadPool.globalInstance().waitForDone(20000)
for _ in range(200):
    QCoreApplication.processEvents()
_page = f.pile.currentWidget()
_tuiles = _page.findChildren(QToolButton)
_sans_bulle = [t.text() for t in _tuiles if not t.toolTip().strip()]
_eteintes_muettes = [t.text() for t in _tuiles
                     if not t.isEnabled() and "Indisponible" not in t.toolTip()]
_coupes = [t.text() for t in _tuiles
           if t.fontMetrics().horizontalAdvance(t.text()) > t.width() - 12]
_sc = _page.findChildren(QScrollArea)[0]
_deborde = _sc.horizontalScrollBar().maximum() > 0
print(f"OUTILS_TUILES={len(_tuiles)}/{len(_O.CATALOGUE)}")
print(f"OUTILS_SANS_BULLE={','.join(_sans_bulle)}")
print(f"OUTILS_ETEINTES_MUETTES={','.join(_eteintes_muettes)}")
print(f"OUTILS_LIBELLES_COUPES={','.join(_coupes)}")
print(f"OUTILS_DEBORDE={'oui' if _deborde else 'non'}")
print(f"TYPES_INDISTINCTS={','.join(identiques)}")
print(f"TYPES_VIDES={','.join(vides)}")
print(f"TYPES_SANS_FAMILLE={','.join(sans_famille)}")
print(f"TYPES_MAUVAIS_SYMBOLE={','.join(mauvais)}")
#  ATTENDU CALCULÉ, PAS ÉCRIT EN DUR. La version précédente exigeait
#  « PAGES=18 » ; ajouter la neuvième entrée de menu l'a fait rougir pour
#  une bonne nouvelle. Un banc qui punit l'ajout d'une page apprend à
#  ignorer les rouges.
attendu = len(A.MENU) + len(SECTIONS)
print(f"PAGES={vues}/{attendu}")
PYEOF
	)"
	TUILES="$(grep -o 'OUTILS_TUILES=[0-9]*/[0-9]*' <<< "$ESSAI" | cut -d= -f2)"
	if [ -n "$TUILES" ] && [ "${TUILES%/*}" = "${TUILES#*/}" ]; then
		ok "la page Outils affiche les ${TUILES%/*} tuiles du catalogue"
	else
		non "tuiles manquantes : ${TUILES:-mesure absente}"
	fi
	grep -q 'OUTILS_SANS_BULLE=$' <<< "$ESSAI" \
		&& ok "chaque tuile porte une infobulle" \
		|| non "tuiles muettes : $(grep -o 'OUTILS_SANS_BULLE=.*' <<< "$ESSAI")"
	grep -q 'OUTILS_ETEINTES_MUETTES=$' <<< "$ESSAI" \
		&& ok "et chaque tuile ÉTEINTE dit pourquoi — aucun faux bouton" \
		|| non "éteintes sans motif : $(grep -o 'OUTILS_ETEINTES_MUETTES=.*' <<< "$ESSAI")"
	grep -q 'OUTILS_LIBELLES_COUPES=$' <<< "$ESSAI" \
		&& ok "aucun libellé de tuile n'est tronqué" \
		|| non "libellés coupés : $(grep -o 'OUTILS_LIBELLES_COUPES=.*' <<< "$ESSAI")"
	grep -q 'OUTILS_DEBORDE=non' <<< "$ESSAI" \
		&& ok "et la grille ne déborde pas horizontalement à 1280x720" \
		|| non "débordement horizontal de la page Outils"
	grep -q 'TYPES_INDISTINCTS=$' <<< "$ESSAI" \
		&& ok "deux types d'une même famille restent distinguables (bandeau)" \
		|| non "icônes identiques : $(grep -o 'TYPES_INDISTINCTS=.*' <<< "$ESSAI")"
	grep -q 'TYPES_VIDES=$' <<< "$ESSAI" \
		&& ok "les 42 icônes de types se dessinent ENTIÈREMENT (> 65 % de leur boîte)" \
		|| non "icônes vides : $(grep -o 'TYPES_VIDES=.*' <<< "$ESSAI")"
	grep -q 'TYPES_SANS_FAMILLE=$' <<< "$ESSAI" \
		&& ok "chaque extension de la planche est reconnue" \
		|| non "non reconnues : $(grep -o 'TYPES_SANS_FAMILLE=.*' <<< "$ESSAI")"
	grep -q 'TYPES_MAUVAIS_SYMBOLE=$' <<< "$ESSAI" \
		&& ok "et chacune porte le SYMBOLE de sa famille, pas que sa couleur" \
		|| non "symbole incohérent : $(grep -o 'TYPES_MAUVAIS_SYMBOLE=.*' <<< "$ESSAI")"
	#  Chaîne ici-même et non « printf | grep -q » : sous pipefail, grep
	#  ferme le tube dès la correspondance et tue le producteur. C'est une
	#  règle du dépôt, et la CI la vérifie sur tous les bancs.
	PAGES="$(grep -o 'PAGES=[0-9]*/[0-9]*' <<< "$ESSAI" | cut -d= -f2)"
	if [ -n "$PAGES" ] && [ "${PAGES%/*}" = "${PAGES#*/}" ]; then
		ok "la fenêtre s'ouvre et les ${PAGES%/*} pages s'affichent (offscreen)"
	else
		non "le démarrage graphique a échoué :"
		printf '%s\n' "$ESSAI" | tail -12 | sed 's/^/      /'
	fi
	if grep -qi 'RuntimeError\|Traceback' <<< "$ESSAI"; then
		non "une exception est apparue pendant le parcours des pages"
	else
		ok "aucune exception pendant le parcours des pages"
	fi
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués, %d non mesurés\033[0m\n' \
	"$REUSSIS" "$ECHOUES" "$NON_MESURES"
if [ "$NON_MESURES" -gt 0 ]; then
	printf '\033[33mAttention : %d contrôle(s) n%sont PAS pu être joués.\n' \
		"$NON_MESURES" "'"
	printf 'Un banc vert avec des « non mesurés » ne prouve pas ce qu%sil\n' "'"
	printf 'semble prouver.\033[0m\n'
fi
#  EN CI, UN « NON MESURÉ » EST UN ÉCHEC. Ailleurs, non : un développeur
#  sans serveur graphique doit pouvoir jouer les 71 tests de services sans
#  que le banc rougisse pour une mesure qu'il n'a jamais demandée. La CI,
#  elle, existe POUR mesurer : elle pose LEXOS_PRO_EXIGER_MESURE=1, et un
#  contrôle sauté y devient rouge. Sans cette exigence, une étape
#  d'installation ratée rendrait la CI verte sans avoir ouvert la fenêtre.
if [ "${LEXOS_PRO_EXIGER_MESURE:-0}" = "1" ] && [ "$NON_MESURES" -gt 0 ]; then
	printf '\033[31mLEXOS_PRO_EXIGER_MESURE=1 : %d contrôle(s) non mesuré(s)\n' \
		"$NON_MESURES"
	printf 'comptent comme des échecs ici.\033[0m\n'
	exit 1
fi
[ "$ECHOUES" -eq 0 ]
