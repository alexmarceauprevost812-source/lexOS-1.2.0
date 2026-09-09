#!/usr/bin/env bash
# =============================================================================
#  Éprouver la sélection du rétroéclairage — lexos-brightness ET settings.py
# =============================================================================
#  ALEX, photo à l'appui : « dans les paramètres, la luminosité de l'écran
#  ne marche pas ».
#
#  CE QUI SE PASSAIT VRAIMENT. Beaucoup de portables (les ThinkPad d'Alex
#  compris) exposent DEUX interfaces à la fois sous /sys/class/backlight/ :
#  « acpi_videoN » (le firmware ACPI) et une interface native du pilote
#  graphique (« intel_backlight », « amdgpu_bl0»…). Le code choisissait la
#  première par ordre ALPHABÉTIQUE — « acpi_video0 » précède
#  « intel_backlight » — et c'est justement celle qui, sur beaucoup de
#  machines, accepte l'écriture SANS ERREUR sans rien piloter de visible :
#  le curseur bouge, le fichier « brightness » change de valeur, l'écran ne
#  bouge pas d'un cran. Un réglage qui « marche » sans rien faire ne se voit
#  nulle part dans le code, seulement sur la photo.
#
#  DEUX ENDROITS ÉCRIVENT/LISENT CETTE MÊME DÉCISION, ET ILS DOIVENT
#  S'ACCORDER : lexos-brightness (le curseur RÈGLE) et settings.py /
#  _lumiere_etat() (le panneau AFFICHE). S'ils ne préfèrent pas la même
#  interface, la barre affichée peut ne jamais correspondre à ce que le
#  curseur vient de régler — deux vérités pour un seul réglage.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-brightness"
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-brightness introuvable ou non exécutable"; exit 1; }

# --- Fabrique un faux /sys/class/backlight/<nom> ----------------------------
faux_bl() { # faux_bl <nom> <brightness> <max_brightness> [inscriptible:0|1]
	local nom="$1" cur="$2" max="$3" inscriptible="${4:-1}"
	local d="$BANC/bl/$nom"
	mkdir -p "$d"
	printf '%s\n' "$cur" > "$d/brightness"
	printf '%s\n' "$max" > "$d/max_brightness"
	[ "$inscriptible" = "1" ] && chmod u+w "$d/brightness" || chmod u-w "$d/brightness"
}

vide_bl() { rm -rf "${BANC:?}/bl"; mkdir -p "$BANC/bl"; }

lit_python() { # lit_python -> la luminosité rendue par _lumiere_etat()
	LEXOS_BL="$BANC/bl" python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('s', '$SETTINGS')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m._lumiere_etat())
"
}

# =============================================================================
titre "1. acpi_video ET une interface native -> la native gagne, PAS l'ordre alphabétique"
# =============================================================================
vide_bl
faux_bl "acpi_video0"     80 100
faux_bl "intel_backlight" 40 100

SORTIE="$(LEXOS_BL="$BANC/bl" "$OUTIL" 2>&1)"
case "$SORTIE" in
	*"Luminosité : 40%"*) ok "lexos-brightness lit intel_backlight (40 %), pas acpi_video0 (80 %)" ;;
	*"Luminosité : 80%"*) non "l'ordre alphabétique a gagné — acpi_video0 lu au lieu de l'interface native" ;;
	*) non "sortie inattendue : $SORTIE" ;;
esac

V="$(lit_python)"
[ "$V" = "40" ] \
	&& ok "settings.py (_lumiere_etat) est D'ACCORD : 40 %, la même interface" \
	|| non "settings.py a lu $V — désaccord avec lexos-brightness"

# --- On règle avec l'outil, on relit avec l'AUTRE : ils doivent s'entendre --
LEXOS_BL="$BANC/bl" "$OUTIL" 65 >/dev/null 2>&1
V="$(lit_python)"
[ "$V" = "65" ] \
	&& ok "un réglage par lexos-brightness (65 %) est immédiatement vu par settings.py" \
	|| non "après réglage à 65 %, settings.py voit $V — la barre mentirait sur ce que le curseur vient de faire"

# =============================================================================
titre "2. Seul acpi_video existe -> il devient le repli, pas un échec"
# =============================================================================
#  Sur une machine plus ancienne (ou une VM), acpi_video peut être la SEULE
#  interface. Refuser de l'utiliser laisserait la luminosité totalement
#  hors d'atteinte — pire que la préférer par erreur.
vide_bl
faux_bl "acpi_video0" 55 100

SORTIE="$(LEXOS_BL="$BANC/bl" "$OUTIL" 2>&1)"
case "$SORTIE" in
	*"Luminosité : 55%"*) ok "seul acpi_video0 présent -> il est quand même utilisé (mieux que rien)" ;;
	*) non "acpi_video0 aurait dû servir de repli : $SORTIE" ;;
esac

V="$(lit_python)"
[ "$V" = "55" ] \
	&& ok "settings.py fait le même repli — même lecture (55 %)" \
	|| non "settings.py a lu $V au lieu de 55 en repli"

# =============================================================================
titre "3. Deux interfaces natives, aucune acpi_video -> la première par ordre suffit"
# =============================================================================
vide_bl
faux_bl "amdgpu_bl0"      20 100
faux_bl "nvidia_backlight" 90 100

SORTIE="$(LEXOS_BL="$BANC/bl" "$OUTIL" 2>&1)"
case "$SORTIE" in
	*"Luminosité : 20%"*|*"Luminosité : 90%"*)
		ok "sans acpi_video, une interface native est choisie sans hésiter (pas de blocage)" ;;
	*) non "aucune interface native choisie : $SORTIE" ;;
esac

# =============================================================================
titre "4. Aucune interface du tout -> ça le dit, ça n'invente rien"
# =============================================================================
vide_bl
#  ═══ « AUCUNE INTERFACE » VEUT DIRE AUCUNE, xrandr COMPRIS ═══
#  Vider LEXOS_BL ne suffit pas : lexos-brightness a un TROISIÈME recours,
#  « xrandr --brightness », qu'il retient dès qu'un DISPLAY existe. Sur une
#  machine sans écran — le coureur de la CI — le contrôle passait ; lancé
#  sous xvfb-run, ou simplement sur un vrai bureau, il rougissait en lisant
#  « Luminosité : 0% ». Le banc dépendait de sa machine hôte sans le dire.
#  On retire donc DISPLAY pour ce contrôle-ci, et lui seul : c'est la
#  situation qu'il prétend décrire.
SORTIE="$(env -u DISPLAY LEXOS_BL="$BANC/bl" "$OUTIL" 2>&1)"
grep -qi "aucun moyen" <<< "$SORTIE" \
	&& ok "sans aucune interface, lexos-brightness le dit clairement" \
	|| non "sortie inattendue sans interface : $SORTIE"

V="$(lit_python)"
[ "$V" = "-1" ] \
	&& ok "settings.py rend -1 (« pas de rétroéclairage pilotable »), pas une valeur inventée" \
	|| non "settings.py a rendu « $V » au lieu de -1 sans interface"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
