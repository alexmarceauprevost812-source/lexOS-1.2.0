#!/usr/bin/env bash
# =============================================================================
#  L'icône du bureau ne doit pas s'éteindre quand on fait un clic droit
# =============================================================================
#  ALEX, DEUX PHOTOS : « quand je clique sur le bouton droit de la souris, il
#  devient tout noir ». Une icône choisie sur le bureau porte une tuile
#  orange ; dès que le menu du clic droit s'ouvre, la tuile disparaît dans le
#  noir et il ne reste que le libellé.
#
#  ═══ LA CAUSE, RELEVÉE DANS LE BINAIRE DE XFDESKTOP ═══
#  xfdesktop embarque SA feuille de style. On l'a lue dans le binaire plutôt
#  que devinée :
#
#      XfdesktopIconView.view        { background: transparent; … }
#      XfdesktopIconView.view:active { background: alpha(@theme_selected_bg_color, 0.5); }
#
#  Sa vue est TRANSPARENTE au repos — c'est ce qui laisse voir le fond d'écran
#  entre les icônes. Or ce nœud porte la classe « view », et notre règle des
#  fonds liste « .view » parmi tout ce qui doit être noir. Notre feuille est
#  chargée en priorité UTILISATEUR, celle de xfdesktop en priorité
#  APPLICATION : la nôtre gagnait, sur TOUS les états.
#
#  ═══ CE BANC MESURE, IL NE LIT PAS ═══
#  Il ne cherche pas « XfdesktopIconView » dans le fichier — une chaîne
#  présente ne prouve pas qu'elle l'emporte dans la cascade. Il charge les
#  DEUX feuilles dans un vrai GTK 3.24, à leurs vraies priorités, et demande à
#  GTK la couleur résolue du nœud dans chacun des états. C'est la seule façon
#  de voir qui gagne.
#
#  Sans python3-gi ni GTK, la partie mesurée est SAUTÉE proprement — elle ne
#  se fait pas passer pour verte.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

mkdir -p "$BANC/t"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
	bash "$GEN" --target "$BANC/t" --terminal nuit orange >"$BANC/gen.log" 2>&1
CSS="$BANC/t/.themes/LexOS-Noir/gtk-3.0/gtk.css"
[ -r "$CSS" ] || { non "aucun gtk.css produit"; exit 1; }

#  ═══ LE « NOIR DE LexOS » N'EST PLUS ÉCRIT EN DUR ICI ═══
#  Il l'était — « #000000 » — et le jour où Alex a demandé que le fond des
#  fenêtres passe au gris #121214, ce banc a rougi sur la CI pendant trois
#  ISO en annonçant « le fond de fenêtre a bougé ». Il avait raison sur le
#  fait et tort sur le verdict : le fond DEVAIT bouger. Une valeur recopiée
#  dans un banc vieillit en silence et finit par accuser le correctif.
#  On la relève maintenant dans lexos-theme-gen, qui la peint — la même
#  extraction que le garde-fou « La palette des panneaux est celle du
#  bureau » de la CI, à la même fenêtre else/fi.
#  « grep -m1 » est interdit en bout de tuyau dans ce dépôt (la CI le
#  vérifie) : il ferme le tuyau et fait mourir le producteur sur SIGPIPE,
#  ce qui sous pipefail donne un faux rouge — ou un faux vert dans un
#  contrôle inversé. On coupe avec « head -1 », qui vient après le grep.
FOND_FENETRE="$(sed -n '/^else$/,/^fi$/p' "$GEN" \
	| grep '^[[:space:]]*BG=' | grep -oE '#[0-9A-Fa-f]{6}' | head -1)"
if [ -z "$FOND_FENETRE" ]; then
	non "impossible de relever BG dans lexos-theme-gen — les contrôles de fond ne prouveraient rien"
	FOND_FENETRE="#000000"
fi

# =============================================================================
titre "1. La feuille est acceptée EN ENTIER par GTK"
# =============================================================================
#  POURQUOI CE CONTRÔLE EXISTE. La feuille contenait « ::selection », que GTK3
#  ne connaît pas. On croyait ce bloc « ignoré tout seul ». Mesure : il ne
#  l'était pas. gtk_css_provider_load_from_path() a DEUX comportements — sans
#  pointeur d'erreur il avertit et garde le reste ; AVEC pointeur d'erreur il
#  REMET LA FEUILLE À ZÉRO. Tout le thème disparaissait pour qui lisait notre
#  feuille en demandant les erreurs, y compris les règles écrites AVANT.
PY312=""
for P in python3.12 python3.13 python3.11 python3; do
	command -v "$P" >/dev/null 2>&1 || continue
	if "$P" -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" 2>/dev/null; then
		PY312="$P"; break
	fi
done

if [ -z "$PY312" ]; then
	saut "aucun python avec GTK 3 (python3-gi + gir1.2-gtk-3.0) : rien n'a été MESURÉ"
	saut "installer « python3-gi gir1.2-gtk-3.0 » pour éprouver ce correctif"
else
	cat > "$BANC/mesure.py" <<'PY'
import sys, warnings, gi
warnings.filterwarnings("ignore")
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GObject
ecran = Gdk.Screen.get_default()
if ecran is None:
    print("PAS-D-ECRAN"); sys.exit(0)
st = Gtk.Settings.get_default()
#  LE THEME PAR SON NOM, PLUS UNE FEUILLE EN PRIORITE UTILISATEUR. Depuis
#  que le style de LexOS est un vrai theme, le charger comme avant aurait
#  ete mesurer un montage qui n'existe plus — et rester vert pour la
#  mauvaise raison. GTK trouve LexOS-Noir dans le HOME du banc (~/.themes),
#  a la priorite THEME, SOUS la feuille de xfdesktop : la vraie machine.
st.set_property("gtk-theme-name", "LexOS-Noir")
st.set_property("gtk-application-prefer-dark-theme", True)

#  La feuille de xfdesktop, telle qu'elle est dans SON binaire.
xfd = Gtk.CssProvider()
xfd.load_from_data(sys.argv[2].encode())
Gtk.StyleContext.add_provider_for_screen(ecran, xfd, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

#  Le thème est déjà chargé PAR SON NOM, plus haut. On vérifie seulement que
#  sa feuille se lit EN ENTIER — le piège « ::selection » a déjà fait jeter
#  toute une feuille à qui demandait les erreurs — sans l'ajouter une
#  seconde fois à une autre priorité.
notre = Gtk.CssProvider()
try:
    notre.load_from_path(sys.argv[1])
    print("FEUILLE-ENTIERE")
except Exception as e:
    print("FEUILLE-REJETEE %s" % str(e).split("quark: ")[-1].replace("\n", " "))

def couleur(nom, classes, etat):
    p = Gtk.WidgetPath(); p.append_type(GObject.TYPE_NONE)
    p.iter_set_object_name(-1, nom)
    for c in classes: p.iter_add_class(-1, c)
    c = Gtk.StyleContext(); c.set_screen(ecran); c.set_path(p); c.set_state(etat)
    g = c.get_background_color(etat)
    return "#%02X%02X%02X:%.2f" % (round(g.red*255), round(g.green*255), round(g.blue*255), g.alpha)

F = Gtk.StateFlags
print("repos     " + couleur("XfdesktopIconView", ["view"], F.NORMAL))
print("active    " + couleur("XfdesktopIconView", ["view"], F.ACTIVE))
print("actbd     " + couleur("XfdesktopIconView", ["view"], F.ACTIVE | F.BACKDROP))
print("selected  " + couleur("XfdesktopIconView", ["view"], F.SELECTED))
print("selbd     " + couleur("XfdesktopIconView", ["view"], F.SELECTED | F.BACKDROP))
print("fenetre   " + couleur("window", ["background"], F.NORMAL))

#  LES VUES DE FICHIERS. Thunar teinte l'icone choisie avec la couleur de
#  fond lue a l'etat « selected » sur le noeud de classe « view ». Trois
#  noeuds, trois roles : la vue en ICONES de Thunar et la grille
#  d'applications doivent rendre le gris pale ; la vue en LISTE garde
#  l'accent, comme toutes les listes de LexOS.
for nom, cle in (("ExoIconView", "thunar-icones"), ("iconview", "grille"),
                 ("treeview", "liste")):
    for suffixe, fl in (("", F.SELECTED), ("-focus", F.SELECTED | F.FOCUSED),
                        ("-bd", F.SELECTED | F.BACKDROP),
                        ("-bdf", F.SELECTED | F.BACKDROP | F.FOCUSED)):
        print("%s%s %s" % (cle, suffixe, couleur(nom, ["view"], fl)))
    print("%s-repos %s" % (cle, couleur(nom, ["view"], F.NORMAL)))
PY

	#  La feuille de xfdesktop : relevée dans SON binaire quand il est là,
	#  sinon la copie qu'on en a faite — et le banc le dit.
	XFD_CSS=""
	if command -v xfdesktop >/dev/null 2>&1; then
		#  ON LIT TOUT, PUIS ON FILTRE. « strings … | grep -m1 » ferait sortir
		#  grep au premier résultat et casserait le tuyau sous le nez de
		#  strings : sous « pipefail », l'affectation prend alors un code non
		#  nul. Ici personne ne le teste, mais la règle du dépôt ne souffre pas
		#  d'exception au cas par cas — une exception se recopie.
		XFD_BRUT="$(strings -a "$(command -v xfdesktop)" 2>/dev/null)"
		XFD_CSS="$(grep -m1 '^XfdesktopIconView.view {' <<< "$XFD_BRUT" | sed 's/}/}\n/g')"
	fi
	if [ -n "$XFD_CSS" ]; then
		ok "feuille de xfdesktop relevée dans SON binaire (pas une copie de mémoire)"
	else
		XFD_CSS='XfdesktopIconView.view { background: transparent; color: @theme_selected_fg_color; border-radius: 3px; }
XfdesktopIconView.view:active { background: alpha(@theme_selected_bg_color, 0.5); }
XfdesktopIconView .rubberband { background: alpha(@theme_selected_bg_color, 0.2); }'
		saut "xfdesktop absent : on emploie la copie relevée dans son binaire au moment du correctif"
	fi

	#  GTK cherche « LexOS-Noir » dans ~/.themes : on lui fabrique ce foyer.
	mkdir -p "$BANC/home/.themes"
	cp -r "$BANC/t/.themes/LexOS-Noir" "$BANC/home/.themes/" 2>/dev/null
	SORTIE="$(HOME="$BANC/home" "$PY312" "$BANC/mesure.py" "$CSS" "$XFD_CSS" 2>/dev/null)"
	if grep -q "PAS-D-ECRAN" <<< "$SORTIE" ; then
		saut "aucun écran X (installer xvfb et relancer sous « xvfb-run ») : rien n'a été MESURÉ"
	elif [ -z "$SORTIE" ]; then
		non "la mesure GTK n'a rien rendu"
	else
		val() { printf '%s' "$SORTIE" | awk -v k="$1" '$1==k{print $2}'; }

		if grep -q "^FEUILLE-ENTIERE" <<< "$SORTIE" ; then
			ok "GTK accepte la feuille en entier — aucun sélecteur qu'il refuse"
		else
			non "GTK REJETTE la feuille : $(printf '%s' "$SORTIE" | grep '^FEUILLE-REJETEE')"
			non "  (un lecteur qui demande les erreurs perd TOUT le thème, même les règles d'avant)"
		fi

		# =============================================================
		titre "2. La vue du bureau laisse voir le fond d'écran"
		# =============================================================
		REPOS="$(val repos)"
		case "$REPOS" in
			*:0.00) ok "au repos, la vue est transparente ($REPOS) : le fond d'écran passe au travers" ;;
			*)      non "au repos, la vue est OPAQUE ($REPOS) — elle cache le fond d'écran" ;;
		esac
		FEN="$(val fenetre)"
		[ "${FEN%%:*}" = "$FOND_FENETRE" ] \
			&& ok "et une vraie fenêtre garde le fond du bureau ($FEN) : la règle n'a pas débordé" \
			|| non "une fenêtre ordinaire ne vaut plus le fond du bureau ($FEN au lieu de $FOND_FENETRE)"

		# =============================================================
		titre "3. La tuile choisie reste allumée, MENU OUVERT COMPRIS"
		# =============================================================
		#  C'est le contrôle qu'Alex a demandé — et il a CHANGÉ DE FORME à
		#  l'étape 4 du grand ménage des thèmes, pour une raison qui mérite
		#  d'être écrite.
		#
		#  AVANT, notre feuille gagnait par priorité UTILISATEUR : on
		#  imposait l'accent PLEIN, et ce banc l'exigeait. DEPUIS que le
		#  style est un vrai THÈME, la feuille de xfdesktop (priorité
		#  APPLICATION) repasse devant — et c'est voulu, c'est tout l'objet
		#  du ménage. Or elle dit :
		#
		#      XfdesktopIconView.view:active {
		#          background: alpha(@theme_selected_bg_color, 0.5); }
		#
		#  L'application peint sa sélection ELLE-MÊME, à 50 % — mais avec
		#  la couleur qu'elle DEMANDE AU THÈME. Mesuré : #E8590C:0.50.
		#  L'accent est le nôtre, l'intensité est la sienne. C'est
		#  exactement le « officiel normal » demandé : l'application garde
		#  son dessin, le thème fournit les couleurs.
		#
		#  Le bogue d'origine, lui, reste mort : la tuile ne devient NI
		#  noire NI différente quand le menu s'ouvre. C'est ça qu'on tient.
		ACCENT="#E8590C"
		for CAS in "active:choisie" "actbd:choisie, menu ouvert"; do
			K="${CAS%%:*}"; L="${CAS#*:}"
			V="$(val "$K")"
			if [ "${V%%:*}" != "$ACCENT" ]; then
				non "$L : $V — la couleur n'est plus celle du thème"
			elif [ "${V##*:}" = "0.00" ]; then
				non "$L : TRANSPARENTE ($V) — la tuile a disparu, c'est la photo d'Alex"
			else
				ok "$L : l'accent du thème, à l'intensité de xfdesktop ($V)"
			fi
		done

		#  Et le cœur du bogue, dit en une phrase : ouvrir le menu ne doit
		#  RIEN changer — ni sur :active (xfdesktop 4.18) ni sur :selected
		#  (si une version peint par cet état-là).
		if [ "$(val active)" = "$(val actbd)" ] && [ "$(val selected)" = "$(val selbd)" ]; then
			ok "ouvrir le menu du clic droit ne change RIEN à la tuile"
		else
			non "la tuile change quand le menu s'ouvre : $(val active) → $(val actbd)"
		fi

		# =============================================================
		titre "3 bis. THUNAR — le dossier choisi ne devient plus une silhouette"
		# =============================================================
		#  ALEX, DEUX PHOTOS DE THUNAR : le dossier choisi devenait une
		#  SILHOUETTE NOIRE, icone comprise ; et « on pourrait ajouter un gris
		#  pale a la place de tout le mettre orange », « gris pale pour bien
		#  voir le fichier ».
		#
		#  MEME CAUSE QUE LE BUREAU. Thunar TEINTE l'icone choisie avec la
		#  couleur de fond lue a l'etat « selected » sur le noeud de classe
		#  « view ». Notre feuille n'avait aucune regle « .view:selected » :
		#  la lecture retombait sur la regle des fonds, ou « .view » vaut le
		#  noir de LexOS. Icone noire sur fond noir.
		#
		#  LE SELECTEUR A ETE TROUVE PAR SONDAGE, en lancant le vrai Thunar
		#  sous Xvfb avec une couleur criarde posee sur un candidat a la fois :
		#      ExoIconView:selected ....... rien
		#      .standard-view:selected .... rien
		#      .view:selected ............. TEINTE
		GRIS="#C4C8D0"
		ACCENT="#E8590C"
		for CLE in thunar-icones grille; do
			MAUVAIS=0
			for E in "" -focus -bd -bdf; do
				V="$(val "${CLE}${E}")"
				[ "${V%%:*}" = "$GRIS" ] || { non "$CLE$E : $V au lieu de $GRIS"; MAUVAIS=1; }
			done
			[ "$MAUVAIS" = 0 ] && ok "$CLE : gris pâle dans les quatre états, backdrop compris"
			R="$(val "${CLE}-repos")"
			case "$R" in
				"$FOND_FENETRE:1.00") ok "$CLE : au repos, la vue garde le fond du bureau ($FOND_FENETRE)" ;;
				*) non "$CLE : au repos la vue vaut $R au lieu de $FOND_FENETRE — le gris a débordé sur le repos" ;;
			esac
		done
		#  ET L'AUTRE MOITIÉ N'A PAS ÉTÉ EMPORTÉE. Le gris de la grille passe
		#  par « .view:selected » NU, seul sélecteur qui atteigne Thunar. Or
		#  « .view:selected:focus » pèse plus lourd que « treeview.view:
		#  selected » : sans renfort, une ligne de LISTE devenait grise dès
		#  qu'elle prenait le focus. Une ligne qui change de couleur selon
		#  qu'on l'a cliquée ou non — mesuré, pas imaginé.
		MAUVAIS=0
		for E in "" -focus -bd -bdf; do
			V="$(val "liste${E}")"
			[ "${V%%:*}" = "$ACCENT" ] || { non "liste$E : $V au lieu de l'accent $ACCENT"; MAUVAIS=1; }
		done
		[ "$MAUVAIS" = 0 ] && ok "les listes gardent l'accent dans les quatre états — le gris n'a pas débordé"
	fi
fi

# =============================================================================
titre "4. Le correctif est expliqué dans le générateur, pas seulement ici"
# =============================================================================
if grep -q "XfdesktopIconView" "$GEN"; then
	ok "lexos-theme-gen porte les règles du bureau"
else
	non "lexos-theme-gen ne dit rien du bureau — le correctif vient d'ailleurs ?"
fi
if grep -q "strings /usr/bin/xfdesktop\|binaire de xfdesktop\|dans le binaire" "$GEN"; then
	ok "…et dit d'où vient la feuille de xfdesktop : relevée, pas supposée"
else
	non "la provenance de la feuille de xfdesktop n'est écrite nulle part"
fi

# =============================================================================
printf '\n\033[1m═══ VERDICT ═══\033[0m\n'
printf '  %d réussis, %d échoués\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
printf '  \033[32mL'"'"'icône choisie garde sa tuile orange, menu ouvert compris.\033[0m\n'
