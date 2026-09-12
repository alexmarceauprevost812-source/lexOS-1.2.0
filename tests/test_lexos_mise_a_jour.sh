#!/usr/bin/env bash
# =============================================================================
#  « sudo miss a jour » — poser le dépôt sans reconstruire l'ISO
# =============================================================================
#  LE PROBLÈME. Chaque modification d'un script ou d'une feuille CSS demandait
#  une ISO complète : une heure de CI, la gravure, la réinstallation. Ces
#  fichiers-là sont de simples scripts — ils n'ont aucune raison d'exiger une
#  image.
#
#  CE N'EST PAS LE CANAL DE MISE À JOUR DÉFINITIF (paquet .deb + dépôt APT),
#  et ce banc ne prétend pas qu'il l'est.
#
#  ═══ POURQUOI CE FICHIER NE S'APPELLE PAS test_lexos_maj.sh ═══
#  Ce nom est PRIS, et par un autre sujet : test_lexos_maj.sh éprouve la PAGE
#  des mises à jour des Paramètres (« la page sait, elle ne devine plus »).
#  Écraser un banc existant pour respecter un nom aurait supprimé sa
#  couverture sans que personne ne le voie.
#
#  ═══ CE QUE CE BANC TIENT, ET DANS QUEL ORDRE D'IMPORTANCE ═══
#  1. « --essai » n'écrit RIEN. C'est l'assertion la plus importante : un
#     essai qui écrit est pire que pas d'essai du tout, parce qu'on lui fait
#     confiance pour regarder avant d'agir. On compare les empreintes de
#     TOUTE la destination, avant et après.
#  2. Ce qui vit dans l'image (/boot, build.conf, version) n'est JAMAIS
#     touché, même avec --tout. On pose des témoins et on les relit.
#  3. Toutes les portes mènent au même endroit, et AUCUNE ne duplique la
#     logique de copie.
#
#  ═══ ON N'ENVOIE PLUS UNE VARIABLE DANS UN TUYAU VERS grep. JAMAIS. ═══
#  CE BANC A ROUGI EN CI POUR CETTE RAISON, ET LA CAUSE N'AVAIT RIEN À VOIR
#  AVEC CE QU'IL ÉPROUVE :
#      tests/test_lexos_mise_a_jour.sh: line 355: printf: write error: Broken pipe
#      ❌ le dispatcheur n'appelle pas l'outil par exec
#  Le dispatcheur fait 43 ko ; « exec /usr/bin/lexos-mise-a-jour » est au tiers
#  du fichier. « grep -q » S'ARRÊTE AU PREMIER RÉSULTAT et ferme le tuyau —
#  printf, qui écrivait encore, reçoit une erreur. Avec « pipefail », c'est
#  TOUT LE TUYAU qui échoue, donc la condition est fausse ALORS QUE LE MOTIF A
#  ÉTÉ TROUVÉ. C'est une course : elle se perd sur une machine chargée, et se
#  gagne sur la nôtre — le pire genre de défaut.
#  ET LE FAUX ROUGE N'EST PAS LE PLUS GRAVE. Dans un contrôle inversé — « si
#  ce motif est là, ROUGIS » — la même course donne un FAUX VERT : le motif
#  interdit est trouvé, le tuyau échoue, et le banc annonce que tout va bien.
#  La forme sûre est « grep motif <<< "$VAR" » : bash passe le texte par un
#  fichier, il n'y a plus de tuyau à casser. La section 8 le vérifie sur ce
#  banc lui-même.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IC="$RACINE/config/includes.chroot"
OUTIL="$IC/usr/bin/lexos-mise-a-jour"
MISS="$IC/usr/bin/miss"
DISPATCH="$IC/usr/bin/lexos"
GARDE="$RACINE/config/hooks/normal/0255-lexos-noms-reserves.hook.chroot"
BANC="$(mktemp -d)"

#  ═══ LE MÉNAGE DIT CE QU'IL N'A PAS PU FAIRE ═══
#  Un « rm » qui échoue à la fin laisse des dossiers root dans /tmp à chaque
#  exécution, et son message brut n'apprend rien à qui le lit. C'est arrivé à
#  Alex : trois « Permission denied » sous le résumé, sans un mot sur leur
#  cause. Il n'y en a qu'une, et on la NOMME.
nettoyer() {
	rm -rf "$BANC" 2>/dev/null
	if [ -d "$BANC" ]; then
		printf '\n  \033[31m❌\033[0m il reste des fichiers non supprimables dans %s\n' "$BANC"
		printf "     C'est que l'outil s'est ÉLEVÉ sous sudo pendant le banc : un\n"
		printf "     dossier créé par root ne se vide pas depuis un compte ordinaire.\n"
	fi
}
trap nettoyer EXIT

#  ═══ UN FAUX « sudo » EN TÊTE DU PATH, POUR TOUT LE BANC ═══
#  Un banc doit tourner SEUL — sans mot de passe — et ne rien laisser derrière
#  lui. Si l'outil se relance sous sudo, celui-ci laisse un témoin et échoue :
#  la section 8 le dira nommément, au lieu de trois lignes de « rm » que
#  personne ne sait relier à quoi que ce soit.
mkdir -p "$BANC/faux"
{
	printf '#!/bin/sh\n'
	printf ': > "%s"\n' "$BANC/sudo-appele"
	printf 'echo "banc : sudo a ete appele" >&2\n'
	printf 'exit 1\n'
} > "$BANC/faux/sudo"
chmod 755 "$BANC/faux/sudo"
export PATH="$BANC/faux:$PATH"
BASH_ABS="$(command -v bash)"

#  ═══ ON SE SOUVIENT DE CE QUI A ÉCHOUÉ ═══
#  Un ❌ à la ligne 12 d'un banc qui en affiche quarante a défilé bien avant
#  qu'on lise le résumé. Alex n'a pu coller que « 34 réussis, 1 échoués » : il
#  a fallu deviner LEQUEL. On les redit donc à la fin, juste avant le compte.
reussis=0; echoues=0; ECHECS=""
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1))
          ECHECS="${ECHECS}  · ${1}
"; }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$MISS" "$DISPATCH" "$GARDE"; do
	if [ ! -r "$F" ]; then
		non "fichier introuvable : $F"
		printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
		exit 1
	fi
done

# =============================================================================
titre "1. Un faux clone, et un faux système"
# =============================================================================
#  On monte un dépôt crédible : les deux marqueurs que l'outil exige, des
#  fichiers dans chaque arbre autorisé, et un outil en 755 pour éprouver que
#  le bit d'exécution survit.
SRC="$BANC/clone"
DST="$BANC/systeme"
mkdir -p "$SRC/config/includes.chroot/usr/bin" \
         "$SRC/config/includes.chroot/usr/share/lexos" \
         "$SRC/config/includes.chroot/usr/lib/lexos" \
         "$SRC/config/includes.chroot/boot" \
         "$SRC/config/includes.chroot/etc/lexos" \
         "$DST/usr/bin" "$DST/etc/lexos" "$DST/boot"
: > "$SRC/lexos.conf"
printf '#!/bin/sh\necho neuf\n' > "$SRC/config/includes.chroot/usr/bin/lexos-truc"
chmod 755 "$SRC/config/includes.chroot/usr/bin/lexos-truc"
printf 'body{color:red}\n'      > "$SRC/config/includes.chroot/usr/share/lexos/ui.css"
printf 'panneau neuf\n'         > "$SRC/config/includes.chroot/usr/share/lexos/gtk-panneau.css"
printf 'print("neuf")\n'        > "$SRC/config/includes.chroot/usr/lib/lexos/settings.py"

#  ═══ LES TÉMOINS : CE QUI NE DOIT JAMAIS BOUGER ═══
#  On les met des DEUX côtés : dans le clone (pour que l'outil ait la
#  tentation de les copier) et dans le système (pour vérifier qu'ils sont
#  intacts). Sans le côté clone, le contrôle serait vert faute de candidat.
printf 'NOYAU DE L IMAGE\n'     > "$SRC/config/includes.chroot/boot/vmlinuz"
printf 'LEXOS_BUILD=neuf\n'     > "$SRC/config/includes.chroot/etc/lexos/build.conf"
printf '999\n'                  > "$SRC/config/includes.chroot/etc/lexos/version"
printf 'NOYAU D ORIGINE\n'      > "$DST/boot/vmlinuz"
printf 'LEXOS_BUILD=110\n'      > "$DST/etc/lexos/build.conf"
printf '110\n'                  > "$DST/etc/lexos/version"
#  Un fichier déjà présent, DIFFÉRENT : c'est lui qui doit être sauvegardé.
printf '#!/bin/sh\necho vieux\n' > "$DST/usr/bin/lexos-truc"
chmod 755 "$DST/usr/bin/lexos-truc"

lance() { # lance <arguments…>
	LEXOS_MAJ_DEST="$DST" \
	LEXOS_MAJ_ETC="$DST/etc/lexos" \
	LEXOS_MAJ_SRC_DEFAUT="$BANC/inexistant" \
	bash "$OUTIL" --depuis "$SRC" "$@" 2>&1
}
empreintes() { find "$DST" -type f -exec md5sum {} + 2>/dev/null | sort; }

ok "faux clone monté ($(find "$SRC/config/includes.chroot" -type f | wc -l) fichiers)"

# =============================================================================
titre "2. « --essai » n'écrit RIEN — l'assertion qui compte"
# =============================================================================
#  Un essai qui écrit est pire que pas d'essai du tout : on lui fait confiance
#  pour vérifier AVANT d'agir. On ne se contente donc pas de regarder un
#  fichier ou deux — on prend l'empreinte de TOUTE la destination.
AVANT="$(empreintes)"
SORTIE_ESSAI="$(lance --essai)"
APRES="$(empreintes)"
if [ "$AVANT" = "$APRES" ]; then
	ok "après « --essai », pas un octet n'a changé dans la destination"
else
	non "« --essai » A MODIFIÉ la destination :"
	diff <(printf '%s\n' "$AVANT") <(printf '%s\n' "$APRES") | head -8 | sed 's/^/       /'
fi
if grep -q 'usr/bin/lexos-truc' <<< "$SORTIE_ESSAI"; then
	ok "… et il DIT quand même ce qui serait copié"
else
	non "« --essai » ne dit pas ce qu'il copierait — il ne sert à rien"
fi
if [ ! -e "$DST/etc/lexos/maj" ]; then
	ok "« --essai » n'écrit pas non plus la trace /etc/lexos/maj"
else
	non "« --essai » a écrit la trace : la machine se croirait à jour"
fi

# =============================================================================
titre "3. Le vrai passage"
# =============================================================================
SORTIE="$(lance)"

if [ -x "$DST/usr/bin/lexos-truc" ] && grep -q neuf "$DST/usr/bin/lexos-truc"; then
	ok "le fichier est copié ET reste exécutable (755 préservé)"
else
	non "le fichier n'est pas copié, ou a perdu son bit d'exécution"
fi
#  Un chmod perdu et la commande n'existe plus : on lit le mode, pas le seul
#  drapeau -x.
MODE="$(stat -c '%a' "$DST/usr/bin/lexos-truc" 2>/dev/null)"
[ "$MODE" = "755" ] \
	&& ok "le mode est exactement 755" \
	|| non "le mode est $MODE au lieu de 755"

[ -r "$DST/usr/share/lexos/ui.css" ] \
	&& ok "usr/share/lexos est copié lui aussi" \
	|| non "usr/share/lexos n'a pas été copié"
[ -r "$DST/usr/lib/lexos/settings.py" ] \
	&& ok "usr/lib/lexos est copié lui aussi" \
	|| non "usr/lib/lexos n'a pas été copié"

#  ═══ LA SAUVEGARDE ═══
#  Un fichier qu'Alex aurait ajusté à la main ne doit pas disparaître sans
#  trace.
BAK="$(find "$DST/usr/bin" -name 'lexos-truc.lexos-bak-*' | head -1)"
if [ -n "$BAK" ] && grep -q vieux "$BAK"; then
	ok "l'ancien fichier est sauvegardé en $(basename "$BAK")"
else
	non "aucune sauvegarde .lexos-bak-* de l'ancien fichier"
fi

#  ═══ LA TRACE ═══
#  Sans elle, un système mis à jour et un système d'origine se ressemblent
#  trait pour trait, et on perd deux heures à déboguer un fichier qu'on
#  croyait posé.
if [ -r "$DST/etc/lexos/maj" ]; then
	if grep -qE '[0-9a-f]{7}|hors git' "$DST/etc/lexos/maj"; then
		ok "/etc/lexos/maj note la date et le commit : $(tail -1 "$DST/etc/lexos/maj" | cut -c1-46)…"
	else
		non "/etc/lexos/maj existe mais ne contient pas de commit"
	fi
else
	non "/etc/lexos/maj n'est pas écrit — on ne saurait pas ce que porte la machine"
fi

# =============================================================================
titre "4. Ce qui vit dans l'image n'est JAMAIS touché"
# =============================================================================
#  Même avec --tout. /boot rendrait la machine non démarrable ; build.conf et
#  version feraient mentir le système sur ce qu'il est, et on ne saurait plus
#  quelle ISO il porte.
lance --tout >/dev/null 2>&1
for PAIRE in "boot/vmlinuz|NOYAU D ORIGINE" "etc/lexos/build.conf|LEXOS_BUILD=110" "etc/lexos/version|110"; do
	CHEMIN="${PAIRE%%|*}"; ATTENDU="${PAIRE##*|}"
	if grep -qxF "$ATTENDU" "$DST/$CHEMIN" 2>/dev/null; then
		ok "$CHEMIN est intact, même avec --tout"
	else
		non "$CHEMIN a été écrasé : « $(head -1 "$DST/$CHEMIN" 2>/dev/null) » au lieu de « $ATTENDU »"
	fi
done

# =============================================================================
titre "5. Les refus"
# =============================================================================
#  ═══ UN CHEMIN AU HASARD EST REFUSÉ ═══
#  Sans ce contrôle, un chemin tapé de travers déverserait n'importe quoi dans
#  /usr/bin — et il n'y a pas de retour en arrière pour ça.
mkdir -p "$BANC/pasunclone"
if LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
   bash "$OUTIL" --depuis "$BANC/pasunclone" --essai >/dev/null 2>&1; then
	non "un dossier qui n'est pas un clone a été ACCEPTÉ"
else
	ok "un dossier qui n'est pas un clone est refusé (code non nul)"
fi

#  ═══ IL FAUT LES DEUX MARQUEURS, PAS UN ═══
#  Un dossier avec « config/includes.chroot » mais sans « lexos.conf » doit
#  être refusé lui aussi. Le cas ci-dessus (un dossier VIDE) ne le prouve
#  pas : il échoue déjà sur le premier marqueur, et une mutation qui retire
#  le second passerait inaperçue. C'est le piège « protégé deux fois » —
#  trouvé par une mutation, exactement comme il se doit.
mkdir -p "$BANC/moitie/config/includes.chroot"
if LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
   bash "$OUTIL" --depuis "$BANC/moitie" --essai >/dev/null 2>&1; then
	non "un dossier SANS lexos.conf a été accepté — un seul marqueur suffisait"
else
	ok "un dossier sans lexos.conf est refusé (les DEUX marqueurs comptent)"
fi

#  ═══ LA LISTE DES INTERDITS, ÉPROUVÉE DIRECTEMENT ═══
#  ET VOICI POURQUOI IL LE FAUT. Les témoins /boot et build.conf plus haut
#  restent intacts même si on VIDE la liste des interdits — parce que la
#  liste BLANCHE (usr/bin, usr/lib/lexos, usr/share/…) ne visite déjà ni
#  « boot » ni « etc ». interdit() est une SECONDE ceinture qui, pour ces
#  chemins-là, n'est jamais atteinte : trois mutations l'ont montré en
#  restant vertes.
#  Une ceinture qu'aucun test ne serre finit par se détacher sans qu'on le
#  sache. On extrait donc la fonction et sa liste, et on les appelle
#  directement — le jour où quelqu'un élargit ARBRES, elle sera prête.
{
	sed -n '/^INTERDITS="/,/^"$/p' "$OUTIL"
	sed -n '/^interdit() {/,/^}/p' "$OUTIL"
	cat <<'JS'
for CAS in "boot/vmlinuz|1" "etc/lexos/build.conf|1" "etc/lexos/version|1" \
           "etc/lexos/release|1" "lib/live/config|1" \
           "usr/bin/lexos-truc|0" "usr/share/lexos/ui.css|0" "etc/lexos/maj|0"; do
	C="${CAS%%|*}"; ATTENDU="${CAS##*|}"
	if interdit "$C"; then VU=1; else VU=0; fi
	[ "$VU" = "$ATTENDU" ] && printf 'OK   %s -> %s\n' "$C" "$VU" \
	                       || printf 'RATE %s -> %s (attendu %s)\n' "$C" "$VU" "$ATTENDU"
done
JS
} > "$BANC/interdits.sh"
RES="$(bash "$BANC/interdits.sh" 2>&1)"
if grep -q 'RATE' <<< "$RES"; then
	non "interdit() se trompe :"
	printf '%s\n' "$RES" | sed 's/^/       /'
else
	ok "interdit() répond juste sur les huit chemins (5 refusés, 3 permis)"
fi

#  ═══ ET LE POINT D'APPEL, PAS SEULEMENT LA FONCTION ═══
#  Le test ci-dessus prouve qu'interdit() répond juste ; il ne prouve pas
#  qu'on l'APPELLE. Une mutation qui retirait l'appel de copier_un() restait
#  verte, parce qu'aucun chemin interdit n'entre dans le circuit avec la
#  liste blanche par défaut.
#  On élargit donc la liste à « etc » — le clone en a un, avec build.conf
#  dedans — et on exige que le témoin soit TOUJOURS intact. Si l'appel
#  disparaît, build.conf est écrasé et ce contrôle rougit.
printf 'LEXOS_BUILD=110\n' > "$DST/etc/lexos/build.conf"
LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
LEXOS_MAJ_ARBRES="etc" \
	bash "$OUTIL" --depuis "$SRC" --tout >/dev/null 2>&1
if grep -qxF 'LEXOS_BUILD=110' "$DST/etc/lexos/build.conf" 2>/dev/null; then
	ok "même en poussant « etc » dans le circuit, build.conf est refusé à la copie"
else
	non "build.conf a été écrasé quand « etc » entre dans le circuit : le garde-fou n'est pas appelé"
fi

#  ═══ UN DÉPÔT EN COURS D'ÉDITION EST REFUSÉ ═══
#  Copier un arbre qui porte des modifications non commitées, c'est poser du
#  code à moitié écrit — et le symptôme sera incompréhensible, parce que le
#  fichier fautif n'existe dans aucun commit qu'on puisse relire.
if ! command -v git >/dev/null 2>&1; then
	saut "git absent : le refus d'un dépôt sale n'a PAS été éprouvé"
else
	git -C "$SRC" init -q 2>/dev/null
	git -C "$SRC" config user.email banc@lexos >/dev/null 2>&1
	git -C "$SRC" config user.name  banc       >/dev/null 2>&1
	git -C "$SRC" add -A >/dev/null 2>&1
	git -C "$SRC" commit -qm "banc" >/dev/null 2>&1
	printf 'sale\n' > "$SRC/config/includes.chroot/usr/bin/lexos-sale"
	if LEXOS_MAJ_DEST="$DST" LEXOS_MAJ_ETC="$DST/etc/lexos" \
	   bash "$OUTIL" --depuis "$SRC" --essai >/dev/null 2>&1; then
		non "un dépôt avec des modifications non commitées a été ACCEPTÉ"
	else
		ok "un dépôt en cours d'édition est refusé (code non nul)"
	fi
	rm -f "$SRC/config/includes.chroot/usr/bin/lexos-sale"
fi

#  ═══ SANS --paquets, AUCUN apt-get ═══
#  Vérifié en LISANT le programme, pas en le lançant : on ne veut pas
#  déclencher une vraie mise à jour Debian sur la machine de construction pour
#  savoir qu'elle n'aurait pas dû se déclencher.
CODE="$(sed 's/[[:space:]]*#.*$//' "$OUTIL")"
NB_APT="$(grep -c 'apt-get\|apt ' <<< "$CODE")"
if [ "$NB_APT" = "0" ]; then
	ok "aucun appel à apt dans le programme — Debian n'est touché que par « lexos upgrade »"
else
	non "$NB_APT appel(s) à apt dans le code : la mise à jour Debian pourrait partir seule"
fi

#  Sans --skel, on ne touche pas au compte courant.
if grep -q "n'a PAS été reporté" <<< "$SORTIE"; then
	ok "sans --skel, le compte courant n'est pas touché — et c'est DIT"
else
	non "rien ne signale que /etc/skel n'a pas été reporté : on croirait la mise à jour complète"
fi

# =============================================================================
titre "6. Toutes les portes mènent au même endroit"
# =============================================================================
for F in "$OUTIL" "$MISS"; do
	[ -x "$F" ] \
		&& ok "$(basename "$F") est exécutable" \
		|| non "$(basename "$F") n'est pas exécutable"
done

#  L'enrobage doit pardonner l'accent et l'espace : c'est une commande qu'on
#  tape vite, dix fois par jour.
FAUX="$BANC/cible"
printf '#!/bin/sh\nprintf "RECU:[%%s]\\n" "$*"\n' > "$FAUX"; chmod 755 "$FAUX"
sed "s|^CIBLE=.*|CIBLE=$FAUX|" "$MISS" > "$BANC/miss"; chmod 755 "$BANC/miss"

essai_porte() { # essai_porte <libellé> <args…>
	local lib="$1"; shift
	local vu
	vu="$(sh "$BANC/miss" "$@" 2>&1)"
	case "$vu" in
		RECU:*) ok "« miss $lib » atteint lexos-mise-a-jour ($vu)" ;;
		*)      non "« miss $lib » n'atteint pas la cible : $vu" ;;
	esac
}
essai_porte "a jour"  a jour
essai_porte "à jour"  à jour
essai_porte "ajour"   ajour
essai_porte "(rien)"
essai_porte "a jour --essai" a jour --essai

#  ═══ ET IL REFUSE CE QU'IL NE COMPREND PAS ═══
#  Un enrobage qui avale n'importe quoi en silence fera croire un jour qu'une
#  mise à jour a eu lieu alors qu'il y avait une faute de frappe.
SORTIE_F="$(sh "$BANC/miss" mizajour 2>&1)"; CODE_F=$?
if [ "$CODE_F" -ne 0 ] && grep -q 'sudo miss a jour' <<< "$SORTIE_F"; then
	ok "« miss mizajour » est refusé, et le message dit quoi taper"
else
	non "« miss mizajour » : code $CODE_F, sortie « $SORTIE_F »"
fi

#  ═══ LE DISPATCHEUR AUSSI ═══
CODE_D="$(sed 's/[[:space:]]*#.*$//' "$DISPATCH")"
if grep -q 'maj|mise-a-jour' <<< "$CODE_D"; then
	ok "« lexos maj » et « lexos mise-a-jour » sont dans le dispatcheur"
else
	non "le dispatcheur ne connaît pas « maj »"
fi
if grep -q 'exec /usr/bin/lexos-mise-a-jour' <<< "$CODE_D"; then
	ok "le dispatcheur fait EXEC vers l'outil — il ne réimplémente rien"
else
	non "le dispatcheur n'appelle pas l'outil par exec"
fi
#  L'aide doit distinguer les trois, sinon personne ne saura laquelle taper.
if grep -q 'Mettre à jour LexOS lui-même depuis le dépôt' "$DISPATCH"; then
	ok "l'aide distingue « maj » de « update » et « upgrade »"
else
	non "l'aide ne dit pas en quoi « maj » diffère des deux autres"
fi

#  ═══ AUCUNE LOGIQUE DE COPIE DUPLIQUÉE ═══
#  ON LIT LE CODE, PAS LES COMMENTAIRES. Les deux fichiers EXPLIQUENT en
#  commentaire qu'ils ne doivent contenir ni rsync, ni « cp -a », ni
#  « .lexos-bak » — et un grep naïf trouverait ces mots-là dans l'explication
#  elle-même. C'est le piège qui s'est refermé cinq fois dans ce chantier ;
#  on décommente d'abord.
DOUBLON=0
for F in "$MISS" "$DISPATCH"; do
	NU="$(sed 's/[[:space:]]*#.*$//' "$F")"
	for MOTIF in 'rsync' 'cp -a' '\.lexos-bak'; do
		if grep -q -- "$MOTIF" <<< "$NU"; then
			non "$(basename "$F") contient « $MOTIF » : la logique de copie est dupliquée"
			DOUBLON=1
		fi
	done
done
[ "$DOUBLON" = 0 ] && ok "ni miss ni lexos ne dupliquent la logique de copie"

# =============================================================================
titre "7. Le garde de construction — « miss » est-il libre ?"
# =============================================================================
#  LA QUESTION NE PEUT PAS SE RÉPONDRE DEPUIS LE DÉPÔT. « apt-file » demande
#  un index qu'on n'a pas toujours, et « dpkg -S » sur la machine de
#  développement ne répond que pour les paquets installés LÀ — pas pour la
#  suite Debian qu'on assemble. La seule machine qui connaisse la vérité,
#  c'est le chroot en cours de construction.
#
#  Le hook 0255 pose donc la question À DPKG, dans le chroot, et ARRÊTE la
#  construction en cas de collision. Ici on éprouve le hook lui-même.
if ! command -v dpkg >/dev/null 2>&1; then
	saut "dpkg absent : le garde n'a PAS été éprouvé"
else
	#  Cas négatif : un dossier de faux binaires, dpkg n'en connaît aucun.
	FAUXBIN="$BANC/bin"
	mkdir -p "$FAUXBIN"; : > "$FAUXBIN/lexos-truc"; : > "$FAUXBIN/miss"
	if LEXOS_BIN_DIR="$FAUXBIN" sh "$GARDE" >/dev/null 2>&1; then
		ok "sans collision, le garde laisse passer"
	else
		non "le garde échoue alors qu'il n'y a aucune collision"
	fi

	#  ═══ CAS POSITIF : ON PROVOQUE UNE VRAIE COLLISION ═══
	#  Un contrôle qui ne sait que dire « rien à signaler » ne prouve rien.
	#  On fait passer un binaire RÉELLEMENT possédé par un paquet pour un des
	#  nôtres, et on exige que le garde s'arrête. Sans ça, on ne saurait pas
	#  s'il regarde vraiment.
	POSSEDE=""
	for C in ls cat sh; do
		if dpkg -S "/usr/bin/$C" >/dev/null 2>&1; then POSSEDE="$C"; break; fi
	done
	if [ -z "$POSSEDE" ]; then
		saut "aucun binaire dpkg trouvé ici : le cas positif n'a PAS été éprouvé"
	else
		sed "s/^\t\tlexos\*|miss) ;;/\t\tlexos*|miss|$POSSEDE) ;;/" "$GARDE" > "$BANC/garde"
		if LEXOS_BIN_DIR=/usr/bin sh "$BANC/garde" >/dev/null 2>&1; then
			non "le garde N'A PAS vu une collision réelle (/usr/bin/$POSSEDE) — il ne protège rien"
		else
			ok "face à une collision réelle (/usr/bin/$POSSEDE), le garde ARRÊTE la construction"
		fi
	fi
fi

#  Et il examine bien « miss », pas seulement les noms en « lexos » : c'est
#  précisément le nom générique qui a motivé tout ce contrôle.
if grep -q 'lexos\*|miss)' "$GARDE"; then
	ok "le garde surveille « miss » nommément"
else
	non "le garde ne surveille pas « miss » — le nom le plus exposé"
fi

# =============================================================================
titre "8. Le banc n'a pas besoin de root — et la porte des droits tient"
# =============================================================================
#  POURQUOI CETTE SECTION EXISTE. Alex a lancé ce banc depuis son compte. À
#  chaque passage non-essai, l'outil se relançait sous sudo, écrivait dans le
#  faux système SOUS ROOT, et le ménage de fin échouait sur trois fichiers.
#  Un banc qui réclame un mot de passe ne tourne plus tout seul, et un banc
#  qui laisse des dossiers root dans /tmp salit la machine à chaque essai.
if [ -e "$BANC/sudo-appele" ]; then
	non "l'outil s'est élevé sous sudo pendant le banc — il écrirait en root dans /tmp"
else
	ok "le banc n'a jamais eu besoin de sudo — rien de root ne traîne dans /tmp"
fi

#  ═══ ET LA PORTE RESTE GARDÉE, DANS L'AUTRE SENS ═══
#  Le contrôle ci-dessus dit « il ne s'élève pas ». Seul, il serait TOUT AUSSI
#  content d'un outil qui n'exige plus jamais les droits — et qui, le jour où
#  quelqu'un tape la commande sans sudo, échouerait à mi-chemin en laissant
#  /usr à moitié écrit. On éprouve donc le sens inverse : destination NON
#  inscriptible et aucun sudo joignable — l'outil doit refuser en le disant.
#  En root la question ne se pose pas (EUID vaut 0, et root écrit partout) :
#  on le DIT plutôt que d'afficher un vert qui ne prouve rien.
if [ "$(id -u)" -eq 0 ]; then
	saut "banc lancé en root : le refus faute de droits n'a PAS été éprouvé"
else
	mkdir -p "$BANC/verrou"
	chmod 500 "$BANC/verrou"
	VU="$(LEXOS_MAJ_DEST="$BANC/verrou" LEXOS_MAJ_ETC="$BANC/verrou/etc" \
	      PATH=/inexistant "$BASH_ABS" "$OUTIL" --depuis "$SRC" 2>&1)"
	CODE=$?
	if [ "$CODE" -ne 0 ] && grep -q 'droits administrateur' <<< "$VU"; then
		ok "destination non inscriptible, sudo injoignable : l'outil refuse, et le dit"
	else
		non "aucune demande de droits sur une destination non inscriptible : code $CODE, sortie « $VU »"
	fi
	chmod 700 "$BANC/verrou"

	#  ═══ ET SURTOUT AVEC LA DESTINATION DE PRODUCTION ═══
	#  Le contrôle ci-dessus passe par la couture du banc. Celui-ci n'en met
	#  AUCUNE : sans LEXOS_MAJ_DEST, la destination est celle de la vraie vie
	#  (« / »), et c'est ce chemin-là qu'il faut pouvoir montrer gardé — une
	#  couture qu'on éprouve à la place de la valeur réelle finit par diverger
	#  d'elle sans que personne ne le voie.
	#  ON POINTE EXPRÈS UNE SOURCE QUI N'EST PAS UN CLONE : si un jour la porte
	#  des droits saute, l'outil s'arrête au marqueur suivant, et ce banc
	#  n'aura jamais eu l'occasion d'écrire quoi que ce soit dans le vrai /usr.
	#  Le message attendu tranche entre les deux refus.
	VU="$(PATH=/inexistant "$BASH_ABS" "$OUTIL" --depuis "$BANC/pasunclone" 2>&1)"
	CODE=$?
	if [ "$CODE" -ne 0 ] && grep -q 'droits administrateur' <<< "$VU"; then
		ok "sans couture, destination « / » : les droits sont réclamés AVANT toute lecture"
	else
		non "destination réelle « / » : pas de demande de droits (code $CODE) — « $VU »"
	fi
fi

#  ═══ ET AUCUN GROS TEXTE NE REPART DANS UN TUYAU VERS grep ═══
#  Le défaut qui a fait rougir ce banc en CI n'était pas dans ce qu'il
#  éprouve : « printf "$CODE_D" | grep -q » perdait la course contre le
#  « grep -q » qui s'arrête au premier résultat, et pipefail transformait ça
#  en condition fausse. On relit donc CE FICHIER, et on exige qu'il n'y reste
#  aucun tuyau de ce genre.
#  DEUX PRÉCAUTIONS, ET CHACUNE A DÉJÀ SERVI DANS CE CHANTIER :
#  · ON DÉCOMMENTE D'ABORD. Le paragraphe ci-dessus CITE le tuyau fautif pour
#    l'expliquer ; sans ce décommentage, le contrôle trouvait sa propre
#    explication et rougissait — c'est le faux vert (ici faux rouge) de la
#    famille « le contrôle lit un commentaire en croyant lire du code », qui
#    s'est refermé six fois sur ce dépôt.
#  · LE MOTIF S'ÉCRIT « [|] » ET NON « | », pour ne pas se trouver lui-même.
#  Et le décommentage passe par une VARIABLE, pas par « sed | grep » : ce
#  serait le tuyau même qu'on interdit.
MOTIF_TUYAU='(printf|echo)[^|]*[|] *grep'
NU_BANC="$(sed 's/[[:space:]]*#.*$//' "$0")"
if grep -qE "$MOTIF_TUYAU" <<< "$NU_BANC"; then
	non "ce banc renvoie encore une variable dans un tuyau vers grep — tuyau cassé possible"
	grep -nE -m3 "$MOTIF_TUYAU" <<< "$NU_BANC" | sed 's/^/       /'
else
	ok "aucune variable ne repart dans un tuyau vers grep — la course ne peut plus se perdre"
fi

# =============================================================================
titre "9. L'OUTIL SE COPIE SUR LUI-MÊME PENDANT QU'IL TOURNE"
# =============================================================================
#  ═══ CE QUE ÇA FAISAIT, RELEVÉ CHEZ ALEX ═══
#      Fichiers   source : /home/alex/lexOS-2.0
#      /usr/bin/lexos-mise-a-jour: ligne 332: erreur de syntaxe près du
#      symbole inattendu « done »
#
#  La liste des fichiers à copier contient « usr/bin/lexos-mise-a-jour » :
#  l'outil se recopiait sur lui-même en pleine exécution. « cp » écrit DANS le
#  fichier existant, et bash ne charge pas un script d'un coup — il le lit au
#  fil de l'exécution en gardant sa position. Le contenu changeait sous lui,
#  il reprenait au même décalage dans un fichier devenu différent, et tombait
#  au milieu d'un mot.
#
#  ═══ ON REPRODUIT LA SCÈNE EXACTE ═══
#  L'outil QUI TOURNE est celui du faux système ; le faux clone en contient
#  une version DIFFÉRENTE — la même, avec trois mille lignes insérées en
#  tête. C'est ce décalage qui fait trébucher bash s'il relit le fichier.
#  Et il reste du travail APRÈS la copie de l'outil (deux autres outils,
#  triés autour de lui, plus deux autres arbres) : sans ça, la boucle
#  finirait avant que bash n'ait à relire quoi que ce soit, et le banc serait
#  vert sans rien prouver — c'est exactement ce qui est arrivé à Alex ce
#  jour-là, et ce qui a fait croire que tout allait bien.
#
#  MESURÉ AVEC LA VERSION D'AVANT (« cp -a » sur place) :
#      lexos-mise-a-jour: line 369: lage: command not found
#      erreur : Aucun dépôt indiqué et « …/nulle-part » n'existe pas.
#      code de sortie 1, et /etc/lexos/maj JAMAIS écrit
#  « lage » est un morceau du mot « décalage » : bash a repris sa lecture au
#  milieu d'un mot, puis a ré-exécuté l'analyse des arguments depuis le
#  nouveau contenu. L'outil ne faisait plus du tout ce qu'on lui demandait.
SCENE="$BANC/soi-meme"
mkdir -p "$SCENE/clone/config/includes.chroot/usr/bin" \
         "$SCENE/clone/config/includes.chroot/usr/share/lexos" \
         "$SCENE/clone/config/includes.chroot/usr/lib/lexos" \
         "$SCENE/systeme/usr/bin" "$SCENE/systeme/etc/lexos"
: > "$SCENE/clone/lexos.conf"

#  La version « neuve » : la vraie, décalée de trois mille lignes.
{
	head -1 "$OUTIL"
	i=1; while [ "$i" -le 3000 ]; do printf '#  ligne de decalage %d
' "$i"; i=$((i+1)); done
	tail -n +2 "$OUTIL"
} > "$SCENE/clone/config/includes.chroot/usr/bin/lexos-mise-a-jour"
chmod 755 "$SCENE/clone/config/includes.chroot/usr/bin/lexos-mise-a-jour"

#  Du travail avant ET après, dans l'ordre de « find | sort ».
for N in aaa-avant zzz-apres; do
	printf '#!/bin/sh
echo %s
' "$N" > "$SCENE/clone/config/includes.chroot/usr/bin/lexos-$N"
	chmod 755 "$SCENE/clone/config/includes.chroot/usr/bin/lexos-$N"
done
printf 'body{}
'        > "$SCENE/clone/config/includes.chroot/usr/share/lexos/ui.css"
printf 'print("neuf")
' > "$SCENE/clone/config/includes.chroot/usr/lib/lexos/settings.py"

#  L'OUTIL QUI TOURNE EST CELUI DU SYSTÈME — c'est tout l'objet du contrôle.
cp "$OUTIL" "$SCENE/systeme/usr/bin/lexos-mise-a-jour"
chmod 755 "$SCENE/systeme/usr/bin/lexos-mise-a-jour"

SORTIE_SOI="$(cd "$SCENE" && LEXOS_MAJ_DEST="$SCENE/systeme" \
	LEXOS_MAJ_ETC="$SCENE/systeme/etc/lexos" \
	LEXOS_MAJ_SRC_DEFAUT="$SCENE/nulle-part" \
	bash "$SCENE/systeme/usr/bin/lexos-mise-a-jour" --depuis "$SCENE/clone" 2>&1)"
CODE_SOI=$?

[ "$CODE_SOI" = "0" ] \
	&& ok "l'outil se copie sur lui-même et finit NORMALEMENT (code 0)" \
	|| non "l'outil s'est arrêté avec le code $CODE_SOI en se copiant sur lui-même"

#  ═══ ET BASH NE DOIT PAS S'ÊTRE PLAINT ═══
#  Un code 0 ne suffit pas : bash peut se plaindre d'une ligne et continuer.
#  On cherche ses mots à lui, dans les deux langues — le coureur tourne en
#  anglais, la machine d'Alex en français.
#  PAR CHAÎNE ICI-MÊME, PAS PAR UN TUYAU : c'est la règle que ce banc se
#  donne à lui-même quelques lignes plus bas, et elle vient de me reprendre
#  en écrivant ceci. Sous pipefail, grep qui trouve ferme le tuyau, le
#  producteur prend un SIGPIPE, et une correspondance VRAIE ressort en échec.
MOTS_BASH='command not found|commande introuvable|syntax error|erreur de syntaxe|unexpected|inattendu'
PLAINTES="$(grep -icE "$MOTS_BASH" <<< "$SORTIE_SOI" || true)"
if [ "$PLAINTES" = "0" ]; then
	ok "bash ne se plaint de rien — il a lu un fichier stable de bout en bout"
else
	PREMIERE="$(grep -m1 -iE "$MOTS_BASH" <<< "$SORTIE_SOI" || true)"
	non "bash s'est plaint $PLAINTES fois : $PREMIERE"
fi

#  ═══ ET LE TRAVAIL EST FINI, PAS SEULEMENT COMMENCÉ ═══
#  /etc/lexos/maj est écrit À LA FIN. Sa présence prouve que l'exécution est
#  allée jusqu'au bout — c'est précisément ce qui manquait dans la version
#  d'avant, où les fichiers étaient posés mais la trace absente.
[ -r "$SCENE/systeme/etc/lexos/maj" ] \
	&& ok "la trace /etc/lexos/maj est écrite : l'exécution est allée jusqu'au bout" \
	|| non "/etc/lexos/maj absent — l'outil est mort avant la fin, comme chez Alex"

#  ═══ TOUS LES FICHIERS SONT POSÉS ═══
MANQUANTS=""
for REL in usr/bin/lexos-mise-a-jour usr/bin/lexos-aaa-avant usr/bin/lexos-zzz-apres \
           usr/share/lexos/ui.css usr/lib/lexos/settings.py; do
	[ -r "$SCENE/systeme/$REL" ] || MANQUANTS="$MANQUANTS $REL"
done
[ -z "$MANQUANTS" ] \
	&& ok "les cinq fichiers annoncés sont tous posés" \
	|| non "fichiers manquants après le passage :$MANQUANTS"

#  ═══ ET LA NOUVELLE VERSION EST BIEN EN PLACE ═══
#  Un renommage réussi, c'est aussi ça : l'ancien contenu ne doit pas rester.
if cmp -s "$SCENE/clone/config/includes.chroot/usr/bin/lexos-mise-a-jour" \
          "$SCENE/systeme/usr/bin/lexos-mise-a-jour"; then
	ok "le système porte bien la NOUVELLE version de l'outil"
else
	non "l'outil du système n'est pas identique à celui du clone — la copie s'est perdue"
fi

#  ═══ PAS DE RÉSIDU ═══
#  Le temporaire vit dans le même dossier que la destination : s'il survivait,
#  /usr/bin se remplirait de « .lexos-neuf-1234 » à chaque mise à jour.
RESIDUS="$(find "$SCENE/systeme" -name '*.lexos-neuf-*' | wc -l | tr -d ' ')"
[ "$RESIDUS" = "0" ] \
	&& ok "aucun fichier temporaire laissé derrière" \
	|| non "$RESIDUS fichier(s) temporaire(s) .lexos-neuf-* oubliés dans la destination"

# =============================================================================
titre "10. CE QUI EST ANNONCÉ EST CE QUI EST POSÉ"
# =============================================================================
#  ═══ LE CONTRÔLE QUI AURAIT ATTRAPÉ LE DÉFAUT D'ORIGINE ═══
#  Le jour où l'outil s'est écrasé lui-même, « --essai » promettait 4 fichiers.
#  RIEN NE VÉRIFIAIT QU'IL Y EN AVAIT BIEN 4 AU BOUT. Et c'est précisément ce
#  qui rend ce défaut si mauvais : un plantage au milieu de la boucle laisse
#  des fichiers posés et d'autres non, puis le passage SUIVANT annonce « déjà
#  identiques » pour ceux qui sont là — la machine a l'air à jour, et elle ne
#  l'est pas.
#  On compare donc TROIS nombres qui doivent être le même : ce que « --essai »
#  promet, ce que le vrai passage déclare, et ce qu'on trouve SUR LE DISQUE.
#
#  On repart d'une scène neuve : les sections précédentes ont déjà écrit dans
#  leur destination, et un compte fait sur une destination à moitié pleine ne
#  voudrait rien dire.
CPT="$BANC/compte"
mkdir -p "$CPT/clone/config/includes.chroot/usr/bin" \
         "$CPT/clone/config/includes.chroot/usr/share/lexos" \
         "$CPT/clone/config/includes.chroot/usr/lib/lexos" \
         "$CPT/systeme/etc/lexos"
: > "$CPT/clone/lexos.conf"
for N in un deux trois; do
	printf '#!/bin/sh
echo %s
' "$N" > "$CPT/clone/config/includes.chroot/usr/bin/lexos-$N"
	chmod 755 "$CPT/clone/config/includes.chroot/usr/bin/lexos-$N"
done
printf 'body{}
'     > "$CPT/clone/config/includes.chroot/usr/share/lexos/a.css"
printf 'print(1)
'   > "$CPT/clone/config/includes.chroot/usr/lib/lexos/b.py"
ATTENDUS=5

compte_maj() { # compte_maj <arguments…> — rend le nombre annoncé par l'outil
	LEXOS_MAJ_DEST="$CPT/systeme" LEXOS_MAJ_ETC="$CPT/systeme/etc/lexos" \
	LEXOS_MAJ_SRC_DEFAUT="$CPT/nulle-part" \
	bash "$OUTIL" --depuis "$CPT/clone" "$@" 2>&1
}
#  Le nombre se lit sur la ligne de résumé : « N fichier(s) copié(s) » ou
#  « N fichier(s) SERAIENT copiés ». Par chaîne ici-même, jamais par un tuyau.
nombre_annonce() { sed -n 's/.*[^0-9]\([0-9][0-9]*\) fichier(s) \(SERAIENT\)\?.*copi.*/\1/p' <<< "$1" | head -1; }

SORTIE_ESSAI2="$(compte_maj --essai)"
PROMIS="$(nombre_annonce "$SORTIE_ESSAI2")"
[ "$PROMIS" = "$ATTENDUS" ] \
	&& ok "« --essai » promet $PROMIS fichiers, et il y en a bien $ATTENDUS à copier" \
	|| non "« --essai » promet « ${PROMIS:-rien} » alors que le clone en contient $ATTENDUS"

SORTIE_VRAI2="$(compte_maj)"
DECLARES="$(nombre_annonce "$SORTIE_VRAI2")"
[ "$DECLARES" = "$PROMIS" ] \
	&& ok "le vrai passage déclare le même nombre que l'essai ($DECLARES)" \
	|| non "l'essai promettait $PROMIS, le vrai passage déclare « ${DECLARES:-rien} »"

#  ═══ ET SURTOUT : CE QU'ON TROUVE SUR LE DISQUE ═══
#  C'est le seul des trois nombres que l'outil ne peut pas se raconter à
#  lui-même. On ne compte ni la trace /etc/lexos/maj, ni les sauvegardes.
POSES="$(find "$CPT/systeme/usr" -type f ! -name '*.lexos-bak-*' ! -name '*.lexos-neuf-*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$POSES" = "$ATTENDUS" ] \
	&& ok "$POSES fichiers sont VRAIMENT sur le disque — annoncé = posé" \
	|| non "$ATTENDUS annoncés, $POSES posés : la machine se croirait à jour sans l'être"

# =============================================================================
#  ═══ LE RAPPEL, PARCE QU'UN ❌ A DÉJÀ DÉFILÉ ═══
#  Quand on colle la fin d'un banc, on colle le résumé. Sans ce rappel, « 1
#  échoués » ne dit pas lequel, et le diagnostic commence par une devinette.
if [ "$echoues" -gt 0 ]; then
	printf '\n\033[1mCE QUI A ÉCHOUÉ\033[0m\n'
	printf '%s' "$ECHECS"
fi
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mToutes les portes mènent au même endroit, et « --essai » n'\''écrit rien.\033[0m\n'
