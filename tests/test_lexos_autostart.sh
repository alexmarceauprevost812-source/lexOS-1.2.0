#!/usr/bin/env bash
# =============================================================================
#  L'assistant Nextcloud ne s'ouvre plus à chaque démarrage
# =============================================================================
#  ALEX : « la page pour ajouter un compte nextcloud s'affiche tout le temps
#  quand on ouvre l'ordinateur, peux-tu faire en sorte qu'on la voie pas tout
#  le temps ? »
#
#  nextcloud-desktop est dans optional-packages/48-comptes.list, et le hook
#  0250 installe ces listes DANS l'ISO. Le paquet pose son entrée dans
#  /etc/xdg/autostart : le client démarre à chaque session et, faute de
#  compte, ouvre son assistant. Tous les jours.
#
#  ═══ CE QUE CE BANC EXIGE, ET POURQUOI CHAQUE POINT COMPTE ═══
#  · le programme reste INSTALLÉ et lançable — on enlève le démarrage
#    automatique, pas la fonction. « lexos comptes » propose Nextcloud ;
#  · les VOISINS ne sont pas touchés. Un hook qui ratisse un répertoire
#    d'autostart peut très bien emporter nm-applet ou blueman au passage, et
#    ça ne se verrait qu'au prochain démarrage, sans réseau ni Bluetooth ;
#  · les DEUX verrous sont posés. Celui de /etc/skel survit à une mise à
#    jour du paquet mais ne sert qu'aux comptes créés APRÈS ; celui de
#    l'entrée système vaut tout de suite, pour les comptes déjà là. L'un
#    sans l'autre laisse la moitié du problème ;
#  · le fichier de skel porte le MÊME NOM que celui du système. C'est la
#    condition de la norme XDG : un nom différent n'annule rien du tout, et
#    le banc passerait au vert sur un correctif qui ne corrige rien ;
#  · le hook se relance sans doubler ses lignes. Une construction qui
#    rejoue un hook produirait sinon « Hidden=true » trois fois.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0256-lexos-autostart.hook.chroot"
LISTE="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages/48-comptes.list"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$HOOK" ] || { echo "introuvable : $HOOK"; exit 1; }

decor() {
	rm -rf "$BANC/sys" "$BANC/skel"
	mkdir -p "$BANC/sys" "$BANC/skel"
	printf '[Desktop Entry]\nName=Nextcloud\nExec=/usr/bin/nextcloud --background\nType=Application\n' \
		> "$BANC/sys/com.nextcloud.desktopclient.nextcloud.desktop"
	printf '[Desktop Entry]\nName=Réseau\nExec=nm-applet\nType=Application\n' \
		> "$BANC/sys/nm-applet.desktop"
	printf '[Desktop Entry]\nName=Bluetooth\nExec=blueman-applet\nType=Application\n' \
		> "$BANC/sys/blueman.desktop"
}
lancer() {
	LEXOS_AUTOSTART_SYS="$BANC/sys" LEXOS_AUTOSTART_SKEL="$BANC/skel" \
		sh "$HOOK" >"$BANC/journal" 2>&1
}

# =============================================================================
titre "1. LE HOOK TOURNE POUR DE VRAI, SUR UN DÉCOR FABRIQUÉ"
# =============================================================================
decor
if lancer; then
	ok "le hook s'exécute sans erreur"
else
	non "le hook a échoué : $(tail -2 "$BANC/journal" | tr '\n' ' ')"
fi

NC="com.nextcloud.desktopclient.nextcloud.desktop"

# =============================================================================
titre "2. LES DEUX VERROUS SONT POSÉS"
# =============================================================================
if [ -r "$BANC/skel/$NC" ]; then
	ok "l'annulation est posée dans /etc/skel, sous le MÊME nom que l'entrée système"
else
	non "aucun fichier « $NC » dans le skel : rien n'annule l'entrée du système"
fi
grep -q '^Hidden=true' "$BANC/skel/$NC" 2>/dev/null \
	&& ok "…et elle porte « Hidden=true », la façon prévue par la norme XDG" \
	|| non "le fichier du skel n'annule rien : pas de « Hidden=true »"
grep -q '^Hidden=true' "$BANC/sys/$NC" 2>/dev/null \
	&& ok "l'entrée du système est neutralisée aussi — les comptes déjà créés en profitent" \
	|| non "l'entrée système n'est pas touchée : un compte existant reverrait l'assistant"

# =============================================================================
titre "3. LE PROGRAMME RESTE LÀ, ET LES VOISINS AUSSI"
# =============================================================================
#  Le piège de ce genre de correctif : désinstaller au lieu de désactiver.
if grep -q '^nextcloud-desktop' "$LISTE" 2>/dev/null; then
	ok "nextcloud-desktop reste livré : on enlève le démarrage, pas la fonction"
else
	non "nextcloud-desktop a disparu de 48-comptes.list — le correctif a désinstallé au lieu de désactiver"
fi
INTACTS=0
for V in nm-applet.desktop blueman.desktop; do
	if grep -q '^Hidden=true' "$BANC/sys/$V" 2>/dev/null; then
		non "$V a été neutralisé au passage — le réseau ou le Bluetooth ne démarreraient plus"
		INTACTS=1
	fi
	[ -e "$BANC/skel/$V" ] && { non "$V a reçu une annulation dans le skel, sans raison"; INTACTS=1; }
done
[ "$INTACTS" = 0 ] && ok "nm-applet et blueman sont intacts — le hook n'a pas ratissé large"

# =============================================================================
titre "4. LE NOM LISIBLE EST REPRIS, PAS LE NOM DE FICHIER"
# =============================================================================
#  Sans ça, un panneau « applications au démarrage » afficherait
#  « com.nextcloud.desktopclient.nextcloud.desktop » et personne ne saurait
#  ce que c'est — ni comment le remettre.
grep -q '^Name=Nextcloud$' "$BANC/skel/$NC" 2>/dev/null \
	&& ok "le fichier du skel reprend le nom lisible (« Nextcloud »)" \
	|| non "le fichier du skel ne porte pas le nom lisible de l'entrée d'origine"

# =============================================================================
titre "5. DEUX PASSAGES NE DOUBLENT RIEN"
# =============================================================================
lancer
#  « grep -c » rend 0 ET sort en erreur quand il ne trouve rien : sans le
#  « || true », le « || echo 0 » ajoutait un SECOND zéro et le message
#  annonçait « apparaît 0 0 fois ».
N1="$( { grep -c '^Hidden=true' "$BANC/sys/$NC" 2>/dev/null || true; } | head -1)"
[ -n "$N1" ] || N1=0
[ "$N1" = 1 ] \
	&& ok "relancé, le hook n'ajoute pas une deuxième ligne « Hidden=true »" \
	|| non "« Hidden=true » apparaît $N1 fois après deux passages"

# =============================================================================
titre "6. UN NOM DE FICHIER QUI CHANGE EN AMONT NE LE REND PAS AVEUGLE"
# =============================================================================
#  Le fichier a déjà changé de nom une fois chez Nextcloud. Un nom recopié
#  serait faux le jour suivant, et le hook resterait silencieux.
rm -rf "$BANC/sys" "$BANC/skel"; mkdir -p "$BANC/sys" "$BANC/skel"
printf '[Desktop Entry]\nName=Nextcloud\nExec=nextcloud\nType=Application\n' \
	> "$BANC/sys/nextcloud.desktop"
lancer
grep -q '^Hidden=true' "$BANC/sys/nextcloud.desktop" 2>/dev/null \
	&& ok "l'ancien nom « nextcloud.desktop » est trouvé aussi" \
	|| non "le hook ne reconnaît qu'un seul nom de fichier : un changement en amont le rendrait muet"

# =============================================================================
titre "7. RIEN À FAIRE SE DIT, ET NE PLANTE PAS"
# =============================================================================
rm -rf "$BANC/sys" "$BANC/skel"; mkdir -p "$BANC/sys" "$BANC/skel"
printf '[Desktop Entry]\nName=Réseau\nExec=nm-applet\nType=Application\n' > "$BANC/sys/nm-applet.desktop"
if lancer; then
	grep -q 'aucune entrée de démarrage automatique' "$BANC/journal" \
		&& ok "sans Nextcloud installé, le hook le dit et rend la main" \
		|| non "sans Nextcloud, le hook ne dit rien de clair : $(tail -2 "$BANC/journal" | tr '\n' ' ')"
else
	non "le hook échoue quand il n'y a rien à faire"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
