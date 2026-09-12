#!/usr/bin/env bash
# =============================================================================
#  Éprouver la porte d'entrée du hook 0260 — « le module est-il compilé ? »
# =============================================================================
#  verifie_module() décide si une tentative d'installation du pilote NVIDIA
#  est déclarée RÉUSSIE. Tout le hook s'articule dessus : si elle dit oui à
#  tort, la construction est verte et l'ISO démarre sans pilote — l'écran noir
#  de l'Alienware, avec un journal qui dit « ok ».
#
#  LE CAS QUI A MOTIVÉ CE BANC. Le chroot peut contenir DEUX noyaux :
#  LEXOS_KERNEL_CHANNEL=backports fait installer par le hook 0200 un
#  linux-image-amd64 de backports PAR-DESSUS celui de la suite, sans retirer
#  l'ancien. Les en-têtes, eux, étaient demandés par « linux-headers-amd64 »,
#  un méta-paquet qui suit la SUITE : DKMS compilait donc pour l'ANCIEN noyau.
#  L'ancienne porte balayait /lib/modules en entier et trouvait ce module-là.
#  Verte. Et l'image démarre sur le noyau RÉCENT, où il n'y a rien.
#
#  Ce banc joue les deux versions de la porte sur la même scène : la nouvelle
#  doit refuser, l'ANCIENNE doit accepter. Sans cette seconde moitié, rien ne
#  prouverait que le défaut était réel.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0260-lexos-nvidia.hook.chroot"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -f "$HOOK" ] || { echo "hook 0260 introuvable"; exit 1; }

# --- On extrait les fonctions DU VRAI FICHIER, pas une copie -----------------
#  Une copie recollée ici vieillirait en silence : le hook pourrait changer
#  sans que le banc s'en aperçoive. On lit donc le fichier livré.
EXTRAIT="$BANC/extrait.sh"
{
	grep '^NOYAUX_DIR=' "$HOOK"
	sed -n '/^noyau_cible() {$/,/^}$/p' "$HOOK"
	sed -n '/^verifie_module() {$/,/^}$/p' "$HOOK"
} > "$EXTRAIT"

NB_FONCTIONS="$(grep -c '^[a-z_]*() {$' "$EXTRAIT")"
[ "$NB_FONCTIONS" = "2" ] \
	&& ok "les deux fonctions ont été relues dans le hook livré" \
	|| non "extraction ratée ($NB_FONCTIONS fonctions) — tout ce qui suit ne vaudrait rien"
grep -q '^NOYAUX_DIR=' "$EXTRAIT" \
	&& ok "et la racine des noyaux avec elles" \
	|| non "NOYAUX_DIR non relu"

# --- L'ANCIENNE porte, pour mesurer ce qu'elle faisait -----------------------
#  PAS une copie au caractère près : l'originale s'écrivait « find … | grep -q . »,
#  une tournure que la CI de ce dépôt interdit dans les bancs (grep -q ferme le
#  tuyau et tue le producteur). Ce qui compte ici est sa SÉMANTIQUE — elle
#  balayait l'arbre ENTIER et disait oui pour un module trouvé n'importe où —
#  et c'est exactement ce que fait la version ci-dessous.
ancienne_porte() {
	local trouve
	trouve="$(find "${LEXOS_RACINE:-}/lib/modules" -name 'nvidia*.ko*' -print 2>/dev/null | head -1)"
	[ -n "$trouve" ]
}

# --- Une scène : des dossiers de noyaux, et où poser le module ---------------
scene() { # scene <noyau...>   — crée les arbres, vides
	rm -rf "$BANC/racine"
	local k
	for k in "$@"; do mkdir -p "$BANC/racine/lib/modules/$k/updates/dkms"; done
}
pose_module() { # pose_module <noyau>
	mkdir -p "$BANC/racine/lib/modules/$1/updates/dkms"
	touch "$BANC/racine/lib/modules/$1/updates/dkms/nvidia.ko"
}
faux_dkms() { # faux_dkms [<ligne de dkms status>]
	mkdir -p "$BANC/bin"
	if [ "$#" -eq 0 ]; then
		printf '#!/bin/sh\nexit 0\n' > "$BANC/bin/dkms"
	else
		printf '#!/bin/sh\ncat <<EOF\n%s\nEOF\n' "$1" > "$BANC/bin/dkms"
	fi
	chmod +x "$BANC/bin/dkms"
}

porte() { # porte -> 0/1 ; sortie dans $BANC/dit
	( set +e
	  export LEXOS_RACINE="$BANC/racine"
	  export PATH="$BANC/bin:$PATH"
	  # shellcheck disable=SC1090
	  . "$EXTRAIT"
	  verifie_module > "$BANC/dit" 2>&1
	  echo "$?" > "$BANC/code" )
	cat "$BANC/code"
}

vieille_porte() {
	( set +e
	  export LEXOS_RACINE="$BANC/racine"
	  ancienne_porte
	  echo "$?" > "$BANC/code" )
	cat "$BANC/code"
}

# =============================================================================
titre "1. Un seul noyau, module compilé pour lui -> la porte s'ouvre"
# =============================================================================
scene 6.12.48-amd64
pose_module 6.12.48-amd64
faux_dkms
[ "$(porte)" = "0" ] \
	&& ok "module présent pour le noyau de l'image -> accepté" \
	|| non "refusé alors que le module est là :\n$(cat "$BANC/dit")"
grep -q '6.12.48-amd64' "$BANC/dit" \
	&& ok "et le journal NOMME le noyau vérifié" \
	|| non "le journal ne dit pas pour quel noyau :\n$(cat "$BANC/dit")"

# =============================================================================
titre "2. DEUX noyaux, module seulement sous l'ANCIEN -> la porte doit REFUSER"
# =============================================================================
#  La scène exacte de LEXOS_KERNEL_CHANNEL=backports : le noyau récent est
#  celui que live-build mettra dans l'image, et il n'a aucun module.
scene 6.12.48-amd64 6.16.3-amd64
pose_module 6.12.48-amd64
faux_dkms
[ "$(porte)" = "1" ] \
	&& ok "module pour le mauvais noyau -> REFUSÉ" \
	|| non "ACCEPTÉ alors que le noyau de l'image n'a pas de module :\n$(cat "$BANC/dit")"
grep -q '6.16.3-amd64' "$BANC/dit" \
	&& ok "et le journal dit de quel noyau il manque" \
	|| non "le journal ne nomme pas le noyau manquant :\n$(cat "$BANC/dit")"

#  LA PREUVE QUE LE DÉFAUT ÉTAIT RÉEL, pas une précaution théorique.
[ "$(vieille_porte)" = "0" ] \
	&& ok "MESURE : l'ANCIENNE porte acceptait cette même scène (le défaut existait)" \
	|| non "l'ancienne porte refusait déjà — alors ce banc ne prouve rien"

# =============================================================================
titre "3. DEUX noyaux, module sous le RÉCENT -> accepté, et c'est le bon"
# =============================================================================
scene 6.12.48-amd64 6.16.3-amd64
pose_module 6.16.3-amd64
faux_dkms
[ "$(porte)" = "0" ] \
	&& ok "module pour le noyau de l'image -> accepté" \
	|| non "refusé alors que le bon noyau a son module :\n$(cat "$BANC/dit")"
grep -q '6.16.3-amd64' "$BANC/dit" \
	&& ok "et c'est bien le RÉCENT qui est nommé" \
	|| non "le mauvais noyau est nommé :\n$(cat "$BANC/dit")"

# =============================================================================
titre "4. Le plus récent se choisit par VERSION, pas par ordre alphabétique"
# =============================================================================
#  6.12.9 > 6.12.10 en tri alphabétique, et c'est faux. « sort -V » est la
#  différence entre vérifier le bon noyau et vérifier l'avant-dernier.
scene 6.12.9-amd64 6.12.10-amd64
pose_module 6.12.10-amd64
faux_dkms
[ "$(porte)" = "0" ] \
	&& ok "6.12.10 est reconnu plus récent que 6.12.9 (tri de version)" \
	|| non "le tri a désigné le mauvais noyau :\n$(cat "$BANC/dit")"

scene 6.12.9-amd64 6.12.10-amd64
pose_module 6.12.9-amd64
faux_dkms
[ "$(porte)" = "1" ] \
	&& ok "et un module qui n'existe que pour 6.12.9 est bien refusé" \
	|| non "accepté à tort :\n$(cat "$BANC/dit")"

# =============================================================================
titre "5. Aucun noyau sous /lib/modules -> refus, et on le DIT"
# =============================================================================
#  Un dossier vide ne doit pas se lire comme « tout va bien ». C'est le même
#  piège que le repli iwlwifi du hook 0250.
scene
mkdir -p "$BANC/racine/lib/modules"
faux_dkms
[ "$(porte)" = "1" ] \
	&& ok "aucun noyau -> refusé" \
	|| non "accepté sans aucun noyau :\n$(cat "$BANC/dit")"
grep -q 'aucun noyau' "$BANC/dit" \
	&& ok "et le journal l'explique au lieu de se taire" \
	|| non "refus muet :\n$(cat "$BANC/dit")"

# =============================================================================
titre "6. DKMS : « installed » pour l'ancien noyau ne vaut pas pour le nouveau"
# =============================================================================
scene 6.12.48-amd64 6.16.3-amd64
faux_dkms 'nvidia/595.71.05, 6.12.48-amd64, x86_64: installed'
[ "$(porte)" = "1" ] \
	&& ok "DKMS « installed » sur l'ANCIEN noyau -> refusé" \
	|| non "un « installed » pour le mauvais noyau a ouvert la porte :\n$(cat "$BANC/dit")"

scene 6.12.48-amd64 6.16.3-amd64
faux_dkms 'nvidia/595.71.05, 6.16.3-amd64, x86_64: installed'
[ "$(porte)" = "0" ] \
	&& ok "DKMS « installed » sur le noyau de l'image -> accepté" \
	|| non "refusé alors que DKMS l'annonce pour le bon noyau :\n$(cat "$BANC/dit")"

scene 6.12.48-amd64 6.16.3-amd64
faux_dkms 'nvidia/595.71.05, 6.16.3-amd64, x86_64: added'
[ "$(porte)" = "1" ] \
	&& ok "« added » n'est pas « installed » -> refusé" \
	|| non "un module seulement « added » a ouvert la porte :\n$(cat "$BANC/dit")"

# =============================================================================
titre "7. Les en-têtes demandés suivent le noyau de l'image, pas la suite"
# =============================================================================
#  Contrôle de source : c'est la CAUSE, pas le symptôme. Détecter le mauvais
#  noyau sans corriger la demande d'en-têtes laisserait la construction
#  échouer proprement au lieu de réussir — mieux, mais toujours pas d'ISO.
grep -q 'linux-headers-\$KCIBLE_H' "$HOOK" \
	&& ok "le hook demande linux-headers-\$KCIBLE_H (le noyau de l'image)" \
	|| non "le hook ne demande pas les en-têtes du noyau cible"
grep -q 'repli linux-headers-amd64' "$HOOK" \
	&& ok "et le repli sur le méta-paquet s'annonce comme un repli" \
	|| non "le repli linux-headers-amd64 ne se signale pas"

ORDRE_CIBLE="$(grep -n 'linux-headers-\$KCIBLE_H' "$HOOK" | head -1 | cut -d: -f1)"
ORDRE_REPLI="$(grep -n 'apt-get install -y linux-headers-amd64' "$HOOK" | head -1 | cut -d: -f1)"
[ -n "$ORDRE_CIBLE" ] && [ -n "$ORDRE_REPLI" ] && [ "$ORDRE_CIBLE" -lt "$ORDRE_REPLI" ] \
	&& ok "et il est demandé AVANT le repli, pas après" \
	|| non "l'ordre est inversé (cible ligne ${ORDRE_CIBLE:-?}, repli ligne ${ORDRE_REPLI:-?})"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
