#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — le coin actif ne doit RIEN ouvrir à l'ouverture de session
# =============================================================================
#  ALEX : « quand on arrive dans la page de LexOS au début, il nous montre
#  toujours la vue qui zoome où la souris. J'aimerais ne plus le voir. »
#
#  ═══ LE DÉFAUT, ET POURQUOI AUCUN ESSAI À LA MAIN NE LE TROUVAIT ═══
#  Le veilleur démarrait ARMÉ (« arme = True », dont le commentaire disait
#  pourtant « faux »). Si le pointeur se trouvait déjà à moins de 5 px des
#  deux bords au moment du démarrage de la session — ce qui arrive souvent
#  juste après la connexion, et c'est justement le coin du bouton
#  Applications — le premier sondage le voyait dedans, comptait les 140 ms
#  de séjour, et ouvrait la vue d'ensemble. Sans un geste.
#  Pour le reproduire à la main il faut poser la souris dans le coin AVANT
#  d'ouvrir la session, puis ne plus y toucher. Personne ne fait ça exprès.
#  Une machine, si.
#
#  ═══ ON NE LIT PAS LE CODE, ON LE FAIT TOURNER ═══
#  Un « grep arme = False » dirait que la ligne est là. Il ne dirait pas ce
#  que le veilleur FAIT. Ce banc lance donc le vrai programme contre un vrai
#  serveur X, déplace le vrai pointeur, et regarde si « lexos-apercu » est
#  appelé — par un faux lexos-apercu posé devant dans le PATH, qui note
#  chaque appel avec son heure.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VEILLEUR="$RACINE/config/includes.chroot/usr/lib/lexos/coin-actif"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; JAUNE=$'\033[33m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0; NON_MESURES=0; SAUTS=()
ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  %s—%s  %s\n' "$JAUNE" "$FIN" "$1"; NON_MESURES=$((NON_MESURES+1)); SAUTS+=("$1"); }
titre(){ printf '\n%s═══ %s ═══%s\n' "$GRAS" "$1" "$FIN"; }

BANC="$(mktemp -d)"
XVFB_PID=""; VEIL_PID=""
nettoyer() {
	#  PAR LES PID, JAMAIS PAR « pkill -f » : un motif frappe tout ce qui le
	#  cite, y compris le shell qui a lancé ce banc. Le dépôt s'est déjà fait
	#  prendre deux fois.
	[[ -n "$VEIL_PID" ]] && { kill "$VEIL_PID" 2>/dev/null; wait "$VEIL_PID" 2>/dev/null; }
	[[ -n "$XVFB_PID" ]] && { kill "$XVFB_PID" 2>/dev/null; wait "$XVFB_PID" 2>/dev/null; }
	rm -rf "$BANC"
	return 0
}
trap nettoyer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

titre "1. Le fichier et sa ligne de départ"
if [[ -r "$VEILLEUR" ]]; then ok "coin-actif lisible"; else
	non "coin-actif introuvable ($VEILLEUR)"; printf '\n'; exit 1; fi
python3 -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$VEILLEUR" 2>/dev/null \
	&& ok "syntaxe Python valide" \
	|| non "erreur de syntaxe Python"

titre "2. LE VEILLEUR TOURNE POUR DE VRAI — pointeur déjà dans le coin"
#  ═══ CE QUE CE BANC A BESOIN, ET CE QU'IL DIT QUAND ÇA MANQUE ═══
#  Trois outils, et un vrai serveur X. Quand il en manque un, on le DIT :
#  « non mesuré », jamais « réussi ». Un banc qui s'annonce vert sans avoir
#  rien éprouvé est pire que pas de banc.
MANQUE=""
command -v Xvfb    >/dev/null 2>&1 || MANQUE="$MANQUE Xvfb"
command -v python3 >/dev/null 2>&1 || MANQUE="$MANQUE python3"
#  ON CHARGE libX11 EXACTEMENT COMME LE VEILLEUR LE FAIT — « ctypes.CDLL ».
#  Chercher le fichier à des endroits connus, ou fouiller la sortie de
#  ldconfig, c'est deviner ce que fait l'éditeur de liens. Lui demander est
#  plus court ET mesure la vraie chose : si cette ligne passe, x11_ouvre()
#  passera aussi.
#  (Et ça évite le tuyau vers « grep -q » que ce dépôt interdit à juste
#  titre : sous pipefail, grep qui trouve ferme le tuyau, le producteur
#  prend un SIGPIPE, et une correspondance VRAIE ressort en échec.)
python3 -c "import ctypes; ctypes.CDLL('libX11.so.6')" 2>/dev/null \
	|| MANQUE="$MANQUE libX11"

if [[ -n "$MANQUE" ]]; then
	saut "absent :$MANQUE — le veilleur n'a PAS été mis en marche ici"
else
	#  --- Un écran à nous -------------------------------------------------
	#  « -displayfd » : Xvfb prend le premier numéro libre et l'écrit quand
	#  il ACCEPTE les connexions. Pas de numéro tiré au sort, pas de « sleep »
	#  à l'aveugle en espérant qu'il soit prêt.
	#  ═══ « -noreset », ET C'EST CE QUI M'A FAIT PERDRE DEUX FAUX VERTS ═══
	#  Un serveur X SE RÉINITIALISE quand son DERNIER client s'en va — c'est
	#  son comportement normal, pas un accident. Et une réinitialisation
	#  remet le pointeur au MILIEU de l'écran.
	#  L'outil qui place le pointeur est un petit programme : il se connecte,
	#  déplace, relit (0,0), et SORT. S'il était le seul client, le serveur se
	#  réinitialisait aussitôt après, et le veilleur — démarré juste derrière —
	#  voyait (640,400). MESURÉ, trace du veilleur à l'appui :
	#      pointeur placé en 0,0
	#      vu 640 400 arme True entre None      ← il ne voit pas le coin
	#  Le contrôle « rien ne s'ouvre » passait donc au VERT sans que le
	#  pointeur ait jamais été dans le coin : il ne mesurait rien du tout.
	#  Avec « -noreset », le serveur garde son état :
	#      vu 0 0 arme True entre None
	#      vu 0 0 arme True entre 447.75
	#      vu 0 0 arme False entre None         ← il a ouvert la vue
	Xvfb -noreset -displayfd 3 -screen 0 1280x800x24 3>"$BANC/num" >/dev/null 2>&1 &
	XVFB_PID=$!
	for _ in $(seq 1 100); do
		[[ -s "$BANC/num" ]] && break
		kill -0 "$XVFB_PID" 2>/dev/null || break
		sleep 0.1
	done
	if [[ ! -s "$BANC/num" ]]; then
		non "Xvfb n'a pas démarré — rien à mesurer"
	else
	AFF=":$(tr -dc 0-9 < "$BANC/num")"
	export DISPLAY="$AFF"

	#  --- Un faux « lexos-apercu » qui NOTE au lieu d'ouvrir ---------------
	mkdir -p "$BANC/bin"
	cat > "$BANC/bin/lexos-apercu" <<'FAUX'
#!/bin/sh
printf '%s %s\n' "$(date +%s.%N)" "$*" >> "$LEXOS_BANC_APPELS"
FAUX
	chmod +x "$BANC/bin/lexos-apercu"
	export LEXOS_BANC_APPELS="$BANC/appels.txt"
	: > "$LEXOS_BANC_APPELS"
	export PATH="$BANC/bin:$PATH"

	#  --- Le réglage est ALLUMÉ : c'est bien le cas d'Alex ------------------
	export XDG_CONFIG_HOME="$BANC/foyer/.config"
	mkdir -p "$XDG_CONFIG_HOME/lexos"
	printf 'on\n' > "$XDG_CONFIG_HOME/lexos/coin-actif"

	appels() { wc -l < "$LEXOS_BANC_APPELS" | tr -d ' '; }

	#  ═══ ON DÉPLACE LE POINTEUR AVEC XWarpPointer, PAS AVEC xdotool ═══
	#  MESURÉ, et ça m'a coûté un faux vert : « xdotool mousemove 0 0 » sur ce
	#  Xvfb NE DÉPLACE RIEN. Il rend 0, ne dit rien, et le pointeur reste où
	#  il était — vérifié juste après avec « xdotool getmouselocation » :
	#      mousemove 0 0        -> x:640 y:400
	#      mousemove --sync 0 0 -> x:640 y:400
	#  (XTEST est pourtant bien là, listé par xdpyinfo.)
	#  Le contrôle « rien ne s'ouvre » passait donc au vert alors que le
	#  pointeur n'avait JAMAIS été mis dans le coin : il ne mesurait rien.
	#  XWarpPointer, la fonction de X11 elle-même, déplace pour de vrai —
	#  mesuré : (640,400) → (0,0) → (700,500), à chaque fois.
	#  C'est aussi celle qu'emploie la même bibliothèque que le veilleur, donc
	#  une dépendance de moins.
	cat > "$BANC/bin/souris.py" <<'SOURIS'
import ctypes, os, sys
class D(ctypes.Structure): pass
lib = ctypes.CDLL("libX11.so.6")
lib.XOpenDisplay.restype = ctypes.POINTER(D); lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
lib.XDefaultRootWindow.restype = ctypes.c_ulong; lib.XDefaultRootWindow.argtypes = [ctypes.POINTER(D)]
lib.XWarpPointer.argtypes = [ctypes.POINTER(D), ctypes.c_ulong, ctypes.c_ulong,
                             ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint,
                             ctypes.c_int, ctypes.c_int]
lib.XQueryPointer.restype = ctypes.c_int
lib.XQueryPointer.argtypes = [ctypes.POINTER(D), ctypes.c_ulong,
    ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_uint)]
dpy = lib.XOpenDisplay(os.environ["DISPLAY"].encode())
if not dpy:
    print("pas-d-ecran"); raise SystemExit(1)
racine = lib.XDefaultRootWindow(dpy)
lib.XWarpPointer(dpy, 0, racine, 0, 0, 0, 0, int(sys.argv[1]), int(sys.argv[2]))
lib.XFlush(dpy)
#  ET ON RELIT. Un déplacement qu'on n'a pas vérifié, c'est le faux vert de
#  tout à l'heure : le banc croyait le pointeur dans le coin, il ne l'était pas.
rr = ctypes.c_ulong(); cr = ctypes.c_ulong(); rx = ctypes.c_int(); ry = ctypes.c_int()
wx = ctypes.c_int(); wy = ctypes.c_int(); m = ctypes.c_uint()
lib.XQueryPointer(dpy, racine, ctypes.byref(rr), ctypes.byref(cr), ctypes.byref(rx),
                  ctypes.byref(ry), ctypes.byref(wx), ctypes.byref(wy), ctypes.byref(m))
print("%d,%d" % (rx.value, ry.value))
SOURIS

	#  Place le pointeur, et EXIGE qu'il y soit vraiment.
	placer() {
		local vu
		vu="$(timeout 10 python3 "$BANC/bin/souris.py" "$1" "$2" 2>/dev/null)"
		if [[ "$vu" != "$1,$2" ]]; then
			non "le pointeur n'a pas pu être placé en ($1,$2) — il est en « ${vu:-rien} ». Rien n'est mesuré ici."
			return 1
		fi
		return 0
	}

	#  ═══ LA MISE EN SCÈNE DU DÉFAUT ═══
	#  Le pointeur est posé dans le coin AVANT que le veilleur démarre.
	#  C'est exactement l'ouverture de session qu'Alex décrit.
	if placer 0 0; then
	python3 "$VEILLEUR" >"$BANC/veilleur.err" 2>&1 &
	VEIL_PID=$!
	#  Largement plus que le séjour exigé (140 ms) et que le sondage (90 ms) :
	#  s'il devait s'ouvrir, il se serait ouvert dix fois.
	sleep 2
	N1="$(appels)"
	if ! kill -0 "$VEIL_PID" 2>/dev/null; then
		non "le veilleur s'est arrêté tout seul — $(head -3 "$BANC/veilleur.err" | tr '\n' ' ')"
	elif [[ "$N1" = "0" ]]; then
		ok "session ouverte avec le pointeur DÉJÀ dans le coin : rien ne s'ouvre (0 appel en 2 s)"
	else
		non "la vue s'est ouverte toute seule ($N1 appel(s)) — c'est le défaut qu'Alex décrit"
	fi

	#  ═══ ET IL S'ARME TOUT SEUL, AU PREMIER MOUVEMENT ═══
	#  Sans ça, le correctif échangerait un défaut contre un autre : un coin
	#  qui ne s'allume plus JAMAIS.
	placer 640 400 && sleep 0.4 && placer 0 0
	sleep 1.2
	N2="$(appels)"
	if (( N2 > N1 )); then
		ok "sorti du coin puis revenu : la vue s'ouvre (le coin s'est armé seul)"
	else
		non "le coin ne s'arme plus : sorti puis revenu, toujours $N2 appel(s) — la fonction serait morte"
	fi

	#  ═══ LE GARDE-FOU D'ORIGINE TIENT TOUJOURS ═══
	#  Il existe pour un cas précis, écrit en tête du fichier : refermer la
	#  vue en laissant le curseur dans le coin la rouvrirait EN BOUCLE. On ne
	#  l'échange pas contre le correctif d'aujourd'hui.
	sleep 1.5
	N3="$(appels)"
	if (( N3 == N2 )); then
		ok "le pointeur RESTE dans le coin : aucune deuxième ouverture (pas de boucle)"
	else
		non "$(( N3 - N2 )) ouverture(s) de plus sans être ressorti du coin — la vue se rouvrirait en boucle"
	fi

	#  ═══ ET ÉTEINDRE LE RÉGLAGE ARRÊTE LE VEILLEUR, SANS DÉCONNEXION ═══
	#  C'est ce qu'on dit à Alex pour qu'il n'attende pas une ISO.
	printf 'off\n' > "$XDG_CONFIG_HOME/lexos/coin-actif"
	for _ in $(seq 1 40); do
		kill -0 "$VEIL_PID" 2>/dev/null || break
		sleep 0.1
	done
	if kill -0 "$VEIL_PID" 2>/dev/null; then
		non "le veilleur tourne encore 4 s après extinction du réglage"
	else
		ok "éteint dans les Paramètres : le veilleur s'arrête seul (sans déconnexion)"
		VEIL_PID=""
	fi
	fi
	fi
fi

# -----------------------------------------------------------------------------
if (( NON_MESURES > 0 )); then
	printf "\n%sCe qui n'a PAS été mesuré (donc ni réussi ni échoué) :%s\n" "$GRAS" "$FIN"
	for e in "${SAUTS[@]}"; do printf '  %s·%s %s\n' "$JAUNE" "$FIN" "$e"; done
fi
NM="non mesuré"; (( NON_MESURES > 1 )) && NM="non mesurés"
printf '\n%s%d réussis, %d échoués, %d %s%s\n\n' \
	"$GRAS" "$REUSSIS" "$ECHOUES" "$NON_MESURES" "$NM" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
