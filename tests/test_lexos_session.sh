#!/usr/bin/env bash
# =============================================================================
#  Éprouver lexos-session — le bouton rouge
# =============================================================================
#  POURQUOI CE BANC EXISTE, ET POURQUOI IL EST PARTICULIER.
#
#  Tous les autres outils de LexOS, on peut les lancer pour voir. Celui-ci
#  ÉTEINT LA MACHINE. On ne le relit donc pas en hochant la tête — on lui
#  donne de faux outils sur un PATH fermé, et on regarde ce qu'il appelle.
#
#  DEUX RÉGIMES, ET LES DEUX COMPTENT :
#
#    · LEXOS_SESSION_SIMULE=1 — le programme ÉCRIT la commande au lieu de
#      l'exécuter, et « dispo » répond oui à tout. C'est le seul moyen
#      d'éprouver le CHEMIN NORMAL (celui d'une vraie machine XFCE) depuis
#      un conteneur qui n'a ni xfce4-session-logout ni dm-tool.
#
#    · PATH FERMÉ + faux outils — la simulation est ÉTEINTE, « dispo » et
#      « lancer » travaillent pour de vrai, et les faux outils écrivent
#      dans un journal. C'est ce régime-là qui éprouve les REPLIS : sans
#      xfce4-session-logout, est-ce bien systemctl qui prend le relais ?
#      Sans rien du tout, est-ce qu'il le DIT au lieu de rendre 0 ?
#
#  Le second régime est indispensable : en simulation, « dispo » répond oui
#  à tout, donc le premier outil de chaque liste gagne toujours et aucun
#  repli n'est jamais emprunté. Un banc qui n'aurait que la simulation
#  déclarerait les replis corrects sans en avoir exécuté un seul.
# =============================================================================
set -u

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-session"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -x "$OUTIL" ] || { echo "lexos-session introuvable ou non exécutable"; exit 1; }

# --- Un PATH fermé : rien d'autre que ce qu'on y met -------------------------
#  Sans ça, « systemctl absent » ne prouverait rien : la machine hôte
#  pourrait en avoir un vrai, et le repli ne serait jamais éprouvé. C'est
#  l'erreur commise sur test_lexos_materiel, corrigée là-bas puis reprise
#  ici d'emblée.
NECESSAIRES="bash sh env cat id printf echo command"
ferme_path() {
	rm -rf "${BANC:?}/min"; mkdir -p "$BANC/min"
	for c in $NECESSAIRES; do
		reel="$(command -v "$c" 2>/dev/null)" && ln -sf "$reel" "$BANC/min/$c"
	done
}

JOURNAL="$BANC/appels.txt"

#  Fabrique de faux outils qui NOTENT ce qu'on leur demande.
faux() {
	rm -rf "${BANC:?}/bin"; mkdir -p "$BANC/bin"
	for n in "$@"; do
		cat > "$BANC/bin/$n" <<SH
#!/bin/sh
echo "$n \$*" >> "$JOURNAL"
SH
		chmod +x "$BANC/bin/$n"
	done
}

#  Lance l'outil sans simulation, sur le PATH fermé + les faux outils.
reel() {
	: > "$JOURNAL"
	PATH="$BANC/bin:$BANC/min" DISPLAY=":0" "$OUTIL" "$@" 2>"$BANC/err.txt"
	echo "$?" > "$BANC/rc.txt"
}
rc()      { cat "$BANC/rc.txt"; }
appels()  { cat "$JOURNAL" 2>/dev/null; }
erreurs() { cat "$BANC/err.txt" 2>/dev/null; }

#  Lance l'outil en simulation : il écrit la commande qu'il aurait lancée.
simule() { LEXOS_SESSION_SIMULE=1 DISPLAY=":0" "$OUTIL" "$@" 2>&1; }

ferme_path

# ═════════════════════════════════════════════════════════════════════════════
titre "1. Chaque geste appelle la bonne commande (chemin normal)"
#  Ce que fait une VRAIE machine LexOS : xfce4-session-logout est là, dm-tool
#  aussi. On vérifie le premier choix de chaque liste, et les options.
declare -A ATTENDU=(
	[eteindre]="xfce4-session-logout --halt --fast"
	[redemarrer]="xfce4-session-logout --reboot --fast"
	[veille]="xfce4-session-logout --suspend"
	[deconnexion]="xfce4-session-logout --logout --fast"
	[utilisateur]="dm-tool switch-to-greeter"
	[verrouiller]="xflock4"
)
for g in eteindre redemarrer veille deconnexion utilisateur verrouiller; do
	VU="$(simule "$g")"
	if [ "$VU" = "${ATTENDU[$g]}" ]; then
		ok "« $g » -> ${ATTENDU[$g]}"
	else
		non "« $g » a donné « $VU » au lieu de « ${ATTENDU[$g]} »"
	fi
done

#  « --fast » sur l'arrêt, le redémarrage et la déconnexion, PAS sur la
#  veille : xfce4-session-logout demanderait sinon confirmation par-dessus
#  NOTRE fenêtre, qui est déjà la confirmation. Deux questions pour un geste,
#  c'est une de trop — et c'est le genre de détail qui se perd à la
#  relecture suivante si rien ne le tient.
[ "$(simule veille)" = "xfce4-session-logout --suspend" ] \
	&& ok "la veille ne porte pas « --fast » (rien à enregistrer)" \
	|| non "la veille a changé d'options"

#  ═══ LA FENÊTRE EST CELLE DE XFCE ═══
#  ALEX, consigne « fenêtre d'arrêt » : sans argument, le bouton rouge ouvre
#  le dialogue de XFCE. Lu dans xfce4-session-logout/main.c (4.20, trixie) :
#  sans option d'action, il appelle Logout(show_dialog=TRUE) — c'est SA
#  fenêtre, pas la nôtre. Et sans « --fast » : la case « enregistrer la
#  session » est à lui.
[ "$(simule)" = "xfce4-session-logout" ] \
	&& ok "sans argument -> xfce4-session-logout seul : la fenêtre de XFCE, sans --fast" \
	|| non "sans argument il a donné « $(simule) » au lieu d'ouvrir la fenêtre de XFCE"

# ═════════════════════════════════════════════════════════════════════════════
titre "2. Les replis, éprouvés pour de vrai (pas en simulation)"
#  Sans xfce4-session-logout : systemctl doit prendre le relais.
faux systemctl loginctl dm-tool
reel eteindre
[ "$(appels)" = "systemctl poweroff" ] \
	&& ok "sans xfce4-session-logout, l'arrêt passe par systemctl" \
	|| non "repli 1 de l'arrêt : « $(appels) »"

reel deconnexion
#  Sans XDG_SESSION_ID, loginctl ne saurait pas QUELLE session terminer :
#  l'outil doit s'abstenir plutôt que d'en couper une au hasard.
[ -z "$(appels)" ] && [ "$(rc)" != "0" ] \
	&& ok "déconnexion sans XDG_SESSION_ID : on s'abstient et on le dit" \
	|| non "il a tenté quelque chose sans savoir quelle session : « $(appels) »"

: > "$JOURNAL"
PATH="$BANC/bin:$BANC/min" DISPLAY=":0" XDG_SESSION_ID="c7" "$OUTIL" deconnexion 2>/dev/null
[ "$(appels)" = "loginctl terminate-session c7" ] \
	&& ok "avec XDG_SESSION_ID, il termine LA BONNE session" \
	|| non "repli de déconnexion : « $(appels) »"

#  Sans systemctl non plus : loginctl.
faux loginctl
reel eteindre
[ "$(appels)" = "loginctl poweroff" ] \
	&& ok "sans systemctl non plus, l'arrêt passe par loginctl" \
	|| non "repli 2 de l'arrêt : « $(appels) »"

#  Plus rien du tout : il doit le DIRE et rendre non-zéro. Une machine qui
#  ne s'éteint pas ET ne dit rien, c'est quelqu'un qui reclique dix fois.
faux
reel eteindre
if [ "$(rc)" != "0" ] && erreurs | grep -q "rien pour éteindre"; then
	ok "sans aucun outil, il refuse ET nomme ce qui manque"
else
	non "sans outil : rc=$(rc), message « $(erreurs) »"
fi

faux
reel utilisateur
if [ "$(rc)" != "0" ] && erreurs | grep -qi "gestionnaire de connexion"; then
	ok "sans gestionnaire de connexion, il le dit au lieu de faire semblant"
else
	non "changement d'utilisateur sans dm-tool : rc=$(rc), « $(erreurs) »"
fi

#  VERROUILLER — les mêmes replis en cascade que les autres gestes.
faux light-locker-command xfce4-screensaver-command loginctl
reel verrouiller
[ "$(appels)" = "light-locker-command -l" ] \
	&& ok "sans xflock4, verrouiller passe par light-locker-command -l" \
	|| non "repli 1 de verrouiller : « $(appels) »"

faux xfce4-screensaver-command loginctl
reel verrouiller
[ "$(appels)" = "xfce4-screensaver-command -l" ] \
	&& ok "sans light-locker non plus, xfce4-screensaver-command -l prend le relais" \
	|| non "repli 2 de verrouiller : « $(appels) »"

faux loginctl
reel verrouiller
[ "$(appels)" = "loginctl lock-session" ] \
	&& ok "en tout dernier recours, loginctl lock-session" \
	|| non "repli 3 de verrouiller : « $(appels) »"

faux
reel verrouiller
if [ "$(rc)" != "0" ] && erreurs | grep -q "rien pour verrouiller"; then
	ok "sans aucun outil de verrouillage, il le dit au lieu de rendre 0 en silence"
else
	non "verrouiller sans outil : rc=$(rc), « $(erreurs) »"
fi

#  ═══ LA FENÊTRE, EN VRAI : XFCE D'ABORD, LA NÔTRE EN REPLI ═══
#  Avec xfce4-session-logout sur le PATH, c'est lui — et rien d'autre — qui
#  est appelé, sans aucune option. yad est là aussi, pour prouver qu'il
#  n'est PAS préféré.
faux xfce4-session-logout yad zenity systemctl
reel
if [ "$(appels | sed 's/[[:space:]]*$//')" = "xfce4-session-logout" ]; then
	ok "avec xfce4-session-logout présent, la fenêtre est la sienne (yad présent mais ignoré)"
else
	non "avec xfce4-session-logout présent, il a lancé : « $(appels) »"
fi
#  Sans lui : notre fenêtre yad — les CINQ gestes de XFCE, et pas
#  « Verrouiller l'écran », que XFCE n'y met pas non plus.
faux yad zenity systemctl
reel
FEN="$(appels)"
case "$FEN" in
	"yad --list "*) ok "sans xfce4-session-logout, la fenêtre yad s'ouvre (en liste)" ;;
	*) non "sans xfce4-session-logout, il a lancé : « $FEN »" ;;
esac
MANQUE_FEN=""
for L in "Changer d'utilisateur" "Déconnexion" "Éteindre" "Redémarrer" "Mise en veille"; do
	grep -qF -- "$L" <<< "$FEN" || MANQUE_FEN="$MANQUE_FEN « $L »"
done
[ -z "$MANQUE_FEN" ] \
	&& ok "…avec les cinq gestes de la fenêtre de XFCE" \
	|| non "…il manque à la fenêtre yad :$MANQUE_FEN"
if grep -qF "Verrouiller" <<< "$FEN"; then
	non "la fenêtre yad propose encore « Verrouiller l'écran » — la fenêtre de XFCE ne l'a pas"
else
	ok "…et sans « Verrouiller l'écran » : les deux fenêtres disent la même chose"
fi
#  Ni xfce4-session-logout ni yad : zenity, même liste.
faux zenity systemctl
reel
FEN="$(appels)"
case "$FEN" in
	"zenity --list "*) ok "sans yad non plus, zenity prend le relais (en liste)" ;;
	*) non "sans yad, il a lancé : « $FEN »" ;;
esac
if grep -qF "Éteindre" <<< "$FEN" && ! grep -qF "Verrouiller" <<< "$FEN"; then
	ok "…zenity : « Éteindre » y est, « Verrouiller l'écran » n'y est pas"
else
	non "…zenity : « $FEN »"
fi

# ═════════════════════════════════════════════════════════════════════════════
titre "3. Sans écran, il ne coupe RIEN"
#  Le piège de cette famille d'outils : « pas d'affichage » ne doit surtout
#  pas vouloir dire « fais-le quand même ». Quelqu'un en ssh qui tape
#  « lexos session » par curiosité ne doit pas éteindre la machine de
#  quelqu'un d'autre.
faux xfce4-session-logout systemctl loginctl dm-tool
: > "$JOURNAL"
SORTIE="$(PATH="$BANC/bin:$BANC/min" env -u DISPLAY -u WAYLAND_DISPLAY "$OUTIL" 2>&1)"
RC=$?
[ -z "$(appels)" ] \
	&& ok "sans écran, aucune commande n'est lancée" \
	|| non "sans écran il a lancé : « $(appels) »"
[ "$RC" = "0" ] \
	&& ok "et il sort proprement (code 0)" \
	|| non "code de sortie $RC sans écran"
echo "$SORTIE" | grep -q "lexos session eteindre" \
	&& ok "il dit quoi taper à la place" \
	|| non "aucune indication en console"

# ═════════════════════════════════════════════════════════════════════════════
titre "4. Ce qu'il doit refuser"
faux xfce4-session-logout systemctl loginctl dm-tool
reel nimportequoi
[ "$(rc)" != "0" ] && [ -z "$(appels)" ] \
	&& ok "un geste inconnu est refusé, et rien n'est lancé" \
	|| non "geste inconnu : rc=$(rc), appels « $(appels) »"

reel aide
[ "$(rc)" = "0" ] && [ -z "$(appels)" ] \
	&& ok "« aide » n'exécute rien" \
	|| non "« aide » a lancé quelque chose : « $(appels) »"

# ═════════════════════════════════════════════════════════════════════════════
titre "5. Le greffon d'actions a disparu de la barre — tout vit dans la fenêtre"
# ═════════════════════════════════════════════════════════════════════════════
#  DEUXIÈME PASSE, APRÈS LES PHOTOS DE TROP D'OUTILS ET DU DAMIER GRIS. Le
#  greffon 8 (« actions » : verrouiller, veille, redémarrer) devait d'abord
#  garder verrouiller ; Alex l'a ensuite jugé inutile ET a demandé que tout
#  rejoigne le bouton rouge. Le greffon 8 n'existe donc plus DU TOUT, ni son
#  numéro dans plugin-ids : s'il restait quelque part, aux deux endroits ou
#  à aucun, personne ne s'en apercevrait avant la photo suivante.
PANEL="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
PRESENT_8="$(python3 - "$PANEL" <<'PYXML8'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
print(any(p.get("name") == "plugin-8" for p in r.iter("property")))
PYXML8
)"
[ "$PRESENT_8" = "False" ] \
	&& ok "le greffon 8 (verrouiller/veille/redémarrer) n'existe plus dans le panneau" \
	|| non "le greffon 8 est encore défini — les trois boutons d'origine sont peut-être encore là"

DANS_IDS_8="$(python3 - "$PANEL" <<'PYIDS8'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for p in r.iter("property"):
    if p.get("name") == "plugin-ids":
        print("8" in [v.get("value") for v in p])
PYIDS8
)"
[ "$DANS_IDS_8" = "False" ] \
	&& ok "et son numéro n'apparaît plus dans plugin-ids — pas de trou, pas de fantôme" \
	|| non "« 8 » traîne encore dans plugin-ids sans définition : XFCE afficherait un greffon cassé"

#  Et le bouton rouge doit toujours être le DERNIER greffon : c'est ce qui le
#  met tout à droite de l'écran, la demande d'Alex mot pour mot — ça n'a pas
#  changé en retirant le greffon 8.
DERNIER="$(python3 - "$PANEL" <<'PYLAST'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for p in r.iter("property"):
    if p.get("name") == "plugin-ids":
        print([v.get("value") for v in p][-1])
PYLAST
)"
[ "$DERNIER" = "17" ] \
	&& ok "le greffon 17 (bouton rouge) est le dernier — donc le plus à droite" \
	|| non "le dernier greffon est « $DERNIER », pas 17 : le rouge n'est pas au bout"

#  VEILLE ET REDÉMARRER DOIVENT DONC VIVRE ICI, DANS LA FENÊTRE — sinon ils
#  ont disparu du système tout entier, pas juste de la barre.
#
#  ═══ LA FENÊTRE A CHANGÉ DE FORME, ET CES CONTRÔLES AVEC ELLE ═══
#  ALEX : « j'aimerais que ce soit une petite fenêtre qui ouvre dans le
#  côté, au lieu de le voir comme sur la 2e image ». Les six gestes étaient
#  six BOUTONS DE DIALOGUE (--button="…:5") ; yad range ces boutons-là sur
#  une seule rangée horizontale et élargit la fenêtre jusqu'à ce qu'ils
#  tiennent tous — d'où la barre qui traversait l'écran. Ils sont devenus
#  les LIGNES d'une liste verticale, et l'aiguillage se fait maintenant sur
#  le libellé rendu, plus sur un code de sortie. On éprouve donc la ligne ET
#  son aiguillage, comme avant, mais dans la nouvelle forme.
#  ═══ LA LIGNE PORTE MAINTENANT DEUX COLONNES ═══
#  ALEX : « on aimerait ajouter des logos où la fenêtre pour fermer ou
#  redémarrer l'ordinateur. » Chaque geste est précédé de son image, désignée
#  par un CHEMIN vers branding/ — pas par un nom d'icône qu'on espérerait
#  trouver dans le thème, le pari qui a coûté trois ISO au gestionnaire de
#  fichiers.
#
#  On éprouve les deux d'un coup, et c'est voulu : un libellé qui perdrait
#  son image ne serait plus la fenêtre qu'Alex a demandée.
verifie_geste() { # verifie_geste <libellé> <fonction> <nom de l'image>
	#  Les lignes de la liste se terminent par «  \ » (continuation) : le
	#  motif doit l'accepter, sinon aucune ne correspond jamais.
	grep -qE "^[[:space:]]+\"\\\$IMG_$(printf '%s' "$3" | tr '[:lower:]' '[:upper:]')\"[[:space:]]+\"$1\"[[:space:]]*\\\\?$" "$OUTIL" \
		&& ok "la fenêtre propose « $1 », avec son logo ($3)" \
		|| non "« $1 » a disparu de la fenêtre, ou a perdu son logo"
	grep -qE "\"$1\"\)[[:space:]]+$2 ;;" "$OUTIL" \
		&& ok "…et « $1 » appelle bien le geste $2()" \
		|| non "« $1 » est affiché mais n'appelle rien"
}
verifie_geste "Redémarrer" redemarrer redemarrer
verifie_geste "Mise en veille" veille veille
verifie_geste "Éteindre" eteindre arret
verifie_geste "Déconnexion" deconnexion deconnexion
verifie_geste "Changer d'utilisateur" changer_utilisateur utilisateur

#  LA PETITE FENÊTRE SUR LE CÔTÉ, c'est la demande elle-même : une liste
#  verticale (la largeur ne dépend plus du nombre de gestes) et une position
#  calculée sur le bord, pas au centre.
grep -q -- '--list' "$OUTIL" \
	&& ok "les gestes sont une LISTE verticale — la fenêtre peut rester étroite" \
	|| non "la fenêtre emploie encore des boutons en rangée : elle traversera l'écran"
grep -q -- '--posx=' "$OUTIL" \
	&& ok "elle s'ouvre sur le côté (position calculée d'après la largeur de l'écran)" \
	|| non "aucune position : la fenêtre resterait au centre"
grep -q 'POSITION=(--center)' "$OUTIL" \
	&& ok "…et sans xrandr, elle retombe au centre plutôt que sur une position inventée" \
	|| non "sans xrandr, la position serait devinée"

#  VERROUILLER — QUATRIÈME PASSE. Jugé inutile devant un damier gris (l'icône
#  CASSÉE du greffon, pas le verrouillage), redemandé dans la fenêtre, puis
#  SORTI de la fenêtre avec la consigne « fenêtre d'arrêt » : la fenêtre est
#  celle de XFCE, qui n'a pas de bouton de verrouillage, et notre repli
#  montre les mêmes gestes qu'elle. Le geste reste en ligne de commande,
#  par xflock4. On vérifie donc les DEUX : absent des listes, présent au CLI.
LISTES="$(sed -n '/yad --list/,/^fi$/p; /zenity --list/,/^fi$/p' "$OUTIL" | grep -Ev '^[[:space:]]*#')"
if grep -qF "Verrouiller" <<< "$LISTES"; then
	non "« Verrouiller l'écran » est encore dans une liste (yad ou zenity) — la fenêtre de XFCE ne l'a pas"
else
	ok "« Verrouiller l'écran » n'est plus dans aucune liste de la fenêtre (lignes de code, commentaires exclus)"
fi
grep -q 'dispo xflock4' "$OUTIL" \
	&& ok "verrouiller() reste un geste en ligne de commande, par xflock4" \
	|| non "verrouiller() ne s'appuie plus sur xflock4"

# ═════════════════════════════════════════════════════════════════════════════
titre "6. Un logo par geste — et ils EXISTENT vraiment"
# ═════════════════════════════════════════════════════════════════════════════
#  ALEX, photo de la fenêtre : « on aimerait ajouter des logos où la fenêtre
#  pour fermer ou redémarrer l'ordinateur. » Six lignes de texte nu, toutes
#  de la même couleur — rien ne distinguait « Déconnexion » d'« Éteindre »
#  avant de les avoir lues, et ce sont les deux qu'on ne veut pas confondre.
#
#  ═══ POURQUOI CE BANC OUVRE LES FICHIERS ═══
#  Vérifier que le script CITE six images ne prouve rien : cinq d'entre elles
#  viennent d'être dessinées, et un chemin qui ne mène à rien laisse une case
#  vide sans le moindre message. C'est le défaut exact de l'icône du
#  gestionnaire de fichiers — un correctif qui se lit bien et ne s'exécute
#  jamais. On ouvre donc chaque fichier, on le REND à 28 px (la taille réelle
#  dans la liste) et on compte les pixels peints.
BRANDING="$RACINE/branding"
IMAGES="utilisateur deconnexion arret redemarrer veille verrouiller"

for I in $IMAGES; do
	F="$BRANDING/icon-$I.svg"
	if [ ! -r "$F" ]; then
		non "« icon-$I.svg » manque : la ligne correspondante n'aurait pas d'image"
		continue
	fi
	if ! python3 -c "import xml.etree.ElementTree as E,sys; E.parse(sys.argv[1])" "$F" 2>/dev/null; then
		non "« icon-$I.svg » n'est pas un SVG valide"
		continue
	fi
	#  ET IL DOIT DESSINER QUELQUE CHOSE. Un SVG parfaitement valide et
	#  entièrement transparent passerait les deux contrôles ci-dessus.
	if command -v rsvg-convert >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
		PEINTS="$(rsvg-convert -w 28 -h 28 -o "$BANC/$I.png" "$F" 2>/dev/null \
			&& python3 -c "
from PIL import Image
import sys
a = Image.open(sys.argv[1]).convert('RGBA').getchannel('A')
print(sum(n for v, n in enumerate(a.histogram()) if v > 40))
" "$BANC/$I.png")"
		if [ "${PEINTS:-0}" -ge 60 ]; then
			ok "« icon-$I.svg » se rend et peint $PEINTS pixels à 28 px — visible dans la liste"
		else
			non "« icon-$I.svg » ne peint que ${PEINTS:-0} pixels à 28 px : invisible ou presque"
		fi
	else
		non "rsvg-convert ou Pillow absent : « icon-$I.svg » n'a PAS été rendu"
	fi
done

#  ═══ LA COULEUR DIT LE DANGER, ET ELLE NE SUIT PAS L'ACCENT ═══
#  Même règle que l'en-tête de branding/icon-arret.svg : le rouge n'est pas
#  une préférence, c'est un avertissement. Sous un accent vert, une flèche de
#  redémarrage verte dirait « vas-y » à l'endroit précis où il faut dire
#  « attention ». Les quatre autres gestes ne coupent rien : ils portent le
#  jeton #E8590C et suivent donc l'accent choisi.
#  ON DÉPOUILLE LES COMMENTAIRES D'ABORD. Premier jet de ce contrôle : il
#  déclarait icon-arret.svg fautive parce que son EN-TÊTE explique pourquoi
#  elle ne porte pas #E8590C — le mot y était, dans une phrase qui dit le
#  contraire. Ce dépôt s'est déjà fait prendre trois fois par un banc qui
#  lisait de la prose ; on lit le dessin.
couleurs() { # couleurs <fichier svg> -> le SVG sans ses commentaires
	python3 -c "
import re, sys
print(re.sub(r'<!--[\s\S]*?-->', '', open(sys.argv[1], encoding='utf-8').read()))
" "$1"
}
for I in arret redemarrer; do
	D="$(couleurs "$BRANDING/icon-$I.svg")"
	if printf '%s' "$D" | grep -q '#E5484D' && ! printf '%s' "$D" | grep -q '#E8590C'; then
		ok "« $I » est rouge d'avertissement et NE suit pas l'accent"
	else
		non "« $I » coupe la machine et devrait rester rouge, jamais teint par l'accent"
	fi
done
#  ═══ LE PIÈGE QU'UNE MAQUETTE A ATTRAPÉ AVANT LA LIVRAISON ═══
#  Les quatre logos neutres étaient d'abord à l'accent, comme le reste du
#  système. Une maquette de la fenêtre l'a réfuté : la ligne SÉLECTIONNÉE est
#  peinte en accent (règle « treeview.view:selected » de lexos-theme-gen) et
#  yad sélectionne la première d'office — le logo qu'on regarde aurait été le
#  seul invisible. Contrastes calculés : l'accent donne 4,9:1 sur le panneau
#  noir mais 1,0:1 sur lui-même ; le blanc donne 18,4:1 et 3,4:1.
#  Ce contrôle-là empêche quiconque de « rétablir » l'accent sans revivre le
#  même défaut.
for I in utilisateur deconnexion veille verrouiller; do
	D="$(couleurs "$BRANDING/icon-$I.svg")"
	if printf '%s' "$D" | grep -q '#FFFFFF' \
		&& ! printf '%s' "$D" | grep -q '#E8590C' \
		&& ! printf '%s' "$D" | grep -q '#E5484D'; then
		ok "« $I » est blanc — visible aussi sur la ligne sélectionnée"
	else
		non "« $I » n'est pas blanc : à l'accent il disparaîtrait sur la ligne sélectionnée"
	fi
done

#  ═══ ET LE THÈME DE JOUR N'EST PAS OUBLIÉ ═══
#  Du blanc sur du crème ne se voit pas davantage. lexos-theme-gen écrit une
#  copie à l'encre sombre que lexos-session préfère ; sans ce couple-là, le
#  thème de jour perdrait les six logos d'un coup.
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
grep -q 'SESSION_DST=' "$GEN" \
	&& ok "lexos-theme-gen écrit une copie des logos pour le thème de jour" \
	|| non "rien n'est prévu pour le mode clair : six logos blancs sur du crème"
grep -q 'rm -rf "$SESSION_DST"' "$GEN" \
	&& ok "…et il l'efface en repassant en sombre — sinon l'encre noire y resterait" \
	|| non "les copies du mode clair survivraient au retour en sombre : logos noirs sur noir"
grep -q 'SESSION_ICONES' "$OUTIL" \
	&& ok "…et la fenêtre préfère cette copie quand elle existe" \
	|| non "la fenêtre ignore la copie : elle serait écrite pour rien"

#  ON NE SE FIE PAS AU grep : on FAIT TOURNER le générateur dans les deux
#  modes et on regarde ce qu'il écrit. C'est la seule façon de savoir si la
#  substitution atteint vraiment les traits — un sed trop prudent (ou trop
#  gourmand, qui irait réécrire le commentaire) passerait le grep.
if [ -x "$GEN" ] || [ -r "$GEN" ]; then
	FOYER="$BANC/foyer"; mkdir -p "$FOYER"
	LEXOS_BRANDING="$BRANDING" HOME="$FOYER" bash "$GEN" orange --mode clair >/dev/null 2>&1
	CLAIR="$FOYER/.config/lexos/session-icons/icon-verrouiller.svg"
	if [ -r "$CLAIR" ] && grep -q 'stroke="#1B1A17"' "$CLAIR"; then
		ok "en mode clair, le trait passe VRAIMENT à l'encre sombre (#1B1A17)"
	else
		non "en mode clair, le trait n'a pas été réencré : logos blancs sur crème"
	fi
	if [ -r "$CLAIR" ] && grep -q 'POURQUOI BLANC' "$CLAIR"; then
		ok "…et le fichier garde son en-tête, qui explique pourquoi il est blanc"
	else
		non "l'en-tête a été emporté par la substitution : le fichier ne s'explique plus"
	fi
	LEXOS_BRANDING="$BRANDING" HOME="$FOYER" bash "$GEN" orange --mode sombre >/dev/null 2>&1
	if [ ! -d "$FOYER/.config/lexos/session-icons" ]; then
		ok "en repassant en sombre, les copies claires sont effacées"
	else
		non "les copies claires survivent au retour en sombre — logos noirs sur noir"
	fi
fi

#  ═══ ET LES CINQ DE LA FENÊTRE SONT BIEN CITÉS PAR ELLE ═══
#  Une image dessinée que personne n'affiche, c'est le travail d'hier :
#  cinq icônes livrées dans l'ISO et jamais regardées. icon-verrouiller.svg
#  est l'exception assumée : la fenêtre ne propose plus ce geste (quatrième
#  passe, voir la section 5), mais lexos-theme-gen la réencre encore pour le
#  jour et elle reste disponible ; elle ne doit simplement plus être citée.
IMAGES_FENETRE="utilisateur deconnexion arret redemarrer veille"
for I in $IMAGES_FENETRE; do
	grep -q "img $I " "$OUTIL" \
		&& ok "la fenêtre yad emploie « icon-$I.svg »" \
		|| non "« icon-$I.svg » est dessinée mais la fenêtre ne l'emploie pas"
done
grep -q "img verrouiller " "$OUTIL" \
	&& non "la fenêtre résout encore icon-verrouiller.svg pour un geste qu'elle ne montre plus" \
	|| ok "icon-verrouiller.svg n'est plus résolue par la fenêtre (le geste vit au CLI)"

#  Le repli zenity aussi : sans lui, une machine sans yad retomberait sur six
#  lignes nues et la demande ne serait honorée qu'à moitié.
#  Les six chemins sont résolus UNE FOIS dans des variables, et les deux
#  listes emploient les mêmes : deux listes écrites séparément finissent par
#  diverger sans que personne ne s'en aperçoive.
ZEN="$(sed -n '/zenity --list/,/Éteindre/p' "$OUTIL")"
MANQUE_ZEN=""
for I in $IMAGES_FENETRE; do
	V="IMG_$(printf '%s' "$I" | tr '[:lower:]' '[:upper:]')"
	printf '%s' "$ZEN" | grep -q "\$$V" || MANQUE_ZEN="$MANQUE_ZEN $I"
done
if [ -z "$MANQUE_ZEN" ]; then
	ok "le repli zenity montre les mêmes cinq logos (mêmes variables, pas une copie)"
else
	non "le repli zenity oublie :$MANQUE_ZEN"
fi
#  Et il ne doit pas montrer une liste à moitié illustrée : zenity ne sait
#  lire que des CHEMINS, un nom de thème y laisserait une case vide.
grep -q 'ZEN_IMAGES=0' "$OUTIL" \
	&& ok "…et il repasse en liste nue si une seule image manque, plutôt qu'à moitié" \
	|| non "aucun repli : une image manquante donnerait une liste bancale"

#  ═══ LE CHOIX RESTE LISIBLE APRÈS L'AJOUT DE LA COLONNE ═══
#  yad rend la colonne demandée par --print-column. Elle valait 1 quand le
#  libellé était seul ; l'image est passée devant, donc c'est 2. Rester à 1
#  ferait renvoyer un CHEMIN D'IMAGE au « case » — aucune branche ne
#  correspondrait, et la fenêtre se fermerait sans rien faire. Panne muette.
grep -q -- '--print-column=2' "$OUTIL" \
	&& ok "yad renvoie la colonne du LIBELLÉ (2), pas celle de l'image" \
	|| non "--print-column ne pointe pas sur le libellé : la fenêtre ne ferait plus rien"

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s réussi(s), %s échoué(s)\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
