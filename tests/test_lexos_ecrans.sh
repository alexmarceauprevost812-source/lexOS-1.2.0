#!/usr/bin/env bash
# =============================================================================
#  Éprouver les écrans : xrandr garanti, la section qui explique, un seul écran
# =============================================================================
#  TROIS CHOSES, TIRÉES DU DOSSIER « plusieurs écrans et partage d'écran ».
#
#  1. xrandr était posé « au mieux ». SIX chemins en dépendaient, et le pire
#     des six affichait la section Écrans des Paramètres VIDE, sans un mot —
#     l'air de dire « tu n'as aucun écran » sur une machine à quatre écrans
#     allumés. Le paquet passe en obligatoire, ET le code apprend à dire
#     pourquoi la liste est vide : promouvoir règle aujourd'hui, parler règle
#     tous les jours d'après.
#
#  2. « lexos distant partager » envoyait TOUT le bureau combiné. Avec trois
#     dalles côte à côte, une seule image de 5760x1080 : illisible en face, et
#     on montre des écrans qu'on ne voulait pas montrer. « --ecran » choisit.
#
#  3. L'aide de « lexos » documentait « distant partager on » — une commande
#     qui MOURAIT. Vérifié en la lançant avant correction.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISTANT="$RACINE/config/includes.chroot/usr/bin/lexos-distant"
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. Les paquets dont dépend ce qui se VOIT sont obligatoires"
# =============================================================================
STRICT="$RACINE/flavours/standard/desktop.list.chroot"
OPT="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages"
for P in x11-xserver-utils pulseaudio-utils bluez; do
	grep -qxF "$P" "$STRICT" \
		&& ok "$P est obligatoire (son absence ARRÊTE la construction)" \
		|| non "$P n'est plus obligatoire — il pourrait manquer en silence"
	#  Et nulle part ailleurs : deux régimes pour un paquet, c'est deux
	#  promesses contradictoires et personne ne sait laquelle fait foi.
	if grep -rqxF "$P" "$OPT"/*.list 2>/dev/null; then
		non "$P est AUSSI en liste optionnelle — deux vérités pour un paquet"
	else
		ok "$P n'est plus en double dans les listes optionnelles"
	fi
done
#  Ceux qui restent optionnels À RAISON : lexos-display dégrade proprement
#  quand ils manquent (il le dit et propose de les installer).
for P in arandr autorandr; do
	grep -qxF "$P" "$STRICT" \
		&& non "$P est devenu obligatoire alors que son absence est déjà bien gérée" \
		|| ok "$P reste optionnel — « lexos ecran » sait le dire quand il manque"
done

# =============================================================================
titre "2. La section Écrans dit POURQUOI elle est vide"
# =============================================================================
#  On appelle la vraie fonction du pont, dans trois environnements. Sans ça on
#  ne saurait que ce que le code a l'air de faire.
#  ═══ « SANS xrandr » SE FABRIQUE, IL NE SE SUBIT PAS ═══
#  Ce PATH se terminait par « /usr/bin:/bin ». Le cas « sans-xrandr » ne
#  tenait donc que tant que la machine n'avait pas x11-xserver-utils — et
#  installer mpv suffit à l'amener en dépendance. Mesuré : le banc rougissait
#  alors pour une raison qui ne regarde pas le dépôt. On fabrique l'absence
#  avec un PATH de liens symboliques d'où « xrandr » est retiré, comme le
#  dépôt le fait déjà pour convert, ffmpeg, mpv et lightdm.
SANS_XR="$BANC/sans-xrandr"
rm -rf "$SANS_XR"; mkdir -p "$SANS_XR"
for d in /usr/bin /bin /usr/sbin /sbin; do
	[ -d "$d" ] || continue
	for f in "$d"/*; do
		b="$(basename "$f")"
		case "$b" in xrandr) continue ;; esac
		[ -e "$SANS_XR/$b" ] || ln -s "$f" "$SANS_XR/$b" 2>/dev/null
	done
done

sonde() { # sonde <XDG_SESSION_TYPE> <DISPLAY> <avec-xrandr|sans-xrandr>
	rm -rf "${BANC:?}/bin"; mkdir -p "$BANC/bin"
	if [ "$3" = "avec-xrandr" ]; then
		printf '#!/bin/sh\nexit 0\n' > "$BANC/bin/xrandr"; chmod +x "$BANC/bin/xrandr"
	fi
	PATH="$BANC/bin:$SANS_XR" XDG_SESSION_TYPE="$1" DISPLAY="$2" \
	python3 - "$SETTINGS" <<'PY'
import sys, importlib.util, os
spec = importlib.util.spec_from_file_location("s", sys.argv[1])
m = importlib.util.module_from_spec(spec)
#  On ne lance PAS le serveur : on charge le module pour ses fonctions. Le
#  fichier ne démarre son serveur que sous « if __name__ == "__main__" ».
spec.loader.exec_module(m)
print(m._ecrans_probleme())
PY
}

R="$(sonde wayland :0 avec-xrandr 2>/dev/null)"
case "$R" in
	*Wayland*) ok "session Wayland : la cause EXACTE est nommée" ;;
	*) non "Wayland : « $R »" ;;
esac
R="$(sonde x11 :0 sans-xrandr 2>/dev/null)"
case "$R" in
	*x11-xserver-utils*) ok "xrandr absent : le PAQUET à installer est nommé" ;;
	*) non "xrandr absent : « $R »" ;;
esac
R="$(sonde x11 '' avec-xrandr 2>/dev/null)"
case "$R" in
	*DISPLAY*) ok "pas de session graphique : dit, au lieu d'une liste vide" ;;
	*) non "sans DISPLAY : « $R »" ;;
esac
R="$(sonde x11 :0 avec-xrandr 2>/dev/null)"
[ -z "$R" ] \
	&& ok "tout va bien : rien à dire, et on ne dit rien" \
	|| non "un problème est annoncé alors que tout va bien : « $R »"

#  La page doit RECOPIER ce message, pas en inventer un à elle.
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
grep -q 'etat.ecrans_probleme' "$APP" \
	&& ok "la page affiche la cause donnée par le pont" \
	|| non "la page n'affiche pas ecrans_probleme — elle redevient muette"
grep -q 'xrandr absent ou session Wayland' "$APP" \
	&& non "l'ancien message qui mettait les deux causes dans le même sac est resté" \
	|| ok "l'ancien message fourre-tout a disparu"

# =============================================================================
titre "3. Ne partager QU'UN écran"
# =============================================================================
#  Un faux xrandr qui énumère trois écrans dont un BRANCHÉ MAIS ÉTEINT : c'est
#  le cas qui décale les index si on ne filtre pas sur la géométrie active.
faux_xrandr() { # faux_xrandr <oui|non>
	rm -rf "${BANC:?}/bin2"; mkdir -p "$BANC/bin2"
	[ "$1" = "non" ] && return 0
	cat > "$BANC/bin2/xrandr" <<'XR'
#!/bin/sh
cat <<'FIN'
Screen 0: minimum 8 x 8, current 5760 x 1080, maximum 32767 x 32767
DP-0 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
HDMI-0 connected 1920x1080+1920+0 (normal left inverted right x axis y axis) 700mm x 390mm
DP-4 connected (normal left inverted right x axis y axis) 520mm x 320mm
DP-2 connected 1920x1080+3840+0 (normal left inverted right x axis y axis) 600mm x 340mm
DVI-D-0 disconnected (normal left inverted right x axis y axis)
FIN
XR
	chmod +x "$BANC/bin2/xrandr"
}

clip() { # clip <argument>  → la valeur de -clip sur stdout
	PATH="$BANC/bin2:/usr/bin:/bin" \
	bash -c ". '$DISTANT' >/dev/null 2>&1 || true; clip_ecran '$1'" 2>/dev/null
}
messages() { # messages <argument>  → ce qui est dit à l'humain
	PATH="$BANC/bin2:/usr/bin:/bin" \
	bash -c ". '$DISTANT' >/dev/null 2>&1 || true; clip_ecran '$1'" 2>&1 >/dev/null
}

faux_xrandr oui
[ "$(clip DP-0)" = "xinerama0" ] \
	&& ok "DP-0 → xinerama0 (le premier écran actif)" || non "DP-0 → « $(clip DP-0) »"
[ "$(clip HDMI-0)" = "xinerama1" ] \
	&& ok "HDMI-0 → xinerama1" || non "HDMI-0 → « $(clip HDMI-0) »"
#  LE CAS QUI COMPTE : DP-4 est branché mais ÉTEINT, il ne compte pas pour
#  xinerama. Sans le filtre sur la géométrie, DP-2 vaudrait 3 au lieu de 2 et
#  on partagerait le mauvais écran — en croyant avoir choisi le bon.
[ "$(clip DP-2)" = "xinerama2" ] \
	&& ok "un écran branché mais ÉTEINT ne décale pas les index (DP-2 → 2)" \
	|| non "DP-2 → « $(clip DP-2) » : l'écran éteint a décalé le compte"
[ "$(clip 1)" = "xinerama1" ] \
	&& ok "un numéro passe tel quel" || non "« 1 » → « $(clip 1) »"
[ -z "$(clip '')" ] \
	&& ok "sans --ecran, aucun -clip : on partage tout, comme avant" \
	|| non "un -clip est posé sans qu'on l'ait demandé"
grep -q '3 ÉCRANS' < <(messages '') \
	&& ok "mais on PRÉVIENT qu'on montre les trois écrans d'un coup" \
	|| non "trois écrans partagés sans un mot"
grep -q -- '--ecran' < <(messages '') \
	&& ok "et on dit comment n'en montrer qu'un" || non "l'avertissement ne dit pas quoi faire"

#  Une sortie inconnue doit ARRÊTER, pas partager tout par défaut : partager
#  quatre écrans quand on en a demandé un est le contraire de la demande.
if PATH="$BANC/bin2:/usr/bin:/bin" bash -c ". '$DISTANT' >/dev/null 2>&1 || true; clip_ecran 'NEXISTEPAS'" >/dev/null 2>&1; then
	non "une sortie inconnue est acceptée — on partagerait tout sans le dire"
else
	ok "une sortie inconnue arrête net (« voir lexos ecran »)"
fi

faux_xrandr non
if PATH="$BANC/bin2:/usr/bin:/bin" bash -c ". '$DISTANT' >/dev/null 2>&1 || true; clip_ecran 'DP-2'" >/dev/null 2>&1; then
	non "sans xrandr, un nom de sortie est accepté — le -clip serait faux"
else
	ok "sans xrandr, un NOM est refusé en nommant le paquet manquant"
fi
[ "$(clip 0)" = "xinerama0" ] \
	&& ok "sans xrandr, la forme NUMÉRIQUE marche encore (c'est le repli annoncé)" \
	|| non "sans xrandr, même un numéro ne passe plus"

# =============================================================================
titre "4. L'aide décrit des commandes qui existent"
# =============================================================================
faux_xrandr oui
#  ON CAPTURE AVANT DE FILTRER. Avec « pipefail », le code de retour d'un
#  tube est celui du DERNIER échec, pas celui du dernier maillon : la commande
#  meurt exprès (code 1), et le tube aurait donc été rouge même quand grep
#  trouve ce qu'il cherche. Le banc se serait accusé lui-même.
SORTIE="$("$DISTANT" partager --ecran 2>&1 || true)"
case "$SORTIE" in
	*"attend un nom"*) ok "« --ecran » sans valeur le dit au lieu de partager tout" ;;
	*) non "« --ecran » sans valeur passe inaperçu : « $SORTIE »" ;;
esac
SORTIE="$("$DISTANT" 2>&1 || true)"
case "$SORTIE" in
	*--ecran*) ok "l'aide de lexos-distant mentionne --ecran" ;;
	*) non "une option qu'aucune aide ne mentionne n'existe pas pour l'utilisateur" ;;
esac
grep -q -- 'distant partager --ecran' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "l'aide de « lexos » aussi" || non "« lexos » ne mentionne pas --ecran"
grep -q 'distant partager on' "$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& non "« lexos » documente encore « partager on », une commande qui MEURT" \
	|| ok "« partager on » — documenté et inexistant — a disparu de l'aide"

#  Le dispatcher doit transmettre TOUS les arguments : avec « ${1:-} »,
#  « partager once --ecran DP-2 » perdrait l'option en silence.
grep -q 'cmd_partager "\$@"' "$DISTANT" \
	&& ok "le dispatcher transmet tous les arguments" \
	|| non "le dispatcher n'en transmet qu'un — --ecran disparaîtrait en silence"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
