#!/usr/bin/env bash
# =============================================================================
#  Éprouver les fonds d'écran envoyés par Alex — la mise au format 1920 × 1080
# =============================================================================
#  CE QUE CE BANC MESURE, ET POURQUOI IL NE LIT PAS LE CODE.
#
#  Aucune des images d'Alex n'est en 16:9. Laissées à xfdesktop, elles sont
#  étirées ou rognées au hasard selon le style enregistré — la mascotte
#  déformée, la bannière coupée. Le hook 0300 les met donc au format à la
#  construction, avec DEUX recettes différentes parce que les images ne se
#  ressemblent pas.
#
#  Un « grep convert » dirait oui à un cadrage faux. Ce banc EXÉCUTE le vrai
#  fragment du vrai hook, sur les vraies images du dépôt, et MESURE ce qui
#  sort : le format, l'absence de déformation, l'endroit du rognage.
#
#  L'ORDRE : les replis d'abord. Sans convert, aucun fond ne doit être posé —
#  mieux vaut leur absence qu'une image déformée livrée en silence.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
BRANDING="$RACINE/branding"
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

#  Le fragment du hook, découpé entre ses deux repères. On ne recopie pas le
#  code dans le banc : un banc qui éprouve sa propre copie ne prouve rien.
BLOC="$(sed -n '/^# >>> banc: fonds-alex$/,/^# <<< banc: fonds-alex$/p' "$HOOK" | sed '1d;$d')"
[ -n "$BLOC" ] || { echo "fragment « fonds-alex » introuvable dans le hook 0300"; exit 1; }

prepare() { # prepare [--sans-sources]
	rm -rf "${BANC:?}/racine"
	mkdir -p "$BANC/racine/brand" "$BANC/racine/bg"
	if [ "${1:-}" != "--sans-sources" ]; then
		for F in fond-mascotte.jpg fond-tilexal-banniere.jpg; do
			[ -r "$BRANDING/$F" ] && cp "$BRANDING/$F" "$BANC/racine/brand/"
		done
	fi
}
lance() { # lance [PATH=...]
	env "$@" BRAND="$BANC/racine/brand" BG="$BANC/racine/bg" \
		sh -c '
			have() { command -v "$1" >/dev/null 2>&1; }
			'"$BLOC"'
		' 2>&1
}
dim() { identify -format '%wx%h' "$1" 2>/dev/null; }

# =============================================================================
titre "1. LES REPLIS D'ABORD — rien de déformé ne part en silence"
# =============================================================================

# --- convert absent : une ferme de liens symboliques SANS convert -----------
#  ═══ ON FABRIQUE L'ABSENCE, ON NE L'ATTEND PAS ═══
#  « convert absent » est le cas qui compte : imagemagick ne vit que dans des
#  listes facultatives que le hook 0250 pose en tolérant l'échec. Sur cette
#  machine il EST là — alors on lui retire, plutôt que de sauter le contrôle.
SANS_IM="$BANC/sans-im"
mkdir -p "$SANS_IM"
for d in /usr/bin /bin /usr/sbin /sbin; do
	[ -d "$d" ] || continue
	for f in "$d"/*; do
		b="$(basename "$f")"
		case "$b" in convert|magick) continue ;; esac
		[ -e "$SANS_IM/$b" ] || ln -s "$f" "$SANS_IM/$b" 2>/dev/null
	done
done
if PATH="$SANS_IM" command -v convert >/dev/null 2>&1; then
	non "le PATH sans convert n'a pas pu être fabriqué : le contrôle ne prouverait rien"
else
	prepare
	SORTIE="$(lance PATH="$SANS_IM")"
	POSES="$(find "$BANC/racine/bg" -type f 2>/dev/null | wc -l)"
	if [ "$POSES" -eq 0 ] && printf '%s' "$SORTIE" | grep -q 'convert absent'; then
		ok "sans convert : AUCUN fond posé, et le journal le dit"
	else
		non "sans convert : $POSES fichier(s) posé(s), journal « $(printf '%s' "$SORTIE" | head -1) »"
	fi
	#  Et les sources ne doivent PAS être effacées quand rien n'a été produit :
	#  ce serait perdre l'image sans rien donner en échange.
	if [ -r "$BANC/racine/brand/fond-mascotte.jpg" ]; then
		ok "…et les sources sont intactes : on n'efface pas ce qu'on n'a pas su remplacer"
	else
		non "sans convert, la source a quand même été effacée"
	fi
fi

# --- Sources absentes : chaque manque est NOMMÉ ------------------------------
if ! command -v convert >/dev/null 2>&1; then
	saut "convert absent sur cette machine : le reste du banc ne peut pas mesurer"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
	[ "$ECHOUES" -eq 0 ]
	exit
fi
prepare --sans-sources
SORTIE="$(lance)"
if printf '%s' "$SORTIE" | grep -q 'fond-mascotte.jpg absent' \
   && printf '%s' "$SORTIE" | grep -q 'fond-tilexal-banniere.jpg absent'; then
	ok "sources absentes : les DEUX manques sont nommés par leur nom de fichier"
else
	non "sources absentes : le journal ne nomme pas les deux fichiers"
fi

# =============================================================================
titre "2. LE FORMAT — 1920 × 1080, mesuré sur l'image produite"
# =============================================================================
if [ ! -r "$BRANDING/fond-mascotte.jpg" ] || [ ! -r "$BRANDING/fond-tilexal-banniere.jpg" ]; then
	saut "les sources ne sont pas dans branding/ : rien à mesurer"
else
prepare
SORTIE="$(lance)"
MASC="$BANC/racine/bg/wallpaper-mascotte.jpg"
TILE="$BANC/racine/bg/wallpaper-tilexal.jpg"
for PAIRE in "wallpaper-mascotte.jpg" "wallpaper-tilexal.jpg"; do
	D="$(dim "$BANC/racine/bg/$PAIRE")"
	[ "$D" = "1920x1080" ] \
		&& ok "$PAIRE : $D" \
		|| non "$PAIRE : « $D » (attendu 1920x1080) — xfdesktop l'étirerait"
done

# =============================================================================
titre "3. LE PORTRAIT EST CENTRÉ, ET RIEN N'EST ROGNÉ"
# =============================================================================
#  ═══ « NE ROGNE RIEN » SE MESURE, ÇA NE SE LIT PAS ═══
#  1392 × 1680 mis à la hauteur donne 895 × 1080. Deux choses à prouver :
#    · l'image tient ENTIÈRE — on la compare à un redimensionnement pur, sans
#      cadre : si le hook avait rogné, les deux ne coïncideraient pas ;
#    · elle est CENTRÉE — les bandes noires gauche et droite sont égales.
#  Alex : « bien le centre a ecren ».
if python3 -c 'import PIL' 2>/dev/null && [ -r "$MASC" ]; then
	convert "$BRANDING/fond-mascotte.jpg" -resize x1080 "$BANC/attendu.png" 2>/dev/null
	MESURE="$(python3 - "$MASC" "$BANC/attendu.png" <<'PY' 2>/dev/null
import sys
from PIL import Image, ImageChops, ImageStat
prod = Image.open(sys.argv[1]).convert("RGB")
att  = Image.open(sys.argv[2]).convert("RGB")
W, H = prod.size
w, h = att.size
x = (W - w) // 2
#  Écart moyen entre la zone centrale du produit et le redimensionnement pur.
#  Non nul à cause du JPEG, mais très petit si rien n'a été rogné ni déformé.
ecart = ImageStat.Stat(ImageChops.difference(prod.crop((x, 0, x + w, H)), att)).mean[0]
#  Les bandes : première et dernière colonne non noire du produit.
def largeur_contenu(im):
    iw, ih = im.size
    cols = [c for c in range(iw)
            if any(sum(im.getpixel((c, y))) > 40 for y in range(0, ih, 8))]
    return (cols[0], iw - 1 - cols[-1], cols[-1] - cols[0] + 1) if cols else (-1, -1, -1)
g, d, larg_prod = largeur_contenu(prod)
_, _, larg_att = largeur_contenu(att)
print("%.2f %d %d %d %d %d" % (ecart, g, d, w, larg_prod, larg_att))
PY
)"
	set -- $MESURE
	#  $4 (la largeur du redimensionnement de référence) n'est plus lue : le
	#  contrôle qui s'en servait mesurait faux. On la laisse tomber plutôt que
	#  de garder une variable morte au milieu des mesures.
	ECART="${1:-99}"; GAUCHE="${2:--1}"; DROITE="${3:--1}"
	LARG_PROD="${5:--1}"; LARG_ATT="${6:--2}"
	if awk "BEGIN{exit !($ECART < 6)}"; then
		ok "le portrait tient entier : écart $ECART/255 contre un simple redimensionnement (rien n'est rogné)"
	else
		non "écart $ECART/255 contre le redimensionnement pur : l'image a été rognée ou déformée"
	fi
	#  Les bandes ne se mesurent pas sur le CADRE (895 px de large calculé)
	#  mais sur le CONTENU VISIBLE : le fond de l'image est lui-même noir, la
	#  personne ne touche pas les bords du portrait. On compare donc les deux
	#  côtés entre eux — égaux = centré, quelle que soit la marge interne.
	DELTA=$(( GAUCHE > DROITE ? GAUCHE - DROITE : DROITE - GAUCHE ))
	if [ "$GAUCHE" -ge 0 ] && [ "$DELTA" -le 12 ]; then
		ok "le portrait est centré : ${GAUCHE} px de noir à gauche, ${DROITE} px à droite"
	else
		non "décentré : ${GAUCHE} px à gauche contre ${DROITE} px à droite"
	fi
	#  ═══ DEUX PREMIERS JETS DE CE CONTRÔLE ONT ÉTÉ FAUX ═══
	#  1er : comparer $LARG (la largeur du redimensionnement de RÉFÉRENCE) à
	#  1920. Cette valeur vient de la source, pas du produit : elle valait 895
	#  quoi qu'ait fait le hook. Mutation « -resize 1920x1080! » : VERT.
	#  2e : exiger une marge noire à gauche du produit. Mutation : VERT aussi —
	#  le portrait a lui-même un FOND NOIR, et la personne ne touche pas les
	#  bords. Étiré, il reste donc des colonnes noires ; la marge ne distingue
	#  pas « cadre ajouté » de « fond de l'image ».
	#  3e, celui-ci : la LARGEUR DU CONTENU VISIBLE, comparée à celle du même
	#  contenu simplement redimensionné. Étirer multiplie la première par
	#  1920/895 ≈ 2,15 sans toucher la seconde. Un contrôle qui ne peut pas
	#  tomber est pire que pas de contrôle : il rassure à tort.
	DL=$(( LARG_PROD > LARG_ATT ? LARG_PROD - LARG_ATT : LARG_ATT - LARG_PROD ))
	if [ "$LARG_PROD" -gt 0 ] && [ "$DL" -le 6 ]; then
		ok "le contenu garde ses proportions : ${LARG_PROD} px de large, comme le redimensionnement pur (${LARG_ATT})"
	else
		non "contenu de ${LARG_PROD} px contre ${LARG_ATT} attendus : le portrait a été étiré"
	fi
else
	saut "Pillow absent : le centrage du portrait n'est pas mesuré"
fi

# =============================================================================
titre "4. LA BANNIÈRE EST ROGNÉE EN HAUT, PAS AU CENTRE"
# =============================================================================
#  ═══ LE CONTRÔLE QUI DIT OÙ EST PARTI LE ROGNAGE ═══
#  1920 × 1280 -> 1920 × 1080 : 200 px doivent disparaître. Pris au centre
#  (100/100), ils mangeraient le buste en bas — mesuré : le contenu descend
#  jusqu'à la ligne 1278 sur 1280, le mot « Explore » du chandail touche le
#  bord. Pris en haut, on ne perd que le sommet des flammes.
#  On le prouve en comparant la DERNIÈRE ligne du produit à la dernière ligne
#  de la source : identiques = rien n'a été retiré en bas.
if python3 -c 'import PIL' 2>/dev/null && [ -r "$TILE" ]; then
	MESURE="$(python3 - "$TILE" "$BRANDING/fond-tilexal-banniere.jpg" <<'PY' 2>/dev/null
import sys
from PIL import Image, ImageChops, ImageStat
prod = Image.open(sys.argv[1]).convert("RGB")
src  = Image.open(sys.argv[2]).convert("RGB")
W, H = prod.size
w, h = src.size
def bande_bas(im, n=8):
    return im.crop((0, im.size[1] - n, im.size[0], im.size[1]))
bas = ImageStat.Stat(ImageChops.difference(bande_bas(prod), bande_bas(src))).mean[0]
def bande_haut(im, n=8):
    return im.crop((0, 0, im.size[0], n))
haut = ImageStat.Stat(ImageChops.difference(bande_haut(prod), bande_haut(src))).mean[0]
#  ═══ ON COMPARE LES BORDS AU SOURCE, PAS À DU NOIR ABSOLU ═══
#  Premier jet : « aucune colonne sombre sur les bords ». Rouge — et à tort.
#  Mesuré : la SOURCE elle-même a 24 px sombres de chaque côté (la pluie
#  Matrix s'y éteint). Exiger du contenu vif jusqu'au pixel 0 demandait au
#  hook de corriger l'image d'Alex, pas de la mettre au format. Ce qu'on
#  doit prouver, c'est que la largeur n'a pas été RÉDUITE : les bords du
#  produit sont ceux de la source.
def bords(im):
    w, h = im.size
    cols = [c for c in range(w)
            if any(sum(im.getpixel((c, y))) > 40 for y in range(0, h, 8))]
    return (cols[0], w - 1 - cols[-1]) if cols else (-1, -1)
pg, pd = bords(prod)
sg, sd = bords(src)
print("%.2f %.2f %d %d %d %d" % (bas, haut, pg, pd, sg, sd))
PY
)"
	set -- $MESURE
	BAS="${1:-99}"; HAUT="${2:-0}"; CG="${3:--1}"; CD="${4:--1}"
	SG="${5:--2}"; SD="${6:--2}"
	if awk "BEGIN{exit !($BAS < 6)}"; then
		ok "le bas est intact : écart $BAS/255 avec la source (le buste et « Explore » restent entiers)"
	else
		non "le bas a bougé (écart $BAS/255) : le rognage a mangé le buste"
	fi
	if awk "BEGIN{exit !($HAUT > 6)}"; then
		ok "le haut a bien changé : écart $HAUT/255 — les 200 px ont été pris là"
	else
		non "le haut est identique à la source (écart $HAUT/255) : rien n'a été rogné en haut"
	fi
	if [ "$CG" = "$SG" ] && [ "$CD" = "$SD" ]; then
		ok "la bannière garde toute sa largeur : mêmes bords que la source (${CG} px / ${CD} px, comme elle)"
	else
		non "bords ${CG}/${CD} contre ${SG}/${SD} au source : la bannière a été réduite au lieu d'être rognée"
	fi
else
	saut "Pillow absent : l'endroit du rognage n'est pas mesuré"
fi

# =============================================================================
titre "5. LES SOURCES NE PARTENT PAS DANS L'ISO"
# =============================================================================
#  Elles ne sont effacées QU'À leur chemin de production : sans cette garde,
#  lancer ce banc supprimerait les images du dépôt. On éprouve donc la garde,
#  pas l'effacement — et on vérifie que le dépôt est toujours là.
if grep -q '\[ "\$BRAND" = "/usr/share/lexos/branding" \]' "$HOOK"; then
	ok "l'effacement des sources est gardé par le chemin de production"
else
	non "l'effacement n'est pas gardé : un banc pourrait manger branding/"
fi
if [ -r "$BRANDING/fond-mascotte.jpg" ] && [ -r "$BRANDING/fond-tilexal-banniere.jpg" ]; then
	ok "…et les sources du dépôt ont survécu à ce banc"
else
	non "ce banc vient d'effacer les sources du dépôt"
fi
fi

# =============================================================================
titre "6. ILS APPARAISSENT DANS LES PARAMÈTRES"
# =============================================================================
#  ═══ LA LISTE EST CODÉE EN DUR — VÉRIFIÉ, PAS SUPPOSÉ ═══
#  La consigne demandait de regarder si la page ratisse le dossier. Elle ne
#  le fait pas : FONDS dans settings.py et les boutons dans app.js sont deux
#  listes écrites à la main. Un fond ajouté au hook et nulle part ailleurs
#  n'apparaîtrait donc JAMAIS dans les Paramètres. Ce contrôle est là pour
#  ça, et il tombera au prochain fond ajouté à moitié.
for CLE in mascotte tilexal; do
	if grep -q "\"$CLE\":" "$SETTINGS" && grep -q "setFond('$CLE')" "$APP"; then
		ok "« $CLE » est dans le moteur ET dans la page"
	else
		non "« $CLE » manque dans settings.py ou dans app.js : le fond serait invisible"
	fi
done
#  Le nom affiché doit être lisible, pas le nom du fichier.
if grep -q '>Mascotte<' "$APP" && grep -q '>TI-LEX-AL<' "$APP"; then
	ok "les boutons portent un nom lisible, pas « wallpaper-tilexal.jpg »"
else
	non "un bouton porte un nom de fichier au lieu d'un nom lisible"
fi
#  Le chemin nommé par le moteur doit être CELUI QUE LE HOOK ÉCRIT.
for PAIRE in "mascotte wallpaper-mascotte.jpg" "tilexal wallpaper-tilexal.jpg"; do
	set -- $PAIRE
	if grep -q "backgrounds/lexos/$2" "$SETTINGS" && grep -q "$2" "$HOOK"; then
		ok "« $1 » : le moteur et le hook nomment le même fichier ($2)"
	else
		non "« $1 » : le moteur et le hook ne parlent pas du même fichier"
	fi
done

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
