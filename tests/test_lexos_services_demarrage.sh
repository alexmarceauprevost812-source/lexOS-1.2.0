#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — les deux services LexOS qui coûtaient 106 s au démarrage
# =============================================================================
#  MESURÉ SUR LE ThinkPad, pas supposé (systemd-analyze blame, 5 septembre) :
#
#      1min 24.450s  lexos-update-check.service
#           21.891s  lexos-gpu-garde.service
#      graphical.target @33.053s
#
#  Les deux premiers de la liste, loin devant tout le reste, et les deux à
#  nous. Deux causes différentes, et aucune n'est « le script est lent ».
#
#  ═══ 1. update-check : le travail était bon, le MOMENT était mauvais ═══
#  « apt-get update » télécharge les index Debian : c'est long, et c'est
#  normal. Ce qui ne l'était pas : le faire à pleine priorité pendant
#  l'ouverture de session, en se battant avec le bureau pour le disque et le
#  réseau. Et il partait au démarrage malgré « OnBootSec=10min », parce que
#  « Persistent=true » rattrape IMMÉDIATEMENT une échéance manquée.
#
#  ═══ 2. gpu-garde : vingt secondes DEVANT l'écran de connexion ═══
#  Le script est rapide — il lit /sys plutôt que d'appeler lspci. Le coût vient
#  d'update-initramfs, et de la place du service : ordonné avant le
#  gestionnaire de connexion, ses vingt secondes sont AJOUTÉES devant l'écran.
#
#  ═══ CE QUE CE BANC PROTÈGE AVANT TOUT ═══
#  Pas les 106 secondes. LA PANNE QU'ON POURRAIT CAUSER EN LES CHERCHANT.
#  gpu-garde existe pour qu'une seule ISO « pro » démarre aussi bien sur
#  l'Alienware (RTX 5060) que sur le ThinkPad Intel. « Optimiser » ce service
#  jusqu'à ce qu'il ne fasse plus son travail rendrait un écran noir sur
#  l'Alienware — infiniment plus cher que vingt secondes. Le banc joue donc les
#  DEUX machines sur une fausse arborescence PCI, et la machine avec carte est
#  celle qu'il surveille le plus.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNITS="$RACINE/config/includes.chroot/usr/lib/systemd/system"
GARDE="$RACINE/config/includes.chroot/usr/lib/lexos/gpu-garde"
DIFFERE="$RACINE/config/includes.chroot/usr/lib/lexos/gpu-initramfs-differe"
CHECK="$RACINE/config/includes.chroot/usr/bin/lexos-update-check"
SVC_CHECK="$UNITS/lexos-update-check.service"
TMR_CHECK="$UNITS/lexos-update-check.timer"
SVC_GPU="$UNITS/lexos-gpu-garde.service"
SVC_INIT="$UNITS/lexos-gpu-initramfs.service"
MODELE="$UNITS/lexos-claude-installation.service"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0; ECHECS=()

ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); ECHECS+=("$1"); }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT INT TERM

#  Une clé de section systemd : on lit la valeur, pas la présence du mot.
#  « Nice » apparaît dans les commentaires d'explication de ces unités ; un
#  contrôle qui lit la prose se déclencherait sur sa propre justification.
cle() { # cle <fichier> <clé> -> valeur ou vide
	sed 's/[[:space:]]*#.*$//' "$1" 2>/dev/null \
		| grep -E "^$2=" | tail -1 | cut -d= -f2- | sed 's/[[:space:]]*$//'
}

# -----------------------------------------------------------------------------
titre "1. Les fichiers sont là"
for c in "$GARDE:gpu-garde" "$DIFFERE:gpu-initramfs-differe" "$CHECK:lexos-update-check" \
         "$SVC_CHECK:lexos-update-check.service" "$TMR_CHECK:lexos-update-check.timer" \
         "$SVC_GPU:lexos-gpu-garde.service" "$SVC_INIT:lexos-gpu-initramfs.service"; do
	f="${c%%:*}"; n="${c#*:}"
	[[ -r "$f" ]] && ok "$n présent" || non "$n introuvable ($f)"
done
for f in "$GARDE" "$DIFFERE" "$CHECK"; do
	[[ -r "$f" ]] || continue
	sh -n "$f" 2>/dev/null && ok "syntaxe sh de $(basename "$f")" \
		|| non "erreur de syntaxe dans $(basename "$f")"
done
[[ -x "$DIFFERE" ]] && ok "gpu-initramfs-differe est exécutable" \
	|| non "gpu-initramfs-differe n'est pas exécutable (chmod 755)"

# -----------------------------------------------------------------------------
titre "2. update-check : la retenue de lexos-claude-installation"
#  ═══ ON COMPARE AU MODÈLE, PAS À UNE VALEUR ÉCRITE EN DUR ═══
#  lexos-claude-installation.service fait la même sorte de travail — télécharger
#  en arrière-plan quelque chose dont personne n'attend le résultat — et il est
#  correctement élevé depuis toujours. Lire SES valeurs plutôt que de recopier
#  10 et « idle » ici garde les deux services alignés : si un jour on décide
#  que Nice=15 vaut mieux, on le change à un seul endroit.
if [[ -r "$MODELE" && -r "$SVC_CHECK" ]]; then
	for K in Nice IOSchedulingClass; do
		ATTENDU="$(cle "$MODELE" "$K")"
		VU="$(cle "$SVC_CHECK" "$K")"
		if [[ -z "$ATTENDU" ]]; then
			non "le modèle (claude-installation) n'a plus de $K — contrôle sans repère"
		elif [[ "$VU" == "$ATTENDU" ]]; then
			ok "$K=$VU, comme lexos-claude-installation"
		else
			non "$K vaut « ${VU:-rien} », le modèle dit « $ATTENDU »"
		fi
	done
	#  Et la valeur doit rester une VRAIE retenue : Nice=0 ou une classe
	#  « realtime » passeraient la comparaison si le modèle dérivait aussi.
	N="$(cle "$SVC_CHECK" Nice)"
	if [[ "${N:-0}" -gt 0 ]] 2>/dev/null; then
		ok "Nice est bien une retenue (>0)"
	else
		non "Nice=${N:-absent} ne cède la place à personne"
	fi
	[[ "$(cle "$SVC_CHECK" IOSchedulingClass)" == "idle" ]] \
		&& ok "les entrées-sorties passent en dernier (idle)" \
		|| non "IOSchedulingClass n'est pas « idle »"
else
	non "modèle ou unité introuvable — comparaison impossible"
fi

# -----------------------------------------------------------------------------
titre "3. update-check : le rattrapage ne tombe plus au démarrage"
if [[ -r "$TMR_CHECK" ]]; then
	#  Persistent=true est BON — une machine éteinte trois jours doit rattraper.
	#  C'est le rattrapage IMMÉDIAT qui coûtait, pas le rattrapage.
	[[ "$(cle "$TMR_CHECK" Persistent)" == "true" ]] \
		&& ok "Persistent=true conservé — la vérification a toujours lieu" \
		|| non "Persistent a disparu : une machine longtemps éteinte ne rattraperait plus"
	R="$(cle "$TMR_CHECK" RandomizedDelaySec)"
	if [[ -z "$R" ]]; then
		non "aucun RandomizedDelaySec — le rattrapage repart pendant l'ouverture de session"
	else
		ok "RandomizedDelaySec=$R — le rattrapage est étalé"
	fi
	#  Un délai d'une minute ne servirait à rien : l'ouverture de session dure
	#  plus longtemps que ça. On exige un ordre de grandeur utile.
	SEC="$(sed -E 's/^([0-9]+)min$/\1/;t;s/^([0-9]+)h$/\1/;t;s/.*/0/' <<< "$R")"
	case "$R" in
		*h)   SEC=$(( SEC * 3600 )) ;;
		*min) SEC=$(( SEC * 60 )) ;;
		*)    SEC=0 ;;
	esac
	if (( SEC >= 600 )); then
		ok "le délai vaut au moins dix minutes ($R)"
	else
		non "le délai « $R » est trop court pour sortir du démarrage"
	fi
	[[ "$(cle "$TMR_CHECK" AccuracySec)" == "1h" ]] \
		&& ok "AccuracySec=1h — systemd peut choisir un moment calme" \
		|| non "AccuracySec n'est plus 1h : systemd n'a plus de latitude"
fi

# -----------------------------------------------------------------------------
titre "4. update-check : apt ne peut plus traîner indéfiniment"
if [[ -r "$CHECK" ]]; then
	CODE="$(sed 's/[[:space:]]*#.*$//' "$CHECK")"
	if [[ "$(wc -l <<< "$CODE")" -lt 10 ]]; then
		non "le décommentage n'a presque rien laissé — contrôle invalide"
	elif grep -qE 'timeout +[0-9]+ +apt-get +update' <<< "$CODE"; then
		ok "l'apt-get update est enrobé d'un timeout"
	else
		non "aucun timeout autour de l'apt-get — un réseau muet pendrait le service"
	fi
	#  Le plafond du script doit être SOUS celui de l'unité, sinon systemd tue
	#  le service avant qu'il ait pu renoncer proprement.
	T="$(grep -oE 'timeout +[0-9]+' <<< "$CODE" | head -1 | grep -oE '[0-9]+')"
	U="$(cle "$SVC_CHECK" TimeoutStartSec)"
	if [[ -n "$T" && -n "$U" ]] && (( T < U )); then
		ok "le script renonce ($T s) avant que systemd ne le tue ($U s)"
	else
		non "le timeout du script (${T:-absent}) n'est pas sous TimeoutStartSec (${U:-absent})"
	fi
fi

# -----------------------------------------------------------------------------
titre "5. gpu-garde : plus de systemd-udev-settle"
if [[ -r "$SVC_GPU" ]]; then
	CODE_GPU="$(sed 's/[[:space:]]*#.*$//' "$SVC_GPU")"
	#  Décommenté : l'unité EXPLIQUE longuement pourquoi udev-settle est parti.
	if grep -q 'udev-settle' <<< "$CODE_GPU"; then
		non "systemd-udev-settle est encore tiré — 2,7 s, et systemd le déconseille"
	else
		ok "systemd-udev-settle n'est plus tiré"
	fi
	#  ═══ CE QU'IL NE FAUT PAS CASSER ═══
	grep -q '^SuccessExitStatus=0 1' <<< "$CODE_GPU" \
		&& ok "SuccessExitStatus=0 1 conservé — un échec ne bloque pas le démarrage" \
		|| non "SuccessExitStatus=0 1 a disparu : un échec pourrait empêcher de démarrer"
	grep -q 'ConditionPathExists=/sys/bus/pci/devices' <<< "$CODE_GPU" \
		&& ok "ConditionPathExists=/sys/bus/pci/devices conservé" \
		|| non "la condition sur le bus PCI a disparu"
	grep -q 'Before=.*display-manager' <<< "$CODE_GPU" \
		&& ok "Before=display-manager conservé — quand il Y A du travail, il passe devant" \
		|| non "Before=display-manager a disparu : les réglages arriveraient trop tard"
fi

# -----------------------------------------------------------------------------
#  ═══ À PARTIR D'ICI, ON EXÉCUTE. ═══
#  Lire le script dirait ce qu'il contient. On veut savoir ce qu'il FAIT — sur
#  une fausse arborescence PCI et un faux /etc/modprobe.d, avec un
#  update-initramfs témoin qui écrit au lieu de travailler.
# -----------------------------------------------------------------------------
mkdir -p "$BAC/bin"
cat > "$BAC/bin/update-initramfs" <<'TEMOIN'
#!/bin/sh
printf 'appelé: %s\n' "$*" >> "$TEMOIN_INITRAMFS"
exit 0
TEMOIN
chmod 755 "$BAC/bin/update-initramfs"
export TEMOIN_INITRAMFS="$BAC/initramfs.txt"

#  Une machine : faux bus PCI, faux modprobe.d, faux /run et /var/log.
machine() { # machine <racine> <vendor|vide pour aucune carte> <class>
	local R="$1" V="${2:-}" C="${3:-}"
	rm -rf "$R"; mkdir -p "$R/sys/bus/pci/devices" "$R/etc/modprobe.d" \
		"$R/run" "$R/var/log" "$R/proc"
	#  Un démarrage sur DISQUE par défaut. La session démo est jouée à part.
	printf 'BOOT_IMAGE=/vmlinuz root=/dev/sda1 quiet splash\n' > "$R/proc/cmdline"
	#  Un pont hôte, toujours présent sur du vrai matériel : sans lui, le banc
	#  éprouverait une machine sans aucun PCI, qui n'existe pas.
	mkdir -p "$R/sys/bus/pci/devices/0000:00:00.0"
	printf '0x8086\n' > "$R/sys/bus/pci/devices/0000:00:00.0/vendor"
	printf '0x060000\n' > "$R/sys/bus/pci/devices/0000:00:00.0/class"
	if [[ -n "$V" ]]; then
		mkdir -p "$R/sys/bus/pci/devices/0000:01:00.0"
		printf '%s\n' "$V" > "$R/sys/bus/pci/devices/0000:01:00.0/vendor"
		printf '%s\n' "$C" > "$R/sys/bus/pci/devices/0000:01:00.0/class"
	fi
	#  Les deux fichiers tels que l'ISO « pro » les pose à la construction.
	printf 'blacklist nouveau\n' > "$R/etc/modprobe.d/lexos-blacklist-nouveau.conf"
	printf 'options nvidia-drm modeset=1\n' > "$R/etc/modprobe.d/lexos-nvidia-drm.conf"
}

lance_garde() { # lance_garde <racine> -> journal
	env PATH="$BAC/bin:$PATH" TEMOIN_INITRAMFS="$TEMOIN_INITRAMFS" \
		LEXOS_RACINE="$1" sh "$GARDE" 2>&1
}

# -----------------------------------------------------------------------------
titre "6. Une machine SANS carte NVIDIA (le ThinkPad)"
: > "$TEMOIN_INITRAMFS"
machine "$BAC/intel"
J="$(lance_garde "$BAC/intel")"
for F in lexos-blacklist-nouveau.conf lexos-nvidia-drm.conf; do
	if [[ -f "$BAC/intel/etc/modprobe.d/$F.sans-nvidia" && ! -f "$BAC/intel/etc/modprobe.d/$F" ]]; then
		ok "$F est mis de côté — « nouveau » reste disponible"
	else
		non "$F n'a pas été rangé : nouveau resterait interdit pour rien"
	fi
done
#  ═══ L'ASSERTION QUI RETIRE LES VINGT SECONDES ═══
#  Ranger les réglages n'a aucun effet sur CE démarrage-ci : l'état voulu est
#  que « nouveau » redevienne disponible, et l'initramfs doit rattraper avant
#  le PROCHAIN démarrage, pas avant cet écran de connexion.
if [[ -s "$TEMOIN_INITRAMFS" ]]; then
	non "update-initramfs a été appelé devant l'écran de connexion : $(cat "$TEMOIN_INITRAMFS")"
else
	ok "update-initramfs n'est PAS appelé — les 20 s quittent le démarrage"
fi
#  Mais le travail ne doit pas être PERDU : un témoin le réclame pour après.
if [[ -f "$BAC/intel/run/lexos/gpu-initramfs-requis" ]]; then
	ok "un témoin réclame l'initramfs pour après l'ouverture de session"
else
	non "aucun témoin : l'initramfs ne serait jamais rafraîchi"
fi
#  ═══ ET IL DOIT LE DIRE ═══ Un service qui déplace des fichiers du système
#  et remet du travail à plus tard sans laisser de trace est indéboguable le
#  jour où ça tourne mal. Le journal existe pour ça ; on vérifie qu'il sert.
if [[ -z "$J" ]]; then
	non "le premier passage n'a rien écrit — impossible de savoir ce qu'il a fait"
else
	grep -q 'aucune carte NVIDIA' <<< "$J" \
		&& ok "le journal dit pourquoi il a rangé les réglages" \
		|| non "le journal ne dit pas pourquoi les réglages ont bougé : $J"
	grep -qE 'initramfs à rafraîchir|remis après' <<< "$J" \
		&& ok "le journal annonce l'initramfs remis à plus tard" \
		|| non "rien n'annonce que l'initramfs est différé — ça passerait pour un oubli"
fi

titre "7. Le deuxième démarrage ne fait plus rien du tout"
: > "$TEMOIN_INITRAMFS"
rm -rf "$BAC/intel/run/lexos"
J2="$(lance_garde "$BAC/intel")"
if [[ -s "$TEMOIN_INITRAMFS" ]]; then
	non "update-initramfs rappelé alors que rien n'a changé"
else
	ok "update-initramfs n'est pas rappelé — rien n'a changé"
fi
if [[ -f "$BAC/intel/run/lexos/gpu-initramfs-requis" ]]; then
	non "un témoin est reposé alors qu'il n'y a plus rien à faire"
else
	ok "aucun témoin reposé — la sortie anticipée fonctionne"
fi
if [[ -z "$J2" ]]; then
	ok "et il ne dit rien : pas une ligne de journal pour ne rien faire"
else
	non "il parle encore alors qu'il n'a rien fait : $J2"
fi

# -----------------------------------------------------------------------------
titre "8. Une machine AVEC carte NVIDIA (l'Alienware) — le garde-fou"
#  ═══ C'EST L'ASSERTION QUI COMPTE ═══
#  La panne que ce contrôle prévient — écran noir sur l'Alienware — coûte
#  infiniment plus cher que les vingt secondes qu'on cherche à gagner. Rien de
#  ce qui précède ne doit avoir changé quoi que ce soit sur ce chemin-là.
: > "$TEMOIN_INITRAMFS"
machine "$BAC/alien" "0x10de" "0x030000"
#  On part de l'état « déjà rangé », comme après un passage sur une machine
#  sans carte : c'est le cas qui exige de remettre les fichiers.
for F in lexos-blacklist-nouveau.conf lexos-nvidia-drm.conf; do
	mv "$BAC/alien/etc/modprobe.d/$F" "$BAC/alien/etc/modprobe.d/$F.sans-nvidia"
done
JA="$(lance_garde "$BAC/alien")"
for F in lexos-blacklist-nouveau.conf lexos-nvidia-drm.conf; do
	if [[ -f "$BAC/alien/etc/modprobe.d/$F" ]]; then
		ok "$F est remis en place — le pilote propriétaire garde la carte"
	else
		non "$F n'a PAS été remis : nouveau prendrait la RTX, écran noir"
	fi
done
#  Et ici, l'initramfs N'EST PAS différé : l'interdiction de « nouveau » vaut
#  dès l'initramfs, d'où nouveau est chargé par KMS avant même la racine.
if [[ -s "$TEMOIN_INITRAMFS" ]]; then
	ok "update-initramfs est appelé TOUT DE SUITE sur ce chemin"
else
	non "l'initramfs est différé alors qu'une carte NVIDIA est là — risque d'écran noir"
fi
if [[ -f "$BAC/alien/run/lexos/gpu-initramfs-requis" ]]; then
	non "un témoin diffère l'initramfs sur une machine avec carte NVIDIA"
else
	ok "aucun témoin : rien n'est remis à plus tard sur ce chemin"
fi
if [[ -z "$JA" ]]; then
	non "le passage Alienware n'a rien écrit dans le journal"
else
	grep -q 'carte NVIDIA détectée' <<< "$JA" \
		&& ok "le journal nomme la carte trouvée" \
		|| non "le journal ne dit pas qu'une carte a été trouvée : $JA"
	grep -q 'initramfs mis à jour' <<< "$JA" \
		&& ok "le journal confirme l'initramfs refait tout de suite" \
		|| non "rien ne confirme l'initramfs sur le chemin qui en dépend"
fi

titre "9. Sur l'Alienware aussi, le deuxième démarrage ne fait rien"
: > "$TEMOIN_INITRAMFS"
JA2="$(lance_garde "$BAC/alien")"
[[ -s "$TEMOIN_INITRAMFS" ]] \
	&& non "update-initramfs rappelé alors que les réglages sont déjà en place" \
	|| ok "rien à faire, rien de fait"
[[ -z "$JA2" ]] \
	&& ok "et pas une ligne de journal pour ne rien faire" \
	|| non "il parle encore alors qu'il n'a rien fait : $JA2"

titre "10. Une puce audio NVIDIA n'est pas une carte graphique"
#  0x0403 = audio. Les cartes NVIDIA en portent une ; la prendre pour un GPU
#  remettrait la liste noire sur une machine sans carte graphique NVIDIA.
: > "$TEMOIN_INITRAMFS"
machine "$BAC/audio" "0x10de" "0x040300"
lance_garde "$BAC/audio" >/dev/null
if [[ -f "$BAC/audio/etc/modprobe.d/lexos-blacklist-nouveau.conf.sans-nvidia" ]]; then
	ok "la puce audio NVIDIA n'est pas prise pour un GPU"
else
	non "une puce audio NVIDIA suffit à garder la liste noire — faux positif"
fi

# -----------------------------------------------------------------------------
titre "11. Le service différé fait bien le travail"
if [[ -x "$DIFFERE" ]]; then
	R4="$BAC/differe"; rm -rf "$R4"; mkdir -p "$R4/run/lexos" "$R4/var/log" "$R4/proc"
	printf 'BOOT_IMAGE=/vmlinuz root=/dev/sda1 quiet splash\n' > "$R4/proc/cmdline"
	: > "$R4/run/lexos/gpu-initramfs-requis"
	: > "$TEMOIN_INITRAMFS"
	env PATH="$BAC/bin:$PATH" TEMOIN_INITRAMFS="$TEMOIN_INITRAMFS" \
		LEXOS_RACINE="$R4" sh "$DIFFERE" >/dev/null 2>&1
	[[ -s "$TEMOIN_INITRAMFS" ]] \
		&& ok "avec le témoin, il appelle update-initramfs" \
		|| non "le témoin est là mais l'initramfs n'est pas rafraîchi"
	[[ -f "$R4/run/lexos/gpu-initramfs-requis" ]] \
		&& non "le témoin traîne après un succès — le travail serait refait" \
		|| ok "le témoin est retiré après le succès"
	#  Sans témoin, il ne doit rien faire : c'est ce qui l'empêche de coûter
	#  vingt secondes à chaque ouverture de session.
	: > "$TEMOIN_INITRAMFS"
	env PATH="$BAC/bin:$PATH" TEMOIN_INITRAMFS="$TEMOIN_INITRAMFS" \
		LEXOS_RACINE="$R4" sh "$DIFFERE" >/dev/null 2>&1
	[[ -s "$TEMOIN_INITRAMFS" ]] \
		&& non "il travaille sans témoin — vingt secondes à chaque session" \
		|| ok "sans témoin, il ne fait rien"
fi

titre "12. L'unité différée n'est pas devant l'écran de connexion"
if [[ -r "$SVC_INIT" ]]; then
	CODE_I="$(sed 's/[[:space:]]*#.*$//' "$SVC_INIT")"
	grep -q 'ConditionPathExists=/run/lexos/gpu-initramfs-requis' <<< "$CODE_I" \
		&& ok "elle ne démarre que si le témoin est là" \
		|| non "elle démarrerait à chaque session, témoin ou pas"
	grep -qE '^After=.*graphical\.target' <<< "$CODE_I" \
		&& ok "elle est ordonnée APRÈS le bureau" \
		|| non "rien ne la place après le bureau — elle pourrait le retarder"
	grep -q 'Before=' <<< "$CODE_I" \
		&& non "elle passe devant quelque chose — c'est exactement ce qu'on fuit" \
		|| ok "elle ne passe devant rien"
	N="$(cle "$SVC_INIT" Nice)"
	[[ -n "$N" && "$N" -gt 0 ]] 2>/dev/null \
		&& ok "Nice=$N — elle cède la place à la session" \
		|| non "aucune retenue de priorité (Nice=${N:-absent})"
	[[ "$(cle "$SVC_INIT" IOSchedulingClass)" == "idle" ]] \
		&& ok "ses entrées-sorties passent en dernier" \
		|| non "IOSchedulingClass n'est pas « idle »"
fi

# -----------------------------------------------------------------------------
titre "13. Sur une ISO sans réglages NVIDIA, il ne lit même pas le bus"
#  ═══ POURQUOI C'EST MESURÉ AU CHRONOMÈTRE ═══
#  Seule l'ISO « pro » pose les deux fichiers de /etc/modprobe.d. Sur les
#  autres saveurs, ce service n'a rien à décider — et pourtant il parcourait le
#  bus PCI, et attendait jusqu'à une seconde qu'il se peuple si le répertoire
#  était vide. La sortie anticipée ne se voit dans AUCUN fichier produit :
#  c'est du temps, donc c'est le temps qu'on mesure. Le partage est large —
#  quelques millisecondes contre une seconde pleine — donc la mesure n'est pas
#  fragile.
RV="$BAC/vide"; rm -rf "$RV"
mkdir -p "$RV/sys/bus/pci/devices" "$RV/etc/modprobe.d" "$RV/run" "$RV/var/log" "$RV/proc"
printf 'BOOT_IMAGE=/vmlinuz root=/dev/sda1 quiet splash\n' > "$RV/proc/cmdline"
#  Bus PCI VIDE et aucun réglage : c'est le cas qui déclenchait l'attente.
#  DEBUT_NS / FIN_NS, et pas DEBUT / FIN : « FIN » est la séquence qui éteint
#  la couleur, trois lignes plus haut dans ce fichier. L'écraser imprimait
#  l'horodatage au milieu de chaque coche.
: > "$TEMOIN_INITRAMFS"
DEBUT_NS="$(date +%s%N)"
lance_garde "$RV" >/dev/null
FIN_NS="$(date +%s%N)"
MS=$(( (FIN_NS - DEBUT_NS) / 1000000 ))
if (( MS < 500 )); then
	ok "il sort en ${MS} ms sans lire le bus (l'attente d'une seconde est évitée)"
else
	non "il a mis ${MS} ms : il attend le bus alors qu'il n'a rien à gérer"
fi
[[ -s "$TEMOIN_INITRAMFS" ]] \
	&& non "il a touché à l'initramfs sans avoir aucun réglage à gérer" \
	|| ok "et il ne touche à rien"

# -----------------------------------------------------------------------------
titre "14. Le bus qui arrive en retard — le remplaçant d'udev-settle"
#  ═══ CE QU'ON A RETIRÉ, ET CE QUI LE REMPLACE ═══
#  L'unité tirait « Wants=systemd-udev-settle.service » : 2,7 s au démarrage,
#  pour une unité que systemd déconseille. Elle n'était pas nécessaire — les
#  répertoires de /sys/bus/pci/devices et leurs fichiers « vendor » et
#  « class » sont créés par le NOYAU à l'énumération PCI, avant le premier
#  programme de l'espace utilisateur ; udev ne fait qu'agir dessus ensuite.
#
#  Reste le doute honnête : ET SI LE BUS N'ÉTAIT PAS ENCORE LÀ ? Le script
#  attend alors, borné à une seconde. Ce contrôle joue exactement ce cas —
#  un bus vide qui se peuple 300 ms plus tard — parce qu'un filet de sécurité
#  qu'on n'a jamais vu retenir personne n'est pas un filet, c'est une phrase.
RT="$BAC/tardif"; rm -rf "$RT"
mkdir -p "$RT/sys/bus/pci/devices" "$RT/etc/modprobe.d" "$RT/run" "$RT/var/log" "$RT/proc"
printf 'BOOT_IMAGE=/vmlinuz root=/dev/sda1 quiet splash\n' > "$RT/proc/cmdline"
#  Les réglages sont là mais MIS DE CÔTÉ : il faudra donc lire le bus pour
#  décider, et trouver la carte, pour les remettre.
printf 'blacklist nouveau\n' > "$RT/etc/modprobe.d/lexos-blacklist-nouveau.conf.sans-nvidia"
printf 'options nvidia-drm modeset=1\n' > "$RT/etc/modprobe.d/lexos-nvidia-drm.conf.sans-nvidia"
#  La carte NVIDIA n'apparaît qu'après 300 ms, comme si le noyau finissait
#  d'énumérer pendant que le service démarre.
(
	sleep 0.3
	mkdir -p "$RT/sys/bus/pci/devices/0000:01:00.0"
	printf '0x10de\n' > "$RT/sys/bus/pci/devices/0000:01:00.0/vendor"
	printf '0x030000\n' > "$RT/sys/bus/pci/devices/0000:01:00.0/class"
) &
TARDIF=$!
: > "$TEMOIN_INITRAMFS"
lance_garde "$RT" >/dev/null
wait "$TARDIF" 2>/dev/null || true
if [[ -f "$RT/etc/modprobe.d/lexos-blacklist-nouveau.conf" ]]; then
	ok "le bus arrivé en retard est quand même vu — les réglages sont remis"
else
	non "le bus tardif n'a pas été attendu : sur l'Alienware, écran noir"
fi

# -----------------------------------------------------------------------------
titre "15. En session démo, on ne touche JAMAIS à l'initramfs"
#  ═══ POURQUOI CE CAS EXISTE ═══
#  En session démo, le système de fichiers est un empilement en mémoire :
#  régénérer l'initramfs n'y sert à rien, et prend vingt secondes au pire
#  moment — celui où quelqu'un essaie LexOS pour la première fois, depuis une
#  clé USB, et se fait une idée de sa vitesse. Les DEUX chemins doivent se
#  taire, celui qui range comme celui qui remet.
for CAS in "demo-intel::le ThinkPad" "demo-alien:0x10de:l'Alienware"; do
	NOM="${CAS%%:*}"; RESTE="${CAS#*:}"
	VEND="${RESTE%%:*}"; QUI="${RESTE#*:}"
	: > "$TEMOIN_INITRAMFS"
	if [[ -n "$VEND" ]]; then
		machine "$BAC/$NOM" "$VEND" "0x030000"
		for F in lexos-blacklist-nouveau.conf lexos-nvidia-drm.conf; do
			mv "$BAC/$NOM/etc/modprobe.d/$F" "$BAC/$NOM/etc/modprobe.d/$F.sans-nvidia"
		done
	else
		machine "$BAC/$NOM"
	fi
	printf 'BOOT_IMAGE=/live/vmlinuz boot=live components quiet splash\n' \
		> "$BAC/$NOM/proc/cmdline"
	lance_garde "$BAC/$NOM" >/dev/null
	if [[ -s "$TEMOIN_INITRAMFS" ]]; then
		non "session démo sur $QUI : update-initramfs appelé pour rien"
	else
		ok "session démo sur $QUI : l'initramfs n'est pas touché"
	fi
	#  Et les fichiers doivent tout de même être placés : c'est ce qui décide
	#  du pilote pour CE démarrage-ci, initramfs ou pas.
	if [[ -n "$VEND" ]]; then
		[[ -f "$BAC/$NOM/etc/modprobe.d/lexos-blacklist-nouveau.conf" ]] \
			&& ok "session démo sur $QUI : les réglages sont quand même remis" \
			|| non "session démo sur $QUI : les réglages n'ont pas été remis"
	else
		[[ -f "$BAC/$NOM/etc/modprobe.d/lexos-blacklist-nouveau.conf.sans-nvidia" ]] \
			&& ok "session démo sur $QUI : les réglages sont quand même rangés" \
			|| non "session démo sur $QUI : les réglages n'ont pas été rangés"
	fi
done
#  Le service différé aussi : témoin présent, session démo, il retire le témoin
#  sans travailler.
if [[ -x "$DIFFERE" ]]; then
	RD="$BAC/differe-demo"; rm -rf "$RD"; mkdir -p "$RD/run/lexos" "$RD/var/log" "$RD/proc"
	printf 'BOOT_IMAGE=/live/vmlinuz boot=live quiet splash\n' > "$RD/proc/cmdline"
	: > "$RD/run/lexos/gpu-initramfs-requis"
	: > "$TEMOIN_INITRAMFS"
	env PATH="$BAC/bin:$PATH" TEMOIN_INITRAMFS="$TEMOIN_INITRAMFS" \
		LEXOS_RACINE="$RD" sh "$DIFFERE" >/dev/null 2>&1
	[[ -s "$TEMOIN_INITRAMFS" ]] \
		&& non "le service différé travaille en session démo" \
		|| ok "le service différé ne travaille pas en session démo"
fi

# -----------------------------------------------------------------------------
titre "16. Les deux unités sont ACTIVÉES à la construction"
#  ═══ SANS « systemctl enable », TOUT LE RESTE EST DÉCORATIF ═══
#  Une unité posée dans /usr/lib/systemd/system et jamais activée ne démarre
#  jamais. Pour lexos-gpu-initramfs, l'oubli serait invisible : le témoin
#  s'accumulerait dans /run, personne ne le ramasserait, et l'initramfs
#  resterait périmé — sans un message, sans un symptôme, jusqu'au jour où
#  quelqu'un branche une carte NVIDIA.
HOOK_INST="$RACINE/config/hooks/normal/0500-lexos-installer.hook.chroot"
if [[ -r "$HOOK_INST" ]]; then
	CODE_H="$(sed 's/[[:space:]]*#.*$//' "$HOOK_INST")"
	if [[ "$(grep -c . <<< "$CODE_H")" -lt 40 ]]; then
		non "le décommentage du hook 0500 n'a presque rien laissé — contrôle invalide"
	else
		for U in lexos-gpu-garde.service lexos-gpu-initramfs.service; do
			grep -qE "systemctl enable +$U" <<< "$CODE_H" \
				&& ok "$U est activée à la construction" \
				|| non "$U n'est jamais activée — elle ne démarrerait pas"
		done
	fi
	grep -qE 'chmod 0755 /usr/lib/lexos/gpu-initramfs-differe' <<< "$CODE_H" \
		&& ok "le script différé est rendu exécutable à la construction" \
		|| non "le script différé pourrait arriver sans son bit d'exécution"
fi
#  La minuterie d'update-check, elle, est activée ailleurs (hook 0250).
HOOK_OPT="$RACINE/config/hooks/normal/0250-lexos-optional.hook.chroot"
if [[ -r "$HOOK_OPT" ]]; then
	grep -qE 'systemctl enable +lexos-update-check\.timer' \
		<<< "$(sed 's/[[:space:]]*#.*$//' "$HOOK_OPT")" \
		&& ok "lexos-update-check.timer est activée à la construction" \
		|| non "la minuterie n'est jamais activée — plus aucune vérification"
fi

# -----------------------------------------------------------------------------
titre "17. Le banc ne se tire pas dans le pied"
MOTIF='(printf|echo|cat|sed)[^|]*[|][[:space:]]*grep[[:space:]]+-[a-zA-Z]*[qm]'
if grep -qE "$MOTIF" <<< "$(sed 's/[[:space:]]*#.*$//' "${BASH_SOURCE[0]}")"; then
	non "un tuyau « texte | grep -q » traîne ici — course au tuyau cassé"
else
	ok "aucun « texte | grep -q » dans ce banc"
fi

# -----------------------------------------------------------------------------
if (( ECHOUES > 0 )); then
	printf '\n%sCe qui ne va pas :%s\n' "$GRAS" "$FIN"
	for e in "${ECHECS[@]}"; do printf '  %s·%s %s\n' "$ROUGE" "$FIN" "$e"; done
fi
printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
