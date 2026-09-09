#!/usr/bin/env bash
# =============================================================================
#  Éprouver l'extinction « TÉLÉVISEUR 1980 » — celle qui n'était nulle part
# =============================================================================
#  ALEX : « une animation pour fermer les fenêtres comme une vieille T.V. —
#  l'effet d'animation n'est pas là quand je ferme des fenêtres. »
#
#  IL AVAIT RAISON, ET CE N'ÉTAIT PAS UN RÉGLAGE DE TRAVERS.
#  L'effet était configuré — pour COMPIZ : 01-lexos-compiz pose
#  « close-effects = Glide 2 », qui est exactement ce geste. Mais Compiz a été
#  RETIRÉ de Debian trixie. lexos-wm cherche le binaire, ne le trouve pas,
#  écrit « compiz absent » et se replie sur xfwm4 — QUI N'A AUCUNE ANIMATION
#  d'ouverture ni de fermeture. Il n'y avait pas un réglage à corriger : il
#  n'y avait pas de moteur. L'interrupteur des Paramètres, lui, restait là et
#  ne commandait plus rien.
#
#  picom sait animer depuis sa v12 (son propre CHANGELOG : « Animations! Yes,
#  now picom officially supports animations », v12-rc1). C'est lui qui joue
#  l'extinction, avec un script écrit à la main.
#
#  CE QUE CE BANC SURVEILLE, ET POURQUOI CHAQUE POINT A COÛTÉ QUELQUE CHOSE :
#
#   · LE SCRIPT D'ANIMATION DOIT DÉFINIR « opacity » POUR LA FERMETURE. Le
#     manuel de picom le dit en toutes lettres : une variable de sortie non
#     définie prend la valeur par défaut de l'état, et pour « close » c'est 0 —
#     « so you will just see it disappear instantly ». L'animation jouerait
#     alors sur une fenêtre déjà invisible. C'est le piège qui donne un effet
#     « qui ne marche pas » sans la moindre erreur.
#
#   · L'ÉCHELLE A POUR ORIGINE LE COIN HAUT-GAUCHE. Sans les deux « offset »,
#     la fenêtre ne se referme pas sur son centre : elle se colle en haut. Ce
#     n'est plus un téléviseur, c'est un store qui tombe.
#
#   · LE SIGNE MOINS VEUT DES ESPACES AUTOUR. « 1-scale-y » n'est pas une
#     soustraction pour picom : c'est le NOM d'une variable, parce que les
#     noms peuvent contenir un tiret. Le manuel prévient ; on le vérifie.
#
#   · « TOURNE » NE DOIT PAS SE RECONNAÎTRE DANS N'IMPORTE QUELLE COMMANDE.
#     Mesuré pendant l'écriture : « pgrep -f <chemin de la config> » répondait
#     « en marche » sur une machine sans picom, parce que la commande qui
#     posait la question contenait ce chemin. Même défaut que le serveur de
#     partage, refait par distraction.
#
#   · ET LE COMPOSITEUR DE xfwm4 DOIT REVENIR quand picom s'arrête. Sans ce
#     retour, une panne de picom laisse un bureau sans ombres ni transparence,
#     et personne ne fait le lien avec une animation.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-crt"
WM="$RACINE/config/includes.chroot/usr/bin/lexos-wm"
CONF="$RACINE/config/includes.chroot/usr/share/lexos/picom/lexos-tv.conf"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
LISTE="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages/30-dock-effets.list"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

#  ═══ LE FOYER DU BANC EST AUSSI SON DOSSIER DE RÉGLAGES ═══
#  lexos-crt lit son état dans « ${XDG_CONFIG_HOME:-$HOME/.config}/lexos/crt ».
#  Poser HOME ne suffit donc PAS : là où XDG_CONFIG_HOME est déjà dans
#  l'environnement — c'est le cas du coureur de la CI — l'outil allait lire un
#  fichier que le banc n'écrit jamais, et « voulu() » rendait son défaut « on ».
#  Trois contrôles rougissaient pour cette seule raison : « effets éteints »
#  voyait un allumage, et les deux bascules répondaient à l'envers.
#  On épingle les DEUX variables, ensemble, partout où le banc joue au foyer.
export XDG_CONFIG_HOME="$BANC/foyer/.config"
mkdir -p "$XDG_CONFIG_HOME/lexos"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$WM" "$CONF" "$MOTEUR" "$PAGE" "$LISTE"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. LE SCRIPT D'ANIMATION — ce que le manuel de picom exige"
# =============================================================================
#  On lit le fichier livré. Chaque contrôle vient d'une phrase du manuel, pas
#  d'un goût : ce sont les quatre façons connues d'écrire une animation qui
#  ne se voit pas.
SANS_COM="$BANC/conf-nue"
sed 's/#.*$//' "$CONF" > "$SANS_COM"

grep -q 'triggers *= *\[ *"close" *\]' "$SANS_COM" \
	&& ok "un déclencheur « close » existe — c'est la demande d'Alex" \
	|| non "aucun déclencheur « close » : rien ne jouera à la fermeture"

grep -q 'triggers *= *\[ *"open" *\]' "$SANS_COM" \
	&& ok "et un déclencheur « open » : la fenêtre s'allume comme elle s'éteint" \
	|| non "aucun déclencheur « open »"

#  L'OPACITÉ, LE PIÈGE PRINCIPAL. On la cherche dans le bloc « close » lui-même,
#  pas n'importe où dans le fichier : la trouver dans le bloc « open » ne
#  prouverait rien.
python3 - "$SANS_COM" <<'PY' > "$BANC/blocs" 2>/dev/null || true
import re, sys
txt = open(sys.argv[1], encoding="utf-8").read()
#  Découper la liste « animations = ( {...}, {...} ) » en blocs de premier
#  niveau, en comptant les accolades.
d = txt.find("animations")
blocs, prof, debut = [], 0, None
for i, c in enumerate(txt[d:], start=d):
    if c == "{":
        if prof == 0:
            debut = i
        prof += 1
    elif c == "}":
        prof -= 1
        if prof == 0 and debut is not None:
            blocs.append(txt[debut:i + 1])
            debut = None
#  ON CHERCHE UNE AFFECTATION, PAS UNE SOUS-CHAÎNE. « blur-opacity » et
#  « shadow-opacity » CONTIENNENT le mot « opacity » : un simple « in b »
#  restait donc vrai après avoir retiré l'opacité elle-même. Mesuré — la
#  mutation qui enlève « opacity = { … } » du bloc « close » n'a pas fait
#  rougir la première version de ce banc, alors que c'est exactement le
#  défaut le plus grave que ce contrôle est censé attraper.
def affecte(bloc, nom):
    return re.search(r"(?m)^\s*" + re.escape(nom) + r"\s*=", bloc) is not None

for b in blocs:
    if '"close"' in b:
        print("CLOSE", *(affecte(b, n) for n in
                         ("opacity", "scale-y", "scale-x",
                          "offset-x", "offset-y", "shadow-opacity")))
PY
LU="$(grep '^CLOSE' "$BANC/blocs" | head -1)"
if [ -z "$LU" ]; then
	non "impossible de relire le bloc « close » du script — contrôle non joué"
else
	read -r _ O_ SY SX OX OY SO <<< "$LU"
	[ "$O_" = "True" ] \
		&& ok "le bloc « close » définit « opacity » — sans elle, la fenêtre est invisible dès la 1re image" \
		|| non "le bloc « close » ne définit PAS « opacity » : l'animation jouerait sur une fenêtre déjà transparente"
	[ "$SY" = "True" ] && [ "$SX" = "True" ] \
		&& ok "il écrase (scale-y) puis referme (scale-x) : les deux temps du tube cathodique" \
		|| non "il manque scale-x ou scale-y — ce n'est plus le geste d'un téléviseur"
	[ "$OX" = "True" ] && [ "$OY" = "True" ] \
		&& ok "les deux « offset » sont là : l'échelle a pour origine le coin haut-gauche, sans eux ça tombe en haut" \
		|| non "sans offset-x/offset-y, la fenêtre se colle en haut au lieu de se refermer sur son centre"
	[ "$SO" = "True" ] \
		&& ok "l'ombre est retirée pendant l'effet — une ombre pleine taille autour d'une ligne trahit le truc" \
		|| non "l'ombre reste pleine taille pendant l'écrasement"
fi

#  LE SIGNE MOINS. Le manuel : « minus signs in expressions must be surrounded
#  by spaces », parce qu'un nom de variable peut contenir un tiret.
#  ON NE PEUT PAS INTERDIRE TOUS LES TIRETS COLLÉS : « window-width »,
#  « scale-x » et « cubic-bezier » en portent, et ce sont des NOMS. La première
#  version de ce contrôle les accusait tous, et rendait rouge un fichier juste.
#  Ce qui distingue une soustraction, c'est un CHIFFRE ou une PARENTHÈSE contre
#  le tiret : « 1-scale-y », « )-x », « x-2 ». Aucun nom n'a cette forme.
if grep -qE '"[^"]*([0-9)]-|-[0-9(])[^"]*"' "$SANS_COM"; then
	non "une expression a un « - » collé à un chiffre ou une parenthèse : picom y lirait un nom"
else
	ok "aucune soustraction collée : les « - » de calcul ont leurs espaces"
fi

#  LES NOMS EMPLOYÉS EXISTENT-ILS VRAIMENT ? Ceux-ci sont relevés dans le
#  source de picom (src/wm/win.h et src/transition/script.c). Un nom inventé
#  serait accepté par libconfig comme une variable ordinaire — et n'animerait
#  rien, en silence.
MANQUE=""
for V in scale-x scale-y offset-x offset-y opacity blur-opacity shadow-opacity \
         window-width window-height duration delay start end curve; do
	grep -q -- "$V" "$SANS_COM" || MANQUE="$MANQUE $V"
done
[ -z "$MANQUE" ] \
	&& ok "les noms de variables employés sont ceux du moteur d'animation" \
	|| non "noms absents du script :$MANQUE"

# =============================================================================
titre "2. LE FICHIER EST LU PAR UN VRAI picom"
# =============================================================================
#  Une accolade oubliée ou un point-virgule manquant, et picom refuse tout le
#  fichier. Seul un vrai picom peut le dire.
if ! command -v picom >/dev/null 2>&1; then
	saute "picom absent : la syntaxe n'a PAS été éprouvée (installer picom)"
elif ! command -v xvfb-run >/dev/null 2>&1; then
	saute "xvfb-run absent : picom n'a pas d'écran pour lire le fichier"
else
	SORTIE="$(timeout 60 xvfb-run -a picom --config "$CONF" --diagnostics 2>&1)"
	case "$SORTIE" in
		*"Config file used"*)
			ok "picom lit le fichier et l'accepte (v$(picom --version 2>/dev/null | tr -d 'v'))" ;;
		#  UN FICHIER REFUSÉ ET UN picom QUI NE DÉMARRE PAS NE SONT PAS LA
		#  MÊME CHOSE. Sur un coureur sans pilote graphique, picom s'arrête
		#  avant d'avoir rien à dire du fichier — en conclure que le fichier
		#  est mauvais serait un rouge qui ne parle pas du code. On ne
		#  retient donc que ce que picom dit VRAIMENT de la configuration.
		*"syntax error"*|*"Failed to parse"*|*"onfig file"*[Ee]"rror"*)
			non "picom refuse le fichier :\n$(printf '%s' "$SORTIE" | head -5)" ;;
		*)
			saute "picom n'a pas pu démarrer ici (pas de pilote graphique) — la syntaxe n'a PAS été éprouvée" ;;
	esac
fi

# =============================================================================
titre "3. « EN MARCHE » NE DOIT PAS SE DÉCLENCHER SUR SON PROPRE NOM"
# =============================================================================
#  Le défaut mesuré pendant l'écriture : « pgrep -f <chemin> » se reconnaît
#  dans n'importe quelle commande citant ce chemin. On lance donc un leurre
#  qui le cite SANS être picom, et on regarde ce que l'outil répond.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le faux positif n'a PAS été éprouvé"
else
	CHEMIN_CONF="$(readlink -f "$CONF")"
	(exec -a "cat $CHEMIN_CONF" sleep 8) & LEURRE=$!
	sleep 0.3
	T="$(HOME="$BANC/foyer" bash "$OUTIL" --json 2>/dev/null \
		| python3 -c 'import json,sys; print(json.load(sys.stdin)["tourne"])' 2>/dev/null)"
	kill "$LEURRE" 2>/dev/null; wait "$LEURRE" 2>/dev/null
	[ "$T" = "False" ] \
		&& ok "un processus qui cite le fichier ne fait plus dire « en marche »" \
		|| non "l'outil se dit en marche ($T) à cause d'un processus qui cite son fichier"

	#  ET IL DOIT RECONNAÎTRE UN VRAI picom SUR NOTRE FICHIER. Un contrôle qui
	#  ne saurait que dire « non » passerait le contrôle ci-dessus sans rien
	#  valoir : c'est arrivé, à cause d'un chemin non normalisé
	#  (« /usr/bin/../share/… » n'est pas la même CHAÎNE que « /usr/share/… »).
	#  ═══ ON N'A PAS BESOIN D'UN COMPOSITEUR QUI MARCHE ═══
	#  Ce qu'on éprouve ici, c'est la RECONNAISSANCE : un processus nommé
	#  picom, dont la ligne de commande cite notre fichier. Lancer le vrai
	#  picom demandait un serveur X et un pilote graphique — absents du
	#  coureur de la CI, où il mourait aussitôt et faisait rougir le banc pour
	#  une raison qui n'a rien à voir avec le code.
	#
	#  Une COPIE de « sh » nommée « picom » a exactement la signature qui
	#  compte : /proc/<pid>/comm vaut « picom » — c'est le nom du FICHIER
	#  exécuté, pas argv[0], donc « exec -a picom … » ne suffirait pas — et sa
	#  ligne de commande porte le chemin de notre configuration.
	#
	#  « sh » et non « sleep » : sleep REFUSE les options qu'il ne connaît pas
	#  et s'arrête aussitôt, si bien qu'il n'y avait plus aucun processus à
	#  reconnaître au moment du contrôle. sh, lui, accepte n'importe quels
	#  arguments après « -c » et les garde dans sa ligne de commande.
	if command -v sh >/dev/null 2>&1; then
		mkdir -p "$BANC/faux"
		cp "$(command -v sh)" "$BANC/faux/picom"
		"$BANC/faux/picom" -c 'sleep 30' --config "$CHEMIN_CONF" &
		PPICOM=$!
		sleep 0.5
		T="$(HOME="$BANC/foyer" bash "$OUTIL" --json 2>/dev/null \
			| python3 -c 'import json,sys; print(json.load(sys.stdin)["tourne"])' 2>/dev/null)"
		#  ON TUE PAR PID, jamais par motif : « pkill -f <motif> » frappe tout
		#  ce qui cite ce motif, y compris le shell qui lance ce banc. Vécu.
		kill "$PPICOM" 2>/dev/null
		wait "$PPICOM" 2>/dev/null
		[ "$T" = "True" ] \
			&& ok "et il reconnaît un processus picom lancé sur notre fichier" \
			|| non "un processus picom tourne sur notre fichier et l'outil dit « $T »"
	else
		saute "« sleep » introuvable : la reconnaissance n'a PAS été éprouvée"
	fi
fi

# =============================================================================
titre "4. LES TROIS CONDITIONS, ET CE QUI SE PASSE QUAND ELLES MANQUENT"
# =============================================================================
#  On invente une machine : un picom dont on choisit la version, un glxinfo
#  dont on choisit la réponse, un xfconf-query qui NOTE ce qu'on lui demande.
mkdir -p "$BANC/bin" "$BANC/foyer"
cat > "$BANC/bin/glxinfo" <<'SH'
#!/bin/sh
if [ "${BANC_3D:-oui}" = "oui" ]; then
  printf 'direct rendering: Yes\nOpenGL renderer string: NVIDIA GeForce RTX 3060\n'
else
  printf 'direct rendering: Yes\nOpenGL renderer string: llvmpipe (LLVM 17)\n'
fi
SH
cat > "$BANC/bin/picom" <<'SH'
#!/bin/sh
case "$1" in
  --version) printf 'v%s\n' "${BANC_PICOM_V:-12.5}"; exit 0 ;;
esac
#  Un picom qui vit le temps qu'on lui dit, puis rend la main : c'est ce qui
#  permet d'éprouver le RETOUR du compositeur de xfwm4.
printf '%s\n' "$*" >> "${BANC_TRACE:?}"
sleep "${BANC_PICOM_VIE:-1}"
SH
cat > "$BANC/bin/xfconf-query" <<'SH'
#!/bin/sh
#  On ne note que ce qui nous intéresse : l'allumage du compositeur.
for a in "$@"; do
  case "$a" in true|false) printf 'compositing=%s\n' "$a" >> "${BANC_XFCONF:?}" ;;
  esac
done
exit 0
SH
chmod +x "$BANC/bin"/*
export BANC_TRACE="$BANC/picom-args" BANC_XFCONF="$BANC/xfconf"
: > "$BANC_TRACE"; : > "$BANC_XFCONF"
CHEMIN="$BANC/bin:$PATH"

essai_demarrer() { # $1 = version picom, $2 = 3D, $3 = ce qu'on attend
	: > "$BANC_TRACE"; : > "$BANC_XFCONF"
	PATH="$CHEMIN" HOME="$BANC/foyer" BANC_PICOM_V="$1" BANC_3D="$2" \
		LEXOS_CRT_DELAI=0 BANC_PICOM_VIE=1 \
		timeout 30 bash "$OUTIL" --demarrer >/dev/null 2>&1
}

printf 'on\n' > "$BANC/foyer/.config/lexos/crt" 2>/dev/null || {
	mkdir -p "$BANC/foyer/.config/lexos"; printf 'on\n' > "$BANC/foyer/.config/lexos/crt"; }

#  ═══ TOUT EST LÀ ═══
essai_demarrer 12.5 oui
if grep -q -- '--config' "$BANC_TRACE"; then
	ok "picom v12 + 3D réelle : picom est lancé avec notre fichier"
else
	non "picom v12 + 3D réelle : picom n'a PAS été lancé"
fi
grep -q 'compositing=false' "$BANC_XFCONF" \
	&& ok "le compositeur de xfwm4 est éteint pendant ce temps" \
	|| non "le compositeur de xfwm4 n'a pas été éteint : deux compositeurs se battraient"
#  LE RETOUR. C'est le contrôle qui protège d'un bureau sans ombres après une
#  panne : le faux picom rend la main au bout d'une seconde.
grep -q 'compositing=true' "$BANC_XFCONF" \
	&& ok "et il REVIENT quand picom s'arrête" \
	|| non "le compositeur de xfwm4 n'est pas rendu : un bureau sans ombres après la moindre panne"

#  ═══ PICOM TROP ANCIEN ═══
essai_demarrer 10 oui
if grep -q -- '--config' "$BANC_TRACE"; then
	non "picom v10 : lancé quand même — l'option « animations » n'existe pas avant la v12"
else
	ok "picom v10 : on ne le lance pas, il n'a pas d'animations"
fi
grep -q 'compositing=false' "$BANC_XFCONF" \
	&& non "picom v10 : le compositeur de xfwm4 a été éteint pour rien" \
	|| ok "picom v10 : on ne touche pas au compositeur de xfwm4"

#  ═══ PAS D'ACCÉLÉRATION 3D ═══
essai_demarrer 12.5 non
if grep -q -- '--config' "$BANC_TRACE"; then
	non "rendu logiciel : picom lancé quand même — la machine deviendrait collante"
else
	ok "rendu logiciel (llvmpipe) : on ne lance rien"
fi

#  ═══ EFFETS NON DEMANDÉS ═══
printf 'off\n' > "$BANC/foyer/.config/lexos/crt"
essai_demarrer 12.5 oui
if grep -q -- '--config' "$BANC_TRACE"; then
	non "effets éteints : picom lancé quand même"
else
	ok "effets éteints : rien n'est lancé"
fi
printf 'on\n' > "$BANC/foyer/.config/lexos/crt"

# =============================================================================
titre "5. LE MOTEUR DES PARAMÈTRES REFUSE CE QUI NE PEUT PAS MARCHER"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le moteur n'a PAS été éprouvé"
else
	cat > "$BANC/act.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import settings
try:
    for arg, bout, quoi in (
            ("on", "trop ancien", "allumer avec un picom trop ancien"),
            ("peut-etre", "valeur inattendue", "une valeur inventée")):
        r = settings.act_crt(arg)
        print(("OK|" if (not r.get("ok") and bout in r.get("erreur", "")) else "NON|") +
              "refusé : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))

    #  LA BASCULE. Elle ne se refuse QUE dans le sens de l'allumage : depuis
    #  « on », elle éteint, et éteindre est toujours permis. La première
    #  version de ce contrôle attendait un refus quel que soit le sens — elle
    #  accusait le code d'accepter ce qu'il avait parfaitement le droit
    #  d'accepter. On pose donc l'état AVANT, dans chaque sens.
    import pathlib
    etat_f = pathlib.Path(settings.os.environ["HOME"]) / ".config/lexos/crt"
    etat_f.parent.mkdir(parents=True, exist_ok=True)

    etat_f.write_text("off\n", encoding="utf-8")
    r = settings.act_crt("toggle")
    print(("OK|" if (not r.get("ok") and "trop ancien" in r.get("erreur", "")) else "NON|") +
          "la bascule depuis « off » veut allumer, et tombe sur le refus (%s)"
          % r.get("erreur", "ACCEPTÉ !"))

    etat_f.write_text("on\n", encoding="utf-8")
    r = settings.act_crt("toggle")
    print(("OK|" if r.get("ok") else "NON|") +
          "la bascule depuis « on » éteint, et c'est toujours permis (%s)"
          % r.get("erreur", "fait"))
    #  « off » doit RESTER possible même quand « on » est impossible : on doit
    #  toujours pouvoir éteindre ce qu'on n'arrive pas à allumer.
    r = settings.act_crt("off")
    print(("OK|" if r.get("ok") else "NON|") +
          "mais « off » reste possible (%s)" % r.get("erreur", "fait"))
except Exception as _e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")
PY
	SORTIE_A="$(cd "$RACINE" && PATH="$CHEMIN:$RACINE/config/includes.chroot/usr/bin" \
		HOME="$BANC/foyer" BANC_PICOM_V=10 BANC_3D=oui \
		python3 "$BANC/act.py" "$RACINE/config/includes.chroot/usr/lib/lexos" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_A" ]; then
		non "le moteur n'a rien rendu"
	elif ! grep -q '^FIN|' <<< "$SORTIE_A"; then
		non "le banc s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_A
EOF
	fi
fi

# =============================================================================
titre "6. LA PAGE DIT CE QUI MANQUE, AU LIEU D'UN INTERRUPTEUR MUET"
# =============================================================================
if ! command -v node >/dev/null 2>&1; then
	saute "node absent : la page n'a PAS été rendue"
else
	cat > "$BANC/rendu.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  + "\n;globalThis.__banc = { contenu, pose: e => { etat = e; } };\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}}, addEventListener(){} },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
const T = bac.__banc;
const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);
const base = {dispo:true, voulu:"on", tourne:true, picom:true,
              picom_version:12, picom_min:12, accel3d:true, script:true};
try {
  T.pose({crt: base});
  let h = T.contenu("apparence");
  dit(h.includes("basculeCrt()"), "tout est là : l'interrupteur est offert");
  dit(h.includes("En marche"), "et la page dit qu'il tourne");

  //  LES TROIS EMPÊCHEMENTS, CHACUN NOMMÉ. C'est tout l'enjeu : un
  //  interrupteur qui revient tout seul à sa place sans un mot est le geste le
  //  plus déroutant qu'une page puisse offrir.
  T.pose({crt: Object.assign({}, base, {picom:false, tourne:false})});
  h = T.contenu("apparence");
  dit(!h.includes("basculeCrt()") && h.includes("lexos install picom"),
      "picom absent : pas d'interrupteur, mais la commande qui l'installe");

  T.pose({crt: Object.assign({}, base, {picom_version:10, tourne:false})});
  h = T.contenu("apparence");
  dit(!h.includes("basculeCrt()") && h.includes("trop ancien"),
      "picom trop ancien : pas d'interrupteur, et on dit pourquoi");

  T.pose({crt: Object.assign({}, base, {accel3d:false, tourne:false})});
  h = T.contenu("apparence");
  dit(!h.includes("basculeCrt()") && h.includes("accélération 3D"),
      "pas de 3D : pas d'interrupteur, et on dit pourquoi");

  T.pose({crt: {}});
  h = T.contenu("apparence");
  dit(h.includes("lexos-crt n'a pas répondu"),
      "outil muet : la page le dit au lieu d'un interrupteur au hasard");

  //  L'ANCIENNE PROMESSE ÉTAIT FAUSSE : picom s'allume dans la session en
  //  cours, il n'y a plus rien à attendre.
  T.pose({crt: base});
  dit(!T.contenu("apparence").includes("prochaine ouverture de session"),
      "la page ne promet plus « à la prochaine ouverture de session »");
} catch (e) {
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS
	SORTIE_P="$(node "$BANC/rendu.js" "$PAGE" 2>&1 | grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_P" ]; then
		non "la page n'a rien rendu"
	elif ! grep -q '^FIN|' <<< "$SORTIE_P"; then
		non "le rendu s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_P
EOF
	fi
fi

# =============================================================================
titre "7. TOUT EST BRANCHÉ — l'ISO, la session, le routeur"
# =============================================================================
#  ═══ DANS LA LISTE STRICTE, ET DANS AUCUNE AUTRE ═══
#  CE QUE CE CONTRÔLE DISAIT AVANT : « picom est dans 30-dock-effets.list ».
#  Il l'était — et c'était le défaut. Cette liste-là, le hook 0250 l'installe
#  « au mieux » et TOLÈRE UNE ABSENCE EN SILENCE. Le contrôle bénissait donc
#  l'endroit exact où la fonction pouvait mourir sans un bruit.
#  Pour mesa-utils c'est pire encore : glxinfo n'est pas l'effet, c'est ce qui
#  DÉCIDE de l'effet — accel_3d() commence par « command -v glxinfo ». Sans
#  lui, la réponse est « pas d'accélération 3D réelle » sur une machine
#  parfaitement capable, et picom n'est jamais lancé.
STRICTE="$RACINE/config/package-lists/lexos-core.list.chroot"
for P in picom mesa-utils; do
	if grep -qE "^$P\$" "$STRICTE"; then
		ok "$P est dans la liste STRICTE : son absence arrête la construction"
	else
		non "$P n'est pas obligatoire — l'ISO peut sortir sans lui, en silence"
	fi
	#  ET NULLE PART AILLEURS. Un paquet dans les deux listes redevient
	#  « au mieux » pour le hook 0250, qui l'installe une seconde fois sans
	#  garde. La CI l'interdit ; le banc le vérifie ici aussi, parce que
	#  c'est ici qu'on saura pourquoi ça compte.
	if grep -qE "^$P\$" "$LISTE"; then
		non "$P est AUSSI dans 30-dock-effets.list : il redevient « au mieux »"
	else
		ok "$P n'est plus dans la liste « au mieux »"
	fi
done

sed 's/#.*$//' "$WM" > "$BANC/wm.sh"
grep -q 'lexos-crt --demarrer' "$BANC/wm.sh" \
	&& ok "lexos-wm lance le superviseur à l'ouverture de session" \
	|| non "personne ne lance lexos-crt : l'effet n'existerait qu'en tapant la commande"
grep -q 'setsid' "$BANC/wm.sh" \
	&& ok "…et détaché : la ligne suivante REMPLACE ce processus par xfwm4" \
	|| non "le superviseur n'est pas détaché — il mourrait au « exec xfwm4 »"

sed 's/#.*$//' "$RACINE/config/includes.chroot/usr/bin/lexos" > "$BANC/routeur.sh"
grep -q 'exec lexos-crt' "$BANC/routeur.sh" \
	&& ok "« lexos crt » mène à l'outil" \
	|| non "le routeur n'appelle pas lexos-crt"

sed 's/#.*$//' "$MOTEUR" > "$BANC/moteur.py"
grep -q 'lexos-crt' "$BANC/moteur.py" \
	&& ok "le moteur des Paramètres passe par lexos-crt" \
	|| non "le moteur ne passe pas par lexos-crt"
#  UNE SEULE DÉFINITION. En écrivant ceci, j'ai ajouté un act_crt et un
#  _crt_etat alors qu'il en existait déjà : Python garde le DERNIER, et
#  l'ancien interrupteur de la page lisait soudain un dictionnaire là où il
#  attendait un booléen. Un doublon ne fait pas d'erreur — il change qui gagne.
for F in act_crt _crt_etat; do
	N="$(grep -c "^def $F" "$MOTEUR")"
	[ "$N" = "1" ] \
		&& ok "une seule définition de $F" \
		|| non "$N définitions de $F : la dernière écrase l'autre en silence"
done
#  « _crt_etat, » et non « _crt_etat(), » : depuis que les collecteurs sont
#  lancés DE FRONT, la table d'etat() porte la fonction, pas son appel. Le
#  contrôle vise la clé et son collecteur — ce qui compte — pas la
#  ponctuation, qui a déjà changé une fois.
for C in '"crt": act_crt,' '"crt": _crt_etat,'; do
	N="$(grep -cF "$C" "$MOTEUR")"
	[ "$N" = "1" ] \
		&& ok "une seule entrée « $C »" \
		|| non "$N entrées « $C » : la dernière gagne, sans un mot"
done

# =============================================================================
titre "7bis. LES « rules » N'AVALENT PAS LES FENÊTRES ORDINAIRES"
# =============================================================================
#  ═══ CE QUE PERSONNE NE VÉRIFIAIT ═══
#  picom applique la PREMIÈRE règle qui correspond et s'arrête là (manuel,
#  section RULES). Une règle dont la condition est trop large avale donc les
#  fenêtres normales — et comme les deux règles de ce fichier remplacent
#  l'animation par un simple fondu de 80 ms, l'extinction « téléviseur » ne
#  jouerait plus JAMAIS. Le fichier resterait valide, picom démarrerait sans
#  se plaindre, et l'effet aurait disparu sans un mot.
#  L'ordre de la règle Whisker est déjà tenu par test_lexos_menu_whisker.sh ;
#  ce qui manquait, c'est de savoir CE QUE LES CONDITIONS ATTRAPENT.
#
#  ON LES ÉVALUE, ON NE LES LIT PAS. Un « grep window_type » dirait seulement
#  que le mot est là. On rejoue donc les opérateurs de picom employés ici
#  — « = » (égalité), « *= » (sous-chaîne), « || » — sur des fenêtres
#  représentatives, et on regarde laquelle attrape quoi.
#  ET SI UNE CONDITION EMPLOIE UN OPÉRATEUR QUE CE CONTRÔLE NE CONNAÎT PAS,
#  IL ROUGIT au lieu de conclure : un évaluateur qui ignore ce qu'il ne
#  comprend pas rendrait un vert qui ne prouve rien.
VERDICT="$(python3 - "$CONF" <<'PYEOF'
import re, sys

texte = open(sys.argv[1], encoding='utf-8').read()
#  Les conditions, DANS L'ORDRE du fichier : c'est l'ordre qui décide.
conditions = re.findall(r'match\s*=\s*"([^"]*)"', texte)
if not conditions:
    print("AUCUNE|aucune condition « match » trouvée dans le fichier")
    raise SystemExit

TERME = re.compile(r"^\s*(\w+)\s*(\*=|=)\s*'([^']*)'\s*$")

def attrape(cond, fen):
    for morceau in cond.split('||'):
        m = TERME.match(morceau)
        if not m:
            raise ValueError(morceau.strip())
        champ, op, val = m.group(1), m.group(2), m.group(3)
        vu = fen.get(champ)
        if vu is None:
            continue
        if (op == '=' and vu == val) or (op == '*=' and val in vu):
            return True
    return False

#  Quatre fenêtres, et ce qu'on attend de chacune.
CAS = [
    ("une fenêtre ordinaire (un terminal, un navigateur)",
     {"window_type": "normal", "name": "Terminal", "class_g": "Xfce4-terminal"}, None),
    ("une boîte de dialogue",
     {"window_type": "dialog", "name": "Enregistrer sous", "class_g": "Thunar"}, None),
    ("le menu Whisker",
     {"window_type": "menu", "name": "Whisker Menu", "class_g": "wrapper-2.0"}, 0),
    ("un menu contextuel (clic droit)",
     {"window_type": "popup_menu", "name": "", "class_g": "Thunar"}, 1),
]

for libelle, fen, attendu in CAS:
    try:
        touchee = next((i for i, c in enumerate(conditions) if attrape(c, fen)), None)
    except ValueError as e:
        print("INCONNU|opérateur non reconnu dans une condition : %s" % e)
        raise SystemExit
    if touchee == attendu:
        if attendu is None:
            print("OK|%s : aucune règle ne l'attrape → elle garde l'extinction « téléviseur »" % libelle)
        else:
            print("OK|%s : attrapée par la règle n° %d, celle qui lui est destinée" % (libelle, attendu + 1))
    elif attendu is None:
        print("NON|%s est AVALÉE par la règle n° %d : elle perdrait l'extinction « téléviseur »"
              % (libelle, touchee + 1))
    elif touchee is None:
        print("NON|%s n'est attrapée par AUCUNE règle : elle s'éteindrait comme un téléviseur, ce qui est trop lent pour elle" % libelle)
    else:
        print("NON|%s est attrapée par la règle n° %d au lieu de la n° %d"
              % (libelle, touchee + 1, attendu + 1))
PYEOF
)"
while IFS='|' read -r VERD MSG; do
	case "$VERD" in
		OK)  ok "$MSG" ;;
		NON) non "$MSG" ;;
		*)   non "les règles n'ont pas pu être évaluées : $MSG" ;;
	esac
done <<< "$VERDICT"

# =============================================================================
titre "8. L'EFFET EST-IL ALLUMÉ DANS CE QU'ON LIVRE ?"
# =============================================================================
#  ═══ LE TROU QUE CES QUARANTE CONTRÔLES LAISSAIENT ═══
#  Tout ce qui précède éprouve la MÉCANIQUE : le script d'animation est
#  conforme au manuel, un vrai picom le lit, les trois conditions sont
#  vérifiées, la page dit ce qui manque, tout est branché. Quarante contrôles,
#  zéro rouge — et l'effet ne jouait sur AUCUNE machine fraîchement installée.
#
#  MESURÉ : lexos.conf posait « LEXOS_CRT_EFFECTS="off" », build.sh le recopie
#  dans /etc/lexos/build.conf, et « voulu() » le lit AVANT tout le reste :
#
#      build.conf=on  -> voulu = on
#      build.conf=off -> voulu = off        ← ce qu'on livrait
#
#  Sur « off », cmd_demarrer écrit « effets non demandés — rien à faire » et
#  sort avant même de regarder si picom est là. Aucun des quarante contrôles
#  ne pouvait le voir : ils éprouvaient l'outil, jamais le RÉGLAGE LIVRÉ.
#  Un interrupteur en position « arrêt » n'est pas une panne de la machine ;
#  c'est quand même une fonction absente pour celui qui s'en sert.
CONF_LEXOS="$RACINE/lexos.conf"
DEFAUT="$(sed -n 's/^LEXOS_CRT_EFFECTS="\([^"]*\)".*/\1/p' "$CONF_LEXOS" | tail -1)"
[ "$DEFAUT" = "on" ] \
	&& ok "lexos.conf livre l'effet ALLUMÉ (LEXOS_CRT_EFFECTS=\"on\")" \
	|| non "lexos.conf livre « ${DEFAUT:-?} » : sur une machine neuve, l'animation ne joue jamais"

#  ET LA VALEUR VOYAGE VRAIMENT JUSQU'À L'ISO.
grep -q 'LEXOS_CRT_EFFECTS=' "$RACINE/build.sh" \
	&& ok "build.sh recopie ce réglage dans /etc/lexos/build.conf" \
	|| non "build.sh ne recopie pas LEXOS_CRT_EFFECTS : l'ISO ne saurait pas ce qu'on a choisi"

#  ═══ ON NE LIT PAS « voulu() », ON LA FAIT TOURNER ═══
#  Deux fichiers build.conf pour de vrai, et on demande son avis à l'outil.
#  C'est ce qui manquait : le chemin de build.conf était écrit en dur, donc
#  aucun banc ne pouvait éprouver la décision sans écrire dans /etc.
for V in on off; do
	FOYER="$BANC/voulu-$V"
	mkdir -p "$FOYER/.config/lexos"
	printf 'LEXOS_CRT_EFFECTS="%s"\n' "$V" > "$BANC/build-$V.conf"
	VU="$(HOME="$FOYER" XDG_CONFIG_HOME="$FOYER/.config" \
	      LEXOS_BUILD_CONF="$BANC/build-$V.conf" \
	      bash "$OUTIL" --json 2>/dev/null | sed -n 's/.*"voulu": "\([^"]*\)".*/\1/p')"
	[ "$VU" = "$V" ] \
		&& ok "build.conf=$V → l'outil répond « $VU » (mesuré, pas lu)" \
		|| non "build.conf=$V → l'outil répond « ${VU:-rien} » : la décision ne suit pas le réglage"
done

#  ET L'ÉTAT ÉCRIT PAR L'UTILISATEUR GAGNE SUR LE DÉFAUT DE LA CONSTRUCTION.
#  Sans ça, « lexos crt on » sur une ISO livrée en « off » ne tiendrait pas
#  d'une session à l'autre — et personne ne comprendrait pourquoi.
FOYER="$BANC/voulu-priorite"
mkdir -p "$FOYER/.config/lexos"
printf 'on\n' > "$FOYER/.config/lexos/crt"
printf 'LEXOS_CRT_EFFECTS="off"\n' > "$BANC/build-priorite.conf"
VU="$(HOME="$FOYER" XDG_CONFIG_HOME="$FOYER/.config" \
      LEXOS_BUILD_CONF="$BANC/build-priorite.conf" \
      bash "$OUTIL" --json 2>/dev/null | sed -n 's/.*"voulu": "\([^"]*\)".*/\1/p')"
[ "$VU" = "on" ] \
	&& ok "le choix de l'utilisateur passe DEVANT le défaut de la construction" \
	|| non "le défaut de la construction écrase le choix de l'utilisateur (« $VU »)"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
