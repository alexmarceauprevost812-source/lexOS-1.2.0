#!/usr/bin/env bash
# =============================================================================
#  Le panneau « Partager » — la page, et le chemin qui y mène
# =============================================================================
#  ALEX, PHOTO DE L'ISO 72 : « la page pour partager, elle est pas pareille ».
#  Elle ne pouvait pas l'être : « lexos share qr » ouvrait une fenêtre yad, un
#  dialogue GTK générique qui ne prend pas le thème LexOS. Le panneau la
#  remplace par le patron de tous les autres — une page web locale dans une
#  fenêtre Qt.
#
#  ═══ CE QUE CE BANC GARDE, ET POURQUOI CHAQUE POINT A COÛTÉ QUELQUE CHOSE ═══
#  · LE REPLI TERMINAL. Sans lui, « lexos share qr » ne servirait plus à rien
#    sur une machine sans bureau — en console, par SSH, en mode secours — là
#    où c'est justement le plus utile. Quatre conditions le déclenchent, et
#    elles doivent TOUTES rendre 1.
#  · FENETRE_PID. Le « wait -n » de lexos-share attend la première des deux
#    fins pour arrêter le serveur de partage. Sans ce PID, fermer la fenêtre
#    laisse un partage ouvert — un serveur qu'on croit fermé et qui sert
#    encore le dossier personnel sur le réseau.
#  · UN SEUL CHEMIN DÉMARRE UN SERVEUR. partage.py ne doit JAMAIS lancer
#    share-server.py : deux chemins qui démarrent, deux façons d'arrêter, et
#    un jour un serveur oublié.
#  · 127.0.0.1. Le serveur de la fenêtre sert l'interface, pas les fichiers :
#    il n'a aucune raison d'être joignable depuis le réseau.
#  · AUCUNE COULEUR EN DUR. La règle du dépôt, déjà tenue par un contrôle de
#    CI ; on la tient aussi ici, et de la MÊME façon que lui — un banc plus
#    tolérant que la CI laisserait passer une construction rouge.
# =============================================================================
set -uo pipefail

#  ═══ AUCUNE VARIABLE NE REPART DANS UN TUYAU VERS « grep -q » ═══
#  Mesuré sur test_lexos_installateur_bandeau.sh : 54 échecs sur 300 essais.
#  « grep -q » s'arrête au premier résultat et ferme le tuyau ; ce qui écrivait
#  encore prend une erreur, et « pipefail » transforme ça en condition FAUSSE
#  alors que le motif a été trouvé. On emploie « <<< » partout.
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IC="$RACINE/config/includes.chroot"
WEB="$IC/usr/share/lexos/partage/web"
PY="$IC/usr/lib/lexos/partage.py"
SHARE="$IC/usr/bin/lexos-share"

REUSSIS=0; ECHOUES=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()   { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. Les fichiers du panneau sont là"
# =============================================================================
for F in "$WEB/index.html" "$WEB/style.css" "$WEB/app.js" "$PY"; do
	if [[ -s "$F" ]]; then
		ok "${F#"$IC/"} est posé"
	else
		non "${F#"$IC/"} MANQUE ou est vide"
	fi
done

if [[ -x "$PY" ]]; then
	ok "partage.py est exécutable"
else
	non "partage.py n'est pas exécutable — lexos-share le lance par python3, mais le bit dit l'intention"
fi

# =============================================================================
titre "2. ui.css est un LIEN, pas une copie"
# =============================================================================
#  Une copie diverge le jour où l'accent change, et personne ne s'en aperçoit :
#  le panneau garde l'ancienne palette et a l'air « presque » juste. Les autres
#  panneaux (settings, ia, volet) pointent tous sur ../../ui.css.
if [[ -L "$WEB/ui.css" ]]; then
	CIBLE="$(readlink "$WEB/ui.css")"
	if [[ -r "$WEB/ui.css" ]]; then
		ok "ui.css est un lien vers « $CIBLE », et il résout"
	else
		non "ui.css est un lien CASSÉ vers « $CIBLE » — sans lui, aucun var() ne résout : texte sans couleur sur fond sans couleur"
	fi
else
	non "ui.css est une COPIE — elle divergera de la source unique sans que personne ne le voie"
fi

#  Le fichier d'aperçu détourne fetch pour montrer des données d'exemple :
#  livré dans l'ISO, il ferait une page qui ment.
if [[ -e "$WEB/apercu.html" ]]; then
	non "apercu.html est dans l'ISO — c'est un fichier de travail qui simule les données"
else
	ok "apercu.html n'est pas embarqué"
fi

# =============================================================================
titre "3. Aucune couleur en dur — le blanc du QR est un jeton"
# =============================================================================
#  ═══ ON LIT LE FICHIER ENTIER, COMMENTAIRES COMPRIS ═══
#  C'est ce que fait le contrôle de CI « L'accent n'est écrit qu'à un seul
#  endroit ». Un banc qui décommenterait serait PLUS TOLÉRANT que la CI :
#  il passerait au vert sur un fichier qui fait échouer la construction.
#  Conséquence assumée : on n'explique pas une couleur en citant son code,
#  même dans un commentaire.
#  ═══ ZÉRO COULEUR EN DUR, Y COMPRIS LE BLANC DU QR ═══
#  Premier jet : on tolérait #FFFFFF dans style.css, « justifié en
#  commentaire ». LA CI L'A REFUSÉ, et elle avait raison — deux contrôles,
#  que je ne connaissais pas en écrivant le panneau :
#    · « Rien ne reste noir en mode clair » interdit TOUTE couleur opaque
#      posée en fond ou en texte dans une feuille de panneau. Une exception
#      « justifiée en commentaire » se recopie ; un jeton s'explique une fois.
#    · « L'accent n'est écrit qu'à un seul endroit » lit le fichier ENTIER,
#      commentaires compris.
#  Le blanc du QR est donc devenu --qr-fond dans ui.css, hors des deux blocs
#  de mode : ce n'est pas une couleur de thème mais une exigence de LECTURE
#  — c'est la caméra du téléphone qui décide, pas le mode du bureau.
for F in "$WEB/style.css" "$WEB/index.html"; do
	DURES="$(grep -oniE '#[0-9A-Fa-f]{3,8}\b|rgba?\([0-9 ,.]+\)' "$F" || true)"
	if [[ -z "$DURES" ]]; then
		ok "$(basename "$F") n'écrit AUCUNE couleur en dur"
	else
		non "$(basename "$F") écrit des couleurs en dur :\n$(sed 's/^/       /' <<< "$DURES")"
	fi
done

#  LE JETON DOIT EXISTER LÀ OÙ IL EST DÉCLARÉ, sinon var(--qr-fond) ne résout
#  pas et le cadre du QR devient transparent — un QR sombre sur fond sombre,
#  que l'appareil photo ne lit plus. La panne serait invisible au banc si on
#  se contentait de vérifier que style.css emploie le jeton.
UICSS="$IC/usr/share/lexos/ui.css"
if grep -qE '^\s*--qr-fond:\s*#FFFFFF;' "$UICSS"; then
	ok "--qr-fond est déclaré blanc dans ui.css, hors des blocs de mode"
else
	non "--qr-fond n'est pas déclaré blanc dans ui.css — le cadre du QR serait transparent"
fi
if grep -q 'var(--qr-fond)' "$WEB/style.css"; then
	ok "…et le cadre du QR l'emploie"
else
	non "le cadre du QR n'emploie pas var(--qr-fond)"
fi
#  Hors des blocs de mode : le blanc ne doit PAS être redéfini en clair.
if grep -q -- '--qr-fond' < <(sed -n '/data-mode="clair"/,/^}/p' "$UICSS"); then
	non "--qr-fond est redéfini dans le bloc du mode clair — le QR suivrait le thème au lieu de rester lisible"
else
	ok "…et il n'est redéfini par aucun mode : le QR reste lisible sur un bureau clair"
fi

# =============================================================================
titre "4. lexos-share ouvre le panneau, et garde son repli"
# =============================================================================
#  ═══ ON DÉCOMMENTE D'ABORD ═══
#  Les commentaires de lexos-share racontent justement le passage de yad au
#  panneau : ils CITENT « yad ». Un contrôle qui lit le fichier brut trouverait
#  l'explication et croirait lire du code — le faux rouge de la famille qui
#  s'est refermée six fois sur ce dépôt.
CODE="$(sed 's/^[[:space:]]*#.*$//' "$SHARE")"
QR="$(sed -n '/^cmd_qr() {/,/^}/p' <<< "$CODE")"

if [[ -z "${QR//[[:space:]]/}" ]]; then
	non "cmd_qr n'a pas pu être extraite de lexos-share — rien n'a été mesuré"
else
	ok "cmd_qr extraite ($(grep -c . <<< "$QR") lignes de code)"
fi

if grep -q 'yad' <<< "$QR"; then
	non "cmd_qr appelle encore yad — la fenêtre ne prendra pas le thème LexOS"
else
	ok "cmd_qr n'appelle plus yad"
fi

if grep -q 'partage.py\|\$PANNEAU\|"\$PANNEAU"' <<< "$QR"; then
	ok "cmd_qr lance bien le panneau"
else
	non "cmd_qr ne lance pas partage.py — « lexos share qr » n'ouvrirait plus rien"
fi

if grep -q 'FENETRE_PID=\$!' <<< "$QR"; then
	ok "FENETRE_PID est posé — le « wait -n » pourra arrêter le serveur"
else
	non "FENETRE_PID n'est plus posé : fermer la fenêtre laisserait le partage OUVERT"
fi

for ARG in -- --url --recus --minutes; do
	[[ "$ARG" == "--" ]] && continue
	if grep -q -- "$ARG" <<< "$QR"; then
		ok "…et $ARG lui est passé"
	else
		non "$ARG n'est pas passé au panneau"
	fi
done

#  LES QUATRE PORTES DU REPLI. Chacune doit rendre 1 : c'est ce qui fait
#  retomber la commande sur le QR en caractères.
FEN="$(sed -n '/fenetre_qr() {/,/^\t}/p' <<< "$CODE")"
declare -A PORTES=(
	["DISPLAY"]="ni DISPLAY ni WAYLAND_DISPLAY"
	["command -v python3"]="python3 absent"
	["PANNEAU"]="partage.py absent"
	["PySide6"]="PySide6 absent"
)
for MOTIF in "${!PORTES[@]}"; do
	if grep -q -- "$MOTIF" <<< "$FEN"; then
		ok "repli prévu : ${PORTES[$MOTIF]}"
	else
		non "aucune garde pour « ${PORTES[$MOTIF]} » — la commande mourrait au lieu de retomber sur le terminal"
	fi
done

NB_RET="$(grep -c 'return 1' <<< "$FEN" || true)"
if [[ "$NB_RET" -ge 4 ]]; then
	ok "fenetre_qr rend 1 dans $NB_RET cas — le repli reste atteignable"
else
	non "fenetre_qr ne rend 1 que $NB_RET fois : une garde a perdu son repli"
fi

if grep -q 'qrencode -t ANSIUTF8' <<< "$CODE"; then
	ok "le repli terminal (QR en caractères) est toujours là"
else
	non "le QR en caractères a disparu — sur une machine sans bureau, la commande ne montre plus rien"
fi

#  QR_PNG a disparu avec yad. Un « rm -f » sur une variable qui n'existe plus
#  ne retire rien, mais il ment sur ce que fait le code.
if grep -q 'QR_PNG' <<< "$CODE"; then
	non "QR_PNG survit dans le code alors que le fichier temporaire n'existe plus"
else
	ok "QR_PNG a disparu du code avec le fichier temporaire"
fi

# =============================================================================
titre "5. Le panneau n'est pas un deuxième serveur de partage"
# =============================================================================
#  ═══ LA VRAIE QUESTION EST « EST-CE QU'IL LE LANCE ? » ═══
#  Deux jets ont manqué la cible avant celui-ci, et les deux étaient des faux
#  ROUGES sur de la prose :
#    · chercher « share-server » dans le fichier décommenté trouvait la
#      DOCSTRING, qui explique justement que ce panneau ne le démarre pas ;
#    · retirer aussi les docstrings trouvait encore le texte d'aide d'une
#      option (« adresse déjà servie par share-server »).
#  Dans les deux cas, la seule façon de faire passer le banc aurait été
#  d'effacer une explication juste : le contrôle aurait gagné contre la
#  documentation. On regarde donc les APPELS, dans l'arbre syntaxique :
#  subprocess, os.exec*, os.system, Popen — et on refuse qu'un seul d'entre
#  eux porte le nom du serveur de partage. Un import du module aussi.
LANCEMENTS=""
if command -v python3 >/dev/null 2>&1; then
	LANCEMENTS="$(python3 - "$PY" <<'PYEOF'
import ast, sys

src = open(sys.argv[1], encoding="utf-8").read()
arbre = ast.parse(src)
FAUTIF = ("share-server", "share_server")

def nom_appele(f):
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        base = nom_appele(f.value)
        return f"{base}.{f.attr}" if base else f.attr
    return ""

trouves = []
for n in ast.walk(arbre):
    if isinstance(n, (ast.Import, ast.ImportFrom)):
        mods = [a.name for a in n.names]
        if isinstance(n, ast.ImportFrom) and n.module:
            mods.append(n.module)
        for m in mods:
            if any(f in m for f in FAUTIF):
                trouves.append(f"import {m}")
        continue
    if not isinstance(n, ast.Call):
        continue
    appele = nom_appele(n.func)
    if not (appele.startswith("subprocess.") or appele.startswith("os.exec")
            or appele in ("os.system", "os.spawnv", "Popen", "run")):
        continue
    for c in ast.walk(n):
        if isinstance(c, ast.Constant) and isinstance(c.value, str) \
           and any(f in c.value for f in FAUTIF):
            trouves.append(f"{appele}(… {c.value!r} …)")
print("\n".join(trouves))
PYEOF
)" || LANCEMENTS="ERREUR"
fi

if [[ "$LANCEMENTS" == "ERREUR" ]]; then
	non "partage.py n'a pas pu être analysé — le contrôle « un seul serveur » n'est pas éprouvé"
elif [[ -z "$LANCEMENTS" ]]; then
	ok "partage.py ne LANCE aucun serveur de partage : un seul chemin le démarre, un seul l'arrête"
else
	non "partage.py lance le serveur de partage :\n$(sed 's/^/       /' <<< "$LANCEMENTS")"
fi

#  ═══ ON NE CONCLUT JAMAIS UNE ABSENCE SUR UN TEXTE VIDE ═══
#  Ce contrôle a été VERT SUR DU VIDE pendant deux exécutions : la variable
#  qu'il lisait n'existait plus, « grep » échouait sur une variable non
#  définie, et la branche « rien trouvé » se déclarait satisfaite. Une
#  assertion d'absence sur un texte vide passe toujours — c'est le même piège
#  que la plage sed qui sortait vide dans le banc de l'écran de démarrage.
#  On mesure donc d'abord que le texte est là.
NU_PY=""
if command -v python3 >/dev/null 2>&1; then
	NU_PY="$(python3 - "$PY" <<'PYEOF'
import ast, sys
a = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for n in ast.walk(a):
    if isinstance(n, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        c = n.body
        if c and isinstance(c[0], ast.Expr) and isinstance(c[0].value, ast.Constant) \
           and isinstance(c[0].value.value, str):
            n.body = c[1:] or [ast.Pass()]
print(ast.unparse(a))
PYEOF
)" || NU_PY=""
fi

if [[ "$(printf '%s' "$NU_PY" | wc -l)" -lt 50 ]]; then
	non "le code de partage.py n'a pas pu être lu ($(printf '%s' "$NU_PY" | wc -l) lignes) — les contrôles d'écoute ne prouveraient rien"
else
	ok "le code de partage.py est lisible ($(printf '%s' "$NU_PY" | wc -l) lignes, prose retirée)"

	if grep -q "'127.0.0.1'" <<< "$NU_PY"; then
		ok "le serveur de la fenêtre n'écoute que sur 127.0.0.1"
	else
		non "le serveur de la fenêtre ne se lie pas explicitement à 127.0.0.1"
	fi

	if grep -qE "0\\.0\\.0\\.0|'', *port|\"\", *port" <<< "$NU_PY"; then
		non "le serveur de la fenêtre écoute sur toutes les interfaces — l'interface deviendrait joignable du réseau"
	else
		ok "…et il n'écoute sur aucune autre interface"
	fi
fi

# =============================================================================
titre "6. La liste des actions est FERMÉE"
# =============================================================================
#  ═══ ON IMPORTE LE MODULE, ON NE LE RELIT PAS ═══
#  Les imports Qt de partage.py sont DANS main() — le module s'importe donc
#  sans serveur graphique. On lit ACTIONS pour de vrai : un grep aurait trouvé
#  la même chose dans un commentaire, et n'aurait rien dit d'un ensemble
#  construit ailleurs.
if command -v python3 >/dev/null 2>&1; then
	LU="$(python3 - "$PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("partage", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
a = getattr(m, "ACTIONS", None)
print(type(a).__name__, "|", ",".join(sorted(a)) if isinstance(a, (set, frozenset)) else a)
PYEOF
)" || LU=""
	case "$LU" in
		"set | fermer,ouvrir-recus"|"frozenset | fermer,ouvrir-recus")
			ok "ACTIONS = {fermer, ouvrir-recus}, et rien d'autre" ;;
		"")
			non "partage.py ne s'importe pas — la liste des actions n'a pas pu être lue" ;;
		*)
			non "ACTIONS a changé : « $LU » (attendu : set | fermer,ouvrir-recus)" ;;
	esac
else
	saut "python3 absent : la liste des actions n'a pas été lue"
fi

# =============================================================================
titre "7. Le python compile"
# =============================================================================
if command -v python3 >/dev/null 2>&1; then
	if SORTIE="$(python3 -m py_compile "$PY" 2>&1)"; then
		ok "partage.py passe py_compile"
	else
		non "partage.py ne compile pas :\n$(sed 's/^/       /' <<< "$SORTIE")"
	fi
	find "$IC/usr/lib/lexos" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
else
	saut "python3 absent : la compilation n'a pas été éprouvée"
fi

# =============================================================================
titre "8. La page charge les jetons communs AVANT les siens"
# =============================================================================
#  style.css redéfinit des choses par-dessus ui.css. Dans l'autre ordre, les
#  jetons communs écraseraient le panneau — et le panneau aurait l'air à
#  moitié thémé, ce qui est plus dur à diagnostiquer qu'une page toute nue.
ORD_UI="$(grep -n 'href="ui.css"' "$WEB/index.html" | head -1 | cut -d: -f1)"
ORD_ST="$(grep -n 'href="style.css"' "$WEB/index.html" | head -1 | cut -d: -f1)"
if [[ -n "$ORD_UI" && -n "$ORD_ST" && "$ORD_UI" -lt "$ORD_ST" ]]; then
	ok "ui.css est chargé avant style.css (lignes $ORD_UI puis $ORD_ST)"
else
	non "l'ordre des feuilles est faux ou l'une manque (ui.css=$ORD_UI, style.css=$ORD_ST)"
fi

# =============================================================================
titre "9. Le panneau suit le mode clair"
# =============================================================================
#  ═══ LA CI L'A VU AVANT MOI, ET C'EST UN VRAI DÉFAUT ═══
#  « lexos theme clair » repeint le bureau en crème. Sans ce câblage, CETTE
#  fenêtre serait restée noire au milieu — en négatif du reste, exactement le
#  défaut trouvé après l'ISO 71 sur les trois autres panneaux.
#  Le mode voyage par l'adresse : le lanceur lit ~/.config/lexos/mode et
#  l'ajoute en ?mode=…, la page pose l'attribut AVANT le premier rendu.
if grep -q 'dataset.mode' "$WEB/index.html"; then
	ok "la page lit ?mode= et pose l'attribut"
else
	non "la page ne lit pas ?mode= — elle resterait sombre sur un bureau clair"
fi

if grep -q 'index.html?mode=' "$PY"; then
	ok "le lanceur passe le mode dans l'adresse"
else
	non "le lanceur ne passe pas ?mode= — la page ne saurait jamais qu'on est en clair"
fi

#  ═══ ET LE REPLI DE LA LECTURE : SOMBRE, TOUJOURS ═══
#  On EXÉCUTE la fonction sur les cas qui comptent plutôt que de relire son
#  code : un fichier illisible ne doit pas empêcher la fenêtre de s'ouvrir.
if command -v python3 >/dev/null 2>&1; then
	VU="$(python3 - "$PY" <<'PYEOF'
import importlib.util, os, sys, tempfile
spec = importlib.util.spec_from_file_location("partage", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
res = []
with tempfile.TemporaryDirectory() as d:
    os.environ["XDG_CONFIG_HOME"] = d
    res.append(("absent", m.mode_apparence()))
    os.makedirs(os.path.join(d, "lexos"), exist_ok=True)
    f = os.path.join(d, "lexos", "mode")
    for nom, octets in (("clair", b"clair\n"), ("sombre", b"sombre\n"),
                        ("vide", b""), ("illisible", b"\xff\xfe cassE")):
        open(f, "wb").write(octets)
        res.append((nom, m.mode_apparence()))
print(";".join(f"{a}={b}" for a, b in res))
PYEOF
)" || VU=""
	if [[ "$VU" == "absent=sombre;clair=clair;sombre=sombre;vide=sombre;illisible=sombre" ]]; then
		ok "le mode est lu juste sur les cinq cas (absent, clair, sombre, vide, illisible)"
	else
		non "la lecture du mode ne répond pas juste : « $VU »"
	fi
else
	saut "python3 absent : la lecture du mode n'a pas été éprouvée"
fi

# =============================================================================
titre "10. La fenêtre allégée — et le pied qu'on peut encore atteindre"
# =============================================================================
#  ALEX, DEUX PHOTOS : « la fenêtre en montre trop ». Elle affichait, autour du
#  QR, un paragraphe sur le Wi-Fi, une légende sous le code, un bloc « Ça
#  marche dans les deux sens », et deux rangées « KDE Connect » et
#  « Bluetooth ». Six explications pour un geste qui n'en demande aucune.
HTML="$WEB/index.html"
CSS="$WEB/style.css"
JS="$WEB/app.js"
PY="$IC/usr/lib/lexos/partage.py"

#  ═══ ON CHERCHE LE TEXTE AFFICHÉ, PAS LE MOT ═══
#  Le commentaire d'index.html RACONTE ce qui a été retiré et cite donc chacun
#  de ces morceaux. Un grep nu sur le fichier se déclencherait sur l'explication
#  du correctif — dixième fois que ce piège se présente dans ce dépôt. On
#  décommente d'abord : on retire <!-- … --> et /* … */, puis on cherche.
NU="$(python3 - "$HTML" <<'PYNU'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r"<!--.*?-->", " ", t, flags=re.S)
t = re.sub(r"/\*.*?\*/", " ", t, flags=re.S)
sys.stdout.write(t)
PYNU
)"
partie() { # description, texte qui ne doit PLUS s'afficher
	if grep -qF "$2" <<< "$NU"; then
		non "« $2 » s'affiche encore"
	else
		ok "retiré : $1"
	fi
}
partie "le paragraphe sur le Wi-Fi"        "Rien à installer côté téléphone"
partie "la légende sous le QR"             "Scanne avec l'appareil photo"
partie "le bloc « les deux sens »"         "Ça marche dans les deux sens"
partie "la rangée du dossier de réception" 'id="recus"'
#  Les deux rangées d'appareils ne sont plus DANS l'état : elles arrivent sur
#  demande. Ce qu'on vérifie, c'est qu'elles ont quitté /api/etat — pas
#  qu'elles ont disparu du produit.
if grep -q 'e\["moyens"\] = moyens()' "$PY"; then
	non "kdeconnect-cli et bluetoothctl sont encore appelés à chaque ouverture (4 s chacun)"
else
	ok "les appareils proches ont quitté /api/etat"
fi
#  SANS LA BARRE DE TÊTE : le Python écrit « /api/appareils » (un chemin
#  absolu, c'est ce que le serveur compare) et la page « api/appareils » (une
#  adresse RELATIVE, comme api/etat et api/action juste à côté). Chercher la
#  forme absolue des deux côtés faisait rougir ce contrôle sur un câblage
#  parfaitement juste.
if grep -q 'api/appareils' "$PY" && grep -q 'api/appareils' "$JS"; then
	ok "…et ils arrivent sur demande, par /api/appareils"
else
	non "le bouton « Scanner un appareil proche » n'a pas de source"
fi

#  ═══ CE QUI RESTE ═══
garde() { # description, motif
	if grep -qF "$2" <<< "$NU"; then ok "$1"; else non "$1 — « $2 » absent"; fi
}
garde "le QR est toujours là"                  'id="qr"'
garde "l'adresse est un bouton cliquable"      '<button class="adresse" id="url"'
garde "la ligne d'état est en place"           'id="etat-texte"'
garde "le bouton orange demandé par Alex"      'id="appareils"'
garde "« Ouvrir le dossier des reçus » reste"  'id="ouvrir"'
garde "« Fermer le partage » reste"            'id="fermer"'
garde "le compte à rebours reste"              'id="reste"'

# -----------------------------------------------------------------------------
#  ═══ L'ÉCRITURE BLANCHE DU BOUTON — DEMANDÉE, ET SEULEMENT ICI ═══
#  Alex : « le reste de LexOS écrit ses boutons orange en noir. Ici blanc. Ne
#  l'uniformise pas au passage. » Le blanc passe donc par un jeton à lui, pas
#  par --ac-txt, qui est partagé par tous les panneaux.
UICSS="$IC/usr/share/lexos/ui.css"
if grep -qE '^\s*--partage-btn-txt:\s*#FFFFFF;' "$UICSS"; then
	ok "--partage-btn-txt est déclaré blanc dans ui.css"
else
	non "--partage-btn-txt n'est pas déclaré : le bouton n'aurait aucune couleur d'écriture"
fi
if grep -q 'var(--partage-btn-txt)' "$CSS"; then
	ok "…et le bouton l'emploie"
else
	non "le bouton n'emploie pas le jeton"
fi
#  ET --ac-txt N'A PAS BOUGÉ. C'est l'interdiction explicite d'Alex : le
#  changer aurait repeint les Paramètres, le Volet et les Cartes du même coup.
if grep -qE '^\s*--ac-txt:#000;' "$UICSS"; then
	ok "--ac-txt reste noir — les autres panneaux n'ont pas été touchés"
else
	non "--ac-txt a changé : l'écriture blanche a débordé sur tout LexOS"
fi

# -----------------------------------------------------------------------------
#  ═══ LES TROIS ÉTATS, ET PAS UN QUATRIÈME ═══
NIV="$(grep -oE '"niveau": "[a-z-]+"' "$PY" | sort -u | wc -l)"
if [ "$NIV" -eq 3 ]; then
	ok "diagnostic() rend exactement trois niveaux"
else
	non "diagnostic() rend $NIV niveaux au lieu de trois"
fi
for T in "Prêt" "Pare-feu à ouvrir" "Le téléphone doit être sur le même Wi-Fi"; do
	if grep -qF "$T" "$PY"; then ok "l'état « $T » existe"; else non "l'état « $T » manque"; fi
done
#  La page doit savoir peindre les deux classes que le Python peut demander.
if grep -q '\.etat\.pret' "$CSS" && grep -q '\.etat\.souci' "$CSS"; then
	ok "la page sait peindre « prêt » et « à faire »"
else
	non "un des deux états n'a pas de style : la ligne resterait grise"
fi

# -----------------------------------------------------------------------------
#  ═══ LE PIED RESTE ATTEIGNABLE, QUOI QU'ON AFFICHE AU-DESSUS ═══
#  Mesuré pendant l'écriture : 803 px de contenu dans une fenêtre de 660 dès
#  qu'on déployait les appareils proches — « Fermer le partage » passait sous
#  le bord, invisible et donc inatteignable. Même famille que l'avertissement
#  de l'installateur, qui tenait sur 2146 px.
#  Trois lignes tiennent la correction ; retirer n'importe laquelle la défait,
#  et « min-height:0 » est la plus facile à perdre — sans elle, un enfant de
#  flex ne descend jamais sous sa hauteur de contenu et « overflow » ne
#  déclenche rien.
if grep -q '#app{height:100%' "$CSS"; then
	ok "la page a une hauteur FIXE, elle ne grandit plus avec son contenu"
else
	non "#app grandit encore avec son contenu — le pied repassera sous le bord"
fi
if grep -q 'flex:1 1 auto;overflow-y:auto;min-height:0' "$CSS"; then
	ok "la zone centrale défile (avec le min-height:0 qui le rend possible)"
else
	non "la zone centrale ne défile pas : le trop-plein poussera le pied dehors"
fi
#  Pas de tuyau vers « grep -q » : il ferme le tuyau au premier résultat, et
#  sous « pipefail » le producteur qui écrit encore fait échouer TOUT le
#  tuyau — alors que le motif a été trouvé. La substitution de processus sort
#  le producteur du tuyau. La CI refuse cette forme dans tous les bancs.
if grep -q '^\.pied{$' "$CSS" \
   && grep -q 'flex:none' < <(grep -A1 '^\.pied{$' "$CSS"); then
	ok "le pied est épinglé"
else
	non "le pied n'est pas épinglé"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[[ "$ECHOUES" -eq 0 ]]
