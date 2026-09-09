#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-icones-bureau — recaler les raccourcis du bureau
# =============================================================================
#  ═══ LE PIÈGE QUE CET OUTIL EXISTE POUR COUVRIR ═══
#  Le correctif de l'ISO fait pointer le lanceur SYSTÈME du terminal sur
#  l'icône LexOS. Mais une icône POSÉE SUR LE BUREAU n'est pas ce lanceur :
#  c'est une COPIE, avec sa propre ligne « Icon= », figée au jour où elle a
#  été faite. Alex aurait vu le correctif partout SAUF à l'endroit exact de
#  sa photo.
#
#  ON REJOUE SA SITUATION, on ne la décrit pas : un lanceur système corrigé,
#  une copie périmée sur le bureau, et un raccourci écrit à la main qui ne
#  doit surtout pas bouger.
#
#  L'ORDRE : ce qu'il ne doit PAS toucher passe avant ce qu'il doit corriger.
#  Un outil qui écrit dans le dossier personnel se juge d'abord sur ce qu'il
#  laisse tranquille.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-icones-bureau"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-icones-bureau introuvable ou non exécutable"; exit 1; }

#  Le décor : on le refait à neuf avant chaque cas, pour qu'un contrôle ne
#  travaille jamais sur ce qu'un autre a laissé.
decor() {
	rm -rf "${BANC:?}/d"
	mkdir -p "$BANC/d/Bureau" "$BANC/d/local" "$BANC/d/apps"
	#  Le lanceur du paquet, et la surcharge LexOS par-dessus.
	printf '[Desktop Entry]\nType=Application\nName=Xfce Terminal\nName[fr]=Terminal Xfce\nExec=xfce4-terminal\nIcon=org.xfce.terminal\nActions=preferences;\n\n[Desktop Action preferences]\nName=Terminal Preferences\nExec=xfce4-terminal --preferences\n' \
		> "$BANC/d/apps/xfce4-terminal.desktop"
	sed 's/^Icon=.*/Icon=lexos-terminal/' "$BANC/d/apps/xfce4-terminal.desktop" \
		> "$BANC/d/local/xfce4-terminal.desktop"
	#  LA SITUATION D'ALEX : la copie du bureau porte l'ANCIENNE icône.
	cp "$BANC/d/apps/xfce4-terminal.desktop" "$BANC/d/Bureau/xfce4-terminal.desktop"
	chmod +x "$BANC/d/Bureau/xfce4-terminal.desktop"
	#  Un raccourci écrit à la main : aucun lanceur système du même nom.
	printf '[Desktop Entry]\nType=Application\nName=Mon script\nExec=/home/lex/truc.sh\nIcon=une-icone-a-moi\n' \
		> "$BANC/d/Bureau/mon-script.desktop"
	#  Une copie que la personne a RENOMMÉE — même nom de fichier qu'un
	#  lanceur système.
	#  ═══ SON ICÔNE DOIT DIFFÉRER DE CELLE DU LANCEUR, ET C'EST LE POINT ═══
	#  Premier jet : les deux portaient la même icône. L'outil sautait donc
	#  ce fichier avant même de l'ouvrir, et le contrôle « le nom ne bouge
	#  pas » ne prouvait rien — mutation vérifiée : en faisant recopier le
	#  lanceur ENTIER par-dessus la copie, le banc restait VERT. Avec deux
	#  icônes différentes, le fichier est vraiment traité, et le contrôle
	#  porte enfin sur ce qu'il annonce.
	printf '[Desktop Entry]\nType=Application\nName=Mon terminal a moi\nExec=xfce4-terminal --title=Perso\nIcon=vieille-icone\n' \
		> "$BANC/d/Bureau/perso.desktop"
	printf '[Desktop Entry]\nType=Application\nName=Perso\nExec=/bin/true\nIcon=lexos-terminal\n' \
		> "$BANC/d/apps/perso.desktop"
}
lance() {
	env LEXOS_BUREAU_DIR="$BANC/d/Bureau" \
	    LEXOS_APPS_DIRS="$BANC/d/local $BANC/d/apps" \
	    bash "$OUTIL" "$@" 2>&1
}
icone_de() { sed -n 's/^Icon=//p' "$1" | head -1; }

# =============================================================================
titre "1. CE QU'IL NE TOUCHE PAS"
# =============================================================================
decor
lance >/dev/null
if [ "$(icone_de "$BANC/d/Bureau/mon-script.desktop")" = "une-icone-a-moi" ]; then
	ok "un raccourci sans lanceur système du même nom n'est pas touché"
else
	non "un raccourci personnel a été modifié alors qu'il n'a aucune référence à suivre"
fi
#  Le nom et la commande d'une copie renommée sont des choix de la personne.
#  On s'assure D'ABORD que ce fichier a bien été traité — sinon le contrôle
#  suivant serait vert pour la mauvaise raison.
if [ "$(icone_de "$BANC/d/Bureau/perso.desktop")" = "lexos-terminal" ]; then
	ok "la copie renommée a bien été traitée (son icône est recalée)"
else
	non "la copie renommée n'a pas été traitée : le contrôle suivant ne prouverait rien"
fi
if grep -q '^Name=Mon terminal a moi$' "$BANC/d/Bureau/perso.desktop" \
   && grep -q '^Exec=xfce4-terminal --title=Perso$' "$BANC/d/Bureau/perso.desktop"; then
	ok "…et son nom et sa commande n'ont pas bougé pour autant"
else
	non "le nom ou la commande d'un raccourci a été écrasé — l'outil déborde de son rôle"
fi
#  Rien n'est écrit dans les catalogues système.
if grep -q '^Icon=org.xfce.terminal$' "$BANC/d/apps/xfce4-terminal.desktop"; then
	ok "les lanceurs système ne sont pas modifiés"
else
	non "l'outil a écrit dans le catalogue système"
fi
#  Aucun fichier temporaire laissé derrière.
RESTES="$(find "$BANC/d/Bureau" -name '*.lexos.*' 2>/dev/null | wc -l)"
[ "$RESTES" = "0" ] \
	&& ok "aucun fichier temporaire laissé sur le bureau" \
	|| non "$RESTES fichier(s) temporaire(s) oublié(s) sur le bureau"

# =============================================================================
titre "2. « --essai » N'ÉCRIT RIEN"
# =============================================================================
decor
AVANT="$(icone_de "$BANC/d/Bureau/xfce4-terminal.desktop")"
SORTIE="$(lance --essai)"
APRES="$(icone_de "$BANC/d/Bureau/xfce4-terminal.desktop")"
if [ "$AVANT" = "$APRES" ]; then
	ok "après « --essai », le fichier est inchangé"
else
	non "« --essai » a modifié le fichier : « $AVANT » -> « $APRES »"
fi
if grep -q 'lexos-terminal' <<< "$SORTIE"; then
	ok "…et il annonce quand même ce qu'il changerait"
else
	non "« --essai » ne dit pas ce qu'il ferait"
fi

# =============================================================================
titre "3. LE CAS D'ALEX : la copie périmée est recalée"
# =============================================================================
decor
lance >/dev/null
if [ "$(icone_de "$BANC/d/Bureau/xfce4-terminal.desktop")" = "lexos-terminal" ]; then
	ok "la copie du bureau prend l'icône du lanceur système"
else
	non "la copie du bureau garde « $(icone_de "$BANC/d/Bureau/xfce4-terminal.desktop") »"
fi
#  UNE SEULE LIGNE CHANGE. Un outil qui réécrirait le fichier perdrait les
#  actions et les traductions, exactement ce que la surcharge du lanceur a
#  pris soin de conserver.
DIFFS="$(diff "$BANC/d/apps/xfce4-terminal.desktop" "$BANC/d/Bureau/xfce4-terminal.desktop" | grep -c '^[<>]')"
[ "$DIFFS" = "2" ] \
	&& ok "une seule ligne diffère de l'original (actions et traductions gardées)" \
	|| non "$DIFFS lignes changées au lieu de 2"
#  Le bit d'exécution : sans lui, XFCE marque le raccourci « non fiable » et
#  demande confirmation à chaque double-clic.
[ -x "$BANC/d/Bureau/xfce4-terminal.desktop" ] \
	&& ok "le droit d'exécution du raccourci est conservé" \
	|| non "le raccourci a perdu son droit d'exécution : XFCE le dira « non fiable »"
#  ═══ CE CONTRÔLE RÉPÉTAIT LE PRÉCÉDENT — CORRIGÉ ═══
#  Premier jet : il revérifiait « l'icône vaut lexos-terminal », ce que la
#  ligne du dessus disait déjà. Les deux catalogues portant la même valeur,
#  il ne pouvait pas distinguer lequel avait servi : VERT quoi qu'il arrive.
#  On donne maintenant DEUX valeurs différentes, et on regarde laquelle sort.
decor
sed -i 's/^Icon=.*/Icon=icone-de-usr-share/' "$BANC/d/apps/xfce4-terminal.desktop"
sed -i 's/^Icon=.*/Icon=icone-de-usr-local/' "$BANC/d/local/xfce4-terminal.desktop"
lance >/dev/null
PRIS="$(icone_de "$BANC/d/Bureau/xfce4-terminal.desktop")"
if [ "$PRIS" = "icone-de-usr-local" ]; then
	ok "…et c'est bien /usr/local qui sert de référence, pas /usr/share"
else
	non "référence prise : « $PRIS » — /usr/share a gagné, l'ordre des catalogues est faux"
fi

# =============================================================================
titre "4. IL PEUT SE RELANCER, ET IL SAIT NE RIEN AVOIR À FAIRE"
# =============================================================================
SORTIE="$(lance)"
if grep -qE 'déjà d.accord' <<< "$SORTIE"; then
	ok "au second passage : rien à changer, et il le dit"
else
	non "second passage : « $(head -1 <<< "$SORTIE") »"
fi
#  Un bureau vide, ou pas de bureau du tout : il rend la main sans se plaindre.
rm -f "$BANC/d/Bureau"/*.desktop
SORTIE="$(lance)"; RC=$?
[ "$RC" = "0" ] && grep -q 'aucun raccourci' <<< "$SORTIE" \
	&& ok "bureau vide : il rend 0 et le dit" \
	|| non "bureau vide : code $RC, « $(head -1 <<< "$SORTIE") »"
SORTIE="$(env LEXOS_BUREAU_DIR="$BANC/nexistepas" bash "$OUTIL" 2>&1)"; RC=$?
[ "$RC" = "0" ] && grep -q 'aucun dossier Bureau' <<< "$SORTIE" \
	&& ok "sans dossier Bureau : il rend 0 et le dit" \
	|| non "sans dossier Bureau : code $RC, « $(head -1 <<< "$SORTIE") »"

# =============================================================================
titre "5. UNE COPIE SANS LIGNE « Icon= »"
# =============================================================================
#  Un raccourci fabriqué à la main peut ne pas en avoir. L'outil doit la
#  poser, pas échouer en silence.
decor
grep -v '^Icon=' "$BANC/d/apps/xfce4-terminal.desktop" > "$BANC/d/Bureau/xfce4-terminal.desktop"
lance >/dev/null
if [ "$(icone_de "$BANC/d/Bureau/xfce4-terminal.desktop")" = "lexos-terminal" ] \
   && [ "$(grep -c '^Icon=' "$BANC/d/Bureau/xfce4-terminal.desktop")" = "1" ]; then
	ok "sans ligne « Icon= », elle est posée — une seule fois"
else
	non "une copie sans « Icon= » n'a pas été corrigée correctement"
fi
if grep -q '^\[Desktop Entry\]' "$BANC/d/Bureau/xfce4-terminal.desktop"; then
	ok "…et l'en-tête [Desktop Entry] est intact"
else
	non "l'en-tête a été abîmé en posant l'icône"
fi

# =============================================================================
titre "6. IL EST ATTEIGNABLE"
# =============================================================================
#  Un outil que le dispatcheur n'appelle pas est un outil qu'Alex ne trouvera
#  jamais — c'est le contrôle 16 du dépôt, rejoué ici sur ce cas précis.
grep -q 'lexos-icones-bureau' "$DISPATCH" \
	&& ok "« lexos icones-bureau » est branché dans le dispatcheur" \
	|| non "le dispatcheur n'appelle pas lexos-icones-bureau"
#  ═══ ET CE CONTRÔLE-CI NE POUVAIT PAS TOMBER ═══
#  Premier jet : il cherchait « icones-bureau » dans une chaîne qui contenait
#  déjà un grep du FICHIER ENTIER — la branche du dispatcheur suffisait donc
#  à le rendre vert, même sans une ligne d'aide. On lit maintenant la seule
#  zone d'aide, repérée par la ligne d'aide d'un outil voisin déjà en place.
#  PAS DE PLAGE DE LETTRES ACCENTUÉES DANS UNE EXPRESSION. « [a-zà-ÿ-] »
#  a fait tomber la CI sur « grep: Invalid collation character » : selon la
#  locale du coureur, « à-ÿ » n'est pas une plage valide — les deux bornes
#  tiennent sur deux octets en UTF-8. Ici la même ligne passait, alors le
#  banc etait vert en local et rouge sur GitHub. On décrit maintenant la
#  FORME de la ligne d'aide, qui ne depend d'aucune locale.
AIDE_ZONE="$(grep -E '^[[:space:]]+\$\{A\}[^$]+\$\{R\}' "$DISPATCH")"
if grep -q 'icones-bureau' <<< "$AIDE_ZONE"; then
	ok "…et il a sa ligne dans l'aide de « lexos »"
else
	non "aucune ligne d'aide : Alex ne pourrait pas découvrir la commande"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
