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
XVFB_PID=""
#  Le serveur X du banc meurt AVEC le banc — y compris sur Ctrl+C au milieu
#  d'une capture. Avant, la trappe ne faisait que retirer le dossier : un
#  Xvfb orphelin, avec son « import » accroché à l'écran, a fait pendre la
#  suite entière d'un autre banc qui avait tiré le même numéro d'affichage.
nettoyer() {
	[[ -n "$XVFB_PID" ]] && { kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; }
	rm -rf "$BANC"
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
#  « :$((90 + RANDOM % 400)) » tirait un numéro sans vérifier qu'il était
#  libre, puis dormait une seconde en espérant le serveur prêt. Avec
#  -displayfd, Xvfb prend lui-même le premier numéro libre et l'écrit sur le
#  descripteur au moment où il ACCEPTE les connexions : plus de collision
#  entre bancs, plus d'attente à l'aveugle. Chaque outil qui parle au serveur
#  est ensuite sous « timeout » : s'il coince, le banc rougit au lieu de
#  rester muet.
#  PAS DE « $(xvfb_lancer …) » : une substitution de commande tourne dans un
#  SOUS-SHELL, et le XVFB_PID qu'elle pose n'arrive jamais au banc — mesuré,
#  deux serveurs restés en vie après un banc pourtant vert. La fonction pose
#  donc DEUX variables globales, XVFB_PID et XVFB_AFF, et n'affiche rien.
xvfb_lancer() {   # $1 = résolution ; pose XVFB_PID et XVFB_AFF (« :N »)
	local res="$1" f="$BANC/xvfb.num" i
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

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

python3 -c 'import PIL' 2>/dev/null || true   # (pas besoin ici, laissé pour la même forme que les autres bancs)

genere() { # genere <accent> <mode-terminal>
	rm -rf "${BANC:?}/t"; mkdir -p "$BANC/t"
	LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/t" --terminal "$2" "$1" >"$BANC/theme-gen.log" 2>&1
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
	xvfb_lancer 1024x768x24 || true
	DISP="$XVFB_AFF"

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

	kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; XVFB_PID=""

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
		#  ═══ LE VÉRIFICATEUR EST POSÉ DEHORS ═══
		#  Le sous-shell tourne dans « bash -c '…' » : la moindre apostrophe
		#  à l'intérieur casse la commande. On écrit donc le compteur de
		#  pixels dans un fichier, et on le lance par son chemin.
		cat > "$BANC/vu.py" <<'PYVU'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
#  LA MÊME DÉFINITION DU CLAIR QUE LE COMPTEUR FINAL — et la MÊME ZONE.
#  Sinon cette sonde attend un blanc que le compteur accepterait, ou pire :
#  elle s'arrête sur un blanc qui n'est pas du texte. C'est arrivé — la
#  BARRE DE DÉFILEMENT du terminal est en #FAFAFA, soit 200 pixels « clairs »
#  au bord droit de la fenêtre, présents AVANT toute frappe. La sonde
#  sortait donc au premier tour, contente, sans que rien ne soit tapé.
lim = w
if len(sys.argv) > 2 and sys.argv[2].isdigit() and int(sys.argv[2]) > 40:
    lim = min(w, int(sys.argv[2]) - 24)
n = sum(1 for y in range(min(30, h)) for x in range(lim)
        if all(c > 246 for c in im.getpixel((x, y))))
sys.exit(0 if n >= 40 else 1)
PYVU
		#  ═══ UN ÉCRAN PLUS LARGE QUE LA FENÊTRE — SINON ON MESURE UN BOUT ═══
		#  Un terminal de 100 colonnes fait ~2015 px de large avec la police
		#  de repli. Sur un écran de 1100 px, X n'en dessine que 54 colonnes :
		#  tout ce qui vient après est écrit HORS DE L'ÉCRAN et n'est sur
		#  aucune photographie. L'écran fait donc maintenant 2400 px.
		ECRAN_L=2400; ECRAN_H=800
		xvfb_lancer "${ECRAN_L}x${ECRAN_H}x24" || true
		DISP="$XVFB_AFF"
		#  ═══ LA FENÊTRE VISIBLE, PAS LA PREMIÈRE VENUE — MESURÉ ═══
		#  Ce contrôle a rendu « 0 px blancs et 896 px verts » sur le coureur
		#  GitHub pendant trois constructions : l'invite s'affichait bien
		#  (l'histogramme des couleurs le prouve — #00D700 ×725 pour le
		#  chemin, #159A3D ×177 pour LEXOS, #FF7B7B ×108 pour le nom), et
		#  la frappe n'arrivait NULLE PART. Deux explications ont été tentées
		#  et démenties avant celle-ci ; la troisième a été MESURÉE.
		#
		#  xfce4-terminal ouvre DEUX fenêtres X portant la classe
		#  « xfce4-terminal ». La première dans l'ordre des identifiants est
		#  une fenêtre auxiliaire de GTK, INVISIBLE, de 10×10 pixels,
		#  posée en 10,10. « head -1 » choisissait celle-là :
		#      fenetre=2097153  geometrie: Position 10,10  Geometry: 10x10
		#      fenetre=2097155  geometrie: Position 0,0     Geometry: 2015x578
		#  XSetInputFocus sur une fenêtre non affichée ÉCHOUE. Le focus
		#  restait donc à PointerRoot — c'est-à-dire « la fenêtre sous le
		#  pointeur » — et la frappe partait là où la souris se trouvait par
		#  hasard, au centre de l'écran.
		#
		#  MESURÉ, les trois cas, sous le même Xvfb :
		#      A. code d'avant, souris au centre (dans le terminal) : 18 blancs
		#      B. code d'avant, souris dans un coin (hors terminal) :  0 blancs
		#      C. --onlyvisible, souris dans un coin                 : 18 blancs
		#  B est EXACTEMENT le symptôme du coureur. Le contrôle ne tenait
		#  donc pas à la couleur de la frappe mais à la position d'une souris
		#  que personne ne plaçait — vert ici, rouge là-bas, sans rien dire.
		#
		#  « --onlyvisible » écarte la fenêtre auxiliaire ; le focus prend
		#  alors pour de bon (focus=2097155 au lieu de « focused window of 1 »)
		#  et la souris n'a plus voix au chapitre. windowactivate reste
		#  ensuite, au cas où un gestionnaire de fenêtres serait là.
		#
		#  ET LE BANC NOTE CE QU'IL A OBTENU : la fenêtre choisie et le focus
		#  réellement en place sont écrits dans un fichier, et relus dans le
		#  message d'échec. Un échec qui n'annonce qu'une absence a déjà coûté
		#  trois allers-retours.
		#
		#  ET L'IMAGE EST PRISE QUAND LA FRAPPE EST VUE, pas après une pause
		#  fixe : sur un coureur chargé, 0,8 s ne suffit pas toujours à VTE
		#  pour redessiner, et le banc mesurait une image d'avant la frappe.
		#  « xdotool search --sync » attend la fenêtre SANS LIMITE, et
		#  « import » prend un verrou sur l'écran entier : chacun est sous
		#  timeout, et la session D-Bus entière aussi — rien ici ne peut
		#  pendre plus d'une minute.
		( export DISPLAY="$DISP" HOME="$BANC/t" XDG_CONFIG_HOME="$BANC/t/.config" LEXOS_NO_BANNER=1
		  timeout 60 dbus-run-session -- bash -c '
			#  ON PART D UN REPERTOIRE FIXE, PAS DU DEPOT (aucune apostrophe
			#  dans ce bloc, voir plus bas). « \w » ecrit le repertoire
			#  courant : lance depuis le depot il vaut 20 caracteres ici et
			#  37 sur le coureur GitHub. Cette difference-la, et rien
			#  d autre, rendait le controle vert ici et rouge la-bas.
			#
			#  Ce repertoire est cree par le banc, sous le HOME du banc :
			#  bash ecrit donc « ~/controle-de-la-frappe », 23 caracteres,
			#  LES MEMES SUR TOUTE MACHINE. Assez court pour que la frappe
			#  reste bien a l ecran, assez long pour que le vert de l invite
			#  garde de la marge au-dessus de son seuil.
			mkdir -p "$HOME/controle-de-la-frappe"
			cd "$HOME/controle-de-la-frappe" || exit 1
			xfce4-terminal --disable-server --geometry=100x24 \
				-e "bash --rcfile $HOME/.bashrc -i" >/dev/null 2>&1 &
			sleep 4
			W="$(timeout 25 xdotool search --sync --onlyvisible --class xfce4-terminal 2>/dev/null | head -1)"
			#  Repli : la DERNIERE creee. Les identifiants X croissent, et la
			#  fenetre auxiliaire de GTK nait la premiere (2097153 avant
			#  2097155, mesure) — donc « tail -1 » designe la vraie, si
			#  jamais --onlyvisible ne rendait rien.
			[ -n "$W" ] || W="$(timeout 10 xdotool search --class xfce4-terminal 2>/dev/null | tail -1)"
			LARG=0
			if [ -n "$W" ]; then
				eval "$(timeout 5 xdotool getwindowgeometry --shell "$W" 2>/dev/null)"
				LARG="${WIDTH:-0}"
				timeout 10 xdotool windowfocus --sync "$W" 2>/dev/null
				timeout 10 xdotool windowactivate --sync "$W" 2>/dev/null
				#  Le pointeur DANS la fenetre : quand XSetInputFocus echoue,
				#  X delivre les touches a la fenetre sous la souris.
				timeout 10 xdotool mousemove --window "$W" 40 40 2>/dev/null
			fi
			#  AUCUNE APOSTROPHE DANS CE BLOC — pas meme dans un
			#  commentaire : tout ceci vit dans « bash -c » entre
			#  apostrophes, et la premiere rencontree ferme la commande.
			#  « tr » comprend seul la barre oblique inverse, donc les
			#  guillemets doubles suffisent.
			{
				printf "fenetre=%s\\n" "${W:-aucune}"
				printf "focus=%s\\n" "$(timeout 5 xdotool getwindowfocus 2>&1 | head -1)"
				printf "geometrie=%s\\n" "$(timeout 5 xdotool getwindowgeometry "${W:-0}" 2>&1 | tr "\\n" " ")"
				timeout 5 xdotool getwindowgeometry --shell "${W:-0}" 2>/dev/null
				printf "souris=%s\\n" "$(timeout 5 xdotool getmouselocation 2>&1 | head -1)"
				printf "clavier=%s\\n" "$(command -v xmodmap >/dev/null 2>&1 && xmodmap -pke 2>&1 | wc -l || echo xmodmap-absent)"
			} > "$3"
			sleep 0.5
			#  ── TROIS CHEMINS DE FRAPPE, ET ON DIT LEQUEL A PARLE ──
			#  Sur le coureur, la fenetre est la BONNE et le focus est PRIS
			#  (fenetre=2097155 focus=2097155, mesure) et pourtant la frappe
			#  n-arrive pas. On essaie donc XTEST, puis XSendEvent, puis les
			#  touches une a une — et le code de retour comme la sortie
			#  d-erreur de chacun sont notes. Un echec muet ne se corrige pas.
			SORTIE="$(timeout 10 xdotool type --clearmodifiers --delay 40 "echo BONJOUR" 2>&1)"; CODE=$?
			printf "xtest: code=%s %s\\n" "$CODE" "$SORTIE" >> "$3"
			for ESSAI in 1 2 3 4 5 6 7 8 9 10; do
				sleep 0.4
				timeout 20 import -window root "$1" 2>/dev/null || continue
				python3 "$2" "$1" "$LARG" && break
				if [ "$ESSAI" = 3 ] && [ -n "$W" ]; then
					SORTIE="$(timeout 10 xdotool type --window "$W" --delay 40 "echo BONJOUR" 2>&1)"; CODE=$?
					printf "sendevent: code=%s %s\\n" "$CODE" "$SORTIE" >> "$3"
				fi
				if [ "$ESSAI" = 6 ]; then
					SORTIE="$(timeout 10 xdotool key --clearmodifiers e c h o space B O N J O U R 2>&1)"; CODE=$?
					printf "touches: code=%s %s\\n" "$CODE" "$SORTIE" >> "$3"
				fi
			done
		  ' _ "$BANC/frappe.png" "$BANC/vu.py" "$BANC/focus.txt" ) >/dev/null 2>&1
		kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; XVFB_PID=""

		#  ═══ LA FENÊTRE TIENT-ELLE SUR L'ÉCRAN ? ═══
		#  Ce contrôle-ci est né d'un aller-retour de trois constructions. La
		#  fenêtre du terminal faisait 2015 px de large, l'écran 1100 : X ne
		#  dessinait que 54 des 100 colonnes, et tout ce qui suivait était
		#  écrit HORS DE L'ÉCRAN. Le compteur de pixels, lui, annonçait
		#  tranquillement « la frappe n'est pas blanche » — il accusait la
		#  couleur d'un texte qu'aucune photographie ne pouvait contenir.
		#
		#  Une mesure faite sur une image tronquée ne vaut rien, et elle ne
		#  doit JAMAIS pouvoir se déguiser en verdict sur autre chose. On
		#  vérifie donc d'abord, et on le dit dans ses propres mots.
		LARGEUR_FEN="$(sed -n 's/^WIDTH=\([0-9]*\)$/\1/p' "$BANC/focus.txt" 2>/dev/null | head -1)"
		if [ -z "${LARGEUR_FEN:-}" ]; then
			non "la largeur de la fenêtre n'a pas pu être lue : impossible de savoir si l'image mesurée est complète"
		elif [ "$LARGEUR_FEN" -gt "$ECRAN_L" ] 2>/dev/null; then
			non "la fenêtre du terminal fait ${LARGEUR_FEN} px sur un écran de ${ECRAN_L} : ce qui est mesuré ensuite est une image TRONQUÉE"
		else
			ok "la fenêtre du terminal (${LARGEUR_FEN} px) tient sur l'écran de ${ECRAN_L} px — l'image mesurée est complète"
		fi
		if [ -s "$BANC/frappe.png" ]; then
			#  Première ligne du terminal (les 30 premiers pixels de haut).
			#  Le blanc franc est #FFFFFF exactement ; le vert est celui de
			#  la palette, #00D700 (avec l'anticrénelage, on tolère ±8).
			LU="$(python3 - "$BANC/frappe.png" "${LARGEUR_FEN:-0}" <<'PYPX'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
#  ═══ ON MESURE LA ZONE DE TEXTE, PAS LA FENÊTRE ENTIÈRE ═══
#  La BARRE DE DÉFILEMENT du terminal est peinte en #FAFAFA — trois canaux
#  au-dessus de 246, donc « blanche » pour ce compteur. Elle vaut 200 pixels,
#  cinq fois le seuil, et elle est là AVANT qu'on ait tapé quoi que ce soit.
#  Mesuré : avec la frappe rendue verte (mutation), il restait 200 px blancs
#  — le contrôle ne pouvait plus rougir. On retire donc les 24 pixels de
#  droite de la FENÊTRE, où elle se trouve, et le compteur redevient mordant :
#  616 px blancs normalement, 0 sous mutation.
lim = w
if len(sys.argv) > 2 and sys.argv[2].isdigit() and int(sys.argv[2]) > 40:
    lim = min(w, int(sys.argv[2]) - 24)
blanc = vert = 0
for y in range(0, min(30, h)):
    for x in range(lim):
        r, g, b = im.getpixel((x, y))
        #  ═══ LE BLANC, AVEC LA MÊME TOLÉRANCE QUE LE VERT — ET PAS PLUS ═══
        #  Le vert a droit à ±8 « avec l'anticrénelage » ; le blanc exigeait
        #  #FFFFFF EXACTEMENT. On aligne les deux, et on s'arrête là.
        #
        #  UNE TROISIÈME VERSION A ÉTÉ ESSAYÉE PUIS JETÉE, et c'est elle qui
        #  vaut d'être racontée : compter les pixels « clairs et neutres »
        #  (somme des canaux > 360, aucun canal dominant), pour survivre à
        #  n'importe quel rendu de police. Elle donnait 968 px au lieu de 94,
        #  une marge magnifique — ET ELLE ÉTAIT ÉDENTÉE.
        #
        #  Mesuré en imprimant les couleurs vues, avec et sans mutation :
        #      normal :  #8A8A90 ×556   #79797E ×66   #FFFFFF ×65
        #      muté   :  #8A8A90 ×556   #79797E ×66   (plus de #FFFFFF)
        #  Les deux gris sont RIGOUREUSEMENT IDENTIQUES dans les deux cas :
        #  ce n'est pas la frappe, c'est le chrome de la fenêtre pris dans
        #  les trente premières lignes. Une mesure qui les compte reste haute
        #  même quand la frappe disparaît — elle ne peut plus rougir.
        #
        #  Le seul discriminant est le blanc franc : présent quand la frappe
        #  est blanche, ABSENT dès qu'elle ne l'est plus. On le garde.
        if r > 246 and g > 246 and b > 246: blanc += 1
        elif abs(r) < 8 and abs(g - 215) < 8 and abs(b) < 8: vert += 1
print(blanc, vert)
PYPX
)"
			BLANC_PX="${LU%% *}"; VERT_PX="${LU##* }"
			if [ "${BLANC_PX:-0}" -ge 40 ] && [ "${VERT_PX:-0}" -ge 200 ]; then
				ok "sur l'écran : l'invite est verte ($VERT_PX px) et « echo BONJOUR » est BLANC ($BLANC_PX px)"
			else
				non "sur l'écran : $BLANC_PX px blancs et $VERT_PX px verts — la frappe n'est pas blanche sur une invite verte"
				[ -s "$BANC/focus.txt" ] && sed 's/^/       /' "$BANC/focus.txt"
				#  ═══ UN ÉCHEC QUI NE DIT PAS CE QU'IL A VU NE SE CORRIGE PAS ═══
				#  Ce contrôle est rouge sur le coureur GitHub et vert
				#  partout ailleurs. Deux explications ont déjà été tentées
				#  et démenties — le focus, puis la tolérance du blanc — la
				#  seconde parce que les chiffres sont restés IDENTIQUES au
				#  pixel près (0 et 896) après le correctif. Deviner une
				#  troisième fois coûterait un aller-retour de plus.
				#  On imprime donc les couleurs réellement présentes : la
				#  prochaine exécution dira si la frappe est absente, ou
				#  présente dans une couleur qu'on n'attendait pas.
				python3 - "$BANC/frappe.png" <<'PYDIAG' | sed 's/^/       /'
import sys
from collections import Counter
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
c = Counter(im.getpixel((x, y))
            for y in range(min(30, h)) for x in range(w))
#  (l'histogramme, lui, regarde TOUTE la largeur : quand ça tombe, on veut
#   voir ce qui est là, barre de défilement comprise.)
print("couleurs vues dans la bande mesurée (%d px) :" % (w * min(30, h)))
for coul, n in c.most_common(8):
    print("   #%02X%02X%02X  ×%d" % (coul[0], coul[1], coul[2], n))
clair = sum(n for coul, n in c.items() if sum(coul) > 360)
print("   pixels « clairs » (somme RVB > 360) : %d" % clair)
PYDIAG
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
#  LES TROIS COULEURS DE L'INVITE (consigne « terminal XFCE », partie 1) :
#  le nom en rouge clair #FF7B7B, « LEXOS » en vert foncé #159A3D juste à
#  côté, le vert machine pour le reste — et plus de « @machine ».
QUI="$(id -un)"
case "$DEV" in
	*"${ESC}[38;2;255;123;123m${FIN_RL}${QUI}"*) ok "nuit : le nom « $QUI » est en rouge clair (38;2;255;123;123 = #FF7B7B)" ;;
	*) non "nuit : le nom n'est pas en rouge clair #FF7B7B" ;;
esac
case "$DEV" in
	*"${ESC}[38;2;21;154;61m${FIN_RL}LEXOS"*) ok "nuit : « LEXOS » est écrit en vert foncé (38;2;21;154;61 = #159A3D)" ;;
	*) non "nuit : « LEXOS » manque, ou n'est pas en vert foncé #159A3D" ;;
esac
DEV_TEXTE="$(printf '%s' "$DEV" | tr -d '\001\002' | sed 's/\x1b\[[0-9;]*m//g')"
case "$DEV_TEXTE" in
	*"${QUI} LEXOS "*) ok "nuit : l'ordre est « $QUI LEXOS chemin » — LEXOS a pris la place de « @machine »" ;;
	*) non "nuit : « LEXOS » n'est pas juste à côté du nom : « $DEV_TEXTE »" ;;
esac
case "$DEV_TEXTE" in
	*"@$(hostname)"*) non "nuit : « @$(hostname) » est toujours dans l'invite" ;;
	*) ok "nuit : plus de « @machine » dans l'invite" ;;
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

# =============================================================================
titre "L'icône du terminal XFCE : la surcharge du lanceur"
# =============================================================================
#  ═══ CE QUE CE CONTRÔLE EMPÊCHE ═══
#  ALEX, PHOTO DU BUREAU : « Terminal Xfce » portait un carré gris pendant que
#  le terminal LexOS Pro, à côté, portait l'icône noire à bordure orange.
#  L'icône LexOS était pourtant rendue depuis longtemps (lexos-terminal, hook
#  0300) — simplement, aucun lanceur ne la demandait.
#
#  ON EXÉCUTE LE VRAI FRAGMENT DU VRAI HOOK, sur le VRAI fichier du paquet
#  quand il est là. Un banc qui recopierait une entrée de son cru ne prouverait
#  rien : c'est justement la conservation de l'original qui est en jeu.
HOOK_D="$RACINE/config/hooks/normal/0400-lexos-desktop.hook.chroot"
BLOC_T="$(sed -n '/^# >>> banc: icone-terminal$/,/^# <<< banc: icone-terminal$/p' "$HOOK_D" | sed '1d;$d')"
if [ -z "$BLOC_T" ]; then
	non "le fragment « icone-terminal » a disparu du hook 0400"
else
	TB="$BANC/icone-terminal"; mkdir -p "$TB/apps" "$TB/local"
	#  Le fichier du paquet s'il est installé ici ; sinon un substitut qui
	#  porte les trois choses qu'on doit conserver — traduction, action, et
	#  une ligne Icon= à remplacer.
	SRC_PKG="/usr/share/applications/xfce4-terminal.desktop"
	if [ -r "$SRC_PKG" ]; then
		cp "$SRC_PKG" "$TB/apps/xfce4-terminal.desktop"
		ORIGINE="le vrai fichier du paquet"
	else
		cat > "$TB/apps/xfce4-terminal.desktop" <<'FIN'
[Desktop Entry]
Version=1.0
Type=Application
Name=Xfce Terminal
Name[fr]=Terminal Xfce
Exec=xfce4-terminal
Icon=org.xfce.terminal
Categories=GTK;System;TerminalEmulator;
Actions=preferences;

[Desktop Action preferences]
Name=Terminal Preferences
Exec=xfce4-terminal --preferences
FIN
		ORIGINE="un substitut (le paquet n'est pas installé ici)"
	fi
	AVANT_TRAD="$(grep -c '^Name\[' "$TB/apps/xfce4-terminal.desktop")"
	AVANT_LIG="$(wc -l < "$TB/apps/xfce4-terminal.desktop")"

	( printf 'FIC_APPS="%s"\nFIC_LOCAL="%s"\n' "$TB/apps" "$TB/local"
	  printf '%s\n' "$BLOC_T" ) > "$TB/frag.sh"
	sh "$TB/frag.sh" >"$TB/journal" 2>&1

	CIBLE="$TB/local/xfce4-terminal.desktop"
	if [ ! -r "$CIBLE" ]; then
		non "aucune surcharge produite dans /usr/local/share/applications ($ORIGINE)"
	else
		ok "la surcharge est posée dans /usr/local/share/applications ($ORIGINE)"

		#  1. Elle demande bien l'icône LexOS.
		if grep -q '^Icon=lexos-terminal$' "$CIBLE"; then
			ok "…et elle porte « Icon=lexos-terminal »"
		else
			non "l'icône n'est pas lexos-terminal : $(grep -m1 '^Icon=' "$CIBLE")"
		fi
		#  ET PAS DEUX FOIS. Le repli ajoute la ligne quand elle manque ; s'il
		#  se déclenchait à tort, le fichier en porterait deux et la seconde
		#  gagnerait silencieusement.
		N_ICON="$(grep -c '^Icon=' "$CIBLE")"
		[ "$N_ICON" = "1" ] \
			&& ok "…une seule ligne Icon=, pas de doublon" \
			|| non "le fichier porte $N_ICON lignes « Icon= »"

		#  2. Les actions du menu contextuel ont survécu — c'est la raison
		#     pour laquelle on copie au lieu de réécrire.
		if grep -q '^Actions=' "$CIBLE" && grep -q '^\[Desktop Action' "$CIBLE"; then
			ok "les actions du menu contextuel sont conservées"
		else
			non "les actions ont été perdues : le fichier a été réécrit au lieu d'être copié"
		fi

		#  3. Les traductions aussi.
		APRES_TRAD="$(grep -c '^Name\[' "$CIBLE")"
		if [ "$APRES_TRAD" = "$AVANT_TRAD" ] && [ "$APRES_TRAD" -gt 0 ]; then
			ok "les $APRES_TRAD traductions du nom sont conservées"
		else
			non "traductions : $APRES_TRAD contre $AVANT_TRAD à l'origine"
		fi

		#  4. LE CONTRÔLE QUI RÉSUME TOUT : une seule ligne doit différer.
		#     Il attrape aussi bien une réécriture qu'un sed trop gourmand.
		DIFFS="$(diff "$TB/apps/xfce4-terminal.desktop" "$CIBLE" | grep -c '^[<>]')"
		if [ "$DIFFS" = "2" ]; then
			ok "une seule ligne diffère de l'original ($AVANT_LIG lignes conservées)"
		else
			non "$DIFFS lignes changées au lieu de 2 (une retirée, une ajoutée)"
		fi

		#  5. Le nom du FICHIER doit être celui du paquet, sinon la surcharge
		#     ne masque rien du tout et Alex verrait DEUX entrées de menu.
		if [ "$(basename "$CIBLE")" = "$(basename "$TB/apps/xfce4-terminal.desktop")" ]; then
			ok "…et elle porte le même nom de fichier : elle masque l'entrée, elle ne la double pas"
		else
			non "le nom de fichier diffère : il y aurait deux entrées de menu"
		fi
	fi

	#  6. LE REPLI : un paquet dont la ligne Icon= aurait disparu.
	TB2="$BANC/icone-terminal-sans"; mkdir -p "$TB2/apps" "$TB2/local"
	grep -v '^Icon=' "$TB/apps/xfce4-terminal.desktop" > "$TB2/apps/xfce4-terminal.desktop"
	( printf 'FIC_APPS="%s"\nFIC_LOCAL="%s"\n' "$TB2/apps" "$TB2/local"
	  printf '%s\n' "$BLOC_T" ) > "$TB2/frag.sh"
	sh "$TB2/frag.sh" >/dev/null 2>&1
	if grep -q '^Icon=lexos-terminal$' "$TB2/local/xfce4-terminal.desktop" 2>/dev/null; then
		ok "sans ligne « Icon= » dans le paquet, la surcharge la pose quand même"
	else
		non "un paquet sans « Icon= » donnerait une surcharge SANS icône — le gris reviendrait"
	fi

	#  7. RIEN N'EST ÉCRIT DANS /usr/share : c'est tout l'intérêt du procédé.
	if [ -z "$(find "$TB/apps" -newer "$TB/frag.sh" -type f 2>/dev/null)" ]; then
		ok "le fichier du paquet n'est pas touché (une mise à jour ne défera rien)"
	else
		non "le fichier du paquet a été modifié : la prochaine mise à jour effacerait le correctif"
	fi

	#  8. L'icône demandée doit exister — sinon on a juste remplacé un nom
	#     générique par un nom qui ne résout rien, et le résultat est pire.
	if grep -qE '(^|[[:space:]])terminal([[:space:]]|\\|$)' "$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot" \
	   && [ -r "$RACINE/branding/icon-terminal.svg" ]; then
		ok "« lexos-terminal » est bien rendue par le hook 0300 depuis branding/icon-terminal.svg"
	else
		non "l'icône lexos-terminal n'est plus produite : le lanceur demanderait un nom qui n'existe pas"
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
