#!/usr/bin/env bash
# =============================================================================
#  « Regarde que tous les boutons soient corrects » — Alex, après la photo
# =============================================================================
#  CE QUI EST ARRIVÉ, ET POURQUOI UN ŒIL NE SUFFIT PAS.
#
#  Sur la fenêtre de bienvenue, le libellé des boutons était posé sur un
#  rectangle NOIR à l'intérieur du bouton orange, et écrit en BLANC. Deux
#  défauts distincts, invisibles dans le code pris règle par règle :
#
#    · la règle « écriture blanche partout » repeignait les libellés qui sont
#      DANS un bouton — un enfant qui porte sa propre couleur n'hérite pas de
#      celle du parent, si bien que le noir demandé par le bouton n'arrivait
#      jamais au texte ;
#    · GTK bâtit un bouton en « button > box > label » : peindre le bouton ne
#      repeint pas ses enfants, et le fond sombre du thème de base restait
#      dessous. C'est lui, le rectangle noir.
#
#  Chercher ça à l'œil, c'est relire une feuille de 500 lignes en tenant la
#  cascade CSS dans sa tête. Ce banc le fait à la place : il GÉNÈRE la feuille
#  pour de vrai — huit accents, deux modes — puis MESURE le contraste de
#  chaque famille de boutons. 4,5:1 est le seuil de lisibilité courant ;
#  blanc sur l'orange de LexOS n'en donne que 3,4.
# =============================================================================
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

ACCENTS="orange orange-rouge bleu rouge vert gris violet neon"

# --- Mesurer, plutôt que regarder -------------------------------------------
mesure() {   # <fichier css> ; imprime une ligne par famille de boutons
	python3 - "$1" <<'PY'
import re, sys

css = open(sys.argv[1], encoding="utf-8").read()
#  Les commentaires portent des exemples de couleurs ; les lire fausserait
#  tout. On les retire avant d'analyser quoi que ce soit.
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

def lum(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def contraste(a, b):
    l1, l2 = sorted([lum(a), lum(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

#  Chaque règle : (sélecteurs, corps).
regles = re.findall(r"([^{}]+)\{([^{}]*)\}", css)

def valeur(corps, prop):
    m = re.search(rf"(?<![-\w]){prop}\s*:\s*([^;]+)", corps)
    return m.group(1).strip() if m else None

#  Les familles qu'Alex voit à l'écran. Le libellé sert au message d'erreur.
FAMILLES = [
    ("window button",          "boutons de fenêtre et de dialogue"),
    ("headerbar button",       "boutons de barre de titre"),
    ("toolbar button",         "boutons de barre d'outils"),
    ("popover button",         "boutons de menu surgissant"),
    ("combobox button",        "listes déroulantes"),
    ("treeview header button", "en-têtes de colonnes"),
    ("button.suggested-action", "bouton d'action conseillée"),
    ("button.destructive-action", "bouton de suppression"),
]

for cle, libelle in FAMILLES:
    fond = txt = None
    for sels, corps in regles:
        sl = " ".join(sels.split())
        #  On ne retient que la déclaration de base : pas :hover, pas :disabled.
        if ":" in sl.replace("::", ""):
            continue
        if not re.search(rf"(^|,\s*){re.escape(cle)}(\s*,|\s*$)", sl):
            continue
        f = valeur(corps, "background-color")
        t = valeur(corps, "color")
        if f and f.startswith("#"):
            fond = f
        if t and t.startswith("#"):
            txt = t
    if fond and txt:
        print(f"{cle}|{libelle}|{fond}|{txt}|{contraste(fond, txt):.2f}")
    else:
        print(f"{cle}|{libelle}|{fond or '-'}|{txt or '-'}|MANQUE")
PY
}

# ═════════════════════════════════════════════════════════════════════════════
titre "1. Chaque bouton, chaque accent, chaque mode — le texte est-il lisible ?"
PIRE="999"; PIRE_QUOI=""
TOTAL=0
for MODE in sombre clair; do
	for A in $ACCENTS; do
		rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
		LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
			bash "$GEN" --target "$BANC/t" --mode "$MODE" "$A" >/dev/null 2>&1
		CSS="$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css"
		[ -r "$CSS" ] || { non "$A/$MODE : aucune feuille produite"; continue; }
		while IFS='|' read -r cle libelle fond txt ratio; do
			TOTAL=$((TOTAL + 1))
			if [ "$ratio" = "MANQUE" ]; then
				non "$A/$MODE · $libelle : fond ou couleur absent (fond=$fond texte=$txt)"
				continue
			fi
			if awk -v r="$ratio" 'BEGIN{exit !(r < 4.5)}'; then
				non "$A/$MODE · $libelle : $txt sur $fond = ${ratio}:1 — sous 4,5:1, illisible"
			fi
			if awk -v r="$ratio" -v p="$PIRE" 'BEGIN{exit !(r < p)}'; then
				PIRE="$ratio"; PIRE_QUOI="$A/$MODE · $libelle ($txt sur $fond)"
			fi
		done < <(mesure "$CSS")
	done
done
[ "$ECHOUES" -eq 0 ] && ok "$TOTAL familles de boutons mesurées, toutes au-dessus de 4,5:1"
printf '     \033[2mle plus juste : %s = %s:1\033[0m\n' "$PIRE_QUOI" "$PIRE"

# ═════════════════════════════════════════════════════════════════════════════
titre "2. Le libellé prend la couleur de SON bouton"
rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
	bash "$GEN" --target "$BANC/t" orange >/dev/null 2>&1
CSS="$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css"

#  On lit le BLOC en entier, pas deux lignes après le sélecteur : la première
#  version faisait « grep -A2 » et ratait « color: inherit » dès qu'on ajoutait
#  une propriété avant lui. Un banc qui rate sa cible est pire qu'un banc absent.
BLOC_BTN="$(sed -n '/^button label, button box/,/^}/p' "$CSS")"
[ -n "$BLOC_BTN" ] \
	&& ok "la règle des enfants de bouton existe" \
	|| non "plus de règle « button label, button box » — le blanc général reprendrait le dessus"
printf '%s' "$BLOC_BTN" | grep -q 'color: inherit' \
	&& ok "elle propage la couleur du bouton (color: inherit)" \
	|| non "sans « color: inherit », le libellé garde le blanc général"

#  LE COMBINATEUR, ET C'EST LA LEÇON DE LA 72. Un « > » ne franchit qu'un
#  étage : « button > box » rate « button > box > box », et le fond noir y
#  reste. La règle doit employer la DESCENDANCE, qui ne présume d'aucune
#  profondeur.
printf '%s' "$BLOC_BTN" | head -2 | grep -q '>' \
	&& non "la règle emploie « > » : elle ratera les boutons plus profonds d'un étage" \
	|| ok "et elle emploie la descendance, pas un enfant direct à profondeur devinée"

#  La règle générale « écriture blanche partout » doit venir AVANT celle des
#  libellés de boutons, sinon elle la reprend : à spécificité égale, c'est la
#  dernière qui gagne.
LIGNE_GEN="$(grep -n '^label, .label,' "$CSS" | head -1 | cut -d: -f1)"
LIGNE_BTN="$(grep -n 'button label' "$CSS" | head -1 | cut -d: -f1)"
if [ -n "$LIGNE_GEN" ] && [ -n "$LIGNE_BTN" ] && [ "$LIGNE_BTN" -gt "$LIGNE_GEN" ]; then
	ok "et elle est posée APRÈS la règle générale (sinon celle-ci la reprend)"
else
	non "l'ordre des deux règles est faux : générale=$LIGNE_GEN, boutons=$LIGNE_BTN"
fi

# ═════════════════════════════════════════════════════════════════════════════
titre "3. La cascade résolue sur un vrai arbre, pas une recherche de texte"
#  POURQUOI CETTE SECTION A ÉTÉ RÉÉCRITE.
#
#  Sa première version cherchait la CHAÎNE « button > label, button > box »
#  dans la feuille, et se déclarait satisfaite de la trouver. Elle a donc dit
#  vert sur un correctif INERTE : la règle existait bien, mais « color:
#  inherit » sur le libellé héritait du BLANC de la box intermédiaire — la
#  règle des fonds donne explicitement color:#FFFFFF à « box, grid » — au lieu
#  du noir du bouton. Blanc sur orange, 3,58:1 : exactement le défaut que le
#  correctif prétendait réparer.
#
#  Un banc qui vérifie la PRÉSENCE d'une règle ne vérifie rien. Celui-ci
#  RÉSOUT la cascade sur des arbres de nœuds réels — sélecteurs, spécificité,
#  héritage — et mesure la couleur qui arrive vraiment sur le texte.
cascade() {   # <css> ; sort une ligne par forme de bouton
	python3 - "$1" <<'PY'
import re, sys

css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1], encoding="utf-8").read(), flags=re.S)
#  RETIRER LES DECLARATIONS « @…; » AVANT DE DECOUPER LES REGLES.
#  Sans ca, le bloc @define-color qui precede la regle des fonds se retrouve
#  COLLE a sa liste de selecteurs (le decoupage capture tout ce qui separe deux
#  accolades), et un filtre « @ dans les selecteurs » ecarte alors la regle la
#  plus importante de la feuille — celle qui peint « box, grid » en noir sur
#  blanc. C'est exactement ce qui est arrive : le moteur a declare tous les
#  boutons lisibles en ayant perdu de vue la seule regle qui les rendait
#  illisibles.
css = re.sub(r"@[a-zA-Z-]+[^;{}]*;", "", css)

#  --- Un mini-moteur CSS : juste ce qu'il faut pour les sélecteurs employés ici
def analyse_simple(bout):
    m = re.match(r"^([a-zA-Z][\w-]*)?((?:\.[\w-]+)*)$", bout)
    if not m:
        return None
    nom = m.group(1)
    classes = set(m.group(2).split(".")) - {""}
    return (nom, classes)

def analyse_selecteur(sel):
    """→ liste de (combinateur, nom, classes) ; combinateur ' ' ou '>'."""
    sel = sel.strip()
    if not sel or "*" in sel or "[" in sel:
        return None
    morceaux = re.split(r"\s*(>)\s*|\s+", sel)
    morceaux = [m for m in morceaux if m]
    suite, comb = [], " "
    for m in morceaux:
        if m == ">":
            comb = ">"
            continue
        simple = analyse_simple(m)
        if simple is None:
            return None
        suite.append((comb, simple[0], simple[1]))
        comb = " "
    return suite

def correspond(suite, chemin):
    """chemin = [(nom, classes), …] de la racine à la feuille."""
    def teste(i, k):        # i : index dans suite (depuis la fin), k : index chemin
        if i < 0:
            return True
        comb, nom, classes = suite[i]
        if k < 0:
            return False
        n, c = chemin[k]
        if (nom and nom != n) or not classes <= c:
            if i == len(suite) - 1:
                return False
            if comb == ">":
                return False
            return teste(i, k - 1)
        if comb == ">" or i == 0:
            return teste(i - 1, k - 1)
        for j in range(k - 1, -2, -1):
            if teste(i - 1, j):
                return True
        return False
    #  Le dernier simple doit matcher la feuille elle-même.
    comb, nom, classes = suite[-1]
    n, c = chemin[-1]
    if (nom and nom != n) or not classes <= c:
        return False
    return teste(len(suite) - 2, len(chemin) - 2) if len(suite) > 1 else True

def specificite(suite):
    b = sum(len(cl) for _, _, cl in suite)
    c = sum(1 for _, nom, _ in suite if nom)
    return (b, c)

REGLES = []
for sels, corps in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
    if "@" in sels:
        continue
    decl = {}
    for d in corps.split(";"):
        if ":" in d:
            k, v = d.split(":", 1)
            decl[k.strip()] = v.strip()
    for sel in sels.split(","):
        suite = analyse_selecteur(sel)
        if suite and (":" not in sel):
            REGLES.append((suite, specificite(suite), len(REGLES), decl))

def resoudre(chemin, prop, herite):
    """Valeur calculée de prop sur la feuille de `chemin`."""
    gagnante, meilleure = None, None
    for suite, spec, ordre, decl in REGLES:
        if prop not in decl:
            continue
        if not correspond(suite, chemin):
            continue
        cle = (spec, ordre)
        if meilleure is None or cle > meilleure:
            meilleure, gagnante = cle, decl[prop]
    if gagnante == "inherit":
        return resoudre(chemin[:-1], prop, herite) if len(chemin) > 1 else None
    if gagnante is None and herite and len(chemin) > 1:
        return resoudre(chemin[:-1], prop, herite)
    return gagnante

#  --- Les formes que GTK bâtit réellement pour un bouton ---------------------
FORMES = [
    ("texte seul",            [("window", set()), ("button", set()), ("label", set())]),
    ("icone + texte",         [("window", set()), ("button", set()), ("box", set()), ("label", set())]),
    ("boite imbriquee",       [("window", set()), ("button", set()), ("box", set()), ("box", set()), ("label", set())]),
    ("grille interne",        [("window", set()), ("button", set()), ("grid", set()), ("label", set())]),
    ("action conseillee",     [("window", set()), ("button", {"suggested-action"}), ("box", set()), ("label", set())]),
    ("suppression",           [("window", set()), ("button", {"destructive-action"}), ("box", set()), ("label", set())]),
    ("dialogue, icone+texte", [("dialog", set()), ("button", set()), ("box", set()), ("label", set())]),
]

def lum(h):
    h = h.lstrip("#")
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def contraste(a, b):
    l1, l2 = sorted([lum(a), lum(b)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

for nom, chemin in FORMES:
    txt = resoudre(chemin, "color", True)
    #  Le fond visible : le premier ancêtre (en remontant) qui n'est pas
    #  transparent. C'est ce que l'œil voit derrière le texte.
    fond = None
    for k in range(len(chemin), 0, -1):
        f = resoudre(chemin[:k], "background-color", False)
        if f and f.startswith("#"):
            fond = f
            break
        if f == "transparent":
            continue
    if not (txt and txt.startswith("#") and fond):
        print(f"{nom}|{txt}|{fond}|ILLISIBLE")
        continue
    print(f"{nom}|{txt}|{fond}|{contraste(txt, fond):.2f}")
PY
}

#  COMPTEUR LOCAL, et pas le global : la première version lisait $ECHOUES,
#  si bien qu'un échec d'une section PRÉCÉDENTE faisait disparaître le verdict
#  de celle-ci. On ne saurait plus si la cascade est saine ou seulement muette.
MAUVAIS3=0; VU3=0
for MODE in sombre clair; do
	for A in orange bleu neon; do
		rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
		LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
			bash "$GEN" --target "$BANC/t" --mode "$MODE" "$A" >/dev/null 2>&1
		while IFS='|' read -r forme txt fond ratio; do
			VU3=$((VU3 + 1))
			if [ "$ratio" = "ILLISIBLE" ]; then
				non "$A/$MODE · $forme : couleur ou fond irrésolus (texte=$txt fond=$fond)"
				MAUVAIS3=$((MAUVAIS3 + 1))
			elif awk -v r="$ratio" 'BEGIN{exit !(r < 4.5)}'; then
				non "$A/$MODE · $forme : $txt sur $fond = ${ratio}:1 — le texte du bouton est illisible"
				MAUVAIS3=$((MAUVAIS3 + 1))
			fi
		done < <(cascade "$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css")
	done
done
if [ "$VU3" = "0" ]; then
	non "le moteur de cascade n'a résolu AUCUNE forme — il ne prouve rien"
elif [ "$MAUVAIS3" = "0" ]; then
	ok "$VU3 formes de bouton résolues à la cascade, toutes lisibles (3 accents x 2 modes)"
fi

#  Et la forme qui a piégé la première version, nommée à part pour que le
#  message dise quelque chose le jour où elle revient.
rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
	bash "$GEN" --target "$BANC/t" orange >/dev/null 2>&1
LIGNE="$(cascade "$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css" | grep '^icone + texte|')"
COUL="$(printf '%s' "$LIGNE" | cut -d'|' -f2)"
[ "$COUL" = "#000000" ] \
	&& ok "bouton à icône : le libellé est NOIR — il n'hérite plus du blanc de la box" \
	|| non "bouton à icône : libellé $COUL au lieu de #000000 — c'est le défaut de la 72"

# ═════════════════════════════════════════════════════════════════════════════
titre "4. Les faux boutons ne sont pas devenus orange"
#  Le revers du correctif : à force de peindre, on repeint les listes
#  déroulantes et les en-têtes de colonnes. Alex l'avait signalé une fois
#  (« les listes en gros orange ») — ça ne doit pas revenir.
ACC="$(sed -n '/^window button, dialog button/,/}/p' "$CSS" | grep -oE 'background-color: #[0-9A-Fa-f]{6}' | grep -oE '#[0-9A-Fa-f]{6}' | head -1)"
STRUCT="$(sed -n '/^combobox button, combobox button.combo/,/}/p' "$CSS" | grep -oE 'background-color: #[0-9A-Fa-f]{6}' | grep -oE '#[0-9A-Fa-f]{6}')"
[ -n "$ACC" ] && [ -n "$STRUCT" ] && [ "$ACC" != "$STRUCT" ] \
	&& ok "listes déroulantes ($STRUCT) ≠ boutons ($ACC)" \
	|| non "les faux boutons ont repris la couleur d'accent (acc=$ACC struct=$STRUCT)"

# ═════════════════════════════════════════════════════════════════════════════
titre "5. Le rectangle de sélection reste transparent"
#  PHOTO D'ALEX, ISO 74 : en tirant un cadre dans Fichiers pour prendre
#  plusieurs dossiers, le rectangle est un BLOC NOIR OPAQUE. Il cache ce
#  qu'on est justement en train de choisir.
#
#  La cause est la MÊME que celle des boutons de la 72, et c'est pour ça que
#  ce contrôle vit ici, avec le moteur de cascade : pendant le tracé, GTK
#  n'ouvre pas un nœud à part — il reprend le contexte de la vue et lui
#  AJOUTE la classe .rubberband. Le nœud porte donc « iconview », « .view »
#  ET « .rubberband » à la fois. Notre règle des fonds liste « .view »
#  (0,1,0) ; celle d'Arc porte « .rubberband » (0,1,0). À égalité de
#  spécificité, la feuille lue en dernier gagne — la nôtre. Le fond opaque
#  écrasait donc le fond transparent d'Arc.
#
#  ON NE CHERCHE DONC PAS SI LA RÈGLE EXISTE. Une règle « rubberband { … } »
#  toute seule existerait et ne servirait à rien : elle pèse (0,0,1) et
#  perdrait contre notre propre « .view ». On RÉSOUT la cascade sur le nœud
#  réel et on regarde la couleur qui gagne, exactement comme pour les
#  libellés de boutons.
MAUVAIS5=0; VU5=0
for MODE in sombre clair; do
	for A in orange bleu neon; do
		rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
		LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
			bash "$GEN" --target "$BANC/t" --mode "$MODE" "$A" >/dev/null 2>&1
		VERDICT="$(python3 - "$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css" <<'PY'
import re, sys

css = re.sub(r"/\*.*?\*/", "", open(sys.argv[1], encoding="utf-8").read(), flags=re.S)
css = re.sub(r"@[a-zA-Z-]+[^;{}]*;", "", css)

#  Le nœud tel que GTK le construit pendant le tracé du caoutchouc.
ELEM, CLASSES = "iconview", {"view", "rubberband"}


def analyse(bout):
    m = re.match(r"^([a-zA-Z][\w-]*)?((?:\.[\w-]+)*)$", bout.strip())
    if not m:
        return None
    return m.group(1), set(re.findall(r"\.([\w-]+)", m.group(2) or ""))


gagnant = None          # (specificite, ordre, valeur)
for i, (sels, corps) in enumerate(re.findall(r"([^{}]+)\{([^{}]*)\}", css)):
    val = None
    for d in corps.split(";"):
        if ":" in d:
            k, v = d.split(":", 1)
            if k.strip() == "background-color":
                val = v.strip()
    if val is None:
        continue
    for sel in sels.split(","):
        sel = sel.strip()
        #  Un seul nœud : tout sélecteur composé (descendant, enfant) ne peut
        #  pas correspondre. On les écarte proprement au lieu de les rater.
        if not sel or re.search(r"[\s>+~:\[]", sel):
            continue
        a = analyse(sel)
        if not a:
            continue
        el, cl = a
        if el and el != ELEM:
            continue
        if not cl <= CLASSES:
            continue
        spec = (len(cl), 1 if el else 0)
        if gagnant is None or (spec, i) > (gagnant[0], gagnant[1]):
            gagnant = (spec, i, val, sel)

if gagnant is None:
    print("AUCUNE")
else:
    spec, _, val, sel = gagnant
    m = re.match(r"rgba\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*([0-9.]+)\s*\)$", val)
    if m and float(m.group(1)) < 1.0:
        print("OK %s -> %s" % (sel, val))
    else:
        print("OPAQUE %s -> %s" % (sel, val))
PY
)"
		VU5=$((VU5 + 1))
		case "$VERDICT" in
			OK*) : ;;
			*)   non "$A/$MODE · caoutchouc : $VERDICT"; MAUVAIS5=$((MAUVAIS5 + 1)) ;;
		esac
	done
done
if [ "$VU5" = "0" ]; then
	non "aucune feuille examinée pour le caoutchouc — ce contrôle ne prouve rien"
elif [ "$MAUVAIS5" = "0" ]; then
	ok "$VU5 feuilles : la règle qui GAGNE sur le caoutchouc est transparente"
fi

# ═════════════════════════════════════════════════════════════════════════════
titre "6. Le thème de l'utilisateur ne masque jamais le système à moitié"
#  LE DÉFAUT QUI A COÛTÉ QUATRE ISO (71 bleus, 72-74 feuilles blanches).
#  lexos-theme-gen écrivait un thème d'icônes nommé « LexOS » dans le
#  dossier personnel. Le dossier personnel passe AVANT /usr/share, et deux
#  thèmes de même nom ne se complètent pas : le premier trouvé gagne. Or
#  cette copie ne contenait que « places/scalable », là où le thème système
#  a huit tailles fixes plus les icônes d'application. Le thème complet
#  était masqué par une copie qui en portait un neuvième.
#
#  L'indice qui a tranché vient d'Alex, sur le dock : « le fichier change
#  quand je mets la souris dessus ». Plank agrandit au survol — une icône
#  qui change avec la TAILLE, c'est un défaut de choix, pas d'absence.
#
#  Deux règles, et ce banc les tient toutes les deux :
#    · sous l'accent par défaut, AUCUNE copie (elle n'apporterait aucune
#      couleur, seulement un masque) ;
#    · sous un autre accent, la copie est COMPLÈTE et son index.theme
#      déclare exactement ce qui est sur le disque.
#  LE FAUX rsvg-convert N'EMPLOIE QUE LA BIBLIOTHÈQUE STANDARD.
#  Il s'appuyait sur Pillow — qui n'est PAS installé à cette étape de
#  l'intégration continue (elle ne l'installe qu'au banc du hook 0610, plus
#  loin). Il échouait donc en silence, ne posait aucun PNG, et le banc
#  mesurait alors le comportement d'un rsvg-convert CASSÉ en croyant mesurer
#  celui d'un rsvg-convert normal. Un outil de banc qui dépend d'un paquet
#  optionnel n'éprouve pas ce qu'il annonce.
#  (Le service rendu : c'est ce hasard qui a révélé le vrai trou du garde-fou
#  de lexos-theme-gen. Il est corrigé ; le cas est éprouvé plus bas.)
FAUX6="$BANC/faux-rsvg"; mkdir -p "$FAUX6"
cat > "$FAUX6/rsvg-convert" <<'SH'
#!/usr/bin/env bash
python3 - "$@" <<'PY'
import sys, zlib, struct
a = sys.argv
w = int(a[a.index("-w") + 1]); h = int(a[a.index("-h") + 1])
brut = b"".join(b"\x00" + b"\xe8\x59\x0c\xff" * w for _ in range(h))
def bloc(t, d):
    c = t + d
    return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
png = (b"\x89PNG\r\n\x1a\n"
       + bloc(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
       + bloc(b"IDAT", zlib.compress(brut))
       + bloc(b"IEND", b""))
open(a[a.index("-o") + 1], "wb").write(png)
PY
SH
chmod +x "$FAUX6/rsvg-convert"

#  ET UN rsvg-convert QUI ÉCHOUE : présent dans le PATH, mais incapable de
#  produire quoi que ce soit. C'est le cas que l'intégration continue a
#  rencontré pour de vrai, et celui que le garde-fou ne voyait pas — il
#  cherchait des DOSSIERS de taille, or « mkdir -p » les crée avant la
#  conversion et chaque appel se termine par « || true ». Seize dossiers
#  vides suffisaient à le convaincre.
CASSE6="$BANC/rsvg-casse"; mkdir -p "$CASSE6"
printf '#!/bin/sh\nexit 1\n' > "$CASSE6/rsvg-convert"
chmod +x "$CASSE6/rsvg-convert"

theme_utilisateur() {   # <accent> <PATH> ; écrit le dossier du thème sur stdout
	rm -rf "${BANC:?}/u"; mkdir -p "$BANC/u"
	PATH="$1" HOME="$BANC/u" LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		LEXOS_ICONES="$RACINE/config/includes.chroot/usr/share/icons/LexOS" \
		bash "$GEN" --target "$BANC/u" "$2" >/dev/null 2>&1
	printf '%s' "$BANC/u/.local/share/icons/LexOS"
}

D6="$(theme_utilisateur "$FAUX6:$PATH" orange)"
[ ! -d "$D6" ] \
	&& ok "accent par défaut : aucune copie — le thème système complet reste visible" \
	|| non "accent par défaut : une copie masque encore le thème système"

MAUVAIS6=0
for A6 in bleu vert neon; do
	D6="$(theme_utilisateur "$FAUX6:$PATH" "$A6")"
	if [ ! -d "$D6" ]; then
		non "$A6 : aucune copie alors que l'accent diffère — les dossiers garderaient l'orange"
		MAUVAIS6=$((MAUVAIS6 + 1)); continue
	fi
	SUR="$(find "$D6" -mindepth 2 -maxdepth 2 -type d | wc -l)"
	DECL="$(grep -m1 '^Directories=' "$D6/index.theme" | sed 's/^Directories=//' | tr ',' '\n' | grep -c .)"
	FIXES="$(find "$D6/places" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | wc -l)"
	if [ "$SUR" != "$DECL" ]; then
		non "$A6 : index.theme déclare $DECL dossiers pour $SUR sur le disque"
		MAUVAIS6=$((MAUVAIS6 + 1))
	elif [ "$FIXES" -lt 8 ]; then
		non "$A6 : $FIXES tailles fixes seulement — la copie masquerait le système à moitié"
		MAUVAIS6=$((MAUVAIS6 + 1))
	fi
done
[ "$MAUVAIS6" = "0" ] \
	&& ok "trois accents : la copie est complète (8 tailles fixes) et son index dit vrai"

#  ET LE CAS DÉGRADÉ : sans rsvg-convert, on ne peut pas égaler le système,
#  donc on ne masque PAS. Des dossiers de la mauvaise couleur mais visibles
#  valent mieux que des dossiers de la bonne couleur invisibles.
MIN6="$BANC/min6"; rm -rf "$MIN6"; mkdir -p "$MIN6"
for c in bash sh sed grep find mkdir rm cp cat printf env python3 basename dirname date id tr sort head wc; do
	r="$(command -v "$c" 2>/dev/null)" && ln -sf "$r" "$MIN6/$c"
done
D6="$(theme_utilisateur "$MIN6" bleu)"
[ ! -d "$D6" ] \
	&& ok "sans rsvg-convert : pas de copie du tout — on ne masque pas à moitié" \
	|| non "sans rsvg-convert, une copie incomplète masque quand même le système"

#  LE CAS QUI A RENDU LA CI ROUGE : rsvg-convert est là, et il ÉCHOUE. Les
#  dossiers de taille existent (mkdir -p) mais sont vides. Un garde-fou qui
#  regarde les dossiers au lieu de leur contenu laisse alors passer
#  exactement le défaut qu'il devait arrêter.
D6="$(theme_utilisateur "$CASSE6:$MIN6" bleu)"
[ ! -d "$D6" ] \
	&& ok "rsvg-convert présent mais EN ÉCHEC : pas de copie non plus" \
	|| non "rsvg-convert en échec : une copie vide masque le système ($(find "$D6" -type f | wc -l) fichiers)"

# ═════════════════════════════════════════════════════════════════════════════
titre "7. flameshot suit l'accent, et pas l'inverse"
# ═════════════════════════════════════════════════════════════════════════════
#  ALEX, PHOTO DU SÉLECTEUR DE ZONE : « changer la couleur pour orange au
#  lieu de rose ». flameshot.ini est écrit par lexos-theme-gen ; ce banc
#  vérifie que la couleur POSÉE est la bonne, ET que le contraste de l'icône
#  par-dessus (contrastUiColor) tient toujours le seuil WCAG — la même règle
#  que la section 1 applique aux boutons GTK, appliquée ici à un fichier
#  tiers que la section 1 ne regarde pas.
for A in orange bleu violet neon rouge vert gris; do
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" 		bash "$GEN" --target "$BANC/t" "$A" >/dev/null 2>&1
	INI="$BANC/t/.config/flameshot/flameshot.ini"
	[ -r "$INI" ] || { non "$A : aucun flameshot.ini produit"; continue; }

	UI="$(sed -n 's/^uiColor=//p' "$INI")"
	CONTR="$(sed -n 's/^contrastUiColor=//p' "$INI")"

	#  Le calcul de contraste n'a rien à faire sur une valeur absente — une
	#  chaîne vide passée à int(x, 16) plante en Python, et une trace de pile
	#  au milieu d'un banc n'aide personne à voir CE QUI a échoué. On sort
	#  donc AVANT tout calcul.
	if [ -z "$UI" ] || [ -z "$CONTR" ]; then
		non "$A : uiColor ou contrastUiColor manquant dans flameshot.ini"
		continue
	fi

	RATIO="$(python3 -c "
def lum(h):
    h = h.lstrip('#')
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]
l1, l2 = sorted([lum('$UI'), lum('$CONTR')], reverse=True)
print(f'{(l1 + 0.05) / (l2 + 0.05):.2f}')
")"
	if awk -v r="$RATIO" 'BEGIN{exit !(r < 4.5)}'; then
		non "$A : icône $CONTR sur bouton $UI = ${RATIO}:1 — sous 4,5:1"
	else
		ok "$A : $UI, icône $CONTR lisible (${RATIO}:1)"
	fi
done

#  LA PREUVE PAR L'OUTIL RÉEL, QUAND IL EST LÀ. On ne devine pas les clés
#  « uiColor »/« contrastUiColor » — un mauvais nom serait ignoré par
#  flameshot EN SILENCE (QSettings ne proteste jamais d'une clé inconnue) et
#  la barre resterait violette sans qu'aucun test ne le voie. Si le vrai
#  binaire flameshot est disponible sur la machine qui fait tourner ce banc,
#  on lui fait relire NOTRE fichier et VALIDER — pas relire son propre
#  format en se faisant confiance à soi-même.
if command -v flameshot >/dev/null 2>&1; then
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" 		bash "$GEN" --target "$BANC/t" orange >/dev/null 2>&1
	SORTIE_FS="$(HOME="$BANC/t" QT_QPA_PLATFORM=offscreen flameshot config --check 2>&1)"
	echo "$SORTIE_FS" | grep -qi 'no errors' 		&& ok "le flameshot RÉELLEMENT installé valide notre fichier sans se plaindre" 		|| non "flameshot rejette notre fichier : $SORTIE_FS"
else
	printf '  \033[2mflameshot absent de cette machine — contrôle par le vrai binaire sauté (le reste tient quand même)\033[0m\n'
fi

# ═════════════════════════════════════════════════════════════════════════════
titre "8. La grille d'applications ne se peint plus en orange"
# ═════════════════════════════════════════════════════════════════════════════
#  ALEX, capture de la Liste des applications : « la couleur de l'application
#  une fois sélectionnée, il faudrait que le carré orange reste de couleur
#  gris pâle », « au lieu de faire tout un carré orange ».
#
#  Ailleurs, l'accent sur la sélection est juste : une ligne de liste est un
#  ruban fin. Ici c'est une TUILE qui porte déjà une icône colorée — un aplat
#  d'accent de cette taille écrase le dessin qu'on est en train de choisir.
#
#  ═══ DEUX CHOSES À TENIR EN MÊME TEMPS ═══
#  Retirer l'accent de la grille, ET ne pas le retirer partout ailleurs : la
#  règle d'origine nommait la grille, les listes et le survol des menus dans
#  un seul sélecteur. Les séparer sans regarder ce que devient l'autre
#  moitié, c'est repeindre tout le bureau en gris sans s'en apercevoir.
for MODE in sombre clair; do
	for ACC in orange bleu; do
		rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
		HOME="$BANC/t" LEXOS_BRANDING="$RACINE/branding" \
			bash "$GEN" "$ACC" --mode "$MODE" --target "$BANC/t" >/dev/null 2>&1
		CSS8="$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css"
		if [ ! -r "$CSS8" ]; then
			non "$ACC/$MODE : aucune feuille produite"
			continue
		fi
		VERDICT8="$(python3 - "$CSS8" <<'PY2'
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
css = re.sub(r'/\*[\s\S]*?\*/', '', css)   # la prose ne compte pas


def bloc(motif):
    m = re.search(motif + r'[^{]*\{([^}]*)\}', css)
    return m.group(1) if m else None


def val(corps, prop):
    #  « color » ne doit PAS attraper « background-color » : sans l'ancre de
    #  début de ligne, le premier jet lisait le fond et annonçait un contraste
    #  de 1,00 — le libellé accusé d'être illisible alors qu'il est noir.
    if corps is None:
        return None
    m = re.search(r'^\s*' + prop + r'\s*:\s*([^;]+);', corps, re.M)
    return m.group(1).strip() if m else None


def lum(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


grille = bloc(r'iconview:selected')
listes = bloc(r'row:selected, list row:selected, treeview\.view:selected')
fg, bg = val(grille, "color"), val(grille, "background-color")
print("GRILLE_BG:%s" % (bg or ""))
print("GRILLE_FG:%s" % (fg or ""))
print("LISTE_BG:%s" % (val(listes, "background-color") or ""))
print("RAYON:%s" % (val(grille, "border-radius") or ""))
if bg and fg and bg.startswith("#") and fg.startswith("#"):
    a, b = lum(bg) + 0.05, lum(fg) + 0.05
    print("CONTRASTE:%.2f" % (max(a, b) / min(a, b)))
PY2
)"
		lire8() { printf '%s' "$VERDICT8" | sed -n "s/^$1://p"; }
		G_BG="$(lire8 GRILLE_BG)"; G_FG="$(lire8 GRILLE_FG)"
		L_BG="$(lire8 LISTE_BG)"; RAY="$(lire8 RAYON)"; CTR="$(lire8 CONTRASTE)"

		if [ -z "$G_BG" ]; then
			non "$ACC/$MODE : aucune règle pour la grille — la sélection reprendrait l'accent"
			continue
		fi
		#  LE CŒUR : la tuile ne doit PAS porter l'accent, quel qu'il soit.
		if [ "$G_BG" = "$L_BG" ]; then
			non "$ACC/$MODE : la grille porte encore la couleur des listes ($G_BG)"
		else
			ok "$ACC/$MODE : la grille ($G_BG) ne prend plus l'accent ($L_BG)"
		fi
		#  ET L'AUTRE MOITIÉ N'A PAS ÉTÉ EMPORTÉE : les listes et le survol des
		#  menus gardent l'accent. Sans ce contrôle, tout repeindre en gris
		#  passerait pour un succès.
		if [ -n "$L_BG" ] && [ "$L_BG" != "$G_BG" ]; then
			ok "$ACC/$MODE : les listes et les menus gardent bien l'accent"
		else
			non "$ACC/$MODE : la sélection des listes a été emportée avec la grille"
		fi
		#  Le libellé doit rester lisible SUR ce gris : en blanc il disparaît.
		if [ -n "$CTR" ] && [ "${CTR%%.*}" -ge 4 ]; then
			ok "$ACC/$MODE : le libellé garde un contraste de ${CTR}:1 sur la tuile"
		else
			non "$ACC/$MODE : contraste « ${CTR:-?} » entre $G_FG et $G_BG — libellé illisible"
		fi
		#  « Au lieu de faire tout un carré » : des coins, donc.
		if [ -n "$RAY" ]; then
			ok "$ACC/$MODE : la tuile a des coins arrondis ($RAY)"
		else
			non "$ACC/$MODE : la tuile reste un carré franc"
		fi
	done
done

# ═════════════════════════════════════════════════════════════════════════════
titre "Le bouton reste lisible DANS TOUS SES ÉTATS, sur tous les accents"
# ═════════════════════════════════════════════════════════════════════════════
#  ═══ CE QUE CE CONTRÔLE EMPÊCHE DE REVENIR ═══
#  « window button:hover » posait un fond SANS couleur de texte. Le texte
#  restait donc celui du thème de socle — Yaru-dark écrit
#  « button:hover { color: #F7F7F7 } » — pendant que le fond, lui, passait à
#  ACCENT_HI, une teinte PLUS CLAIRE que l'accent. Mesuré à la sonde GTK,
#  accent orange : #F7F7F7 sur #FF7A33, soit 2,42:1, alors que le MÊME bouton
#  au repos est à 5,87:1. Le libellé devenait illisible exactement au moment
#  où la souris le désigne. Sur l'accent vert, 2,23:1.
#
#  C'est la même faute que le menu Whisker, trouvée par la passe qui suivait
#  ce correctif-là : un fond posé sans sa couleur de texte.
#
#  ON NE LIT PAS LE CSS, ON CALCULE LE CONTRASTE. Le générateur est lancé
#  pour de vrai, sur plusieurs accents, et on relit les couleurs qu'il écrit.
GEN_B="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
if [ ! -x "$GEN_B" ]; then
	printf '  \033[2m—\033[0m %s\n' "lexos-theme-gen introuvable : contraste des boutons non mesuré"
else
	for ACC in orange bleu vert violet rouge gris; do
		FOYER="$BANC/foyer-$ACC"; mkdir -p "$FOYER"
		HOME="$FOYER" bash "$GEN_B" "$ACC" --target "$FOYER" >/dev/null 2>&1
		CSSG="$FOYER/.themes/LexOS-Noir/gtk-3.0/gtk.css"
		if [ ! -r "$CSSG" ]; then
			non "accent $ACC : le générateur n'a produit aucun thème"
			continue
		fi
		#  On extrait, pour le survol et pour l'appui, le fond et la couleur
		#  écrits par le générateur, puis on calcule le rapport WCAG.
		RES="$(python3 - "$CSSG" <<'PYC' 2>/dev/null
import re, sys
css = open(sys.argv[1], encoding='utf-8', errors='replace').read()
css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
def lin(v):
    v /= 255.0
    return v/12.92 if v <= 0.03928 else ((v+0.055)/1.055)**2.4
def L(c):
    r, g, b = c
    return .2126*lin(r) + .7152*lin(g) + .0722*lin(b)
def ratio(a, b):
    la, lb = L(a), L(b)
    return (max(la, lb)+.05) / (min(la, lb)+.05)
def hexa(x):
    x = x.lstrip('#')
    return tuple(int(x[i:i+2], 16) for i in (0, 2, 4))
def bloc(motif):
    m = re.search(motif + r'[^{}]*\{([^{}]*)\}', css)
    return m.group(1) if m else None
for nom, motif in (("survol", r'window button:hover'),
                   ("appui",  r'window button:active')):
    b = bloc(motif)
    if b is None:
        print(nom, "ABSENT"); continue
    f = re.search(r'background-color:\s*(#[0-9A-Fa-f]{6})', b)
    t = re.search(r'(?:^|[;\s])color:\s*(#[0-9A-Fa-f]{6})', b)
    if not f or not t:
        print(nom, "PAIRE-INCOMPLETE", "fond" if f else "-", "texte" if t else "-")
        continue
    print(nom, "%.2f" % ratio(hexa(t.group(1)), hexa(f.group(1))), t.group(1), f.group(1))
PYC
)"
		ETAT_KO=""
		while read -r NOM VAL C1 C2; do
			[ -n "$NOM" ] || continue
			case "$VAL" in
				ABSENT)
					non "accent $ACC, $NOM : la règle a disparu du générateur"; ETAT_KO=1 ;;
				PAIRE-INCOMPLETE)
					non "accent $ACC, $NOM : fond sans couleur de texte — la faute d'origine"; ETAT_KO=1 ;;
				*)
					#  4,5:1 est le seuil WCAG AA pour du texte courant. Le
					#  libellé d'un bouton en est.
					if awk "BEGIN{exit !($VAL >= 4.5)}"; then
						:
					else
						non "accent $ACC, $NOM : $C1 sur $C2 = ${VAL}:1, sous le seuil de 4,5:1"
						ETAT_KO=1
					fi ;;
			esac
		done <<< "$RES"
		[ -n "$ETAT_KO" ] || ok "accent $ACC : survol et appui restent lisibles (≥ 4,5:1)"
	done
fi

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
