#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — la fenêtre d'avertissement de l'installateur
# =============================================================================
#  ═══ CE QU'ELLE FAISAIT, MESURÉ ═══
#  Elle n'avait aucune hauteur : yad la calculait sur les ~40 lignes du texte.
#  Mesuré sur un serveur X de 1920×1080 : la fenêtre faisait 2146 px de haut,
#  soit 1066 px HORS ÉCRAN. La moitié basse, boutons compris, était invisible.
#
#  ═══ POURQUOI C'EST LA PIRE FENÊTRE DU DÉPÔT POUR CE DÉFAUT ═══
#  C'est la dernière chose qu'on voit avant qu'un disque puisse être effacé.
#  Deux façons de s'y tromper, et le banc les tient toutes les deux :
#    · l'avertissement TRONQUÉ — BitLocker et Secure Boot sont à la FIN du
#      texte, et ce sont eux qui coûtent un disque quand on ne les a pas lus.
#      Couper vaut donc pire que faire long : le corps doit DÉFILER ;
#    · les BOUTONS hors écran — et alors quelqu'un appuie sur Entrée sans les
#      voir. Ce que fait Entrée devient la seule chose qui compte.
#
#  ═══ CE BANC MESURE LA FENÊTRE, IL NE LIT PAS LES OPTIONS ═══
#  Quand un serveur X et yad sont disponibles, il OUVRE le dialogue à deux
#  résolutions et lit sa géométrie réelle. Une option « --height » présente
#  dans le code ne prouve rien : c'est la fenêtre à l'écran qui décide.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$RACINE/config/includes.chroot/usr/bin/lexos-install"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; JAUNE=$'\033[33m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0; ECHECS=()
ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); ECHECS+=("$1"); }
saut() { printf '  %s—%s  %s\n' "$JAUNE" "$FIN" "$1"; }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

BAC="$(mktemp -d)"
XVFB_PID=""
YAD_PID=""
#  ═══ PAR LE PID, JAMAIS PAR « pkill -f » ═══
#  Il y avait ici « pkill -f "yad --title=BANC-AVERT" ». « -f » compare le
#  motif à la LIGNE DE COMMANDE ENTIÈRE de tous les processus — y compris
#  ceux qui ne font que MENTIONNER ce texte. Mesuré en écrivant les mutations
#  de ce banc : un shell dont la commande contenait la chaîne s'est fait tuer
#  par ce pkill-là, et le tout est sorti avec 144 sans une explication.
#  Le dépôt s'est déjà fait prendre par ce piège avec « pkill -f polkitd ».
#  On sait quel yad on a lancé : on le tue par son numéro.
nettoyer() {
	[[ -n "$YAD_PID" ]] && { kill "$YAD_PID" 2>/dev/null; wait "$YAD_PID" 2>/dev/null; }
	[[ -n "$XVFB_PID" ]] && { kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; }
	rm -rf "$BAC"
	return 0
}
#  UNE TRAPPE DE SIGNAL QUI NE SORT PAS AVALE LE SIGNAL. « trap nettoyer INT
#  TERM » : bash exécute nettoyer, puis REPREND le banc là où il en était —
#  mesuré, un SIGTERM en plein milieu et le banc finit vert comme si de rien
#  n'était. Ctrl+C et TERM font donc « exit », et c'est la trappe EXIT qui
#  nettoie — une seule fois, dans tous les cas.
trap nettoyer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  ═══ XVFB CHOISIT SON NUMÉRO, ET DIT QUAND IL ÉCOUTE ═══
#  Avant : « :$((90 + RANDOM % 8)) » — huit numéros possibles, sans vérifier
#  qu'ils sont libres, puis « sleep 2 » en espérant que le serveur soit prêt.
#  Mesuré : un Xvfb :92 orphelin d'un autre banc (dont l'écran était pris par
#  un « import » resté en plan) a fait tomber le banc entier sur ce numéro —
#  xdotool s'est adressé à l'autre serveur, s'est bloqué sur son verrou, et
#  la suite complète a pendu. Avec -displayfd, Xvfb prend lui-même le premier
#  numéro libre et l'écrit sur le descripteur quand il ACCEPTE les
#  connexions : plus de collision, et plus de « sleep » à l'aveugle.
#  Chaque outil qui parle au serveur est sous « timeout » : s'il coince, le
#  banc rougit en le disant au lieu de rester muet.
#  PAS DE « $(xvfb_lancer …) » : une substitution de commande tourne dans un
#  SOUS-SHELL, et le XVFB_PID qu'elle pose n'arrive jamais au banc — mesuré,
#  deux serveurs restés en vie après un banc pourtant vert. La fonction pose
#  donc DEUX variables globales, XVFB_PID et XVFB_AFF, et n'affiche rien.
xvfb_lancer() {   # $1 = résolution ; pose XVFB_PID et XVFB_AFF (« :N »)
	local res="$1" f="$BAC/xvfb.num" i
	XVFB_AFF=""
	: > "$f"
	Xvfb -displayfd 3 -screen 0 "$res" 3>"$f" >/dev/null 2>&1 &
	XVFB_PID=$!
	for i in $(seq 1 100); do
		[[ -s "$f" ]] && break
		kill -0 "$XVFB_PID" 2>/dev/null || break
		sleep 0.1
	done
	[[ -s "$f" ]] || { kill "$XVFB_PID" 2>/dev/null; XVFB_PID=""; return 1; }
	XVFB_AFF=":$(tr -dc 0-9 < "$f")"
}

# -----------------------------------------------------------------------------
titre "1. Le fichier et ses deux fonctions de mesure"
if [[ -r "$INST" ]]; then ok "lexos-install lisible"; else
	non "lexos-install introuvable ($INST)"; printf '\n'; exit 1; fi
bash -n "$INST" 2>/dev/null && ok "syntaxe bash valide" || non "erreur de syntaxe bash"

#  On DÉCOUPE les deux fonctions du vrai fichier plutôt que de les recopier :
#  un banc qui recopie la logique éprouve sa copie, pas le programme.
for f in ecran_hauteur hauteur_dialogue; do
	DECOUPE="$(awk -v f="$f" '$0 ~ "^"f"\\(\\) \\{"{d=1} d{print} d && /^\}/{exit}' "$INST")"
	if [[ -n "$DECOUPE" ]]; then
		ok "la fonction $f existe et est découpable"
	else
		non "la fonction $f est introuvable — la hauteur ne serait pas calculée"
	fi
done
eval "$(awk '/^ecran_hauteur\(\) \{/,/^\}/' "$INST")"
eval "$(awk '/^hauteur_dialogue\(\) \{/,/^\}/' "$INST")"

# -----------------------------------------------------------------------------
titre "2. Le plafond suit l'écran, il n'est jamais une constante"
#  ═══ L'ASSERTION QUI COMPTE ICI ═══
#  Une constante « --height=620 » irait sur un 1080p et déborderait ENCORE sur
#  le 1366×768 d'un netbook. On rejoue donc le calcul sur des écrans réels en
#  neutralisant la lecture de l'écran.
for cas in "1080:720:1920x1080 — la hauteur voulue tient" \
           "768:648:1366x768 — elle est rabotée à ce que l'écran montre" \
           "600:480:1024x600 — un très petit écran est encore servi" \
           "400:320:un écran absurde ne descend pas sous le plancher"; do
	ecran="${cas%%:*}"; reste="${cas#*:}"
	attendu="${reste%%:*}"; nom="${reste#*:}"
	#  On passe la hauteur par l'ENVIRONNEMENT et on relance un shell : une
	#  fonction redéfinie dans une substitution de commande ne voyait pas la
	#  variable de la boucle, et les quatre cas rendaient tous le plancher —
	#  un banc qui mesure toujours la même chose ne mesure rien.
	vu="$(LEXOS_ECRAN_ESSAI="$ecran" bash -c "
		$(declare -f hauteur_dialogue)
		ecran_hauteur() { printf '%s' \"\$LEXOS_ECRAN_ESSAI\"; }
		hauteur_dialogue 720")"
	if [[ "$vu" == "$attendu" ]]; then ok "$nom → $vu px"
	else non "$nom → $vu px, attendu $attendu"; fi
done
#  Et la marge réservée doit rester une VRAIE marge : sans elle, la fenêtre
#  ferait exactement la hauteur de l'écran et la barre du haut mangerait les
#  boutons.
vu="$(LEXOS_ECRAN_ESSAI=1080 bash -c "
	$(declare -f hauteur_dialogue)
	ecran_hauteur() { printf '%s' \"\$LEXOS_ECRAN_ESSAI\"; }
	hauteur_dialogue 5000")"
if (( vu <= 1080 - 100 )); then ok "au moins 100 px sont réservés au cadre et à la barre ($vu)"
else non "la fenêtre occuperait tout l'écran ($vu px sur 1080)"; fi

# -----------------------------------------------------------------------------
titre "3. La cascade de mesure finit sur ce qui est GARANTI"
CODE="$(sed 's/[[:space:]]*#.*$//' "$INST")"
if [[ "$(grep -c . <<< "$CODE")" -lt 60 ]]; then
	non "le décommentage n'a presque rien laissé — contrôle invalide"
else
	#  xrandr et xdotool ne sont dans AUCUNE liste stricte : s'y fier
	#  reposerait le problème un cran plus loin. python3-gi, lui, est au socle.
	grep -q 'python3 -c' <<< "$CODE" \
		&& ok "python3 (au socle) ferme la cascade de mesure" \
		|| non "la cascade ne finit pas sur un outil garanti"
	grep -qE 'h=768|h=[0-9]+$' <<< "$CODE" \
		&& ok "et une valeur de repli existe si même l'écran ne répond pas" \
		|| non "sans repli, une hauteur vide donnerait une fenêtre sans hauteur"
fi

# -----------------------------------------------------------------------------
titre "4. Le corps défile, et les boutons vivent en dehors"
BLOC="$(awk '/^gui_confirm\(\) \{/,/^\}/' "$INST")"
BLOC_CODE="$(sed 's/[[:space:]]*#.*$//' <<< "$BLOC")"

#  ═══ CHAQUE BRANCHE EST EXAMINÉE SÉPARÉMENT, ET C'EST UNE LEÇON ═══
#  Ce contrôle cherchait « --text-info » dans TOUT le bloc. Une mutation qui
#  le retirait de la seule branche yad restait donc VERTE : le « --text-info »
#  de la branche zenity, dix lignes plus bas, suffisait à le rassurer. Deux
#  branches, deux dialogues, deux vérifications — sinon on ne mesure que la
#  présence d'un mot quelque part.
BR_YAD="$(awk '/command -v yad/,/^\t\tfi$|return \$\?/' <<< "$BLOC_CODE")"
BR_ZEN="$(awk '/command -v zenity/,/return \$\?/' <<< "$BLOC_CODE")"
for paire in "yad:$BR_YAD" "zenity:$BR_ZEN"; do
	nom="${paire%%:*}"; br="${paire#*:}"
	if [[ -z "$br" ]]; then
		non "$nom : branche introuvable — contrôle sans objet"
		continue
	fi
	grep -q -- '--text-info' <<< "$br" \
		&& ok "$nom : le texte passe par une zone qui DÉFILE" \
		|| non "$nom : le texte ne défile pas — un avertissement long serait tronqué"
	grep -q -- '--height=' <<< "$br" \
		&& ok "$nom : une hauteur est imposée au dialogue" \
		|| non "$nom : aucune hauteur — la fenêtre est calculée sur le texte et déborde"
	grep -qE -- '--height="?\$' <<< "$br" \
		&& ok "$nom : cette hauteur est CALCULÉE, pas écrite en dur" \
		|| non "$nom : la hauteur est une constante — elle déborderait sur un petit écran"
done

# -----------------------------------------------------------------------------
titre "5. Ce qu'Entrée déclenche — mesuré, pas supposé"
#  ═══ LE POINT LE PLUS CONTRE-INTUITIF DE CE FICHIER ═══
#  yad donne le focus au PREMIER bouton déclaré, pas au dernier. « Annuler »
#  d'abord veut donc dire « Entrée annule », ce qui est le comportement voulu.
#  Vérifié en envoyant une vraie touche Entrée aux deux ordres : inverser
#  aurait CRÉÉ le danger qu'on croyait corriger.
if grep -qE -- '--button="Annuler[^"]*:1".*|--button="Annuler' <<< "$BLOC_CODE"; then
	premier="$(grep -oE -- '--button="[^"]+"' <<< "$BLOC_CODE" | head -1)"
	if grep -qi 'annuler' <<< "$premier"; then
		ok "yad : « Annuler » est déclaré EN PREMIER — donc c'est lui qu'Entrée déclenche"
	else
		non "yad : le premier bouton est « $premier » — Entrée lancerait l'installation"
	fi
else
	non "yad : aucun bouton « Annuler » trouvé"
fi
#  Côté zenity le danger était RÉEL (mesuré : Entrée installait), et
#  « --default-cancel » est silencieusement ignoré avec --text-info. La case à
#  cocher rend le bouton d'installation insensible tant qu'on n'a pas coché :
#  Entrée ne peut plus rien lancer.
grep -q -- '--checkbox=' <<< "$BLOC_CODE" \
	&& ok "zenity : une case à cocher garde le bouton d'installation" \
	|| non "zenity : rien n'empêche un Entrée distrait de lancer l'installation"
#  Et l'inversion des rôles est INTERDITE : zenity rend le même code pour
#  « Annuler » et pour la fermeture de la fenêtre. Fermer serait devenu
#  « installer ».
if grep -qE -- '--ok-label="Annuler' <<< "$BLOC_CODE"; then
	non "zenity : les rôles sont inversés — fermer la fenêtre lancerait l'installation"
else
	ok "zenity : les rôles ne sont pas inversés (fermer = annuler)"
fi

# -----------------------------------------------------------------------------
titre "6. La fenêtre, ouverte pour de vrai, à deux résolutions"
if ! command -v Xvfb >/dev/null 2>&1 || ! command -v yad >/dev/null 2>&1 \
   || ! command -v xdotool >/dev/null 2>&1; then
	saut "Xvfb, yad ou xdotool absent — la géométrie n'est pas mesurée ici"
else
	for res in 1920x1080 1366x768; do
		haut="${res#*x}"
		if ! xvfb_lancer "${res}x24"; then
			non "$res : Xvfb n'a pas démarré — rien à mesurer"
			continue
		fi
		aff="$XVFB_AFF"
		H="$(DISPLAY="$aff" timeout 20 bash -c "$(declare -f ecran_hauteur hauteur_dialogue); hauteur_dialogue 720")"
		#  ═══ LA PLAINTE DE YAD N'EST PLUS JETÉE ═══
		#  Avant : « 2>&1 » vers /dev/null. Quand la fenêtre ne s'ouvrait pas,
		#  le banc disait « rien à mesurer » ET RIEN D'AUTRE — pas le code de
		#  sortie, pas un mot de yad, pas la liste de ce qui était à l'écran.
		#  Mesuré sur le coureur : ce contrôle est tombé aux constructions 577,
		#  578 et 584, et il était vert aux 574, 575, 576 et 583 — sur le MÊME
		#  code. Sans trace, on ne peut que deviner, et deviner ici veut dire
		#  corriger au hasard la dernière fenêtre avant qu'un disque s'efface.
		PLAINTE="$BAC/yad-$res.err"
		seq 1 40 | sed 's/^/ligne d avertissement assez longue pour remplir la largeur /' \
		  | DISPLAY="$aff" yad --title=BANC-AVERT --width=640 --height="$H" --center \
		      --borders=16 --text-info --wrap --text="avertissement" \
		      --button="Annuler:1" --button="Installer:0" >/dev/null 2>"$PLAINTE" &
		YAD_PID=$!
		#  ═══ ON ATTEND LA FENÊTRE, ON NE DORT PLUS QUATRE SECONDES ═══
		#  ET IL FAUT DIRE CE QUE ÇA CORRIGE, ET CE QUE ÇA NE CORRIGE PAS.
		#  MESURÉ sur ce système, qui est celui du coureur (Ubuntu 24.04, yad
		#  0.40.0-1build3), en chronométrant l'apparition de la fenêtre :
		#      au repos                        : 125 à 242 ms
		#      quatre cœurs saturés (×2)       : 325 à 404 ms
		#      cache de polices vide           : 179 à 181 ms
		#  Quatre secondes n'étaient donc PAS trop courtes : la cause du rouge
		#  est ailleurs, et l'attente ci-dessous ne la corrige pas. Elle reste
		#  juste : un délai fixe affirme une durée qu'on n'a pas mesurée, et
		#  celui-ci s'arrête dès que la fenêtre est là.
		#  « xdotool search --sync », qui attendrait tout seul, N'EXISTE PAS
		#  dans cette version (3.20160805.1) : vérifié dans son propre --help,
		#  qui ne connaît ni --sync ni --timeout. D'où la boucle.
		#  On interroge jusqu'à trente secondes, et on s'arrête tout de suite
		#  si yad est mort : inutile d'attendre un programme qui n'est plus là.
		W=""; TOURS=0
		DEBUT=$(date +%s%N)
		for _ in $(seq 1 60); do
			TOURS=$((TOURS+1))
			W="$(DISPLAY="$aff" timeout 20 xdotool search --name '^BANC-AVERT$' 2>/dev/null | tail -1)"
			[[ -n "$W" ]] && break
			kill -0 "$YAD_PID" 2>/dev/null || break
			sleep 0.5
		done
		MS=$(( ($(date +%s%N) - DEBUT) / 1000000 ))
		if [[ -z "$W" ]]; then
			#  ═══ ET ON DIT LAQUELLE DES PANNES C'EST ═══
			#  Trois questions, trois réponses imprimées. C'est ce qui manquait
			#  aux constructions 577, 578 et 584 : « rien à mesurer » et pas un
			#  fait de plus, donc rien à quoi se raccrocher.
			if kill -0 "$YAD_PID" 2>/dev/null; then
				non "$res : yad TOURNE TOUJOURS après ${MS} ms et n'a pas ouvert de fenêtre"
			else
				wait "$YAD_PID" 2>/dev/null
				non "$res : yad s'est ARRÊTÉ (code $?) après ${MS} ms, sans fenêtre"
			fi
			#  1. ce que yad avait à dire
			if [[ -s "$PLAINTE" ]]; then
				sed -n '1,5p' "$PLAINTE" | sed 's/^/       yad dit : /'
			else
				printf '       %s\n' "yad n'a rien dit sur sa sortie d'erreur"
			fi
			#  2. le serveur X répond-il encore ? (si non, ce n'est pas yad)
			if GEO="$(DISPLAY="$aff" timeout 10 xdotool getdisplaygeometry 2>&1)"; then
				printf '       %s\n' "le serveur X $aff répond : $GEO"
			else
				printf '       %s\n' "le serveur X $aff NE RÉPOND PLUS : $GEO"
			fi
			#  3. ce qui est VRAIMENT à l'écran — une fenêtre ouverte sous un
			#     autre nom se verrait ici.
			VUES="$(DISPLAY="$aff" timeout 20 xdotool search --name '.' 2>/dev/null | head -5)"
			if [[ -n "$VUES" ]]; then
				for id in $VUES; do
					printf '       %s\n' "à l'écran : $(DISPLAY="$aff" timeout 10 xdotool getwindowname "$id" 2>/dev/null)"
				done
			else
				printf '       %s\n' "aucune fenêtre nommée sur $aff"
			fi
			#  4. et le bus de session, que GTK interroge au démarrage : une
			#     recherche d'accessibilité qui n'aboutit pas peut retenir une
			#     application GTK longtemps. Ici il n'y en a PAS et yad démarre
			#     en 180 ms ; sur le coureur, il y en a un. C'est la première
			#     différence entre les deux machines, alors on l'imprime.
			printf '       %s\n' "bus de session : ${DBUS_SESSION_BUS_ADDRESS:-aucun}"
		else
			geo="$(DISPLAY="$aff" timeout 20 xdotool getwindowgeometry --shell "$W" 2>/dev/null)"
			eval "$geo"
			bas=$(( Y + HEIGHT ))
			if (( bas <= haut )); then
				ok "$res : fenêtre ${WIDTH}×${HEIGHT}, bas à ${bas} px — les boutons sont à l'écran"
			else
				non "$res : la fenêtre déborde de $(( bas - haut )) px — boutons hors écran"
			fi
		fi
		kill "$YAD_PID" 2>/dev/null; wait "$YAD_PID" 2>/dev/null; YAD_PID=""
		kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null
		XVFB_PID=""
	done
fi

# -----------------------------------------------------------------------------
titre "7. Le banc ne se tire pas dans le pied"
MOTIF='[^|]\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*[qm]'
if grep -qE "$MOTIF" <<< "$(sed 's/[[:space:]]*#.*$//' "${BASH_SOURCE[0]}")"; then
	non "un texte repart dans un « grep » silencieux — course au tuyau cassé"
else
	ok "aucun texte ne repart dans un « grep » silencieux"
fi

# -----------------------------------------------------------------------------
if (( ECHOUES > 0 )); then
	printf '\n%sCe qui ne va pas :%s\n' "$GRAS" "$FIN"
	for e in "${ECHECS[@]}"; do printf '  %s·%s %s\n' "$ROUGE" "$FIN" "$e"; done
fi
printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
