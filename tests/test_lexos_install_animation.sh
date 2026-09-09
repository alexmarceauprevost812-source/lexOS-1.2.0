#!/usr/bin/env bash
# =============================================================================
#  Éprouver l'animation qui joue avant l'installateur
# =============================================================================
#  CE BANC ÉPROUVE LES ÉCHECS AVANT LE CAS QUI MARCHE, ET CE N'EST PAS UN
#  GOÛT DE PRÉSENTATION.
#
#  C'est le seul écran de LexOS que voit quelqu'un qui n'a PAS ENCORE LexOS.
#  S'il se bloque, la personne ne débogue pas : elle range la clé USB. La
#  question n'est donc pas « est-ce que la vidéo joue » — c'est « est-ce que
#  CALAMARES S'OUVRE, QUOI QU'IL ARRIVE ».
#
#  ON NE LIT PAS LE CODE, ON LE FAIT TOURNER. Chaque cas est joué pour de
#  vrai, sur le vrai lexos-install, avec un faux calamares qui laisse une
#  trace : un PATH sans mpv, un fichier absent, un mpv qui PLANTE, un mpv qui
#  IGNORE SIGTERM et ne s'arrête jamais. Si la trace de calamares n'est pas
#  là, l'installateur ne s'est pas ouvert — et c'est un rouge.
#
#  Les seams (LEXOS_CMDLINE, LEXOS_INSTALL_VIDEO, LEXOS_INSTALL_DELAI,
#  LEXOS_INSTALL_MUET) déplacent ce que le programme lit ; ils ne lui donnent
#  aucun droit et ne changent aucune décision.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-install"
BRANDING="$RACINE/branding"
BANC="$(mktemp -d)"
nettoyer() {
	pkill -x lexosbancfige 2>/dev/null
	rm -rf "$BANC"
	return 0
}
trap nettoyer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$OUTIL" ] || { echo "lexos-install introuvable"; exit 1; }

# --- Le décor ----------------------------------------------------------------
mkdir -p "$BANC/bin" "$BANC/vide"
printf 'BOOT_IMAGE=/vmlinuz boot=live components username=lex quiet splash\n' > "$BANC/cmdline"

#  Un faux calamares qui LAISSE UNE TRACE. C'est lui, le contrôle : sa trace
#  veut dire « l'installateur s'est ouvert ». Rien d'autre ne le prouve.
cat > "$BANC/bin/calamares" <<EOF
#!/bin/sh
echo "calamares lancé: \$*" >> "$BANC/trace"
exit 0
EOF
#  sudo : le script y passe quand il ne tourne pas en root. On le remplace
#  pour que le banc marche des deux côtés, sans jamais élever quoi que ce soit.
cat > "$BANC/bin/sudo" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -E|-n) shift ;; *) break ;; esac; done
exec "$@"
EOF
chmod +x "$BANC/bin/calamares" "$BANC/bin/sudo"

#  Le PATH du banc : le nôtre d'abord, puis le système. On y ajoutera ou
#  retirera mpv selon le cas éprouvé.
CHEMIN="$BANC/bin:$PATH"

lance() { # lance [VAR=val ...] — rend le code de sortie, écrit $BANC/trace
	rm -f "$BANC/trace"
	env PATH="$CHEMIN" \
	    LEXOS_CMDLINE="$BANC/cmdline" \
	    LEXOS_INSTALL_MUET=1 \
	    "$@" bash "$OUTIL" --yes >"$BANC/sortie" 2>&1
}
atteint() { [ -s "$BANC/trace" ]; }

# =============================================================================
titre "1. CALAMARES S'OUVRE, QUOI QU'IL ARRIVE"
# =============================================================================

# --- mpv absent : une ferme de liens symboliques SANS mpv -------------------
SANS_MPV="$BANC/sans-mpv"
mkdir -p "$SANS_MPV"
for d in /usr/bin /bin /usr/sbin /sbin; do
	[ -d "$d" ] || continue
	for f in "$d"/*; do
		b="$(basename "$f")"
		case "$b" in mpv) continue ;; esac
		[ -e "$SANS_MPV/$b" ] || ln -s "$f" "$SANS_MPV/$b" 2>/dev/null
	done
done
if PATH="$SANS_MPV" command -v mpv >/dev/null 2>&1; then
	non "le PATH sans mpv n'a pas pu être fabriqué : le contrôle ne prouverait rien"
else
	rm -f "$BANC/trace"
	env PATH="$BANC/bin:$SANS_MPV" LEXOS_CMDLINE="$BANC/cmdline" \
	    LEXOS_INSTALL_MUET=1 DISPLAY=":99" \
	    LEXOS_INSTALL_VIDEO="$BRANDING/installation.mp4" \
	    bash "$OUTIL" --yes >"$BANC/sortie" 2>&1
	RC=$?
	if [ "$RC" = "0" ] && atteint; then
		ok "sans mpv : Calamares s'ouvre quand même"
	else
		non "sans mpv : code $RC, Calamares $(atteint && echo ouvert || echo 'PAS ouvert')"
	fi
fi

# --- Fichier vidéo absent ----------------------------------------------------
lance DISPLAY=":99" LEXOS_INSTALL_VIDEO="$BANC/vide/pasla.mp4"
RC=$?
if [ "$RC" = "0" ] && atteint; then
	ok "sans le fichier vidéo : Calamares s'ouvre"
else
	non "fichier absent : code $RC, Calamares $(atteint && echo ouvert || echo 'PAS ouvert')"
fi

# --- Pas d'écran (console, ssh) ---------------------------------------------
rm -f "$BANC/trace"
env PATH="$CHEMIN" LEXOS_CMDLINE="$BANC/cmdline" LEXOS_INSTALL_MUET=1 \
    DISPLAY="" WAYLAND_DISPLAY="" bash "$OUTIL" --yes >"$BANC/sortie" 2>&1
RC=$?
if [ "$RC" = "0" ] && atteint; then
	ok "sans écran : rien n'est joué, Calamares s'ouvre"
else
	non "sans écran : code $RC, Calamares $(atteint && echo ouvert || echo 'PAS ouvert')"
fi

# --- mpv qui PLANTE ----------------------------------------------------------
cat > "$BANC/bin/mpv" <<'EOF'
#!/bin/sh
echo "boum" >&2
exit 3
EOF
chmod +x "$BANC/bin/mpv"
lance DISPLAY=":99" LEXOS_INSTALL_VIDEO="$BRANDING/installation.mp4"
RC=$?
if [ "$RC" = "0" ] && atteint; then
	ok "mpv qui plante (code 3) : Calamares s'ouvre quand même"
else
	non "mpv en échec : code $RC, Calamares $(atteint && echo ouvert || echo 'PAS ouvert')"
fi
#  …et sans un mot à l'écran. Une trace d'erreur avant l'installateur serait
#  la première chose que verrait quelqu'un qui essaie LexOS.
if ! grep -qi 'boum' "$BANC/sortie" 2>/dev/null; then
	ok "…et le message d'erreur de mpv ne va PAS à l'écran"
else
	non "le message d'erreur de mpv s'affiche avant l'installateur"
fi

# =============================================================================
titre "2. LA MINUTERIE — un mpv figé ne retient pas l'installateur"
# =============================================================================
#  ═══ CELUI-CI EST LE CAS QUI COMPTE ═══
#  Un mpv qui plante rend la main tout seul. Un mpv FIGÉ, non : c'est lui qui
#  laisserait quelqu'un devant un écran noir sans rien comprendre. On en
#  fabrique un vrai — qui IGNORE SIGTERM — et on mesure le temps écoulé.
#  ═══ « #!/bin/bash » ET PAS « #!/bin/sh » — UN FAUX VERT VÉCU ═══
#  Premier jet : « #!/bin/sh » avec « exec -a ». « exec -a » est une
#  extension de bash que dash n'a PAS : le faux mpv mourait à l'instant même,
#  la minuterie n'était jamais atteinte, et le contrôle affichait « la main
#  est rendue en 0 s » — VERT, en n'ayant rien éprouvé du tout. C'est le 0
#  qui a trahi : un mpv vraiment figé ne peut pas rendre la main avant le
#  délai. D'où la BORNE BASSE ci-dessous, qui rend ce faux vert impossible.
cat > "$BANC/bin/mpv" <<'EOF'
#!/bin/bash
#  Le nom du processus sert au nettoyage du banc.
exec -a lexosbancfige bash -c 'trap "" TERM; while :; do sleep 1; done'
EOF
chmod +x "$BANC/bin/mpv"
#  On vérifie d'abord que le faux mpv SE FIGE VRAIMENT. Sans ça, le contrôle
#  qui suit passerait au vert sur un programme qui rend la main tout seul.
#  « -k 1 » ICI AUSSI, ET C'EST LE MÊME PIÈGE QUE CELUI QU'ON ÉPROUVE :
#  « timeout 2 » seul n'envoie que TERM — que ce faux mpv ignore par
#  construction. Sans le KILL de secours, c'est LE BANC qui restait figé
#  pour toujours. Vécu.
if timeout -k 1 2 "$BANC/bin/mpv" >/dev/null 2>&1; then
	non "le faux mpv figé ne se fige pas : le contrôle de la minuterie ne prouverait rien"
	pkill -x lexosbancfige 2>/dev/null
else
	pkill -x lexosbancfige 2>/dev/null
	#  ═══ LE BANC SE BORNE LUI-MÊME, ET C'EST UNE MUTATION QUI L'A EXIGÉ ═══
	#  Mutation « timeout sans -k » : le défaut est réel — mpv ignore TERM et
	#  ne meurt jamais. Mais le banc, lui, restait figé avec lui : pas de
	#  rouge, pas de vert, juste une CI qui ne rend jamais la main. Un banc
	#  qui pend est presque aussi mauvais qu'un banc faussement vert : on ne
	#  sait pas ce qui ne va pas. On borne donc l'appel à 20 s, largement
	#  au-dessus des 5 s mesurées, pour que la régression donne un ROUGE
	#  qui nomme le problème.
	DEBUT="$(date +%s)"
	rm -f "$BANC/trace"
	timeout -k 3 20 env PATH="$CHEMIN" LEXOS_CMDLINE="$BANC/cmdline" \
	    LEXOS_INSTALL_MUET=1 DISPLAY=":99" \
	    LEXOS_INSTALL_VIDEO="$BRANDING/installation.mp4" \
	    LEXOS_INSTALL_DELAI=3 \
	    bash "$OUTIL" --yes >"$BANC/sortie" 2>&1
	RC=$?
	ECOULE=$(( $(date +%s) - DEBUT ))
	if [ "$RC" = "124" ] || [ "$RC" = "137" ]; then
		non "lexos-install ne rend JAMAIS la main avec un mpv figé : l'installateur ne s'ouvrirait pas"
		RC=""
	fi
	#  BORNE BASSE ET BORNE HAUTE. La basse (≥ 2 s pour un délai de 3)
	#  prouve que mpv a VRAIMENT tourné puis été tué ; la haute (≤ 9 s)
	#  prouve que la minuterie a mordu au lieu d'attendre pour toujours.
	if [ "$RC" = "0" ] && atteint && [ "$ECOULE" -ge 2 ] && [ "$ECOULE" -le 9 ]; then
		ok "mpv figé qui ignore SIGTERM : tué après ${ECOULE} s (délai 3), et Calamares s'ouvre"
	else
		non "mpv figé : ${ECOULE} s (attendu entre 2 et 9), code $RC, Calamares $(atteint && echo ouvert || echo 'PAS ouvert')"
	fi
	pkill -x lexosbancfige 2>/dev/null
fi

#  La minuterie est-elle ÉCRITE, et tue-t-elle vraiment ? « timeout » seul
#  n'envoie que TERM — que le mpv figé ci-dessus ignore. C'est « -k » qui
#  garantit le KILL, et sans lui le contrôle précédent aurait échoué.
if grep -q 'timeout -k 2 "\$delai" mpv' "$OUTIL"; then
	ok "la minuterie tue le processus (timeout -k), elle ne fait pas que demander"
else
	non "la minuterie ne tue pas : un mpv qui ignore TERM bloquerait l'installateur"
fi

# =============================================================================
titre "3. L'ORDRE : on confirme, PUIS on regarde"
# =============================================================================
#  ═══ POSER LA VIDÉO AVANT LA CONFIRMATION SERAIT UN DÉFAUT ═══
#  Ça ferait attendre dix secondes quelqu'un qui allait répondre « non ». On
#  vérifie donc la place de l'appel dans le fichier : après le bloc de
#  confirmation, avant l'exec.
LIG_CONF="$(grep -n 'if (( CONFIRMED != 0 )); then' "$OUTIL" | head -1 | cut -d: -f1)"
LIG_ANIM="$(grep -n '^animation_installation || true' "$OUTIL" | head -1 | cut -d: -f1)"
LIG_EXEC="$(grep -n '^exec calamares -d' "$OUTIL" | head -1 | cut -d: -f1)"
if [ -n "$LIG_CONF" ] && [ -n "$LIG_ANIM" ] && [ -n "$LIG_EXEC" ] \
   && [ "$LIG_ANIM" -gt "$LIG_CONF" ] && [ "$LIG_ANIM" -lt "$LIG_EXEC" ]; then
	ok "l'animation est appelée APRÈS la confirmation (l. $LIG_CONF) et AVANT l'exec (l. $LIG_EXEC)"
else
	non "l'animation n'est pas entre la confirmation et l'exec (conf $LIG_CONF, anim $LIG_ANIM, exec $LIG_EXEC)"
fi

#  Et rien n'a été touché dans les vérifications de disque : la consigne
#  l'interdit explicitement. On le mesure en jouant le refus.
rm -f "$BANC/trace"
printf 'BOOT_IMAGE=/vmlinuz ro quiet splash\n' > "$BANC/cmdline-installe"
env PATH="$CHEMIN" LEXOS_CMDLINE="$BANC/cmdline-installe" DISPLAY="" \
	bash "$OUTIL" --yes >"$BANC/sortie" 2>&1
RC=$?
if [ "$RC" != "0" ] && ! atteint; then
	ok "hors session démo : refus intact, Calamares n'est PAS lancé"
else
	non "hors session démo : code $RC — le garde-fou du disque a bougé"
fi

# =============================================================================
titre "4. LE FORMAT ET LE SON — ce que mpv reçoit vraiment"
# =============================================================================
#  ═══ ON LIT LA LIGNE DE COMMANDE REÇUE, PAS CELLE QU'ON A ÉCRITE ═══
#  Un faux mpv qui note ses arguments : c'est la seule façon de savoir ce qui
#  lui arrive après le passage par le tableau bash et les guillemets.
cat > "$BANC/bin/mpv" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$BANC/args"
exit 0
EOF
chmod +x "$BANC/bin/mpv"

lance DISPLAY=":99" LEXOS_INSTALL_VIDEO="$BRANDING/installation.mp4"
if [ -s "$BANC/args" ]; then
	#  Portrait à sa taille d'origine sur fond noir : « --video-unscaled=yes »
	#  est CE QUI L'APPLIQUE. Sans lui, mpv agrandit le 720×870 pour remplir
	#  la hauteur — ce que la consigne écarte (« pas d'agrandissement »), et
	#  ce qui coûterait du processeur sur la machine modeste qu'on installe.
	if grep -qx -- '--video-unscaled=yes' "$BANC/args"; then
		ok "la vidéo n'est PAS agrandie : --video-unscaled=yes est bien passé"
	else
		non "--video-unscaled=yes absent : le portrait serait agrandi et déformé"
	fi
	if grep -qx -- '--geometry=100%x100%+0+0' "$BANC/args"; then
		ok "la fenêtre couvre l'écran sans dépendre du gestionnaire de fenêtres"
	else
		non "la fenêtre ne couvre pas l'écran : le fond noir ne serait pas plein écran"
	fi
	if grep -qx -- '--no-config' "$BANC/args"; then
		ok "« --no-config » : les réglages mpv de la personne ne s'appliquent pas"
	else
		non "sans --no-config, un ~/.config/mpv pourrait tout changer"
	fi
	#  L'interrupteur du banc et de l'installation en public.
	if grep -qx -- '--no-audio' "$BANC/args"; then
		ok "LEXOS_INSTALL_MUET=1 coupe le son (et pas l'animation)"
	else
		non "LEXOS_INSTALL_MUET=1 ne coupe pas le son"
	fi
	#  Et sans l'interrupteur, le son EXISTE — à volume modéré. C'est une
	#  décision de la consigne : cette vidéo ne joue qu'une fois par machine.
	rm -f "$BANC/args" "$BANC/trace"
	env PATH="$CHEMIN" LEXOS_CMDLINE="$BANC/cmdline" DISPLAY=":99" \
	    LEXOS_INSTALL_VIDEO="$BRANDING/installation.mp4" \
	    bash "$OUTIL" --yes >/dev/null 2>&1
	if grep -qx -- '--volume=70' "$BANC/args" && ! grep -qx -- '--no-audio' "$BANC/args"; then
		ok "sans l'interrupteur : le son joue, à volume modéré (70)"
	else
		non "le son ne joue pas alors que rien ne l'a coupé"
	fi
	#  La table des touches : une touche ou un clic doit couper.
	TABLE="$(grep -m1 -- '--input-conf=' "$BANC/args" | sed 's/^--input-conf=//')"
	if [ -n "$TABLE" ]; then
		ok "une table de touches est passée à mpv (--input-conf)"
	else
		non "aucune table de touches : rien ne couperait la vidéo"
	fi
else
	non "mpv n'a pas été appelé du tout"
fi

#  ═══ LA TABLE EST ÉCRITE PUIS EFFACÉE : ON LA LIT DANS LE PROGRAMME ═══
#  Le fichier temporaire n'existe plus quand le banc regarde. On éprouve donc
#  le contenu tel que le programme l'écrit, en le rejouant.
for TOUCHE in ANY_UNICODE ESC ENTER SPACE MBTN_LEFT MBTN_RIGHT; do
	if grep -q "^${TOUCHE} quit$" "$OUTIL"; then
		:
	else
		non "la touche $TOUCHE ne coupe pas la vidéo"
		TOUCHE_KO=1
	fi
done
[ -z "${TOUCHE_KO:-}" ] && ok "toutes les touches et les trois boutons de souris coupent la vidéo"

# =============================================================================
titre "5. LE FICHIER LIVRÉ"
# =============================================================================
if [ ! -r "$BRANDING/installation.mp4" ]; then
	non "branding/installation.mp4 absent : rien ne jouerait"
elif ! command -v ffprobe >/dev/null 2>&1; then
	saut "ffprobe absent : le format du fichier n'est pas mesuré"
else
	DIM="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
		-of csv=p=0:s=x "$BRANDING/installation.mp4" 2>/dev/null)"
	[ "$DIM" = "720x870" ] \
		&& ok "installation.mp4 : $DIM (le portrait d'Alex, intact)" \
		|| non "installation.mp4 : « $DIM » (attendu 720x870)"
	#  ═══ LE POIDS EST UNE EXIGENCE, PAS UNE STATISTIQUE ═══
	#  L'original faisait 4,5 Mo à 3,7 Mb/s pour dix secondes — « deux à trois
	#  fois trop », et sur une ISO chaque mégaoctet compte. Le plafond de 2 Mo
	#  vient de la consigne.
	POIDS="$(stat -c%s "$BRANDING/installation.mp4")"
	if [ "$POIDS" -le 2097152 ]; then
		ok "poids : $(( POIDS / 1024 )) Ko (sous les 2 Mo demandés)"
	else
		non "poids : $(( POIDS / 1024 )) Ko — au-dessus des 2 Mo demandés"
	fi
	#  Le son doit être là : la consigne le garde pour cet écran-ci.
	if grep -q audio < <(ffprobe -v error -select_streams a \
		-show_entries stream=codec_type -of csv=p=0 \
		"$BRANDING/installation.mp4" 2>/dev/null); then
		ok "la piste sonore est conservée dans le fichier livré"
	else
		non "le ré-encodage a perdu la piste sonore"
	fi
fi

#  Et il doit être COPIÉ dans l'ISO, sinon rien de tout cela ne sert.
if grep -q 'cp branding/\*.mp4' "$RACINE/build.sh"; then
	ok "build.sh copie les .mp4 dans l'ISO"
else
	non "build.sh ne copie pas les .mp4 : la vidéo n'arriverait jamais sur la machine"
fi
#  …et il ne doit PAS être effacé par le hook 0300, qui retire les deux
#  autres vidéos (elles, ce sont des sources de construction ; celle-ci se
#  joue depuis la clé USB).
if ! grep -q 'rm -f.*installation\.mp4' "$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"; then
	ok "le hook 0300 n'efface pas installation.mp4 (elle se joue depuis l'ISO)"
else
	non "le hook 0300 efface installation.mp4 : elle ne serait pas sur la clé"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
