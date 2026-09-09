#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-intro — la vidéo qui joue à l'ouverture de session
# =============================================================================
#  POURQUOI CE BANC EST PARTICULIER, ET CE QU'IL ÉPROUVE EN PREMIER.
#
#  Ce programme tourne entre le mot de passe et le bureau. S'il se bloque,
#  Alex ne voit jamais son bureau. Sa seule règle absolue n'est donc pas
#  « la vidéo joue » — c'est « LA SESSION PART, QUOI QU'IL ARRIVE ». Les
#  replis passent avant le cas qui marche, dans ce fichier comme dans la
#  consigne.
#
#  ON NE LIT PAS LE CODE, ON LE FAIT TOURNER. Chaque repli est joué pour de
#  vrai : un PATH sans mpv, un dossier sans vidéo, un faux mpv qui IGNORE
#  SIGTERM, une ligne de commande de noyau qui dit « boot=live ». Les seams
#  (LEXOS_INTRO_DIR, LEXOS_CMDLINE, LEXOS_PERF_ETAT, LEXOS_INTRO_DELAI)
#  déplacent ce que le programme lit — ils ne lui donnent aucun droit.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-intro"
AUTOSTART="$RACINE/config/includes.chroot/etc/skel/.config/autostart/lexos-intro.desktop"
BRANDING="$RACINE/branding"
BANC="$(mktemp -d)"

XVFB_PID=""
nettoyer() {
	[ -n "$XVFB_PID" ] && { kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; }
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

[ -x "$OUTIL" ] || { echo "lexos-intro introuvable ou non exécutable"; exit 1; }

# --- Le décor commun ---------------------------------------------------------
mkdir -p "$BANC/conf/lexos" "$BANC/marque" "$BANC/vide"

# --- Les deux vidéos jouées sont FABRIQUÉES, pas copiées ---------------------
#  ═══ POURQUOI CE BANC APPELLE LE HOOK 0300 ═══
#  branding/apres-connexion.mp4 est le CARRÉ de 720 × 720 déposé par Alex.
#  Ce n'est PAS ce que lexos-intro ouvre : le hook 0300 en fabrique, à la
#  construction, un 1920 × 1080 — copie agrandie et floutée en fond, le carré
#  net centré par-dessus. Copier la source dans le décor du banc éprouverait
#  donc un fichier QUI N'EXISTE NULLE PART sur une machine LexOS.
#  On exécute le vrai fragment du vrai hook, découpé entre ses deux repères.
#
#  SUR LA SOURCE ENTIÈRE, et ça coûte 24 s — assumé. Une coupe courte
#  fabriquerait une vidéo de 2 s, et la section 5 (le recouvrement mesuré
#  sous Xvfb) regarde la fenêtre mpv APRÈS 5 s : la vidéo serait déjà finie,
#  la fenêtre fermée, et le contrôle passerait au vert en n'ayant rien
#  mesuré. Un banc rapide qui ne prouve plus rien n'est pas un gain.
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
if [ -r "$BRANDING/apres-connexion.mp4" ] && command -v ffmpeg >/dev/null 2>&1; then
	cp "$BRANDING/apres-connexion.mp4" "$BANC/marque/apres-connexion.mp4"
	{
		printf 'have() { command -v "$1" >/dev/null 2>&1; }\nBRAND="%s"\n' "$BANC/marque"
		sed -n '/^# >>> banc: apres-connexion$/,/^# <<< banc: apres-connexion$/p' "$HOOK" \
			| sed '1d;$d'
	} > "$BANC/fragment.sh"
	#  ═══ SOUS « timeout », PARCE QUE CE FRAGMENT S'EST DÉJÀ FIGÉ ═══
	#  « -t » en option d'ENTRÉE bloquait ffmpeg pour toujours (voir le
	#  commentaire du hook). Le hook a son propre filet à 600 s ; ici on
	#  serre à 240, mesuré contre 25 s de fabrication réelle. Un banc qui
	#  pend vingt minutes, personne ne le relance.
	timeout 240 bash "$BANC/fragment.sh" >"$BANC/fragment.log" 2>&1
fi
printf 'medium\n' > "$BANC/perf"
printf 'BOOT_IMAGE=/vmlinuz root=/dev/sda1 ro quiet splash\n' > "$BANC/cmdline"
printf 'boot=live components username=lex quiet splash\n' > "$BANC/cmdline-live"
printf 'vif\n' > "$BANC/perf-vif"

#  Lance l'outil avec le décor, et rend son code de sortie ET son journal.
lance() { # lance [VAR=val ...] -> écrit dans $BANC/err
	env XDG_CONFIG_HOME="$BANC/conf" \
	    LEXOS_INTRO_DIR="$BANC/marque" \
	    LEXOS_CMDLINE="$BANC/cmdline" \
	    LEXOS_PERF_ETAT="$BANC/perf" \
	    DISPLAY=":99" \
	    "$@" bash "$OUTIL" >/dev/null 2>"$BANC/err"
}
journal() { cat "$BANC/err" 2>/dev/null; }

# =============================================================================
titre "1. LA SESSION PART QUOI QU'IL ARRIVE — les replis, éprouvés d'abord"
# =============================================================================
#  Chacun de ces cas doit rendre 0, sans rien afficher, en le disant dans le
#  journal. Un code de sortie non nul remonterait à l'autostart ; un message
#  à l'écran serait la première chose qu'on verrait de sa machine.

# --- mpv absent : un PATH de liens symboliques SANS mpv ----------------------
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
	non "le PATH sans mpv n'a pas pu être fabriqué : le contrôle suivant ne prouverait rien"
else
	lance PATH="$SANS_MPV"
	RC=$?
	if [ "$RC" = "0" ] && grep -q 'mpv absent' <<< "$(journal)"; then
		ok "sans mpv : la session part (code 0) et le journal nomme le paquet manquant"
	else
		non "sans mpv : code $RC, journal « $(journal | head -1) »"
	fi
fi

# --- Fichier absent ----------------------------------------------------------
lance LEXOS_INTRO_DIR="$BANC/vide"
RC=$?
if [ "$RC" = "0" ] && grep -q 'fichier absent' <<< "$(journal)"; then
	ok "sans le fichier vidéo : la session part, et le journal donne le chemin cherché"
else
	non "fichier absent : code $RC, journal « $(journal | head -1) »"
fi

# --- Pas d'écran (console, ssh) ---------------------------------------------
env XDG_CONFIG_HOME="$BANC/conf" LEXOS_INTRO_DIR="$BANC/marque" \
    LEXOS_CMDLINE="$BANC/cmdline" LEXOS_PERF_ETAT="$BANC/perf" \
    DISPLAY="" WAYLAND_DISPLAY="" bash "$OUTIL" >/dev/null 2>"$BANC/err"
RC=$?
if [ "$RC" = "0" ] && grep -q "pas d'écran" <<< "$(journal)"; then
	ok "sans écran : rien n'est lancé, la session part"
else
	non "sans écran : code $RC, journal « $(journal | head -1) »"
fi

# --- Session live ------------------------------------------------------------
#  Quelqu'un qui essaie LexOS depuis une clé veut voir le bureau, pas
#  attendre. Même repère que le garde-fou de la démo : « boot=live ».
lance LEXOS_CMDLINE="$BANC/cmdline-live"
RC=$?
if [ "$RC" = "0" ] && grep -q 'session live' <<< "$(journal)"; then
	ok "en session live : pas de vidéo, la session part"
else
	non "session live : code $RC, journal « $(journal | head -1) »"
fi

# --- Profil « vif » ----------------------------------------------------------
lance LEXOS_PERF_ETAT="$BANC/perf-vif"
RC=$?
if [ "$RC" = "0" ] && grep -q 'profil vif' <<< "$(journal)"; then
	ok "sous le profil « vif » : pas de vidéo — ce profil veut une machine qui répond tout de suite"
else
	non "profil vif : code $RC, journal « $(journal | head -1) »"
fi

# --- Réglage « aucune » ------------------------------------------------------
printf 'aucune\n' > "$BANC/conf/lexos/intro-video"
lance
RC=$?
if [ "$RC" = "0" ] && grep -q 'aucune' <<< "$(journal)"; then
	ok "réglage « aucune » : pas de vidéo, la session part"
else
	non "réglage aucune : code $RC, journal « $(journal | head -1) »"
fi

# --- Réglage abîmé : on ne laisse pas un fichier décider -----------------
printf 'nimportequoi\n' > "$BANC/conf/lexos/intro-video"
lance PATH="$SANS_MPV"
if grep -q 'inconnu' <<< "$(journal)" && grep -q 'mpv absent' <<< "$(journal)"; then
	ok "réglage illisible : on le dit ET on retombe sur « courte » (la suite se déroule)"
else
	non "réglage illisible : « $(journal | head -2 | tr '\n' ' ') »"
fi
rm -f "$BANC/conf/lexos/intro-video"

# =============================================================================
titre "2. LA MINUTERIE DURE — même un mpv figé rend la main"
# =============================================================================
#  Le cas qui enfermerait Alex dehors : mpv vivant mais bloqué, fenêtre
#  plein écran par-dessus tout. On le fabrique — un faux mpv qui IGNORE
#  SIGTERM — et on mesure le temps que le programme met à rendre la main.
FIGE="$BANC/fige"
mkdir -p "$FIGE"
printf '#!/bin/bash\ntrap "" TERM\nexec -a lexosbancfige sleep 300\n' > "$FIGE/mpv"
chmod +x "$FIGE/mpv"
T0="$(date +%s)"
lance PATH="$FIGE:$PATH" LEXOS_INTRO_DELAI=3
RC=$?
T1="$(date +%s)"
ECOULE=$((T1 - T0))
if [ "$RC" = "0" ] && [ "$ECOULE" -le 8 ]; then
	ok "mpv figé (il ignore SIGTERM) : la main est rendue en ${ECOULE} s, code 0"
else
	non "mpv figé : ${ECOULE} s et code $RC — la session resterait derrière la vidéo"
fi
sleep 1
if pgrep -x lexosbancfige >/dev/null 2>&1; then
	non "le mpv figé SURVIT à la minuterie : sa fenêtre resterait sur l'écran"
	pkill -x lexosbancfige 2>/dev/null
else
	ok "…et le processus figé a été TUÉ : « timeout -k » escalade jusqu'à SIGKILL"
fi

# =============================================================================
titre "3. CE QUE LE PROGRAMME NE DOIT JAMAIS FAIRE"
# =============================================================================
CODE="$(sed 's/#.*$//' "$OUTIL")"
#  Aucune fenêtre d'erreur : ni zenity, ni yad, ni notify-send. Le journal,
#  et rien d'autre.
if grep -qE 'zenity|yad|notify-send|xmessage' <<< "$CODE"; then
	non "le programme peut afficher une fenêtre : à l'ouverture de session, ce serait la première chose qu'on voit"
else
	ok "aucune fenêtre d'erreur possible — tout passe par le journal"
fi
#  Il ne rend jamais autre chose que 0 : l'autostart n'a rien à réparer.
if grep -qE '^exit 0$' <<< "$CODE" && ! grep -qE '^[[:space:]]*exit [1-9]' <<< "$CODE"; then
	ok "il ne rend jamais un code d'erreur — sauf sur signal (130/143), comme il se doit"
else
	non "le programme peut rendre un code non nul : l'autostart le signalerait"
fi
#  Le son est COUPÉ par défaut : c'est une décision de vie, pas un détail.
if grep -q 'SON="off"' <<< "$CODE" && grep -q -- '--no-audio' <<< "$CODE"; then
	ok "le son est coupé par défaut, et « --no-audio » est bien ce qui l'applique"
else
	non "le son n'est pas coupé par défaut"
fi
#  Et la configuration de l'utilisateur n'est pas lue : ni ses raccourcis,
#  ni son volume de mpv.
if grep -q -- '--no-config' <<< "$CODE"; then
	ok "« --no-config » : les réglages mpv de l'utilisateur ne s'appliquent pas à cette vidéo"
else
	non "sans --no-config, un ~/.config/mpv pourrait changer le comportement de l'ouverture de session"
fi

# =============================================================================
titre "4. L'ENTRÉE D'AUTOSTART"
# =============================================================================
if [ ! -r "$AUTOSTART" ]; then
	non "aucune entrée d'autostart : la vidéo ne serait jamais lancée"
else
	CODE_D="$(grep -Ev '^[[:space:]]*#' "$AUTOSTART")"
	if grep -qx 'Exec=lexos-intro' <<< "$CODE_D"; then
		ok "l'autostart appelle lexos-intro — pas mpv en direct : les gardes vivent dans le programme"
	else
		non "l'autostart n'appelle pas lexos-intro"
	fi
	if ! grep -qE '^Exec=.*mpv' <<< "$CODE_D"; then
		ok "…et mpv n'est nommé nulle part dans l'entrée"
	else
		non "l'entrée appelle mpv directement : les replis seraient contournés"
	fi
	if grep -qx 'X-GNOME-Autostart-enabled=true' <<< "$CODE_D" && grep -qx 'Terminal=false' <<< "$CODE_D"; then
		ok "l'entrée est active et sans terminal"
	else
		non "l'entrée n'est pas active, ou ouvrirait un terminal"
	fi
fi

# =============================================================================
titre "5. LE RECOUVREMENT NE DÉPEND PAS DU GESTIONNAIRE DE FENÊTRES"
# =============================================================================
#  ═══ CE CONTRÔLE EST NÉ D'UNE MESURE ═══
#  Premier jet : « --fullscreen » seul. Le plein écran passe par une requête
#  au GESTIONNAIRE DE FENÊTRES — or ce programme est lancé au moment même où
#  la session démarre, xfwm4 n'est pas forcément là. Mesuré sous un serveur X
#  SANS gestionnaire : la fenêtre faisait 1080×720 au milieu de l'écran, la
#  vidéo en timbre-poste. On le mesure donc ici, dans les mêmes conditions.
if ! command -v Xvfb >/dev/null 2>&1 || ! command -v xdotool >/dev/null 2>&1 \
   || ! command -v mpv >/dev/null 2>&1 || [ ! -r "$BANC/marque/apres-connexion-16-9.mp4" ]; then
	saut "Xvfb, xdotool, mpv ou la vidéo manquent : le recouvrement n'est pas mesuré"
else
	: > "$BANC/xnum"
	Xvfb -displayfd 3 -screen 0 1920x1080x24 3>"$BANC/xnum" >/dev/null 2>&1 &
	XVFB_PID=$!
	for _ in $(seq 1 100); do [ -s "$BANC/xnum" ] && break; sleep 0.1; done
	if [ ! -s "$BANC/xnum" ]; then
		non "Xvfb n'a pas démarré : le recouvrement n'est pas mesuré"
	else
		AFF=":$(tr -dc 0-9 < "$BANC/xnum")"
		printf 'complete\n' > "$BANC/conf/lexos/intro-video"
		( env XDG_CONFIG_HOME="$BANC/conf" LEXOS_INTRO_DIR="$BANC/marque" \
		      LEXOS_CMDLINE="$BANC/cmdline" LEXOS_PERF_ETAT="$BANC/perf" \
		      DISPLAY="$AFF" bash "$OUTIL" ) >/dev/null 2>&1 &
		JOUEUR=$!
		sleep 5
		FEN="$(DISPLAY="$AFF" timeout 20 xdotool search --class mpv 2>/dev/null | head -1)"
		if [ -z "$FEN" ]; then
			non "aucune fenêtre mpv : la vidéo ne s'est pas ouverte"
		else
			GEO="$(DISPLAY="$AFF" timeout 20 xdotool getwindowgeometry --shell "$FEN" 2>/dev/null)"
			eval "$GEO"
			if [ "${WIDTH:-0}" = "1920" ] && [ "${HEIGHT:-0}" = "1080" ] \
			   && [ "${X:-1}" = "0" ] && [ "${Y:-1}" = "0" ]; then
				ok "SANS gestionnaire de fenêtres, la fenêtre couvre tout l'écran (${WIDTH}×${HEIGHT} en 0,0)"
			else
				non "la fenêtre fait ${WIDTH:-?}×${HEIGHT:-?} en ${X:-?},${Y:-?} — elle ne couvre pas l'écran sans gestionnaire"
			fi
			#  ═══ CE CONTRÔLE A CHANGÉ DE SENS, ET C'EST LA CONSIGNE ═══
			#  Il demandait l'INVERSE : le fichier d'alors était un 1080×720
			#  posé au centre, et on vérifiait 150 px de noir de chaque côté.
			#  Alex a changé de fichier pour un CARRÉ lumineux jusqu'aux
			#  bords, où ces bandes deviendraient 420 px de noir — « pas une
			#  intro, une panne d'affichage ». Le hook 0300 fabrique donc un
			#  1920 × 1080 avec un halo flouté sur les côtés.
			#  On mesure maintenant qu'il N'Y A PLUS DE BANDE : l'image
			#  atteint les deux bords de l'écran. Ce contrôle est passé au
			#  rouge tout seul le jour du changement — c'est exactement ce
			#  qu'on lui demande.
			if command -v import >/dev/null 2>&1 && python3 -c 'import PIL' 2>/dev/null; then
				DISPLAY="$AFF" timeout 20 import -window root "$BANC/ecran.png" 2>/dev/null
				MESURE="$(python3 - "$BANC/ecran.png" <<'PYIMG'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
xs = [x for x in range(w) if any(sum(im.getpixel((x, y))) > 150 for y in range(0, h, 8))]
print("%d %d %d" % (xs[0], xs[-1], w) if xs else "0 0 %d" % w)
PYIMG
)"
				set -- $MESURE
				GAUCHE="$1"; DROITE="$2"; LARG="$3"
				BANDE_D=$((LARG - 1 - DROITE))
				#  ═══ LE SEUIL EST À 100 px, ET IL EST MESURÉ ═══
				#  Il était à 8. Rouge, et à tort : le halo est FLOU et la
				#  vidéo BOUGE. Selon l'image saisie, ses dernières colonnes
				#  tombent sous le seuil de luminosité — mesuré 0 px à gauche
				#  et 37 px à droite sur une image, 0 et 0 sur une autre. Le
				#  contrôle dépendait donc du hasard du moment de la capture.
				#
				#  Ce qu'on veut écarter n'est pas une bande de 37 px : c'est
				#  le carré posé sur du noir, qui en donnerait 420 de chaque
				#  côté (mesuré à la mutation). 100 px laisse quatre fois de
				#  marge sous ce défaut-là tout en absorbant la variation
				#  d'image. Et le contrôle du FICHIER, lui, reste strict :
				#  netteté et luminosité des bandes sont mesurées en
				#  section 7, sur des images extraites, pas sur l'écran.
				if [ "$GAUCHE" -le 100 ] && [ "$BANDE_D" -le 100 ]; then
					ok "aucune bande noire : l'image atteint les deux bords (${GAUCHE} px à gauche, ${BANDE_D} px à droite)"
				else
					non "bandes de ${GAUCHE} et ${BANDE_D} px — le halo n'est pas posé, la vidéo flotte sur du noir"
				fi
			else
				saut "import ou Pillow absent : les bandes noires ne sont pas mesurées"
			fi
			#  ═══ UNE TOUCHE COUPE, TOUT DE SUITE ═══
			T0="$(date +%s)"
			DISPLAY="$AFF" timeout 10 xdotool key --window "$FEN" a 2>/dev/null \
				|| DISPLAY="$AFF" timeout 10 xdotool key a 2>/dev/null
			wait "$JOUEUR" 2>/dev/null
			T1="$(date +%s)"
			if [ $((T1 - T0)) -le 3 ]; then
				ok "une touche arrête la vidéo tout de suite ($((T1 - T0)) s), sans attendre les 10 s"
			else
				non "après la touche, la vidéo a continué $((T1 - T0)) s"
			fi
		fi
		kill "$JOUEUR" 2>/dev/null
		wait "$JOUEUR" 2>/dev/null
	fi
	kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; XVFB_PID=""
	rm -f "$BANC/conf/lexos/intro-video"
fi

# =============================================================================
titre "6. LE RÉGLAGE DES PARAMÈTRES ÉCRIT CE QUE LE PROGRAMME LIT"
# =============================================================================
#  ═══ LE DÉFAUT DE FAMILLE QU'ON ÉVITE ICI ═══
#  Une page qui écrit dans un fichier, un programme qui en lit un autre : les
#  deux marchent seuls, le réglage ne fait rien, et personne ne voit
#  pourquoi. On ne compare donc pas deux chemins écrits à la main — on FAIT
#  écrire la page, puis on FAIT lire le programme, et on regarde s'il obéit.
SETTINGS="$RACINE/config/includes.chroot/usr/lib/lexos"
if ! command -v python3 >/dev/null 2>&1 || [ ! -r "$SETTINGS/settings.py" ]; then
	saut "python3 ou settings.py absent : le réglage n'est pas éprouvé"
else
	rm -rf "$BANC/reglage"; mkdir -p "$BANC/reglage"
	#  Le défaut, AVANT que rien ne soit écrit.
	DEFAUT="$(cd "$SETTINGS" && XDG_CONFIG_HOME="$BANC/reglage" python3 -c '
import settings
e = settings._intro_etat()
print("%s %s" % (e["choix"], "on" if e["son"] else "off"))
' 2>/dev/null)"
	if [ "$DEFAUT" = "courte off" ]; then
		ok "au départ : vidéo « courte » et son COUPÉ — le son ne s'allume pas tout seul"
	else
		non "défauts inattendus : « $DEFAUT » (attendu « courte off »)"
	fi

	#  La page écrit « aucune » ; le programme doit s'arrêter dessus.
	ECRIT="$(cd "$SETTINGS" && XDG_CONFIG_HOME="$BANC/reglage" python3 -c '
import settings
print(settings.act_intro("aucune").get("ok"))
' 2>/dev/null)"
	lance XDG_CONFIG_HOME="$BANC/reglage"
	if [ "$ECRIT" = "True" ] && grep -q 'aucune' <<< "$(journal)"; then
		ok "« Aucune » choisi dans les Paramètres : lexos-intro le lit et ne joue rien"
	else
		non "le réglage écrit par la page n'est pas celui que le programme lit (écrit=$ECRIT, journal « $(journal | head -1) »)"
	fi

	#  Et une valeur inventée est refusée par la page : ce qui atterrit dans
	#  le fichier est relu à chaque ouverture de session.
	REFUS="$(cd "$SETTINGS" && XDG_CONFIG_HOME="$BANC/reglage" python3 -c '
import settings
print(settings.act_intro("nimportequoi").get("ok"))
' 2>/dev/null)"
	[ "$REFUS" = "False" ] \
		&& ok "une valeur inventée est refusée par la page, pas écrite dans le fichier" \
		|| non "la page a accepté une valeur inventée"

	#  L'interrupteur du son bascule, dans les deux sens.
	SONS="$(cd "$SETTINGS" && XDG_CONFIG_HOME="$BANC/reglage" python3 -c '
import settings
a = settings._intro_etat()["son"]
settings.act_intro("son"); b = settings._intro_etat()["son"]
settings.act_intro("son"); c = settings._intro_etat()["son"]
print("%s %s %s" % (a, b, c))
' 2>/dev/null)"
	[ "$SONS" = "False True False" ] \
		&& ok "l'interrupteur du son bascule dans les deux sens" \
		|| non "l'interrupteur du son : « $SONS » (attendu « False True False »)"

	#  La page doit exposer l'état, sinon les boutons ne peuvent pas montrer
	#  le choix courant — le défaut corrigé pour les fonds d'écran.
	APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
	if grep -q 'etat.intro' "$APP" && grep -q 'setIntro' "$APP" && grep -q 'basculeIntroSon' "$APP"; then
		ok "la page lit etat.intro et porte les deux commandes (choix + son)"
	else
		non "la page ne lit pas l'état de la vidéo, ou n'a pas ses commandes"
	fi
	if grep -q '"intro": act_intro,' "$SETTINGS/settings.py"; then
		ok "…et le moteur connaît l'action « intro »"
	else
		non "l'action « intro » n'est pas dans la table du moteur : les boutons seraient morts"
	fi
fi

# =============================================================================
titre "7. LE HALO — ce que le hook 0300 fabrique vraiment"
# =============================================================================
#  ═══ ON MESURE L'IMAGE PRODUITE, PAS LE FILTRE ÉCRIT ═══
#  Le fichier d'Alex est carré (720 × 720) et lumineux jusqu'aux bords. La
#  consigne écarte deux rendus : le carré étiré (la mascotte déformée) et le
#  carré posé sur du noir (420 px de noir de chaque côté d'un carré de
#  flammes — « une panne d'affichage »). Le hook fabrique donc un fond
#  agrandi et FORTEMENT FLOUTÉ, le carré net centré par-dessus.
#
#  Trois choses se vérifient sur l'image, et aucune ne se lit dans le code :
#    · le format est bien 1920 × 1080 ;
#    · le centre est NET (c'est la vidéo, pas le fond) ;
#    · les côtés sont FLOUS et NON NOIRS (c'est le halo, pas des bandes).
#  Un « grep gblur » aurait dit oui à un filtre mal branché.
if ! command -v ffprobe >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1 \
   || ! python3 -c 'import PIL' 2>/dev/null \
   || [ ! -r "$BANC/marque/apres-connexion-16-9.mp4" ]; then
	saut "ffprobe, Pillow ou la vidéo fabriquée manquent : le halo n'est pas mesuré"
else
	for F in apres-connexion-16-9.mp4 apres-connexion-16-9-courte.mp4; do
		DIM="$(ffprobe -v error -select_streams v:0 \
			-show_entries stream=width,height -of csv=p=0:s=x \
			"$BANC/marque/$F" 2>/dev/null)"
		[ "$DIM" = "1920x1080" ] \
			&& ok "$F : $DIM" \
			|| non "$F : « $DIM » (attendu 1920x1080)"
	done

	#  La source carrée ne doit PAS rester dans le dossier : c'est une source
	#  de construction. Mais le hook ne l'efface qu'à son chemin de
	#  production — ici, dans le décor du banc, elle survit à dessein. On
	#  vérifie donc la garde plutôt que l'effacement.
	if grep -q 'if \[ "\$APRES_SRC" = "/usr/share/lexos/branding/apres-connexion.mp4" \]' \
		"$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"; then
		ok "le carré n'est effacé qu'à son chemin de production (le dépôt est à l'abri)"
	else
		non "l'effacement du carré n'est pas gardé : un banc pourrait manger branding/"
	fi

	ffmpeg -v error -y -ss 1 -i "$BANC/marque/apres-connexion-16-9.mp4" \
		-vf crop=1080:1080:420:0 -frames:v 1 "$BANC/centre.png" </dev/null 2>/dev/null
	ffmpeg -v error -y -ss 1 -i "$BANC/marque/apres-connexion-16-9.mp4" \
		-vf crop=420:1080:0:0 -frames:v 1 "$BANC/bande.png" </dev/null 2>/dev/null
	MESURE="$(python3 - "$BANC/centre.png" "$BANC/bande.png" <<'PY' 2>/dev/null
import sys
from PIL import Image, ImageChops, ImageStat
def nettete(a):
    w, h = a.size
    dx = ImageChops.difference(a.crop((1, 0, w, h)), a.crop((0, 0, w - 1, h)))
    dy = ImageChops.difference(a.crop((0, 1, w, h)), a.crop((0, 0, w, h - 1)))
    return (ImageStat.Stat(dx).mean[0] + ImageStat.Stat(dy).mean[0]) / 2
c = Image.open(sys.argv[1]).convert("L")
b = Image.open(sys.argv[2]).convert("L")
print("%.3f %.3f %.1f" % (nettete(c), nettete(b), ImageStat.Stat(b).mean[0]))
PY
)"
	set -- $MESURE
	NET_C="${1:-0}"; NET_B="${2:-0}"; LUM_B="${3:-0}"
	#  Seuils choisis LARGES à dessein : mesuré sur ce fichier, le centre est
	#  7× plus net que la bande (3,52 contre 0,48) et la bande est à 55 de
	#  luminosité. On demande un rapport de 2 et une luminosité de 8 — de quoi
	#  distinguer « halo » de « bandes noires » sans casser au prochain
	#  fichier qu'Alex enverra.
	if awk "BEGIN{exit !($NET_C > $NET_B * 2)}"; then
		ok "le centre est net, les côtés sont flous (netteté $NET_C contre $NET_B)"
	else
		non "le centre n'est pas plus net que les côtés ($NET_C contre $NET_B) : le halo n'est pas posé"
	fi
	if awk "BEGIN{exit !($LUM_B > 8)}"; then
		ok "les côtés sont un halo, pas des bandes noires (luminosité $LUM_B)"
	else
		non "les côtés sont noirs (luminosité $LUM_B) : c'est le rendu que la consigne écarte"
	fi
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
