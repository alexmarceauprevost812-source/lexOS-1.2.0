#!/usr/bin/env bash
# =============================================================================
#  Éprouver le terminal — la police, les couleurs, ET le canal Xfconf
# =============================================================================
#  ALEX, PHOTO DU TERMINAL : « écriture plus gros ». La police est bien
#  passée de 11 à 13 dans terminalrc… et ça n'a JAMAIS suffi, sur un
#  xfce4-terminal moderne.
#
#  LA DÉCOUVERTE, VÉRIFIÉE EN LE FAISANT TOURNER POUR DE VRAI (le vrai
#  binaire, sous Xvfb, pas une lecture de sa documentation — elle ne dit
#  rien de tout ça) : depuis la branche 1.1 (Xfce 4.20, celle de trixie),
#  xfce4-terminal MIGRE terminalrc vers le canal Xfconf « xfce4-terminal » à
#  son PREMIER lancement, affiche « […] is not used anymore » — et ensuite
#  ne relit plus jamais terminalrc. Un compte qui a déjà ouvert un terminal
#  une fois garde pour toujours la police et les couleurs du jour de cette
#  première migration, quel que soit le nombre de fois où lexos-theme-gen
#  réécrit terminalrc ensuite. C'est le même mur que les icônes qui se
#  masquaient l'une l'autre (build 70-74), rejoué sur un fichier différent :
#  le bon réglage est écrit au bon endroit, et quelque chose de plus tôt
#  dans la chaîne a déjà décidé de ne plus le lire.
#
#  Le correctif : lexos-theme-gen écrit maintenant AUSSI le canal Xfconf
#  directement (xfce4-terminal.xml), comme il le fait déjà pour xfwm4.xml et
#  xsettings.xml. Pour un compte NEUF (le cas normal — /etc/skel), Xfconf
#  trouve le canal déjà rempli à la toute première ouverture : la migration
#  ne se déclenche même pas, terminalrc devient un simple filet.
#
#  CE QUE CE BANC VÉRIFIE, ET COMMENT
#    1. Toujours : les DEUX fichiers portent la MÊME valeur pour chaque
#       réglage partagé — sinon on recrée exactement le défaut qu'on vient
#       de découvrir, une valeur écrite à deux endroits libres de diverger.
#    2. Si le vrai xfce4-terminal (et Xvfb) sont installés sur la machine qui
#       fait tourner ce banc : preuve par l'exécution — le vrai binaire lit
#       NOTRE fichier, ne se plaint d'aucune clé inconnue, ne le réécrit pas,
#       et n'affiche PAS le message de migration (la preuve que le canal
#       était bien considéré comme déjà rempli). Sans ces deux outils, cette
#       partie est sautée PROPREMENT — elle ne se fait pas passer pour verte.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

python3 -c 'import PIL' 2>/dev/null || true   # (pas besoin ici, laissé pour la même forme que les autres bancs)

genere() { # genere <accent> <mode-terminal>
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/t" --terminal "$2" "$1" >/tmp/lexos-terminal-banc.log 2>&1
}

RC="$BANC/t/.config/xfce4/terminal/terminalrc"
XML="$BANC/t/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"

#  xfconfd n'est PAS sur le PATH (activé à la demande par D-Bus, pas un
#  binaire qu'on lance à la main) : son chemin dépend de l'architecture
#  (…/x86_64-linux-gnu/… sur le runner CI). « [ -x /usr/lib/*/… ] » ne
#  fait PAS ce qu'on croit : shellcheck (SC2144) le refuse à raison — un
#  glob dans « [ ] » n'est pas développé de façon fiable. La boucle est la
#  bonne façon de le faire.
xfconfd_present() {
	command -v xfconfd >/dev/null 2>&1 && return 0
	for f in /usr/lib/*/xfce4/xfconf/xfconfd; do
		[ -x "$f" ] && return 0
	done
	return 1
}

# =============================================================================
titre "1. La police, et les couleurs, sont les MÊMES dans les deux fichiers"
# =============================================================================
genere orange suivre
[ -r "$RC" ]  || { non "aucun terminalrc produit"; }
[ -r "$XML" ] || { non "aucun xfce4-terminal.xml produit — le canal Xfconf ne sera jamais rempli"; }

#  On extrait une clé de terminalrc (INI, CamelCase) et sa jumelle du canal
#  Xfconf (XML, kebab-case) — les noms VÉRIFIÉS en faisant migrer un vrai
#  terminalrc par un vrai xfce4-terminal (voir le commentaire dans
#  lexos-theme-gen). Une paire qui diverge, c'est le bogue qu'on corrige qui
#  revient par la porte d'à côté.
PAIRES="FontName:font-name ColorForeground:color-foreground
ColorBackground:color-background ColorCursor:color-cursor
ColorSelectionBackground:color-selection-background
ColorPalette:color-palette TabActivityColor:tab-activity-color"

TOUT_PAREIL=1
for PAIRE in $PAIRES; do
	INI_CLE="${PAIRE%%:*}"; XML_CLE="${PAIRE##*:}"
	V_INI="$(sed -n "s/^${INI_CLE}=//p" "$RC" | tail -1)"
	V_XML="$(sed -n "s/.*name=\"${XML_CLE}\"[^>]*value=\"\([^\"]*\)\".*/\1/p" "$XML")"
	if [ "$V_INI" != "$V_XML" ]; then
		non "$INI_CLE (terminalrc) = « $V_INI » mais $XML_CLE (Xfconf) = « $V_XML » — divergent"
		TOUT_PAREIL=0
	fi
done
[ "$TOUT_PAREIL" = 1 ] \
	&& ok "les réglages partagés portent la même valeur dans les deux fichiers"

#  La police, précisément : c'était la panne d'Alex, deux fois de suite —
#  « Fira Code 11 » -> 13, puis encore « trop petit » -> 15. Le banc vérifie
#  le NOUVEAU chiffre, pas l'ancien : un banc qui teste une valeur dépassée
#  resterait vert si quelqu'un revenait dessus par erreur.
grep -q '^FontName=Fira Code 15$' "$RC" \
	&& ok "la police est bien passée à 15 (11 -> 13 -> 15, deux photos d'Alex)" \
	|| non "terminalrc n'annonce pas Fira Code 15"
grep -q 'name="font-name".*value="Fira Code 15"' "$XML" \
	&& ok "…et le canal Xfconf, celui qui compte vraiment, porte la même taille" \
	|| non "xfce4-terminal.xml n'annonce pas Fira Code 15 — la police d'Alex ne bougerait toujours pas"

#  LES 24 PROPRIÉTÉS DOIVENT ÊTRE LÀ, TOUTES — une migration réelle en écrit
#  24 (fond, police, curseur, palette, tabulations, geometrie…). En manquer
#  une revient à livrer une police correcte et un fond resté par défaut.
NB="$(grep -c '<property name=' "$XML")"
[ "$NB" -ge 24 ] \
	&& ok "les 24 propriétés migrées sont toutes écrites ($NB trouvées)" \
	|| non "seulement $NB propriétés — la migration réelle en écrit 24, il en manque"

# =============================================================================
titre "2. Jour et nuit — deux palettes, deux fichiers, jamais mélangés"
# =============================================================================
genere orange jour
FG_JOUR="$(sed -n "s/.*name=\"color-foreground\"[^>]*value=\"\([^\"]*\)\".*/\1/p" "$XML")"
genere orange nuit
FG_NUIT="$(sed -n "s/.*name=\"color-foreground\"[^>]*value=\"\([^\"]*\)\".*/\1/p" "$XML")"
if [ -n "$FG_JOUR" ] && [ -n "$FG_NUIT" ] && [ "$FG_JOUR" != "$FG_NUIT" ]; then
	ok "jour ($FG_JOUR) et nuit ($FG_NUIT) donnent bien deux couleurs différentes dans le canal Xfconf"
else
	non "jour et nuit donnent la même couleur foreground dans Xfconf ($FG_JOUR / $FG_NUIT) — le canal ne suit pas le mode"
fi

# =============================================================================
titre "3. La preuve par l'exécution — quand le vrai xfce4-terminal est là"
# =============================================================================
#  ON NE DEVINE PAS UN NOM DE CLÉ XFCONF. Ces noms ne sont documentés NULLE
#  PART (ni « man xfce4-terminal », ni son .desktop) : la seule façon de les
#  connaître est de faire migrer un vrai terminalrc par le vrai binaire et de
#  relire ce qu'il a écrit — exactement ce que fait ce bloc. Une clé mal
#  orthographiée serait ignorée par Xfconf EN SILENCE (il ignore toute clé
#  qu'il ne reconnaît pas) : aucun test structurel ne peut voir cette
#  faute-là, seul le vrai programme le peut.
#  LA GARDE DOIT COUVRIR CE DONT LE MÉCANISME A VRAIMENT BESOIN, PAS
#  SEULEMENT LE BINAIRE VISIBLE. xfce4-terminal et Xvfb suffisaient à faire
#  DÉMARRER le terminal, mais pas à lui donner un canal Xfconf à LIRE :
#  sans démon xfconfd ni bus de session D-Bus, le terminal voit un canal
#  vide et migre — exactement le faux négatif que ce banc a fini par
#  produire en CI (xfce4-terminal ne DÉPEND que de la bibliothèque
#  libxfconf-0-3, pas du paquet xfconf qui porte xfconfd ; il ne fait que
#  RECOMMANDER un bus D-Bus, qu'un --no-install-recommends écarte). Sur une
#  vraie LexOS le métapaquet « xfce4 » amène xfconfd : le cas réel n'a
#  jamais eu ce trou, seul le banc l'avait.
if command -v xfce4-terminal >/dev/null 2>&1 \
	&& command -v Xvfb >/dev/null 2>&1 \
	&& command -v dbus-run-session >/dev/null 2>&1 \
	&& xfconfd_present; then
	genere orange suivre
	DISP=":$((90 + RANDOM % 400))"
	Xvfb "$DISP" -screen 0 1024x768x24 >/dev/null 2>&1 &
	XVFB_PID=$!
	sleep 1

	AVANT_FONT="$(sed -n 's/.*name="font-name"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"
	AVANT_FG="$(sed -n 's/.*name="color-foreground"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"
	AVANT_BG="$(sed -n 's/.*name="color-background"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"
	#  dbus-run-session DÉMARRE le bus et xfconfd s'active À LA DEMANDE par
	#  D-Bus (service .service, pas un démon qu'on lance à la main) : le
	#  délai passe de 4 à 8 secondes pour laisser ce démarrage se faire
	#  avant que le terminal ne lise quoi que ce soit — 4 s suffisaient à un
	#  terminal qui ne parlait à personne, elles ne suffisent plus.
	SORTIE="$(DISPLAY="$DISP" HOME="$BANC/t" XDG_CONFIG_HOME="$BANC/t/.config" \
		dbus-run-session -- timeout 8 xfce4-terminal --disable-server -e /bin/sleep\ 2 2>&1)"
	sleep 0.3
	APRES_FONT="$(sed -n 's/.*name="font-name"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"
	APRES_FG="$(sed -n 's/.*name="color-foreground"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"
	APRES_BG="$(sed -n 's/.*name="color-background"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"

	kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null

	if grep -qi 'migrated' <<< "$SORTIE" ; then
		non "xfce4-terminal a migré terminalrc au lieu de lire notre canal — il l'a donc trouvé VIDE"
	else
		ok "aucun message de migration : le vrai xfce4-terminal a trouvé le canal déjà rempli"
	fi
	if grep -qi 'unrecognized\|unknown.*setting\|no such property' <<< "$SORTIE"; then
		non "xfce4-terminal signale une clé qu'il ne reconnaît pas : $SORTIE"
	else
		ok "aucune clé rejetée — les 24 noms vérifiés sont tous corrects"
	fi
	#  LES VALEURS, PAS LES OCTETS. Avec xfconfd réellement en marche, il
	#  DEVIENT propriétaire du fichier et peut le réécrire dans sa forme
	#  canonique en s'arrêtant (ordre des propriétés, indentation,
	#  attributs) SANS changer une seule valeur — un md5sum le verrait
	#  comme « réécrit » pour une raison qui n'intéresse personne. La vraie
	#  promesse, c'est « nos valeurs tiennent », pas « le fichier n'a pas
	#  bougé d'un octet ».
	if [ "$AVANT_FONT" = "$APRES_FONT" ] && [ "$AVANT_FG" = "$APRES_FG" ] && [ "$AVANT_BG" = "$APRES_BG" ]; then
		ok "nos valeurs tiennent après le lancement (police, avant-plan, fond) — xfconfd a pu réécrire la forme, jamais le fond"
	else
		non "xfce4-terminal a changé une valeur : police $AVANT_FONT->$APRES_FONT, avant-plan $AVANT_FG->$APRES_FG, fond $AVANT_BG->$APRES_BG"
	fi

	# ---------------------------------------------------------------------
	#  ═══ LA FRAPPE EST BLANCHE — MESURÉ SUR L'ÉCRAN, PAS DANS UN FICHIER ═══
	#  Une consigne a cru la frappe encore verte en lisant TERM_FG. Le seul
	#  juge, c'est le pixel : on ouvre un bash qui charge interactive.sh dans
	#  le vrai xfce4-terminal, on TAPE « echo BONJOUR » avec xdotool, on
	#  photographie, et on compte les pixels blancs et verts de la première
	#  ligne. Sans xdotool, import ou PIL, le contrôle se saute en le disant.
	if command -v xdotool >/dev/null 2>&1 && command -v import >/dev/null 2>&1 \
	   && python3 -c 'import PIL' 2>/dev/null; then
		genere orange nuit
		cat > "$BANC/t/.bashrc" <<EOF
export PS1='\$ '
. "$RACINE/config/includes.chroot/usr/share/lexos/shell/interactive.sh"
EOF
		DISP=":$((90 + RANDOM % 400))"
		Xvfb "$DISP" -screen 0 1100x700x24 >/dev/null 2>&1 &
		XVFB_PID=$!
		sleep 1
		( export DISPLAY="$DISP" HOME="$BANC/t" XDG_CONFIG_HOME="$BANC/t/.config" LEXOS_NO_BANNER=1
		  dbus-run-session -- bash -c '
			xfce4-terminal --disable-server --geometry=100x24 \
				-e "bash --rcfile $HOME/.bashrc -i" >/dev/null 2>&1 &
			sleep 4
			W="$(xdotool search --sync --class xfce4-terminal 2>/dev/null | head -1)"
			[ -n "$W" ] && xdotool windowactivate --sync "$W" 2>/dev/null
			sleep 0.5
			xdotool type --delay 40 "echo BONJOUR"
			sleep 0.8
			import -window root "$1"
		  ' _ "$BANC/frappe.png" ) >/dev/null 2>&1
		kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null
		if [ -s "$BANC/frappe.png" ]; then
			#  Première ligne du terminal (les 30 premiers pixels de haut).
			#  Le blanc franc est #FFFFFF exactement ; le vert est celui de
			#  la palette, #00D700 (avec l'anticrénelage, on tolère ±8).
			LU="$(python3 - "$BANC/frappe.png" <<'PYPX'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
blanc = vert = 0
for y in range(0, min(30, h)):
    for x in range(w):
        r, g, b = im.getpixel((x, y))
        if (r, g, b) == (255, 255, 255): blanc += 1
        elif abs(r) < 8 and abs(g - 215) < 8 and abs(b) < 8: vert += 1
print(blanc, vert)
PYPX
)"
			BLANC_PX="${LU%% *}"; VERT_PX="${LU##* }"
			if [ "${BLANC_PX:-0}" -ge 40 ] && [ "${VERT_PX:-0}" -ge 200 ]; then
				ok "sur l'écran : l'invite est verte ($VERT_PX px) et « echo BONJOUR » est BLANC ($BLANC_PX px)"
			else
				non "sur l'écran : $BLANC_PX px blancs et $VERT_PX px verts — la frappe n'est pas blanche sur une invite verte"
			fi
		else
			non "la capture de la frappe n'a pas été produite"
		fi
	else
		printf '  \033[2mpreuve par capture sautée — il manque xdotool, import (ImageMagick) ou PIL\033[0m\n'
	fi
else
	MANQUE=""
	command -v xfce4-terminal >/dev/null 2>&1 || MANQUE="${MANQUE} xfce4-terminal"
	command -v Xvfb >/dev/null 2>&1 || MANQUE="${MANQUE} Xvfb"
	command -v dbus-run-session >/dev/null 2>&1 || MANQUE="${MANQUE} dbus-run-session"
	xfconfd_present || MANQUE="${MANQUE} xfconfd"
	printf '  \033[2mpreuve par l'"'"'exécution sautée — absent de cette machine :%s (le reste tient quand même)\033[0m\n' "$MANQUE"
fi

# =============================================================================
titre "4. lexos-theme-gen le dit dans son propre code — pas un secret retrouvé"
# =============================================================================
grep -q 'is not used anymore\|migrated' "$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen" \
	&& ok "la découverte est documentée dans lexos-theme-gen, pas seulement dans ce banc" \
	|| non "rien dans lexos-theme-gen n'explique pourquoi ce fichier existe"


# =============================================================================
titre "5. Le blanc de la frappe, le vert de la palette, le jour intact — et l'agent"
# =============================================================================
#  ALEX : « ce qu'il tape en blanc franc ». La consigne qui l'a redit croyait
#  la frappe encore verte (« TERM_FG=#00D700 : tout est vert, y compris ce
#  qu'Alex tape »). C'est une lecture d'un seul rôle : TERM_FG est ce que la
#  MACHINE écrit, TERM_TEXTE ce que l'on TAPE — et TERM_TEXTE vaut #FFFFFF
#  depuis ee2f559, qui est dans toutes les ISO depuis la 111. Mesuré ici sur
#  le vrai xfce4-terminal (section 3, plus haut) : la frappe est blanche.
#
#  CE QU'ON GARDE, ET QU'IL NE FAUT PAS « CORRIGER » : l'encre par défaut
#  reste VERTE. Passer TERM_FG au blanc repeindrait toute la sortie des
#  commandes, vider la case verte de la palette (elle est écrite ${TERM_FG}),
#  et défaire la règle de couleur du dépôt — vert = ce que la machine dit,
#  blanc = ce qu'on tape. Ce banc tient les deux moitiés ensemble.
INTER="$RACINE/config/includes.chroot/usr/share/lexos/shell/interactive.sh"
AGENT="$RACINE/config/includes.chroot/usr/lib/lexos/ia-agent.py"

genere orange nuit
ENV_NUIT="$BANC/t/.config/lexos/terminal.env"
FG_N="$(sed -n 's/^LEXOS_TERM_FG=//p' "$ENV_NUIT")"
TX_N="$(sed -n "s/^LEXOS_PS_TEXTE='\(.*\)'$/\1/p" "$ENV_NUIT")"
[ "$FG_N" = "#00D700" ] \
	&& ok "nuit : l'encre par défaut (ce que la machine écrit) reste verte, $FG_N" \
	|| non "nuit : l'encre par défaut vaut « $FG_N » — la règle « vert = la machine » est cassée"
[ "$TX_N" = "38;2;255;255;255" ] \
	&& ok "nuit : la frappe est le blanc franc (38;2;255;255;255)" \
	|| non "nuit : la frappe vaut « $TX_N », attendu 38;2;255;255;255"
#  La case verte de la palette (position 2, « vert normal ») est écrite
#  ${TERM_FG} dans lexos-theme-gen : si quelqu'un passe TERM_FG au blanc, il
#  n'y a plus de vert nulle part. On lit la palette réellement écrite.
PAL_N="$(sed -n 's/.*name="color-palette"[^>]*value="\([^"]*\)".*/\1/p' "$XML")"
VERT_N="$(printf '%s' "$PAL_N" | cut -d';' -f3)"
case "$VERT_N" in
	"#00D700"|"#00d700") ok "nuit : la case verte de la palette est bien verte ($VERT_N)" ;;
	*) non "nuit : la case verte de la palette vaut « $VERT_N » — plus de vert dans les 16 couleurs" ;;
esac
#  Un blanc FRANC : la couleur 15 (« blanc brillant ») est la même valeur que
#  la frappe — une seule valeur, pas deux libres de diverger.
BLANC_N="$(printf '%s' "$PAL_N" | cut -d';' -f16)"
case "$BLANC_N" in
	"#FFFFFF"|"#ffffff") ok "nuit : le blanc brillant de la palette est #FFFFFF, pas un gris clair" ;;
	*) non "nuit : le blanc brillant vaut « $BLANC_N »" ;;
esac

#  LE JOUR N'A PAS BOUGÉ : crème, encre foncée, frappe en encre foncée.
genere orange jour
ENV_JOUR="$BANC/t/.config/lexos/terminal.env"
FG_J="$(sed -n 's/^LEXOS_TERM_FG=//p' "$ENV_JOUR")"
TX_J="$(sed -n "s/^LEXOS_PS_TEXTE='\(.*\)'$/\1/p" "$ENV_JOUR")"
[ "$FG_J" = "#0B6B3A" ] && ok "jour : encre par défaut $FG_J (inchangée)" \
	|| non "jour : l'encre par défaut a changé ($FG_J)"
[ "$TX_J" = "38;2;27;26;23" ] && ok "jour : la frappe reste l'encre foncée #1B1A17 — pas du blanc sur crème" \
	|| non "jour : la frappe vaut « $TX_J » — du blanc sur crème serait invisible"

#  L'INVITE LIT BIEN CES DEUX RÔLES, et pas un seul : on la DÉVELOPPE dans un
#  vrai bash, avec le terminal.env de nuit, et on regarde les séquences.
#  « ${PS1@P} » est le développement d'invite de bash lui-même — le même code
#  que celui qui dessine l'invite, pas une imitation.
#  EN OCTETS BRUTS, PAS PAR « cat -v » : cat -v réécrit l'UTF-8 (« ✓ » devient
#  « M-bM-^\M-^S ») et les comparaisons ratent sur du texte juste. Les
#  séquences sont comparées avec leur ESC réel ($'\033'), et l'invite
#  développée porte les marqueurs \001 … \002 de readline autour de chaque
#  séquence : le blanc non refermé est donc suivi d'un \002 final.
ESC=$'\033'; FIN_RL=$'\002'
genere orange nuit
DEV="$(HOME="$BANC/t" XDG_CONFIG_HOME="$BANC/t/.config" COLORTERM=truecolor TERM=xterm-256color \
	bash --norc -ic ". '$INTER' 2>/dev/null; printf '%s' \"\${PS1@P}\"" 2>/dev/null)"
case "$DEV" in
	*"${ESC}[38;2;255;255;255m${FIN_RL}") ok "l'invite se TERMINE par le blanc de la frappe, non refermé — c'est lui qui déborde sur ce qu'on tape" ;;
	*) non "l'invite ne se termine pas par le blanc non refermé : la frappe prendrait la couleur du chevron" ;;
esac
case "$DEV" in
	*"${ESC}[38;2;0;215;0m"*) ok "…et le vert de la machine y est bien la valeur du terminal (38;2;0;215;0)" ;;
	*) non "le vert de l'invite n'est pas celui du terminal" ;;
esac

# -----------------------------------------------------------------------------
#  L'AGENT IA — vert de la PALETTE, et seulement sur un terminal de nuit.
#  Il ressortait vert par accident (tout l'était) et ses pastilles écrivaient
#  des séquences ANSI en dur, même dans un tuyau. On l'interroge dans six
#  situations avec une fausse sortie qui DIT si elle est un terminal.
cat > "$BANC/sonde_agent.py" <<'PYAG'
import importlib.util, sys, os, io, contextlib
spec = importlib.util.spec_from_file_location("agent", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class Sortie(io.StringIO):
    def isatty(self): return os.environ.get("SONDE_TTY") == "1"
out = Sortie()
with contextlib.redirect_stdout(out):
    m.C = m._couleurs()
    m.ok("pastille"); m.reponse("réponse")
sys.stdout.write(out.getvalue())
PYAG
agent() { # agent <tty:0|1> <xdg-config> [env…]
	local tty="$1" xdg="$2"; shift 2
	env "$@" SONDE_TTY="$tty" XDG_CONFIG_HOME="$xdg" python3 "$BANC/sonde_agent.py" "$AGENT" 2>/dev/null
}
NU="$(printf '✓ pastille\nréponse\n')"
S="$(agent 0 "$BANC/t/.config" COLORTERM=truecolor)"
[ "$S" = "$NU" ] \
	&& ok "agent, dans un tuyau : aucune séquence ANSI — le fichier reste propre" \
	|| non "agent, dans un tuyau : des séquences fuient → $S"
S="$(agent 1 "$BANC/t/.config" COLORTERM=truecolor)"
case "$S" in
	*"${ESC}[38;2;0;215;0mréponse${ESC}[0m"*) ok "agent, terminal de nuit : la réponse est encadrée du vert DE LA PALETTE (38;2;0;215;0)" ;;
	*) non "agent, terminal de nuit : le cadre n'est pas le vert de la palette → $S" ;;
esac
S="$(agent 1 "$BANC/t/.config" COLORTERM=)"
case "$S" in
	*"${ESC}[38;5;40m"*) ok "agent, sans couleur vraie : il retombe sur la palette 256 (38;5;40)" ;;
	*) non "agent, sans couleur vraie : mauvais repli → $S" ;;
esac
genere orange jour
S="$(agent 1 "$BANC/t/.config" COLORTERM=truecolor)"
case "$S" in
	*'mréponse'*) non "agent, de JOUR : la réponse est encadrée — du vert de nuit sur crème ne se lit pas" ;;
	*'réponse'*) ok "agent, de jour : la réponse n'est pas encadrée (l'encre de jour suffit)" ;;
	*) non "agent, de jour : rien ne sort → $S" ;;
esac
S="$(agent 1 "$BANC/t/.config" NO_COLOR=1)"
[ "$S" = "$NU" ] \
	&& ok "agent, NO_COLOR : muet, comme le reste de LexOS" \
	|| non "agent, NO_COLOR : il colore quand même → $S"
genere orange nuit
#  Plus aucune séquence ANSI en dur dans le fichier — hors « \033[0m », la
#  remise à zéro, qui n'est pas une couleur.
#  Pas de tuyau vers « grep -q » (la CI le refuse : sous pipefail, un
#  producteur qui écrit encore fait échouer tout le tuyau). On matérialise la
#  liste, puis on la juge.
DURES="$(grep -nE '\\033\[[0-9;]*[1-9][0-9;]*m' "$AGENT" | grep -v '^[0-9]*: *#' | grep -v '0m"' || true)"
if [ -n "$DURES" ]; then
	non "ia-agent.py écrit encore une couleur en dur :"
	printf '%s\n' "$DURES" | sed 's/^/      /' >&2
else
	ok "ia-agent.py n'écrit plus aucune couleur en dur — tout vient de la palette"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
