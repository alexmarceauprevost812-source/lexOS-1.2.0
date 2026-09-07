#!/usr/bin/env bash
# =============================================================================
#  Le menu Whisker : noir, arrondi, et il descend en s'ouvrant
# =============================================================================
#  ALEX : le menu du bouton LexOS sortait GRIS, et la barre du haut aussi.
#
#  ═══ CE QUE LA MESURE A DONNÉ, ET POURQUOI ELLE ÉTAIT NÉCESSAIRE ═══
#  Session X réelle, xfce4-whiskermenu-plugin 2.8.3 (la version de trixie),
#  panneau lancé avec la configuration LexOS, menu ouvert :
#
#      WM_CLASS(STRING)          = "wrapper-2.0", "Wrapper-2.0"
#      _NET_WM_WINDOW_TYPE(ATOM) = _NET_WM_WINDOW_TYPE_MENU
#      WM_NAME(STRING)           = "Whisker Menu"
#
#  Deux conséquences, et aucune ne se devinait :
#    · le type CONTIENT « menu », donc la fenêtre était déjà attrapée par la
#      règle générique de lexos-tv.conf (fondu de 80 ms). Sa règle à elle doit
#      donc passer AVANT, puisque picom s'arrête à la première correspondance ;
#    · la CLASSE vaut « wrapper-2.0 » — le programme qui héberge TOUS les
#      greffons du panneau. Une règle sur la classe attraperait l'horloge, le
#      son, la batterie. WM_NAME est le seul discriminant.
#
#  ═══ CE QUE CE BANC GARDE ═══
#  Surtout l'ORDRE des règles picom. Rien d'autre ne le signalerait : un
#  fichier réordonné reste valide, picom démarre sans se plaindre, et le menu
#  reprend simplement le fondu de tout le monde — un défaut qu'on ne voit
#  qu'en le cherchant.
#  Et le garde-fou inverse : les (20, 18, 22) de ui.css et du volet doivent
#  RESTER. Ce sont les voiles des interfaces web, un autre chantier ; un
#  « nettoyage » qui les emporterait avec les gris du panneau serait une
#  régression silencieuse.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css"
PICOM="$RACINE/config/includes.chroot/usr/share/lexos/picom/lexos-tv.conf"
UICSS="$RACINE/config/includes.chroot/usr/share/lexos/ui.css"
VOLET="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/style.css"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()   { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
#  Un contrôle SAUTÉ n'est ni vert ni rouge : la dépendance de mesure manque,
#  ce n'est pas une faute du code. On le dit, on ne le compte pas.
saute() { printf '  \033[2m—\033[0m %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$CSS" "$PICOM"; do
	[[ -r "$F" ]] || { echo "fichier introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. Le fond du menu Whisker suit celui des fenêtres"
# =============================================================================
if grep -q '^#whiskermenu-window {' "$CSS"; then
	ok "la règle #whiskermenu-window existe"
else
	non "aucune règle #whiskermenu-window : le menu retomberait sur le thème de socle"
fi

#  LE FOND DE LA RÈGLE ELLE-MÊME, pas un noir trouvé ailleurs dans le
#  fichier : on lit le bloc, du sélecteur à son accolade fermante.
BLOC="$(sed -n '/^#whiskermenu-window {/,/^}/p' "$CSS")"
#  ═══ LES DEUX VALEURS SONT LIÉES, ET C'EST TOUT L'OBJET DE CE CONTRÔLE ═══
#  Le menu était figé à « rgba(0, 0, 0, 0.96) », écrit EN DUR. Quand le fond
#  des fenêtres est passé de #000000 à #121214 — le gris qu'Alex a choisi
#  parmi trois — le menu, lui, n'a pas bougé : il serait resté noir pur au
#  milieu d'un système qui ne l'est plus.
#
#  Cette feuille est un squelette STATIQUE, posée telle quelle par le hook ;
#  elle ne passe pas par lexos-theme-gen et ne peut donc pas employer une
#  variable. Le lien ne peut être qu'ici : on LIT le BG du générateur et on
#  exige que le menu porte la même teinte. Sans ça les deux redériveront au
#  prochain changement de fond, exactement comme la première fois.
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
#  ═══ ON REPÈRE LA BRANCHE SOMBRE PAR SON TEXTE BLANC, PAS PAR UN MOT ═══
#  Première version : « chercher après la ligne qui dit LexOS Noir ». Elle
#  mordait sur un COMMENTAIRE du mode clair qui cite ce nom, et rapportait le
#  crème #F7F5F0. Pire, le nettoyage « garder les caractères hexadécimaux »
#  gardait le B de « BG » — B est un chiffre hexadécimal. Le contrôle rendait
#  alors une valeur absurde et passait au vert sur TOUT : trois mutations
#  n'ont rien déclenché avant que ceci soit corrigé.
#
#  La branche sombre est celle dont le texte est blanc. On retient le dernier
#  BG rencontré et on le rend quand on croise FG="#FFFFFF" — sans ambiguïté
#  possible, et faux bruyamment si la structure du fichier changeait.
BG_NOIR="$(awk -F'"' '/^\tBG="#[0-9A-Fa-f]{6}"/{bg=$2} /^\tFG="#FFFFFF"/{print bg; exit}' "$GEN")"
if [[ -z "$BG_NOIR" ]]; then
	#  Garde contre le vert sur du vide : sans la valeur de référence, la
	#  comparaison ci-dessous serait creuse.
	non "impossible de lire le BG du mode sombre dans lexos-theme-gen"
elif grep -qE "background-color:[[:space:]]*rgba\([[:space:]]*$((16#${BG_NOIR:1:2})),[[:space:]]*$((16#${BG_NOIR:3:2})),[[:space:]]*$((16#${BG_NOIR:5:2}))" <<< "$BLOC"; then
	ok "…et elle porte la MÊME teinte que le fond des fenêtres ($BG_NOIR)"
else
	non "le menu et le fond des fenêtres ont divergé — attendu $BG_NOIR :\n$BLOC"
fi

#  LES SOUS-NŒUDS EN TRANSPARENT, ET C'EST UNE VRAIE CONTRAINTE. Un noir
#  plein recouvrirait le border-radius de la fenêtre par un rectangle opaque
#  et le menu redeviendrait CARRÉ à l'œil — le piège déjà documenté pour
#  #XfcePanelWindow.
if grep -qE '^#whiskermenu-window (list|scrolledwindow|viewport|treeview\.view|iconview|entry)' "$CSS"; then
	ok "les sous-nœuds du menu ont leur propre règle"
	SOUS="$(sed -n '/^#whiskermenu-window entry,/,/^}/p' "$CSS")"
	if grep -q 'background-color:[[:space:]]*transparent' <<< "$SOUS" ; then
		ok "…et ils sont TRANSPARENTS, pas noirs (sinon l'arrondi serait recouvert)"
	else
		non "les sous-nœuds ne sont pas transparents : l'arrondi du menu serait recouvert"
	fi
else
	non "aucune règle pour les sous-nœuds : la liste garderait le fond du thème de socle"
fi

# =============================================================================
titre "2. Plus aucun gris (20, 18, 22) dans gtk-panneau.css"
# =============================================================================
#  (20, 18, 22) est un gris violacé très foncé. Il se lisait « gris » à côté
#  du #000000 du reste du système — c'est exactement ce qu'Alex voyait.
if grep -q 'rgba(20, 18, 22' "$CSS"; then
	non "il reste des « rgba(20, 18, 22 » dans gtk-panneau.css :\n$(grep -n 'rgba(20, 18, 22' "$CSS")"
else
	ok "aucun « rgba(20, 18, 22 » ne subsiste dans gtk-panneau.css"
fi

for N in XfcePanelWindow XfceNotifyWindow; do
	B="$(sed -n "/^#${N} {/,/^}/p" "$CSS")"
	if grep -qE 'background-color:[[:space:]]*rgba\([[:space:]]*0,[[:space:]]*0,[[:space:]]*0' <<< "$B"; then
		ok "#${N} est passé au noir franc"
	else
		non "#${N} n'a pas un fond noir :\n$(printf '%s' "$B" | grep background-color)"
	fi
done

# =============================================================================
titre "3. LE GARDE-FOU INVERSE — les voiles des interfaces web restent gris"
# =============================================================================
#  ui.css et le volet ne sont PAS le panneau : ce sont les voiles des
#  interfaces web de LexOS. Un futur « nettoyage des gris » qui les
#  emporterait avec ceux du panneau serait une régression silencieuse.
#
#  ═══ CE QU'IL FALLAIT GARDER N'EST PAS AU MÊME ENDROIT DANS LES DEUX ═══
#  Écrire ce contrôle a montré que les deux fichiers ne portent pas la même
#  chose, et qu'un grep identique sur les deux aurait été trompeur :
#
#    · ui.css porte la VRAIE déclaration, « --voile:rgba(20, 18, 22, .96) ».
#      C'est elle qu'un nettoyage emporterait, et c'est elle qu'on garde.
#    · volet/web/style.css ne porte plus la valeur du tout : elle n'y
#      survit qu'en COMMENTAIRE, qui raconte justement qu'elle a été retirée
#      de là et déplacée dans ui.css parce qu'écrite en dur, elle rendait le
#      volet noir sur noir en mode clair. Le volet emploie « var(--voile) ».
#      Garder un commentaire ne protège rien ; ce qui compte ici, c'est que
#      le volet n'ait pas REFAIT marche arrière vers une couleur en dur.
if [[ ! -r "$UICSS" ]]; then
	non "ui.css introuvable — le garde-fou ne peut pas s'exercer"
elif grep -qE '^\s*--voile:\s*rgba\(20,\s*18,\s*22' "$UICSS"; then
	ok "ui.css garde sa déclaration --voile en (20, 18, 22) — autre chantier, on n'y touche pas"
else
	non "ui.css a PERDU sa déclaration --voile : un nettoyage a débordé sur les interfaces web"
fi

if [[ ! -r "$VOLET" ]]; then
	non "volet/web/style.css introuvable — le garde-fou ne peut pas s'exercer"
elif grep -q 'background:\s*var(--voile)' "$VOLET"; then
	ok "le volet passe toujours par var(--voile), pas par une couleur en dur"
else
	non "le volet n'emploie plus var(--voile) : la couleur est retournée en dur, et le mode clair redeviendrait noir sur noir"
fi

# =============================================================================
titre "4. L'accent ne touche pas les noirs"
# =============================================================================
#  lexos-theme-gen recopie gtk-panneau.css en traduisant l'accent (#E8590C,
#  #FF7A33, #A84007 et le triplet « 232, 89, 12 »). Un noir n'est pas un
#  accent : « lexos accent bleu » ne doit RIEN y changer. On ne le suppose
#  pas, on fait tourner le générateur deux fois et on compare.
if [[ -x "$GEN" ]] && command -v bash >/dev/null 2>&1; then
	NOIRS_O=""; NOIRS_B=""
	for A in orange bleu; do
		D="$BANC/$A"; mkdir -p "$D"
		LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" \
		LEXOS_PANNEAU_CSS="$CSS" \
			bash "$GEN" "$A" --target "$D" >/dev/null 2>&1
		G="$D/.themes/LexOS-Noir/gtk-3.0/gtk.css"
		if [[ -r "$G" ]]; then
			V="$(grep -oE 'rgba\(0, 0, 0, 0\.[0-9]+\)' "$G" | sort | tr '\n' ' ')"
			[[ "$A" == orange ]] && NOIRS_O="$V" || NOIRS_B="$V"
		fi
	done
	if [[ -z "$NOIRS_O" || -z "$NOIRS_B" ]]; then
		saute "le générateur n'a pas produit de thème ici — accents non comparés"
	elif [[ "$NOIRS_O" == "$NOIRS_B" ]]; then
		ok "les noirs sont identiques en accent orange et en accent bleu"
	else
		non "l'accent DÉTEINT sur les noirs :\n  orange : $NOIRS_O\n  bleu   : $NOIRS_B"
	fi
	#  Et la règle du menu doit survivre au passage du générateur.
	if grep -q '^#whiskermenu-window {' "$BANC/bleu/.themes/LexOS-Noir/gtk-3.0/gtk.css" 2>/dev/null; then
		ok "…et la règle du menu Whisker survit à la génération du thème"
	else
		saute "thème non généré ici — survie de la règle non vérifiée"
	fi
else
	saute "lexos-theme-gen non exécutable ici — substitution d'accent non éprouvée"
fi

# =============================================================================
titre "5. picom : la règle du menu, et SURTOUT sa place"
# =============================================================================
#  ═══ L'ASSERTION QUI COMPTE ═══
#  picom applique la PREMIÈRE correspondance et s'arrête. La règle générique
#  attrape « window_type *= 'menu' », et la mesure a établi que le menu
#  Whisker EST de ce type. Placée après, la règle dédiée ne serait donc
#  JAMAIS atteinte — sans erreur, sans avertissement, le menu reprenant
#  simplement le fondu de 80 ms de tout le monde.
L_WHISKER="$(grep -n "match = \"name = 'Whisker Menu'\"" "$PICOM" | head -1 | cut -d: -f1)"
L_GENERIQUE="$(grep -n "match = \"window_type \*= 'menu'" "$PICOM" | head -1 | cut -d: -f1)"

if [[ -z "$L_WHISKER" ]]; then
	non "aucune règle picom pour le menu Whisker"
elif [[ -z "$L_GENERIQUE" ]]; then
	non "la règle générique des menus est introuvable — le fichier a changé de forme"
elif (( L_WHISKER < L_GENERIQUE )); then
	ok "la règle du menu Whisker (ligne $L_WHISKER) passe AVANT la générique (ligne $L_GENERIQUE)"
else
	non "MAUVAIS ORDRE : la règle Whisker (ligne $L_WHISKER) est APRÈS la générique (ligne $L_GENERIQUE) — picom ne l'atteindra jamais"
fi

#  ON MATCHE SUR LE NOM, PAS SUR LA CLASSE, et la mesure dit pourquoi : la
#  classe « wrapper-2.0 » est celle de TOUS les greffons du panneau.
BLOCP="$(sed -n "${L_WHISKER:-1},/^	},/p" "$PICOM" 2>/dev/null)"
if [[ -n "$L_WHISKER" ]]; then
	if grep -q "class_g" <<< "$BLOCP" ; then
		non "la règle Whisker matche sur la CLASSE : « wrapper-2.0 » attraperait tout le panneau"
	else
		ok "…et elle matche sur WM_NAME, seul discriminant (la classe est partagée)"
	fi

	#  L'OPACITÉ EST ÉCRITE AUX DEUX DÉCLENCHEURS. Point 2 de l'en-tête du
	#  fichier : une variable de sortie non définie retombe au défaut de
	#  l'état — l'animation jouerait sur une fenêtre déjà transparente.
	N_OPAC="$(printf '%s' "$BLOCP" | grep -c 'opacity[[:space:]]*=[[:space:]]*{')"
	if (( N_OPAC >= 2 )); then
		ok "…et « opacity » est écrit explicitement à l'ouverture ET à la fermeture"
	else
		non "« opacity » n'est pas défini aux deux déclencheurs ($N_OPAC) : l'animation serait invisible"
	fi

	grep -q 'offset-y' <<< "$BLOCP" \
		&& ok "…le menu DESCEND en s'ouvrant (offset-y), ce n'est pas qu'un fondu" \
		|| non "aucun offset-y : le menu ne ferait que se fondre"

	grep -qE 'shadow[[:space:]]*=[[:space:]]*true' <<< "$BLOCP" \
		&& ok "…et son ombre reste ALLUMÉE (grande surface noire sur fond sombre)" \
		|| non "l'ombre du menu Whisker est éteinte : son bord se perdrait"
fi

# =============================================================================
titre "6. lexos-tv.conf reste un fichier libconfig valide"
# =============================================================================
DESEQ="$(python3 - "$PICOM" <<'PY'
import re, sys
code = []
for l in open(sys.argv[1], encoding="utf-8").read().splitlines():
    dans, out = None, []
    for ch in l:
        if dans:
            out.append(ch)
            if ch == dans: dans = None
        elif ch in "\"'":
            dans = ch; out.append(ch)
        elif ch == '#':
            break
        else:
            out.append(ch)
    code.append(''.join(out))
c = '\n'.join(code)
c = re.sub(r'"[^"]*"', '""', c)
c = re.sub(r"'[^']*'", "''", c)
mauvais = [n for o, f, n in (("{","}","accolades"), ("(",")","parentheses"), ("[","]","crochets"))
           if c.count(o) != c.count(f)]
print(" ".join(mauvais))
PY
)"
if [[ -z "$DESEQ" ]]; then
	ok "délimiteurs équilibrés (accolades, parenthèses, crochets)"
else
	non "délimiteurs déséquilibrés : $DESEQ"
fi

#  picom lui-même est le juge de paix — quand il peut tourner. Il lui faut un
#  serveur X : sur un coureur sans écran, on saute plutôt que de rougir.
if ! command -v picom >/dev/null 2>&1; then
	saute "picom absent : validation par picom non faite"
elif [[ -z "${DISPLAY:-}" ]] && ! command -v xvfb-run >/dev/null 2>&1; then
	saute "ni écran ni xvfb-run : picom ne peut pas lire le fichier ici"
else
	LANCE=(picom --config "$PICOM" --diagnostics)
	[[ -z "${DISPLAY:-}" ]] && LANCE=(xvfb-run -a "${LANCE[@]}")
	SORTIE="$(timeout 40 "${LANCE[@]}" 2>&1)"
	#  On cherche une erreur de SYNTAXE, pas les reproches du pilote
	#  graphique (« Failed to enable vsync », EGL…) qui n'ont rien à voir
	#  avec le fichier, ni les options que la version installée ne connaît
	#  pas encore — « rules » et « animations » datent de picom 12.
	if grep -qiE 'syntax error|parse error|configuration file|unmatched|expected' <<< "$SORTIE"; then
		non "picom signale une erreur de syntaxe :\n$(printf '%s' "$SORTIE" | grep -iE 'syntax|parse|expected' | head -3)"
	elif grep -q 'Config file used' <<< "$SORTIE" ; then
		ok "picom lit le fichier sans erreur de syntaxe ($(printf '%s' "$SORTIE" | grep -oE '\*\*Version:\*\* v[0-9]+' | head -1))"
	else
		saute "picom n'a pas pu s'initialiser ici (pilote graphique) — syntaxe non jugée par lui"
	fi
fi

# =============================================================================
titre "7. Le survol du menu Whisker : le fond ET le texte, jamais l'un sans l'autre"
# =============================================================================
#  ═══ CE QUE CE CONTRÔLE EMPÊCHE DE REVENIR ═══
#  ALEX : « quand je passe ma souris sur les menus, on ne voit plus
#  l'écriture. Juste sur celui survolé. » L'icône restait, le texte non.
#
#  La feuille forçait le fond des sous-nœuds du menu à transparent — avec un
#  sélecteur d'ID, donc en battant le fond « sélectionné » du thème — mais ne
#  disait RIEN de la couleur du texte. Le thème continuait de poser la
#  sienne : celle qui va sur SON fond de surlignage, celui qu'on venait
#  d'effacer. Du noir sur le #121214 de la fenêtre.
#
#  La règle est donc : dans ce bloc, toute règle d'état pose les DEUX.
#  Ce contrôle lit les propriétés, pas la prose — les commentaires sont
#  retirés avant d'inspecter quoi que ce soit.

#  On retire les commentaires /* … */ : sans ça, une règle citée en exemple
#  dans un commentaire suffirait à faire passer le contrôle.
CSS_NU="$BANC/panneau-sans-commentaires.css"
sed -e ':a' -e 'N' -e '$!ba' -e 's|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/||g' "$CSS" > "$CSS_NU"

#  Chaque état exigé, et pour chacun : le bloc existe, et il porte les deux
#  propriétés. On extrait le bloc du sélecteur puis on regarde dedans.
bloc_de() { # bloc_de <selecteur exact>
	awk -v sel="$1" '
		index($0, sel"{") == 1 || index($0, sel" {") == 1 { dedans=1; next }
		dedans && /^\}/ { exit }
		dedans { print }
	' <(tr -d '\r' < "$CSS_NU" | sed 's/^[[:space:]]*//')
}

ETATS_KO=""
for SEL in \
	"#whiskermenu-window treeview.view:hover" \
	"#whiskermenu-window treeview.view:selected" \
	"#whiskermenu-window iconview:hover" \
	"#whiskermenu-window iconview:selected"
do
	CORPS="$(bloc_de "$SEL")"
	if [[ -z "$CORPS" ]]; then
		non "état manquant : « $SEL » — le texte redeviendrait celui du thème de base"
		ETATS_KO=1
		continue
	fi
	A_FOND=0; A_TEXTE=0
	grep -q 'background-color:' <<< "$CORPS" && A_FOND=1
	grep -q '^[[:space:]]*color:'  <<< "$CORPS" && A_TEXTE=1
	if [[ "$A_FOND" = 1 && "$A_TEXTE" = 1 ]]; then
		ok "« $SEL » pose le fond ET la couleur du texte"
	else
		non "« $SEL » pose $( [[ "$A_FOND" = 1 ]] && echo 'le fond' || echo 'la couleur' ) SEUL — c'est exactement la faute d'origine"
		ETATS_KO=1
	fi
done
[[ -z "$ETATS_KO" ]] || true

#  ═══ ET LE FOND TRANSPARENT DE L'ÉTAT DE REPOS RESTE ═══
#  Le correctif AJOUTE des états, il n'en retire aucun : un fond plein sur
#  les sous-nœuds recouvrirait le border-radius de la fenêtre et le menu
#  redeviendrait carré. Ce contrôle empêche qu'on « simplifie » ça un jour.
if grep -qE '^#whiskermenu-window treeview\.view,' "$CSS_NU" \
   && bloc_de "#whiskermenu-window iconview" | grep -q 'background-color: transparent'; then
	ok "l'état de repos garde son fond transparent (le menu reste arrondi)"
else
	non "le fond transparent de l'état de repos a disparu : le menu redeviendrait carré"
fi

# =============================================================================
titre "8. LA MESURE : ce que le VRAI moteur GTK résout pour une rangée survolée"
# =============================================================================
#  ═══ UN grep NE PROUVE PAS QU'UNE RÈGLE ATTEINT SON NŒUD ═══
#  Une règle posée sur un nœud imaginaire ne fait rien, et le contrôle 7
#  passerait quand même — il ne lit que du texte. Ici on rebâtit l'arbre réel
#  (GtkWindow nommée « whiskermenu-window » > GtkScrolledWindow >
#  GtkTreeView, les widgets que le greffon construit vraiment : relevé par
#  « nm -D » sur libwhiskermenu.so 2.8.3, qui appelle gtk_tree_view_new et
#  gtk_icon_view_new), on charge le thème RÉELLEMENT GÉNÉRÉ par
#  lexos-theme-gen, et on DEMANDE À GTK la couleur qu'il résout.
SONDE_SRC="$RACINE/tests/aide/whisker-sonde.c"
if ! command -v gcc >/dev/null 2>&1 \
   || ! pkg-config --exists gtk+-3.0 2>/dev/null \
   || ! command -v Xvfb >/dev/null 2>&1 \
   || [[ ! -r "$SONDE_SRC" ]]; then
	saute "gcc, gtk+-3.0 (dev), Xvfb ou la sonde manquent : la couleur résolue n'est pas mesurée"
else
	if ! gcc -o "$BANC/sonde" "$SONDE_SRC" $(pkg-config --cflags --libs gtk+-3.0) 2>"$BANC/gcc.log"; then
		non "la sonde GTK ne compile pas :\n$(head -3 "$BANC/gcc.log")"
	else
		#  Le vrai générateur, avec le squelette du dépôt : c'est la feuille
		#  que la machine d'Alex porte, pas une reconstitution.
		HOME="$BANC" LEXOS_PANNEAU_CSS="$CSS" \
			bash "$GEN" orange --target "$BANC" >/dev/null 2>&1
		THEME="$BANC/.themes/LexOS-Noir/gtk-3.0/gtk.css"
		if [[ ! -r "$THEME" ]]; then
			saute "lexos-theme-gen n'a pas produit de thème ici : couleur non mesurée"
		else
			: > "$BANC/xnum"
			Xvfb -displayfd 3 -screen 0 800x600x24 3>"$BANC/xnum" >/dev/null 2>&1 &
			XPID=$!
			for _ in $(seq 1 100); do [[ -s "$BANC/xnum" ]] && break; sleep 0.1; done
			if [[ ! -s "$BANC/xnum" ]]; then
				non "Xvfb n'a pas démarré : la couleur résolue n'est pas mesurée"
			else
				AFF=":$(tr -dc 0-9 < "$BANC/xnum")"
				SORTIE="$(DISPLAY="$AFF" "$BANC/sonde" "$THEME" 2>/dev/null)"
				#  Le chemin CSS que GTK rend lui-même : si le nœud change de
				#  nom un jour, c'est ici qu'on le verra, pas à l'écran d'Alex.
				if grep -q 'treeview.*\.view' <<< "$SORTIE"; then
					ok "le nœud mesuré est bien « treeview.view » sous #whiskermenu-window"
				else
					non "le chemin CSS rendu par GTK a changé :\n$(head -1 <<< "$SORTIE")"
				fi
				#  LA MESURE QUI COMPTE. Avant le correctif : #000000 sur le
				#  #121214 de la fenêtre, soit 1,12:1 — invisible, la photo
				#  d'Alex. On exige un texte clair ET un fond qui se voit.
				LIGNE="$(grep '^selectionne (' <<< "$SORTIE")"
				TXT="$(grep -oE 'texte #[0-9A-F]{6}' <<< "$LIGNE" | head -1 | cut -d'#' -f2)"
				ALPHA="$(grep -oE 'fond #[0-9A-F]{6} \(a=[0-9.]+\)' <<< "$LIGNE" | grep -oE 'a=[0-9.]+' | cut -d= -f2)"
				if [[ -z "$TXT" ]]; then
					non "la sonde n'a rien mesuré :\n$(head -5 <<< "$SORTIE")"
				else
					#  Luminance relative du texte : on refuse le noir, quel
					#  que soit le chemin par lequel il reviendrait.
					CLAIR="$(python3 -c "
h='$TXT'
r,g,b=int(h[0:2],16),int(h[2:4],16),int(h[4:6],16)
def lin(v):
    v/=255.0
    return v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
print('oui' if 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b) > 0.5 else 'non')" 2>/dev/null)"
					if [[ "$CLAIR" = "oui" ]]; then
						ok "rangée survolée : GTK résout un texte CLAIR (#$TXT) — il était #000000 avant"
					else
						non "rangée survolée : GTK résout #$TXT, un texte sombre sur le fond sombre du menu — le défaut d'Alex est de retour"
					fi
					if [[ -n "$ALPHA" ]] && awk "BEGIN{exit !($ALPHA > 0.02)}"; then
						ok "…et le surlignage se peint vraiment (alpha $ALPHA), la rangée ne reste pas nue"
					else
						non "le surlignage reste transparent (alpha ${ALPHA:-?}) : rien ne montre la rangée survolée"
					fi
				fi
			fi
			kill "$XPID" 2>/dev/null; wait "$XPID" 2>/dev/null
		fi
	fi
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[[ "$ECHOUES" -eq 0 ]]
