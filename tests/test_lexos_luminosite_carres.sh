#!/usr/bin/env bash
# =============================================================================
#  Deux photos d'Alex, deux pannes, un banc
# =============================================================================
#  1. « encore dans des carrés noirs — écriture » (Logithèque). Les tuiles de
#     catégorie portent un dégradé coloré, et par-dessus un RECTANGLE NOIR
#     opaque contenant l'icône et le texte.
#
#     LA CAUSE, VÉRIFIÉE SUR LE VRAI BINAIRE. « strings /usr/bin/gnome-software »
#     livre le gabarit de la tuile :
#         <template class="GsCategoryTile" parent="GtkFlowBoxChild">
#           <child><object class="GtkBox" id="box">
#             <child><object class="GtkImage" id="image"/></child>
#             <child><object class="GtkLabel" id="label"/></child>
#     La tuile est un GtkFlowBoxChild, PAS un GtkButton. Notre thème peignait
#     « box » en noir opaque, et l'exception qui sauve les boutons
#     (« button box ») ne mordait donc pas. Un rectangle noir estampé sur le
#     dégradé — exactement la photo.
#
#  2. « les outils pour la luminosité fonctionnent, mais pas dans les
#     Paramètres. »
#
#     LA CAUSE : sudo ne peut pas demander de mot de passe sans terminal. Au
#     terminal il pose sa question et ça marche ; lancé par les Paramètres —
#     un service sans terminal — il refuse en silence. Même commande, même
#     machine, deux résultats. Et brightnessctl, quand il échouait faute de
#     droits, faisait mourir l'outil au lieu de retomber sur la voie qui SAIT
#     demander les droits.
#
#  ── CE QUE CE BANC ÉPROUVE ─────────────────────────────────────────────────
#  Il ne relit pas des intentions : il FAIT TOURNER lexos-brightness sur un
#  faux /sys et un PATH fermé, et regarde ce qui a été écrit. Le thème, lui,
#  est GÉNÉRÉ puis relu — pas grepé dans le script qui le fabrique.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

# =============================================================================
titre "1. Le thème ne peint plus de rectangle noir sur les tuiles colorées"
# =============================================================================
#  ON GÉNÈRE LE THÈME POUR DE VRAI. Greper le script qui l'écrit dirait que la
#  ligne existe, pas ce que GTK recevra. C'est la feuille livrée qu'on relit.
FOYER="$BANC/foyer"; mkdir -p "$FOYER"
LEXOS_SKEL="$RACINE/config/includes.chroot/etc/skel" LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" HOME="$FOYER" \
	bash "$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen" orange \
	>/dev/null 2>&1

CSS4="$FOYER/.themes/LexOS-Noir/gtk-4.0/gtk.css"
CSS3="$FOYER/.themes/LexOS-Noir/gtk-3.0/gtk.css"

if [[ -r "$CSS4" && -r "$CSS3" ]]; then
	ok "les deux feuilles (GTK 3 et GTK 4) ont bien été écrites"
else
	non "le thème n'a pas été généré — tout le reste de cette section serait creux"
fi

#  LE CŒUR DU CORRECTIF. « box » ne doit plus figurer dans une règle qui pose
#  un fond OPAQUE. On isole le sélecteur qui contient « box » et on lit sa
#  déclaration, plutôt que de deviner d'après l'ordre des lignes.
regle_de() { # regle_de <fichier> <noeud>  → le corps de la règle qui liste ce nœud
	python3 - "$1" "$2" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)          # les commentaires ne comptent pas
noeud = sys.argv[2]
for sel, corps in re.findall(r'([^{}]+)\{([^{}]*)\}', src):
    #  le nœud doit apparaître comme un sélecteur de type A LUI SEUL,
    #  pas en descendant (« button box ») ni en fragment (« flowbox »).
    #  LE PREMIER SÉLECTEUR TRAÎNE CE QUI LE PRÉCÈDE. Les « @define-color »
    #  ne sont pas des blocs : entre la dernière accolade fermante et
    #  « window » il y a trente lignes de définitions, et elles arrivent
    #  collées au premier nom. On ne garde donc que la dernière ligne.
    for part in (p.split('\n')[-1].strip() for p in sel.split(',')):
        if part == noeud:
            print(corps.strip().replace("\n", " "))
PY
}

for NOEUD in box grid overlay flowbox stack viewport frame; do
	CORPS="$(regle_de "$CSS4" "$NOEUD")"
	if [[ -z "$CORPS" ]]; then
		ok "« $NOEUD » n'est plus peint du tout — rien à estamper"
	elif grep -qi 'background-color:[[:space:]]*transparent' <<< "$CORPS" ; then
		ok "« $NOEUD » est transparent — le dégradé de la tuile se voit"
	else
		non "« $NOEUD » porte encore un fond opaque : $CORPS"
	fi
done

#  ET LES VRAIES SURFACES GARDENT LE FOND DU THÈME. Un correctif qui rendrait
#  la fenêtre transparente échangerait un défaut contre un pire.
#
#  ═══ ON LIT LA VALEUR, ON NE LA FIGE PLUS ═══
#  Ce contrôle exigeait « #000000 » écrit en dur. Le jour où Alex a choisi
#  #121214 pour le fond des fenêtres — un gris parmi trois qu'il a comparés —
#  il a rougi sur un changement PARFAITEMENT VOULU, en annonçant « le
#  correctif a débordé sur les surfaces », ce qui envoyait chercher au mauvais
#  endroit. Ce qu'il doit tenir, c'est que ces quatre nœuds portent LE FOND DU
#  THÈME et pas du transparent — pas qu'ils portent une couleur précise
#  décidée une fois.
BG_THEME="$(awk -F'"' '/^\tBG="#[0-9A-Fa-f]{6}"/{bg=$2} /^\tFG="#FFFFFF"/{print bg; exit}' \
	"$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen")"
if [[ ! "$BG_THEME" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
	non "fond du mode sombre illisible dans lexos-theme-gen — contrôle sans repère"
	BG_THEME="#000000"
fi
for NOEUD in window dialog popover textview; do
	CORPS="$(regle_de "$CSS4" "$NOEUD")"
	if grep -qiF "background-color: $BG_THEME" <<< "$CORPS" ; then
		ok "« $NOEUD » porte le fond du thème ($BG_THEME) — il n'a pas été rendu transparent"
	else
		non "« $NOEUD » ne porte plus le fond du thème ($BG_THEME) : $CORPS"
	fi
done

#  LA MÊME EXIGENCE EN GTK 3 : la Logithèque est en GTK 4, mais les deux
#  feuilles sortent du même générateur et une divergence serait invisible.
CORPS3="$(regle_de "$CSS3" "box")"
if [[ -z "$CORPS3" ]] || grep -qi 'transparent' <<< "$CORPS3"; then
	ok "GTK 3 dit la même chose que GTK 4"
else
	non "GTK 3 peint encore « box » en opaque : $CORPS3"
fi

# =============================================================================
titre "2. La luminosité se règle SANS terminal (le cas des Paramètres)"
# =============================================================================
#  ON FABRIQUE UN FAUX RÉTROÉCLAIRAGE, non inscriptible, et un PATH fermé où
#  « sudo » refuse (comme sans terminal) mais « pkexec » accepte. C'est
#  exactement la situation d'Alex : ça marche au terminal, pas aux Paramètres.
SYS="$BANC/sys/class/backlight/intel_backlight"; mkdir -p "$SYS"
printf '1000\n' > "$SYS/max_brightness"
printf '500\n'  > "$SYS/brightness"

OUTILS="$BANC/outils"; mkdir -p "$OUTILS"
JOURNAL="$BANC/appels.txt"; : > "$JOURNAL"

#  sudo qui REFUSE toujours : c'est ce que fait sudo sans terminal.
cat > "$OUTILS/sudo" <<SUDO
#!/bin/sh
printf 'sudo %s\n' "\$*" >> "$JOURNAL"
exit 1
SUDO
#  pkexec qui ACCEPTE : l'agent graphique de la session a répondu.
cat > "$OUTILS/pkexec" <<PKX
#!/bin/sh
printf 'pkexec %s\n' "\$*" >> "$JOURNAL"
shift_prog="\$1"; shift
exec "\$shift_prog" "\$@"
PKX
#  brightnessctl qui ÉCHOUE faute de droits — le compte n'est pas dans « video ».
cat > "$OUTILS/brightnessctl" <<BCTL
#!/bin/sh
printf 'brightnessctl %s\n' "\$*" >> "$JOURNAL"
exit 1
BCTL
chmod +x "$OUTILS"/*

#  Le banc a besoin de vrais outils de base : on les résout AVANT de fermer le
#  PATH, sinon c'est le banc qui casse et non le script qu'on éprouve.
for T in tee cat chmod mkdir printf awk sed grep basename; do
	P="$(command -v "$T" 2>/dev/null)" && [[ -e "$OUTILS/$T" ]] || \
		{ [[ -n "$P" ]] && ln -sf "$P" "$OUTILS/$T"; }
done

BRIGHT="$RACINE/config/includes.chroot/usr/bin/lexos-brightness"

#  POURQUOI ON SUPPRIME LE FICHIER AU LIEU DE LE PASSER EN LECTURE SEULE.
#  Ce banc peut tourner en root (c'est le cas dans la CI), et le noyau
#  n'applique PAS les droits d'accès à root : « chmod -w » suivi de
#  « [[ -w ]] » répond quand même « oui », le script prend la voie directe, et
#  on n'éprouverait jamais l'élévation de droits. Le fichier absent produit le
#  MÊME embranchement — « [[ -w ]] » est faux — pour root comme pour un compte
#  ordinaire. C'est le chemin de code d'Alex qu'on veut atteindre, pas la
#  reproduction littérale de ses permissions.
rm -f "$SYS/brightness"

SORTIE="$(LEXOS_BL="$BANC/sys/class/backlight" \
	PATH="$OUTILS:/usr/bin:/bin" NO_COLOR=1 \
	"$BASH" "$BRIGHT" 60 2>&1)"
CODE=$?

if grep -q '^pkexec' "$JOURNAL"; then
	ok "pkexec a été employé — la voie des Paramètres, celle qui sait demander le mot de passe"
else
	non "pkexec n'a jamais été appelé : sans terminal, le réglage reste refusé"
fi

if grep -q '^brightnessctl' "$JOURNAL"; then
	ok "brightnessctl a bien été essayé en premier (le moyen le plus propre)"
else
	non "brightnessctl n'a pas été essayé"
fi

#  ET SURTOUT : on n'est pas mort sur son échec.
if [[ "$CODE" -eq 0 ]]; then
	ok "l'échec de brightnessctl ne tue plus l'outil — il retombe sur /sys"
else
	non "l'outil a abandonné (code $CODE) : $(printf '%s' "$SORTIE" | tail -1)"
fi

#  LA VALEUR ÉCRITE EST LA BONNE : 60 % de 1000 = 600. Un banc qui vérifie
#  seulement « quelque chose a été écrit » laisserait passer un mauvais calcul.
VAL="$(cat "$SYS/brightness" 2>/dev/null)"
if [[ "$VAL" == "600" ]]; then
	ok "60 % de 1000 = 600 écrit dans le fichier — la bonne valeur, pas juste une écriture"
else
	non "valeur écrite : « $VAL » au lieu de 600"
fi

#  « sudo -n » AVANT pkexec, ET JAMAIS sudo SANS « -n ». Sans le drapeau,
#  sudo BLOQUE en attendant une saisie qui ne viendra jamais : le réglage ne
#  serait pas refusé, il serait SUSPENDU — pire qu'une erreur.
#  CE QUI COMPTE N'EST PAS QUE SUDO SOIT APPELÉ, MAIS QU'IL PORTE « -n ».
#  L'outil s'en sert d'abord comme SONDE (« sudo -n true » : ai-je le droit
#  sans mot de passe ?), et seulement ensuite pour écrire. Les deux doivent
#  porter le drapeau : sans lui, sudo attend une saisie qui ne viendra jamais
#  d'un service sans terminal, et le réglage ne serait pas refusé mais
#  SUSPENDU — pire qu'une erreur, parce qu'on ne voit rien du tout.
#
#  Une première version de ce contrôle exigeait que toute ligne « sudo » soit
#  « sudo -n tee », et criait donc sur la sonde « sudo -n true », pourtant
#  parfaitement correcte. C'était le contrôle qui avait tort, pas l'outil.
SANS_N="$(grep '^sudo ' "$JOURNAL" | grep -vE '^sudo -n ' || true)"
if [[ -n "$SANS_N" ]]; then
	non "sudo appelé sans « -n » — le service resterait bloqué : $SANS_N"
else
	ok "tout appel à sudo porte « -n » : rien ne peut bloquer sans terminal"
fi

# =============================================================================
titre "3. Le curseur des Paramètres ne cache plus les échecs"
# =============================================================================
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
CORPS_LUM="$(python3 - "$APP" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^async function setLum\b[\s\S]*?\n\}', s, re.M)
print(m.group(0) if m else "")
PY
)"

if [[ -n "$CORPS_LUM" ]]; then
	ok "setLum() a bien été trouvée"
else
	non "setLum() introuvable — les contrôles suivants seraient creux"
fi

if grep -q 'r.erreur\|erreur' <<< "$CORPS_LUM"; then
	ok "elle lit le motif du refus au lieu de jeter la réponse"
else
	non "elle jette encore la réponse : un refus resterait muet, comme sur la photo"
fi

if grep -q 'rafraichir(' <<< "$CORPS_LUM" ; then
	ok "elle rafraîchit — le curseur retombe sur la valeur réelle de la machine"
else
	non "elle ne rafraîchit pas : le curseur mentirait sur l'état de l'écran"
fi

# =============================================================================
titre "4. Le menu du clic droit est lisible (la photo du dock d'Alex)"
# =============================================================================
#  ALEX : « le menu quand on clique sur le bouton droit de la souris — il
#  ouvre le menu mais il est trop petit à mon goût, peux-tu faire en sorte
#  qu'il soit plus visible. »
#
#  LE MENU PHOTOGRAPHIÉ EST CELUI DE PLANK. « Épingler au Dock » est sa propre
#  traduction française de « _Keep in Dock » — relevée dans le plank.mo du
#  paquet, pas devinée. Plank dessine ses menus avec GTK : ça se règle donc
#  dans NOTRE feuille de style, pas dans un réglage de plank.
#
#  On éprouve la feuille GÉNÉRÉE, celle que GTK reçoit — pas le squelette qui
#  la nourrit : c'est la sortie qui compte.
corps_regle() { # corps_regle <fichier> <fragment de sélecteur>
	python3 -c '
import re, sys
src = re.sub(r"/\*.*?\*/", "", open(sys.argv[1], encoding="utf-8").read(), flags=re.S)
cible = sys.argv[2]
for sel, corps in re.findall(r"([^{}]+)\{([^{}]*)\}", src):
    if cible in " ".join(sel.split()):
        print(corps.strip().replace("\n", " "))
' "$1" "$2"
}

for V in 3 4; do
	F="$FOYER/.themes/LexOS-Noir/gtk-${V}.0/gtk.css"
	CORPS="$(corps_regle "$F" "menu menuitem")"
	if grep -q 'font-size:[[:space:]]*1\.12em' <<< "$CORPS"; then
		ok "GTK $V : les entrées de menu sont agrandies (1.12em)"
	else
		non "GTK $V : le menu n'a pas de taille agrandie — $CORPS"
	fi
	#  LA TAILLE SEULE NE SUFFIT PAS : à 4 px de haut les rangées se touchent
	#  et on clique la voisine. C'est le rembourrage qui fait la cible.
	if grep -qE 'padding:[[:space:]]*([89]|1[0-9])px' <<< "$CORPS"; then
		ok "GTK $V : les rangées sont assez hautes pour être visées"
	else
		non "GTK $V : rembourrage trop faible, les rangées se toucheraient — $CORPS"
	fi
done

#  ═══ « em », PAS DES PIXELS ═══ Une taille figée annulerait « lexos access
#  gros-texte » précisément là où il sert le plus. C'est la règle que le dépôt
#  s'était déjà donnée pour les boutons ; le menu doit la suivre.
CORPS="$(corps_regle "$FOYER/.themes/LexOS-Noir/gtk-3.0/gtk.css" "menu menuitem")"
if grep -qE 'font-size:[[:space:]]*[0-9]+px' <<< "$CORPS" ; then
	non "la taille du menu est figée en pixels : le gros-texte n'y ferait plus rien"
else
	ok "la taille est relative — elle suivra « lexos access gros-texte »"
fi

#  ═══ ET LES MENUS DE GTK 4 ═══ La même feuille sert aux deux versions, mais
#  GTK 4 n'emploie plus « menuitem » : sans règle « modelbutton », le correctif
#  ne vaudrait que pour la moitié des applications.
if grep -q 'popover.menu modelbutton' "$FOYER/.themes/LexOS-Noir/gtk-4.0/gtk.css"; then
	ok "les menus de GTK 4 (modelbutton) sont couverts eux aussi"
else
	non "GTK 4 non couvert : le clic droit resterait minuscule dans ces applications"
fi


printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
