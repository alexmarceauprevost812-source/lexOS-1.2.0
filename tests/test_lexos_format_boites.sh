#!/usr/bin/env bash
# =============================================================================
#  Une boîte qui propose trois choix doit MONTRER trois choix
# =============================================================================
#  ALEX : « la page de formatage, on pourrait-tu la mettre un peu plus gros
#  pour bien voir tout le menu ? » Il signalait des descriptions coupées.
#
#  ═══ CE QU'IL N'AVAIT PAS VU, ET QUI ÉTAIT PIRE ═══
#  À 560x260, la liste des systèmes de fichiers n'avait la place que de DEUX
#  rangées. Trois sont proposées dans le code. « ext4 » était donc offert par
#  le programme et INVISIBLE à l'écran : une fonction inatteignable, pas un
#  défaut de confort. Et le repli zenity du bouton rouge, lui, n'avait AUCUNE
#  taille : sur cinq gestes, trois s'affichaient — « Éteindre » tombait sous
#  le bord.
#
#  ═══ POURQUOI UNE TAILLE EN DUR VIEILLIT ═══
#  LexOS livre DOUZE écritures à la main, et Alex en change quand il veut.
#  Une écriture manuscrite est plus large et plus haute, à taille égale,
#  qu'une police d'interface. 560x260 n'était pas absurde : il avait été
#  choisi avec une autre police. C'est un problème de CLASSE, pas une boîte
#  à retoucher — d'où ce banc, qui refait la mesure pour les quinze polices.
#
#  ═══ COMMENT LA MESURE EST FAITE ═══
#  On ne peut pas imposer une police à zenity depuis un banc : mesuré, ni
#  « gtk-font-name » dans settings.ini ni une règle CSS utilisateur ne
#  changent son rendu ici. On construit donc la MÊME boîte avec les MÊMES
#  widgets GTK (dialogue, étiquette, liste dans un défilement, boutons), où
#  la police s'impose par Gtk.Settings — et on compare la place OFFERTE à la
#  liste avec celle qu'elle DEMANDE. Si la demande dépasse l'offre, GTK met
#  un ascenseur : des lignes sont cachées. C'est exactement le défaut d'Alex.
#
#  LA RÉPLIQUE EST CALIBRÉE, PAS SUPPOSÉE. zenity dessine EN PLUS un grand
#  titre dans la fenêtre et ses propres marges, que la réplique n'a pas.
#  Relevé en rendant les deux côte à côte sous Xvfb : la réplique offre
#  126 px de plus que zenity à taille de fenêtre égale. On retire donc ces
#  126 px avant de conclure. Sans cette correction, le banc aurait déclaré
#  que 560x260 tenait — alors que la capture d'Alex montre le contraire.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMAT="$RACINE/config/includes.chroot/usr/bin/lexos-format"
SESSION="$RACINE/config/includes.chroot/usr/bin/lexos-session"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$FORMAT" "$SESSION" "$DISPATCH"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

#  Le code est lu SANS ses commentaires : ce banc a des contrôles qui
#  cherchent des motifs que les commentaires citent aussi. « Le contrôle lit
#  la prose » est le faux vert le plus fréquent de ce dépôt.
FORMAT_NU="$BANC/format.nu"; sed 's/^[[:space:]]*#.*$//' "$FORMAT"  > "$FORMAT_NU"
SESSION_NU="$BANC/session.nu"; sed 's/^[[:space:]]*#.*$//' "$SESSION" > "$SESSION_NU"

# =============================================================================
titre "1. TOUTE LISTE DÉCLARE SA TAILLE — les deux moitiés"
# =============================================================================
#  Le défaut de lexos-session n'était pas une mauvaise taille : c'était
#  l'ABSENCE de taille. Une liste sans --height reçoit la fenêtre par défaut
#  de zenity (480x320), qui ne tient pas cinq lignes. Ce contrôle-ci attrape
#  la prochaine liste qu'on écrira sans y penser.
manque=0
while IFS=: read -r fic lig; do
	[ -n "$lig" ] || continue
	#  ═══ LE BLOC S'ARRÊTE À LA FIN DE LA COMMANDE, PAS APRÈS N LIGNES ═══
	#  Première version : « les 14 lignes qui suivent ». Elle a laissé passer
	#  une mutation — la fenêtre débordait sur l'appel SUIVANT, qui avait
	#  encore sa hauteur, et le contrôle voyait un --height qui n'était plus
	#  celui de cette liste-ci. On coupe maintenant à la première ligne qui
	#  ne se termine pas par une barre oblique inverse : c'est là que la
	#  commande finit, et le shell le dit de la même façon.
	BLOC="$(awk -v d="$lig" 'NR < d { next }
	                          { print }
	                          NR > d && !/\\$/ { exit }
	                          NR == d && !/\\$/ { exit }' "$fic")"
	L=0; H=0
	grep -q -- '--width='  <<< "$BLOC" && L=1
	grep -q -- '--height=' <<< "$BLOC" && H=1
	if [ "$L" = 1 ] && [ "$H" = 1 ]; then
		continue
	fi
	non "$(basename "$fic") ligne $lig : une liste sans $( [ "$L" = 0 ] && printf -- '--width '; [ "$H" = 0 ] && printf -- '--height' )"
	manque=1
done < <(grep -n -- '--list' "$FORMAT_NU" "$SESSION_NU" | sed "s|^\([^:]*\):\([0-9]*\):.*|\1:\2|")
[ "$manque" = 0 ] && ok "chaque liste de lexos-format et lexos-session déclare largeur ET hauteur"

# =============================================================================
titre "2. LA BOÎTE DES SYSTÈMES DE FICHIERS PROPOSE BIEN TROIS CHOIX"
# =============================================================================
#  Le cœur de la consigne : ce que le code offre doit être ce que l'écran
#  montre. On compte d'abord ce que le code offre.
RANGS="$(grep -cE '^[[:space:]]+(TRUE|FALSE)[[:space:]]+[a-z0-9]+[[:space:]]+"' "$FORMAT_NU")"
[ "$RANGS" = 3 ] \
	&& ok "la liste déclare bien 3 systèmes de fichiers" \
	|| non "la liste déclare $RANGS rangées : le reste de ce banc parle d'autre chose"

for FS in vfat exfat ext4; do
	grep -qE "^[[:space:]]+(TRUE|FALSE)[[:space:]]+${FS}[[:space:]]" "$FORMAT_NU" \
		&& ok "« $FS » est proposé dans la liste" \
		|| non "« $FS » a disparu de la liste"
done
#  …et il est VRAIMENT accepté ensuite : une ligne offerte que le « case »
#  refuserait serait un autre genre de mensonge.
for FS in vfat exfat ext4; do
	grep -qE "^[[:space:]]*($FS\||$FS\)|.*\|$FS\))" "$FORMAT_NU" \
		&& ok "…et « $FS » est accepté par le case qui suit" \
		|| non "« $FS » est proposé mais refusé plus bas"
done

# =============================================================================
titre "3. CHAQUE TAILLE DIT AVEC QUOI ELLE A ÉTÉ VÉRIFIÉE"
# =============================================================================
#  « MESURÉ, PAS DEVINÉ » : la pratique du dépôt. Une taille sans trace de
#  mesure est une taille qu'on rechangera au jugé dans six mois.
for F in "$FORMAT" "$SESSION"; do
	N="$(basename "$F")"
	if grep -q 'MESURÉ, PAS DEVINÉ' "$F"; then
		ok "$N garde la trace de sa mesure"
	else
		non "$N ne dit nulle part avec quelle écriture ses tailles ont été vérifiées"
	fi
done

# =============================================================================
titre "4. LA MESURE : la liste reçoit plus de place qu'elle n'en demande"
# =============================================================================
PY=""
for C in python3.12 python3.13 python3.11 python3; do
	command -v "$C" >/dev/null 2>&1 || continue
	if "$C" -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" 2>/dev/null; then
		PY="$C"; break
	fi
done
if [ -z "$PY" ]; then
	saute "aucun python avec GTK 3 (python3-gi + gir1.2-gtk-3.0) : rien n'a été MESURÉ"
elif ! command -v xvfb-run >/dev/null 2>&1; then
	saute "xvfb-run absent : la mesure demande un écran, elle n'a PAS été faite"
else
	#  Les polices d'Alex vivent dans le dépôt, pas sur la machine du banc :
	#  on les rend visibles à fontconfig le temps de la mesure.
	POL="$RACINE/config/includes.chroot/usr/share/fonts/truetype/lexos"
	mkdir -p "$BANC/xdg/fonts" "$BANC/home/.config"
	cp "$POL"/*.ttf "$BANC/xdg/fonts/" 2>/dev/null || true
	fc-cache -f "$BANC/xdg/fonts" >/dev/null 2>&1 || true

	#  UN SEUL écran pour toute la section : « xvfb-run » par mesure
	#  coûterait quinze démarrages de serveur X par boîte.
	AFF=""
	for N in $(seq 90 130); do
		[ -e "/tmp/.X${N}-lock" ] && continue
		Xvfb ":$N" -screen 0 1366x768x24 >/dev/null 2>&1 &
		XVFB_PID=$!
		for _ in $(seq 1 40); do
			DISPLAY=":$N" xdpyinfo >/dev/null 2>&1 && { AFF=":$N"; break; }
			sleep 0.25
		done
		[ -n "$AFF" ] && break
		kill "$XVFB_PID" 2>/dev/null
	done
	if [ -z "$AFF" ]; then
		saute "aucun écran X n'a pu être ouvert : rien n'a été MESURÉ"
		printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
		[ "$ECHOUES" -eq 0 ]
		exit
	fi
	export DISPLAY="$AFF"
	trap 'kill "$XVFB_PID" 2>/dev/null; rm -rf "$BANC"' EXIT

	cat > "$BANC/tient.py" <<'PYFIN'
import sys, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
police, larg, haut, etiquette = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
colonnes = sys.argv[5].split("|")
lignes = [l.split("|") for l in sys.argv[6:]]
Gtk.Settings.get_default().set_property("gtk-font-name", police)
dlg = Gtk.Dialog(title="BOITE")
dlg.add_button("Annuler", Gtk.ResponseType.CANCEL)
dlg.add_button("Valider", Gtk.ResponseType.OK)
dlg.set_default_size(larg, haut)
c = dlg.get_content_area(); c.set_spacing(6); c.set_border_width(5)
lab = Gtk.Label(label=etiquette); lab.set_xalign(0); lab.set_line_wrap(True)
c.pack_start(lab, False, False, 0)
radio = colonnes[0] != "-"
if radio:
    mag = Gtk.ListStore(*([bool] + [str] * (len(colonnes) - 1)))
    for l in lignes:
        mag.append([l[0] == "TRUE"] + l[1:])
else:
    colonnes = colonnes[1:]
    mag = Gtk.ListStore(*([str] * len(colonnes)))
    for l in lignes:
        mag.append(l[1:])
vue = Gtk.TreeView(model=mag)
if radio:
    rd = Gtk.CellRendererToggle(); rd.set_radio(True)
    vue.append_column(Gtk.TreeViewColumn(colonnes[0], rd, active=0))
    for i, t in enumerate(colonnes[1:], start=1):
        vue.append_column(Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i))
else:
    for i, t in enumerate(colonnes):
        vue.append_column(Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i))
defil = Gtk.ScrolledWindow()
defil.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
defil.add(vue)
c.pack_start(defil, True, True, 0)
dlg.show_all(); dlg.resize(larg, haut)
for _ in range(200):
    while Gtk.events_pending(): Gtk.main_iteration()
#  126 px : ce que zenity dessine EN PLUS de la réplique (son grand titre
#  dans la fenêtre, et ses marges). Relevé en rendant les deux côte à côte.
CHROME_ZENITY = 126
print("%d %d %d %d" % (defil.get_allocated_width(),
                       defil.get_allocated_height() - CHROME_ZENITY,
                       vue.get_preferred_width()[1],
                       vue.get_preferred_height()[1]))
PYFIN

	#  Les quinze polices que « lexos police » sait poser. Écrites ici parce
	#  que le banc doit pouvoir rougir si le dispatcheur en perd une :
	#  contrôle juste en dessous.
	POLICES=(
		"Patrick Hand 12" "Comic Neue 12" "Delius 12" "Short Stack 11"
		"Neucha 12" "Handlee 12" "Kalam 11" "Architects Daughter 11"
		"Indie Flower 12" "Caveat 14" "Gloria Hallelujah 10" "Shantell Sans 11"
		"Cantarell 11" "Noto Serif 10" "Monospace 10"
	)
	perdues=0
	for P in "${POLICES[@]}"; do
		#  Le nom de famille seul : le dispatcheur écrit « Kalam 11 », on
		#  cherche « Kalam ». Cantarell est le défaut du système, pas une
		#  entrée du dispatcheur.
		FAM="${P% *}"
		[ "$FAM" = "Cantarell" ] && continue
		grep -qF "$FAM" "$DISPATCH" || { non "« $FAM » n'est plus proposée par « lexos police » : la mesure ne couvre plus ce qu'Alex peut choisir"; perdues=1; }
	done
	[ "$perdues" = 0 ] && ok "les quatorze polices mesurées sont bien celles que « lexos police » sait poser"

	mesure() {   # $1 nom-de-la-boîte  $2 largeur  $3 hauteur  $4… arguments de tient.py
		local nom="$1" larg="$2" haut="$3"; shift 3
		local pire_l="" pire_h="" mauvais=0
		for P in "${POLICES[@]}"; do
			local R
			R="$(timeout 60 "$PY" "$BANC/tient.py" "$P" "$larg" "$haut" "$@" 2>/dev/null)"
			[ -n "$R" ] || { non "$nom : la mesure n'a rien rendu pour « $P »"; return; }
			local ol oh dl dh
			read -r ol oh dl dh <<< "$R"
			[ "$dl" -gt "$ol" ] && { non "$nom, « $P » : la liste demande ${dl} px de large, la boîte n'en offre que ${ol}"; mauvais=1; }
			[ "$dh" -gt "$oh" ] && { non "$nom, « $P » : la liste demande ${dh} px de haut, la boîte n'en offre que ${oh}"; mauvais=1; }
			[ -z "$pire_l" ] || [ "$dl" -gt "$pire_l" ] && pire_l="$dl"
			[ -z "$pire_h" ] || [ "$dh" -gt "$pire_h" ] && pire_h="$dh"
		done
		[ "$mauvais" = 0 ] && ok "$nom (${larg}x${haut}) : tient pour les quinze polices — au pire ${pire_l}x${pire_h} demandés"
	}

	#  Les tailles sont RELUES dans le script, pas recopiées ici : sinon le
	#  banc mesurerait une boîte imaginaire et resterait vert quand la vraie
	#  rétrécit.
	TAILLE_FS="$(grep -A6 -- '--column="Description"' "$FORMAT_NU" | grep -oE -- '--width=[0-9]+ --height=[0-9]+' | head -1)"
	FS_L="$(grep -oE '[0-9]+' <<< "${TAILLE_FS%% *}")"
	FS_H="$(grep -oE '[0-9]+' <<< "${TAILLE_FS##* }")"
	if [ -z "$FS_L" ] || [ -z "$FS_H" ]; then
		non "taille de la boîte des systèmes de fichiers illisible dans lexos-format"
	else
		export XDG_DATA_HOME="$BANC/xdg" HOME="$BANC/home" XDG_CONFIG_HOME="$BANC/home/.config"
		mesure "systèmes de fichiers" "$FS_L" "$FS_H" \
			"Sélectionnez des éléments dans la liste ci-dessous." \
			"|Système de fichiers|Description" \
			"TRUE|vfat|FAT32 — partout, même les téléphones (4 Go max par fichier)" \
			"FALSE|exfat|exFAT — partout aussi, sans limite de taille" \
			"FALSE|ext4|ext4 — Linux seulement, sans limite"
	fi

	SUP="$(grep -A3 -- '--column="Support"' "$FORMAT_NU" | grep -oE -- '--width=[0-9]+ --height=[0-9]+' | head -1)"
	SUP_L="$(grep -oE '[0-9]+' <<< "${SUP%% *}")"; SUP_H="$(grep -oE '[0-9]+' <<< "${SUP##* }")"
	if [ -z "$SUP_L" ] || [ -z "$SUP_H" ]; then
		non "taille de la liste des supports illisible dans lexos-format"
	else
		#  CINQ disques : le nombre de rangées dépend de ce qui est branché,
		#  et c'est précisément ce qu'une hauteur fixe oublie.
		mesure "supports amovibles" "$SUP_L" "$SUP_H" \
			"Sélectionnez des éléments dans la liste ci-dessous." \
			"-|Support|Détails" \
			"x|/dev/sdb|sdb    57,3G SanDisk Ultra USB 3.0  (2 partitions)" \
			"x|/dev/sdc|sdc   931,5G Seagate Expansion HDD  (1 partition, montée sur /media/alex/Sauvegardes)" \
			"x|/dev/mmcblk0|mmcblk0  29,7G SD Card Reader     (1 partition)" \
			"x|/dev/sdd|sdd    14,9G Kingston DataTraveler   (1 partition)" \
			"x|/dev/sde|sde     3,7G Generic Flash Disk      (aucune partition)"
	fi

	SES="$(grep -oE -- '--width=[0-9]+ --height=[0-9]+' "$SESSION_NU" | tail -1)"
	SES_L="$(grep -oE '[0-9]+' <<< "${SES%% *}")"; SES_H="$(grep -oE '[0-9]+' <<< "${SES##* }")"
	if [ -z "$SES_L" ] || [ -z "$SES_H" ]; then
		non "taille des listes de lexos-session illisible"
	else
		mesure "session (bouton rouge)" "$SES_L" "$SES_H" \
			"Tu es connecté en tant que alexandre-marceau-prevost." \
			"-|Que faire ?" \
			"x|Changer d'utilisateur" "x|Déconnexion" "x|Mise en veille" \
			"x|Redémarrer" "x|Éteindre"
	fi

	# =====================================================================
	titre "5. LA MESURE MORD — l'ancienne taille est rejetée"
	# =====================================================================
	#  Sans ce contrôle, rien ne prouve que la mesure sait dire non. On lui
	#  repasse la taille d'AVANT, celle de la capture d'Alex : elle doit
	#  refuser.
	R="$(timeout 60 "$PY" "$BANC/tient.py" "Short Stack 11" 560 260 \
		"Sélectionnez des éléments dans la liste ci-dessous." \
		"|Système de fichiers|Description" \
		"TRUE|vfat|FAT32 — compatible partout, y compris téléphones (fichiers < 4 Go)" \
		"FALSE|exfat|exFAT — comme FAT32, mais sans limite de taille de fichier" \
		"FALSE|ext4|ext4 — Linux seulement, pas de limite" 2>/dev/null)"
	if [ -z "$R" ]; then
		non "la mesure n'a rien rendu sur l'ancienne taille : le contrôle ne prouve rien"
	else
		read -r ol oh dl dh <<< "$R"
		if [ "$dl" -gt "$ol" ] || [ "$dh" -gt "$oh" ]; then
			ok "560x260 est bien rejeté (demandé ${dl}x${dh}, offert ${ol}x${oh}) — la mesure sait dire non"
		else
			non "560x260 passe la mesure : elle ne sait pas dire non, tout le reste est sans valeur"
		fi
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
