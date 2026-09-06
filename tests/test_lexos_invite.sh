#!/usr/bin/env bash
# =============================================================================
#  Éprouver l'INVITE du terminal — sa forme et ses couleurs
# =============================================================================
#  ALEX, PHOTO DU TERMINAL, DEUX REMARQUES DANS LA MÊME MINUTE :
#
#    1. « l'écriture, la ligne est pas complète et a déjà une espace — faire
#       en sorte que ça suive ---> ». L'invite tenait sur DEUX lignes :
#
#           lex@lexos ~
#           ❯
#
#       parce que PS1 portait un saut de ligne juste avant le chevron.
#
#    2. « écriture blanc pour écriture de utilisateur, vert pour lexos ».
#       Le chemin et le chevron étaient ORANGE, et la frappe héritait de cet
#       orange (PS1 se termine par une couleur qu'on ne referme pas).
#
#  POURQUOI CE BANC EXISTE, ALORS QUE LE TERMINAL EN AVAIT DÉJÀ UN.
#  test_lexos_terminal.sh éprouve le terminalrc et le canal Xfconf — le
#  fond, la police, les seize couleurs. Il ne touche PAS à PS1 : on a
#  cherché, aucun banc de ce dépôt ne lisait interactive.sh. L'invite était
#  la seule pièce visible à chaque seconde d'utilisation à n'avoir aucun
#  filet. Les deux défauts ci-dessus ont donc pu tenir sans que rien ne
#  proteste.
#
#  COMMENT ON L'ÉPROUVE — PAR L'EXÉCUTION, PAS PAR LA LECTURE.
#  On ne cherche pas « \n » dans le fichier : on lance un VRAI bash
#  interactif, on lui fait lire interactive.sh, et on lui demande de
#  DÉVELOPPER PS1 (« ${PS1@P} », l'opérateur de bash qui applique les
#  échappements d'invite). Ce qui revient est exactement ce que le terminal
#  affichera, séquences ANSI comprises. Un banc qui aurait lu le fichier
#  aurait manqué que « \n » n'est pas le seul chemin vers une deuxième
#  ligne — et surtout, il n'aurait rien dit des COULEURS, qui ne sont pas
#  dans ce fichier : elles viennent de terminal.env, écrit par
#  lexos-theme-gen. Ici on génère les deux modes pour de vrai et on vérifie
#  que la couleur du fichier est bien celle qui ressort dans l'invite.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$RACINE/config/includes.chroot/usr/share/lexos/shell/interactive.sh"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT
mkdir -p "$BANC/home"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$SH" ] || { non "interactive.sh introuvable"; exit 1; }

#  Le VRAI développement de PS1, par bash lui-même.
#    invite <code-retour> <COLORTERM> [XDG_CONFIG_HOME]
#  --norc --noprofile : le banc ne doit pas hériter du .bashrc de la machine
#  qui le fait tourner ; -i pour que « $- » contienne « i », sans quoi
#  interactive.sh se retire avant même de poser l'invite.
invite() {
	local code="$1" ct="$2" xdg="${3:-$BANC/vide-config}"
	HOME="$BANC/home" XDG_CONFIG_HOME="$xdg" COLORTERM="$ct" TERM=xterm-256color \
		bash --norc --noprofile -i -c \
		". \"$SH\"; __lexos_code=$code; printf '%s' \"\${PS1@P}\"" 2>/dev/null
}

#  Découpe l'invite développée en segments : ('e', séquence) pour une
#  séquence ANSI, ('t', texte) pour ce qui s'affiche. Les marqueurs \001 et
#  \002 (« ce qui suit ne prend pas de place à l'écran ») sont retirés : ils
#  servent à bash pour compter les colonnes, pas au terminal.
#  Le découpeur est écrit dans un FICHIER, et pas donné à python sur son
#  entrée standard : « python3 - <<PY » consomme justement cette entrée pour
#  y lire son propre script, et sys.stdin ne rend alors plus rien. Le banc
#  a commencé sa vie ainsi et ne mesurait donc RIEN — vingt lignes de
#  verdicts calculés sur une chaîne vide.
DECOUPE="$BANC/segments.py"
cat > "$DECOUPE" <<'PY'
import re, sys
brut = sys.stdin.buffer.read().decode("utf-8", "replace")
brut = brut.replace("\001", "").replace("\002", "")
for m in re.finditer(r"\033\[([0-9;]*)m|([^\033]+)", brut):
    if m.group(1) is not None:
        print("e\t" + m.group(1))
    else:
        print("t\t" + m.group(2).replace("\n", "<SAUT-DE-LIGNE>"))
PY
segments() { python3 "$DECOUPE"; }

#  Le contraste d'une séquence (38;2;r;g;b ou 38;5;n, avec ou sans « 1; »)
#  sur un fond #hex — dans un FICHIER, pour la même raison que le découpeur.
CONTRASTE="$BANC/contraste.py"
cat > "$CONTRASTE" <<'PYC'
import sys, re
def lum(c):
    v = [int(c[i:i+2], 16)/255 for i in (1, 3, 5)]
    v = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in v]
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
s = sys.argv[1]
m = re.match(r"(?:1;)?38;2;(\d+);(\d+);(\d+)$", s)
if m:
    fg = "#%02X%02X%02X" % tuple(int(g) for g in m.groups())
else:
    m = re.match(r"(?:1;)?38;5;(\d+)$", s)
    if not m:
        print("0"); sys.exit()
    n = int(m.group(1)); niv = [0, 95, 135, 175, 215, 255]
    if n >= 232:
        v = 8 + (n-232)*10; fg = "#%02X%02X%02X" % (v, v, v)
    elif n >= 16:
        k = n-16; fg = "#%02X%02X%02X" % (niv[k//36], niv[(k//6) % 6], niv[k % 6])
    else:
        print("0"); sys.exit()
a, b = lum(fg), lum(sys.argv[2])
if a < b:
    a, b = b, a
print("%.2f" % ((a+0.05)/(b+0.05)))
PYC

# =============================================================================
titre "1. UNE SEULE LIGNE — « faire en sorte que ça suive --> »"
# =============================================================================
P_OK="$(invite 0 truecolor)"
if [ -z "$P_OK" ]; then
	non "bash n'a rien développé : PS1 est vide (interactive.sh s'est-il retiré ?)"
else
	#  PAS « grep -q $'\n' » : grep coupe son motif AUX sauts de ligne, on
	#  lui donnerait donc un motif VIDE, qui répond oui sur n'importe quoi.
	#  Le filtrage de motif de bash, lui, compare la chaîne entière.
	case "$P_OK" in
		*$'\n'*)
			non "l'invite contient encore un saut de ligne — elle tient sur deux lignes"
			printf '%s' "$P_OK" | segments | sed 's/^/       /' ;;
		*)  ok "l'invite développée ne contient AUCUN saut de ligne" ;;
	esac

	#  Le texte visible, séquences ANSI ôtées. C'est ce qu'Alex voit.
	VISIBLE="$(printf '%s' "$P_OK" | segments | grep -P '^t\t' | cut -f2- | tr -d '\n')"
	printf '       vu à l'"'"'écran : «%s»\n' "$VISIBLE"

	case "$VISIBLE" in
		*'❯ ') ok "l'invite se termine par « ❯ » suivi d'une espace" ;;
		*'❯')  non "le chevron est bien là, mais l'espace qui le suit a disparu" ;;
		*)     non "l'invite ne se termine pas par le chevron : «$VISIBLE»" ;;
	esac

	#  « a déjà une espace » : Alex avait relevé que l'espace existait déjà.
	#  Le saut de ligne devait donc devenir UNE espace, pas deux.
	if grep -q '  ❯' <<< "$VISIBLE" ; then
		non "deux espaces avant le chevron — le saut de ligne a été doublé"
	elif grep -q ' ❯ ' <<< "$VISIBLE" ; then
		ok "une seule espace de chaque côté du chevron"
	else
		non "l'espace avant le chevron manque : «$VISIBLE»"
	fi

	if grep -q '❯  ' <<< "$VISIBLE" ; then
		non "deux espaces APRÈS le chevron"
	else
		ok "une seule espace après le chevron"
	fi
fi

# =============================================================================
titre "2. Trois rôles : le nom en rouge clair, LEXOS en vert foncé, la machine en vert"
# =============================================================================
#  ALEX, consigne « terminal XFCE » : « le nom de l'utilisateur en rouge
#  clair, à côté LEXOS en vert foncé ». Le mot LEXOS REMPLACE « @\h ». Le
#  chemin et le chevron restent écrits par la MACHINE et portent la MÊME
#  couleur. Ce banc ne connaît aucune valeur : il vérifie que le nom, LEXOS
#  et le chevron portent TROIS couleurs distinctes, que chemin et chevron
#  n'en font qu'une, et (section 5) que chacune vient du fichier généré.
mapfile -t SEG < <(printf '%s' "$P_OK" | segments)

#  La couleur en vigueur au moment où un texte donné est écrit.
couleur_de() { # couleur_de <texte cherché>
	local courante="" type texte
	for L in "${SEG[@]}"; do
		type="${L%%$'\t'*}"; texte="${L#*$'\t'}"
		if [ "$type" = "e" ]; then
			#  « 0 » referme : on repart de rien. Sinon la dernière
			#  séquence posée est celle qui peint.
			if [ "$texte" = "0" ]; then courante=""; else courante="$texte"; fi
		elif [ "$type" = "t" ] && [[ "$texte" == *"$1"* ]]; then
			printf '%s' "$courante"; return 0
		fi
	done
	return 1
}

C_CHEVRON="$(couleur_de '❯' || true)"
C_CHEMIN="$(couleur_de "$(basename "$BANC/home")" || true)"
#  Le chemin développé par « \w » est le répertoire courant du banc, pas le
#  faux HOME : on le cherche par son dernier segment, qui y figure toujours.
C_CHEMIN="$(couleur_de "$(basename "$PWD")" || true)"
C_NOM="$(couleur_de "$(id -un)" || true)"
C_LOGO="$(couleur_de "LEXOS" || true)"

if [ -z "$C_CHEVRON" ]; then
	non "impossible de relever la couleur du chevron"
else
	ok "le chevron est peint (séquence $C_CHEVRON)"
	if [ -n "$C_CHEMIN" ] && [ "$C_CHEMIN" = "$C_CHEVRON" ]; then
		ok "le chemin porte la MÊME couleur que le chevron (vert machine)"
	else
		non "le chemin ($C_CHEMIN) et le chevron ($C_CHEVRON) ne sont pas de la même couleur"
	fi
	if [ -n "$C_NOM" ] && [ "$C_NOM" != "$C_CHEVRON" ]; then
		ok "le nom d'utilisateur a SA couleur ($C_NOM), distincte du vert machine"
	else
		non "le nom ($C_NOM) porte encore la couleur de la machine ($C_CHEVRON) — il doit être rouge clair"
	fi
	if [ -n "$C_LOGO" ] && [ "$C_LOGO" != "$C_CHEVRON" ] && [ "$C_LOGO" != "$C_NOM" ]; then
		ok "« LEXOS » est écrit, avec une troisième couleur ($C_LOGO) — ni celle du nom, ni celle de la machine"
	else
		non "« LEXOS » manque de l'invite, ou porte la couleur du nom ($C_NOM) ou de la machine ($C_CHEVRON) : vu « $C_LOGO »"
	fi
	#  « @\h » a disparu : LEXOS le remplace. On cherche le nom de machine
	#  précédé de « @ » dans le TEXTE développé, pas dans le fichier.
	TEXTE_INVITE="$(for L in "${SEG[@]}"; do [ "${L%%$'\t'*}" = "t" ] && printf '%s' "${L#*$'\t'}"; done)"
	if [[ "$TEXTE_INVITE" == *"@$(hostname)"* ]] || [[ "$TEXTE_INVITE" == *"$(id -un)@"* ]]; then
		non "l'invite écrit encore « @machine » : LEXOS devait le remplacer"
	else
		ok "plus de « @machine » : le mot LEXOS a pris la place"
	fi
	if [[ "$TEXTE_INVITE" == *"$(id -un) LEXOS "* ]]; then
		ok "l'ordre est « nom LEXOS chemin » — LEXOS juste à côté du nom"
	else
		non "LEXOS n'est pas juste à côté du nom : « $TEXTE_INVITE »"
	fi
fi

# =============================================================================
titre "3. « écriture blanc pour l'utilisateur » — PS1 finit sur la couleur de frappe"
# =============================================================================
#  Le mécanisme : PS1 se termine par une couleur qu'on ne referme PAS, elle
#  déborde donc sur la frappe. Si la dernière séquence de l'invite est un
#  « 0 » (remise à zéro), la frappe reprend la couleur par défaut du
#  terminal et la demande d'Alex tombe à l'eau sans que rien ne le dise.
DERNIER=""
for L in "${SEG[@]}"; do
	[ "${L%%$'\t'*}" = "e" ] && DERNIER="${L#*$'\t'}"
done
if [ -z "$DERNIER" ]; then
	non "l'invite ne finit sur aucune séquence de couleur"
elif [ "$DERNIER" = "0" ]; then
	non "l'invite finit sur une remise à zéro : la frappe n'aura pas de couleur"
elif [ "$DERNIER" = "$C_CHEVRON" ]; then
	non "la frappe porte la couleur de la MACHINE — elle doit s'en distinguer"
else
	ok "l'invite finit sur une couleur ouverte ($DERNIER) : c'est elle qui peint la frappe"
fi

#  PS0 remet à zéro à l'appui sur Entrée, sinon toute la SORTIE de la
#  commande hériterait du blanc de la frappe.
#  On DÉVELOPPE PS0 comme PS1 : « \e[0m » dans le fichier n'est du texte
#  que jusqu'à ce que bash l'interprète. Comparer la chaîne brute ferait
#  passer un PS0 écrit autrement (« \033[0m », « \[\e[0m\] ») pour un
#  PS0 cassé, et l'inverse.
#  TERM EST POSÉ ICI COMME DANS invite(), ET CE N'EST PAS UN DÉTAIL.
#  interactive.sh ne pose l'invite que si le terminal sait l'afficher :
#  « case "${TERM:-dumb}" in dumb|linux-m|unknown) ;; ». Ces deux
#  sous-shells-ci l'avaient oublié. Sur cette machine ça ne se voyait pas —
#  TERM y est hérité —, mais sur le coureur de la CI il ne l'est PAS : le
#  fichier se retirait, PS0 n'existait pas, et le banc annonçait un défaut
#  qui n'en était pas un. Vingt et un verts et un rouge, tous les jours,
#  pour une variable d'environnement. Le contrôle suivant fige le
#  comportement au lieu de le subir.
PS0_VU="$(HOME="$BANC/home" TERM=xterm-256color bash --norc --noprofile -i -c \
	". \"$SH\"; printf '%s' \"\${PS0-ABSENT}\"" 2>/dev/null)"
PS0_DEV="$(HOME="$BANC/home" TERM=xterm-256color bash --norc --noprofile -i -c \
	". \"$SH\"; printf '%s' \"\${PS0@P}\"" 2>/dev/null | tr -d '\001\002')"
if [ "$PS0_VU" = "ABSENT" ]; then
	non "PS0 n'est pas posé : tout l'écran prendrait la couleur de la frappe"
elif [ "$PS0_DEV" = $'\033[0m' ]; then
	ok "PS0 remet la couleur à zéro : la sortie des commandes n'est pas blanche"
else
	non "PS0 ne remet pas à zéro (développé : $(printf '%q' "$PS0_DEV"))"
fi

#  ET SUR UN TERMINAL QUI NE SAIT PAS AFFICHER DE COULEUR, ON NE POSE RIEN.
#  C'est ce que dit le « case TERM » d'interactive.sh, et c'est ce qui rend
#  la ligne ci-dessus obligatoire. Un banc qui hérite de TERM sans le dire
#  éprouve la machine qui le fait tourner, pas le fichier.
PS0_DUMB="$(HOME="$BANC/home" TERM=dumb bash --norc --noprofile -i -c \
	". \"$SH\"; printf '%s' \"\${PS0-ABSENT}\"" 2>/dev/null)"
if [ "$PS0_DUMB" = "ABSENT" ]; then
	ok "terminal « dumb » : aucune invite en couleur n'est posée — le repli marche"
else
	non "terminal « dumb » : une invite en couleur est quand même posée ($(printf '%q' "$PS0_DUMB"))"
fi

# =============================================================================
titre "4. Le chevron vire au ROUGE quand la commande précédente a échoué"
# =============================================================================
P_KO="$(invite 127 truecolor)"
mapfile -t SEG < <(printf '%s' "$P_KO" | segments)
C_CHEVRON_KO="$(couleur_de '❯' || true)"
if [ -z "$C_CHEVRON_KO" ]; then
	non "impossible de relever la couleur du chevron après un échec"
elif [ "$C_CHEVRON_KO" = "$C_CHEVRON" ]; then
	non "le chevron garde sa couleur après un échec : le seul signal de l'invite est perdu"
else
	ok "après un code 127, le chevron change de couleur ($C_CHEVRON → $C_CHEVRON_KO)"
fi
#  Et le reste de l'invite, lui, ne bouge PAS : seul le chevron alerte.
if [ "$(couleur_de "$(basename "$PWD")" || true)" = "$C_CHEMIN" ]; then
	ok "le chemin, lui, garde son vert : seul le chevron alerte"
else
	non "l'échec a repeint autre chose que le chevron"
fi

# =============================================================================
titre "5. Les couleurs viennent du fichier GÉNÉRÉ, pas d'une valeur en dur"
# =============================================================================
#  On génère les deux modes pour de vrai, puis on redemande l'invite en lui
#  donnant ce fichier-là. Si la valeur du fichier ne ressort pas dans
#  l'invite, c'est que le lien est cassé — le défaut exact que ce dépôt a
#  déjà connu : la bonne couleur écrite au bon endroit, et quelque chose de
#  plus tôt dans la chaîne qui ne la lit plus.
for MODE in nuit jour; do
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/t" --terminal "$MODE" orange \
		>"$BANC/gen-$MODE.log" 2>&1
	ENV="$BANC/t/.config/lexos/terminal.env"
	if [ ! -r "$ENV" ]; then
		non "$MODE : aucun terminal.env produit"
		continue
	fi
	# shellcheck disable=SC1090
	( set -a; . "$ENV"; set +a
	  [ -n "${LEXOS_PS_TEXTE:-}" ] ) \
		|| { non "$MODE : LEXOS_PS_TEXTE absent du fichier généré"; continue; }

	ATTENDU_M="$(sed -n "s/^LEXOS_PS_MACHINE='\(.*\)'$/\1/p" "$ENV")"
	ATTENDU_T="$(sed -n "s/^LEXOS_PS_TEXTE='\(.*\)'$/\1/p"   "$ENV")"

	mapfile -t SEG < <(invite 0 truecolor "$BANC/t/.config" | segments)
	VU_M="$(couleur_de '❯' || true)"
	VU_T=""
	for L in "${SEG[@]}"; do
		[ "${L%%$'\t'*}" = "e" ] && VU_T="${L#*$'\t'}"
	done

	[ "$VU_M" = "$ATTENDU_M" ] \
		&& ok "$MODE : le vert de l'invite est celui du fichier ($ATTENDU_M)" \
		|| non "$MODE : le fichier dit $ATTENDU_M, l'invite affiche $VU_M"
	#  Les deux rôles de la consigne « terminal XFCE » : le nom, LEXOS.
	ATTENDU_U="$(sed -n "s/^LEXOS_PS_UTILISATEUR='\(.*\)'$/\1/p" "$ENV")"
	ATTENDU_L="$(sed -n "s/^LEXOS_PS_LOGO='\(.*\)'$/\1/p" "$ENV")"
	VU_U="$(couleur_de "$(id -un)" || true)"
	VU_L="$(couleur_de "LEXOS" || true)"
	[ -n "$ATTENDU_U" ] && [ "$VU_U" = "$ATTENDU_U" ] \
		&& ok "$MODE : le rouge clair du nom est celui du fichier ($ATTENDU_U)" \
		|| non "$MODE : le fichier dit « $ATTENDU_U » pour le nom, l'invite affiche « $VU_U »"
	[ -n "$ATTENDU_L" ] && [ "$VU_L" = "$ATTENDU_L" ] \
		&& ok "$MODE : le vert foncé de LEXOS est celui du fichier ($ATTENDU_L)" \
		|| non "$MODE : le fichier dit « $ATTENDU_L » pour LEXOS, l'invite affiche « $VU_L »"
	ATTENDU_E="$(sed -n "s/^LEXOS_PS_ERREUR='\(.*\)'$/\1/p" "$ENV")"
	[ -n "$ATTENDU_U" ] && [ "1;$ATTENDU_U" != "$ATTENDU_E" ] && [ "$ATTENDU_U" != "${ATTENDU_E#1;}" ] \
		&& ok "$MODE : le rouge clair du nom n'est PAS le rouge d'erreur du chevron (signature ≠ signal)" \
		|| non "$MODE : le nom et l'erreur portent le même rouge — on ne distinguerait plus une commande en échec"
	[ "$VU_T" = "$ATTENDU_T" ] \
		&& ok "$MODE : la couleur de frappe est celle du fichier ($ATTENDU_T)" \
		|| non "$MODE : le fichier dit $ATTENDU_T, l'invite affiche $VU_T"

	#  Et le repli palette 256, pour la console texte et les vieux ssh qui
	#  afficheraient « 38;2;255;255;255 » en clair au milieu de l'invite.
	ATTENDU_256="$(sed -n "s/^LEXOS_PS_TEXTE_256='\(.*\)'$/\1/p" "$ENV")"
	VU_256=""
	mapfile -t SEG < <(invite 0 "" "$BANC/t/.config" | segments)
	for L in "${SEG[@]}"; do
		[ "${L%%$'\t'*}" = "e" ] && VU_256="${L#*$'\t'}"
	done
	[ -n "$ATTENDU_256" ] && [ "$VU_256" = "$ATTENDU_256" ] \
		&& ok "$MODE : sans COLORTERM, l'invite retombe sur la palette 256 ($ATTENDU_256)" \
		|| non "$MODE : repli 256 attendu $ATTENDU_256, vu $VU_256"
	ATTENDU_U256="$(sed -n "s/^LEXOS_PS_UTILISATEUR_256='\(.*\)'$/\1/p" "$ENV")"
	ATTENDU_L256="$(sed -n "s/^LEXOS_PS_LOGO_256='\(.*\)'$/\1/p" "$ENV")"
	VU_U256="$(couleur_de "$(id -un)" || true)"
	VU_L256="$(couleur_de "LEXOS" || true)"
	[ -n "$ATTENDU_U256" ] && [ "$VU_U256" = "$ATTENDU_U256" ] && [ -n "$ATTENDU_L256" ] && [ "$VU_L256" = "$ATTENDU_L256" ] \
		&& ok "$MODE : en 256 couleurs, le nom ($ATTENDU_U256) et LEXOS ($ATTENDU_L256) retombent sur leurs replis" \
		|| non "$MODE : replis 256 du nom/LEXOS attendus $ATTENDU_U256 / $ATTENDU_L256, vus $VU_U256 / $VU_L256"
	#  …et ces replis restent TROIS couleurs : un repli 256 de LEXOS égal au
	#  vert machine fondrait le mot dans le chemin en console texte.
	ATTENDU_M256="$(sed -n "s/^LEXOS_PS_MACHINE_256='\(.*\)'$/\1/p" "$ENV")"
	[ -n "$ATTENDU_M256" ] && [ "$ATTENDU_L256" != "$ATTENDU_M256" ] && [ "$ATTENDU_U256" != "$ATTENDU_M256" ] && [ "$ATTENDU_U256" != "$ATTENDU_L256" ] \
		&& ok "$MODE : en 256 couleurs aussi, nom / LEXOS / machine sont trois couleurs distinctes" \
		|| non "$MODE : en 256 couleurs, deux des trois rôles se confondent (nom $ATTENDU_U256, LEXOS $ATTENDU_L256, machine $ATTENDU_M256)"

	#  Le contraste, mesuré sur le VRAI fond du mode. Une frappe blanche sur
	#  le crème du thème de jour serait invisible : c'est pour ça que jour et
	#  nuit n'ont pas la même encre.
	BG="$(sed -n 's/^LEXOS_TERM_BG=//p' "$ENV")"
	RAPPORT="$(python3 - "$ATTENDU_T" "$BG" <<'PY'
import sys, re
def lum(c):
    v = [int(c[i:i+2], 16)/255 for i in (1, 3, 5)]
    v = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in v]
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
m = re.match(r"38;2;(\d+);(\d+);(\d+)$", sys.argv[1])
if not m:
    print("0"); sys.exit()
fg = "#%02X%02X%02X" % tuple(int(g) for g in m.groups())
a, b = lum(fg), lum(sys.argv[2])
if a < b: a, b = b, a
print("%.2f" % ((a+0.05)/(b+0.05)))
PY
)"
	if awk -v r="$RAPPORT" 'BEGIN{exit !(r >= 4.5)}'; then
		ok "$MODE : la frappe donne $RAPPORT:1 sur le fond $BG (seuil AA 4,5)"
	else
		non "$MODE : la frappe ne donne que $RAPPORT:1 sur $BG — illisible"
	fi
	#  Le nom et LEXOS aussi — en couleur vraie ET en 256 : « le vert foncé
	#  sur fond noir se lit mal », le seuil est mesuré sur le vrai fond.
	for ROLE in "nom:$ATTENDU_U" "LEXOS:$ATTENDU_L" "nom-256:$ATTENDU_U256" "LEXOS-256:$ATTENDU_L256"; do
		R="$(python3 "$CONTRASTE" "${ROLE#*:}" "$BG")"
		if awk -v r="$R" 'BEGIN{exit !(r >= 4.5)}'; then
			ok "$MODE : ${ROLE%%:*} donne $R:1 sur $BG"
		else
			non "$MODE : ${ROLE%%:*} ne donne que $R:1 sur $BG — « le vert foncé sur fond noir se lit mal »"
		fi
	done
done

# =============================================================================
titre "6. L'orange a quitté l'INVITE, pas le TERMINAL"
# =============================================================================
#  La demande d'Alex portait sur l'invite et la frappe. Le curseur, la
#  sélection et l'onglet actif gardent l'accent : les retirer aussi aurait
#  été un correctif trop large, et personne ne l'aurait vu venir.
#  ON LIT LE CODE, PAS LES COMMENTAIRES. Les deux fichiers EXPLIQUENT que
#  C_SAISIE s'appelait ainsi avant — un banc naïf lirait sa propre
#  explication et se déclarerait en échec. Ce dépôt s'est déjà fait prendre
#  trois fois à cette faute ; on coupe les commentaires d'abord.
code_seul() { sed 's/#.*$//' "$1"; }
if grep -q 'C_SAISIE\|PS_SAISIE' < <(code_seul "$SH"); then
	non "interactive.sh emploie encore « saisie » dans son code : l'ancien nom traîne"
else
	ok "interactive.sh ne connaît plus que C_MACHINE, C_TEXTE, C_ERREUR et C_DIM"
fi
if grep -q "LEXOS_PS_SAISIE" < <(code_seul "$GEN"); then
	non "lexos-theme-gen écrit encore LEXOS_PS_SAISIE — une clé que personne ne lit"
else
	ok "lexos-theme-gen n'écrit plus de clé d'invite orpheline"
fi
if grep -q 'CursorColor=\${TERM_CURSEUR}\|TabActivityColor=\${TERM_SAISIE}' "$GEN"; then
	ok "le terminal garde bien l'accent pour son curseur et son onglet actif"
else
	non "l'accent a disparu du terminalrc : le correctif a débordé sur le curseur"
fi

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mL'"'"'invite tient sur une ligne, en vert, et ce qu'"'"'on tape est blanc.\033[0m\n'
