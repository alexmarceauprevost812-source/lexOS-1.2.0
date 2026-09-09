#!/usr/bin/env bash
# =============================================================================
#  Éprouver LexOS Pro Terminal — le terminal officiel qui remplace l'ancien
# =============================================================================
#  ALEX : « c'est le new terminal officiel de LexOS Pro, pour le terminal
#  normal je veux que ce soit lui qui le remplace. »
#
#  ══ CE QUE CE BANC SURVEILLE, ET POURQUOI CHAQUE POINT A COÛTÉ QUELQUE CHOSE ══
#
#  1. LES COMMANDES S'EXÉCUTENT POUR DE VRAI. La page d'origine simulait un
#     système de fichiers ENTIER en mémoire (un projet fictif, un « lex
#     status » qui prétendait construire du code qui n'existe pas). Un
#     terminal qui remplace le vrai doit toucher le vrai disque — sinon
#     « ls » ment sur ce qui est vraiment là.
#
#  2. LE PONT EXÉCUTE N'IMPORTE QUOI, EXPRÈS — donc SEUL qui peut l'atteindre
#     compte. Trois verrous : 127.0.0.1 seulement, un jeton tiré au hasard
#     exigé dans un en-tête (jamais dans l'URL toute seule — une page
#     malveillante pourrait sinon poster en aveugle avant toute vérification
#     CORS), et l'Origine quand le navigateur en pose une.
#
#  3. CE QUI NE PEUT PAS MARCHER EST DIT, PAS CACHÉ. Cette fenêtre n'a pas de
#     grille de caractères ni de curseur qu'on déplace : les programmes
#     plein écran (vim, nano, htop, less, man…) sont reconnus AVANT d'être
#     lancés, et renvoient vers le Terminal classique au lieu d'un carnage
#     de codes d'échappement.
#
#  4. AUCUNE COMMANDE FICTIVE NE MASQUE PLUS UNE VRAIE COMMANDE. La page
#     d'origine réimplémentait ls/cd/cat/mkdir/rm/grep/find/wc/tree/whoami/
#     uname/env/ps/neofetch en JavaScript, contre l'arbre en mémoire. Si un
#     seul de ces noms redevenait un « built-in » local, taper « ls » ne
#     montrerait plus JAMAIS le vrai dossier — un bogue qui ne se verrait
#     qu'en cherchant un fichier qu'on sait pourtant présent.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/terminal-pro/web/index.html"
LANCEUR="$RACINE/config/includes.chroot/usr/bin/lexos-pro-terminal"
BUREAU="$RACINE/config/includes.chroot/usr/share/applications/lexos-pro-terminal.desktop"
HOOK="$RACINE/config/hooks/normal/0455-lexos-terminal-pro.hook.chroot"
DISPATCH="$RACINE/config/includes.chroot/usr/bin/lexos"
COMPLETION="$RACINE/config/includes.chroot/usr/share/bash-completion/completions/lexos"
DOCKITEM="$RACINE/config/includes.chroot/etc/skel/.config/plank/dock1/launchers/01-terminal.dockitem"
PANNEAU="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
RACCOURCIS="$RACINE/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$BACKEND" "$PAGE" "$LANCEUR" "$BUREAU" "$HOOK" "$DISPATCH" "$COMPLETION" \
         "$DOCKITEM" "$PANNEAU" "$RACCOURCIS"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. LE BACKEND : renvoyé au banc du pseudo-terminal"
# =============================================================================
#  CETTE SECTION A ÉTÉ VIDÉE, ET C'EST LE SIGNE QUE LE TRAVAIL EST FAIT.
#  Elle éprouvait executer() : un bash JETABLE par commande, l'entrée fermée
#  (stdin=DEVNULL), la sortie ramassée d'un bloc, un délai de 25 s, et
#  ansi_vers_html() qui RETIRAIT en silence tout ce qui n'était pas une
#  couleur — déplacements du curseur, effacements d'écran.
#
#  ALEX : « j'ai beau essayer le terminal LexOS Pro, je suis même pas capable
#  de lancer claude ». Ces quatre choses étaient la raison. Il n'y a plus de
#  bash jetable ni de journal de lignes : un vrai pseudo-terminal, un shell
#  par volet, et xterm.js qui tient la grille de caractères.
#
#  Ce que cette section éprouvait est donc devenu SANS OBJET — et ce qui l'a
#  remplacé est éprouvé ailleurs, plus sévèrement :
#    · tests/test_lexos_terminal_pty.sh          le pty et les quatre routes
#    · tests/test_lexos_terminal_navigateur.sh   l'affichage, dans Chromium
#
#  On garde ici UN contrôle : que l'ancien chemin ne revienne pas par la
#  petite porte. Un « executer() » qui reparaîtrait à côté du pty rendrait
#  le comportement du terminal dépendant de la commande tapée.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent"
else
	#  ═══ ON LIT DU CODE, PAS DE LA PROSE ═══
	#  « sed 's/#.*//' » ne suffit pas ici : l'en-tête du fichier est une
	#  DOCSTRING, pas un commentaire « # », et elle raconte exprès ce qui a
	#  disparu — « LISTE_TUI », « capture_output », le délai de 25 s. Un
	#  grep sur le texte brut serait donc rouge à jamais, et la tentation
	#  serait d'effacer l'explication pour faire taire le banc : on perdrait
	#  la seule trace écrite de pourquoi claude ne démarrait pas.
	#
	#  On passe donc par le TOKENIZER de Python : il ne rend que les noms,
	#  les opérateurs et les nombres — jamais le contenu d'une chaîne ni
	#  d'un commentaire. Ce qui reste est du code, et rien d'autre.
	python3 - "$BACKEND" > "$BANC/pont-code.txt" <<'PY'
import io, sys, token, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
mots = []
for t in tokenize.generate_tokens(io.StringIO(src).readline):
    if t.type in (token.NAME, token.OP, token.NUMBER):
        mots.append(t.string)
sys.stdout.write(" ".join(mots))
PY
	CODE_PONT="$(cat "$BANC/pont-code.txt")"
	MORTS=""
	for MOTIF in "def executer" "def ansi_vers_html" "LISTE_TUI" "DELAI_MAX" "capture_output" "DEVNULL"; do
		grep -qF "$MOTIF" <<< "$CODE_PONT" && MORTS="$MORTS $MOTIF"
	done
	if [ -z "$MORTS" ]; then
		ok "l'ancien chemin (bash jetable, entrée fermée, délai, journal de lignes) a bien disparu"
	else
		non "l'ancien chemin est de retour dans le pont :$MORTS"
	fi
	#  ET LE NOUVEAU EST BIEN LÀ : sans ce contrôle, un fichier VIDE
	#  passerait le contrôle ci-dessus avec les honneurs.
	#  Le tokenizer retire aussi les CHAÎNES : « /api/flux » n'y est plus.
	#  On le cherche donc dans le fichier, mais sur la ligne de code qui
	#  l'utilise — pas dans l'en-tête qui le décrit.
	if grep -qF "pty . fork" <<< "$CODE_PONT" && grep -qE '^\s*if chemin == "/api/flux"' "$BACKEND"; then
		ok "le pont repose bien sur un pseudo-terminal et sert le flux (/api/flux)"
	else
		non "le pont n'a ni pty.fork ni /api/flux — le terminal ne peut rien afficher"
	fi
fi

# =============================================================================
titre "2. SÉCURITÉ — ce qui reste vrai après le pty"
# =============================================================================
#  Le modèle n'a pas bougé (127.0.0.1, jeton, Origine) mais les routes, si :
#  /api/exec a disparu ; /api/flux, /api/saisie, /api/taille et /api/fermer
#  l'ont remplacée. LA MATRICE COMPLÈTE — quatre routes contre trois refus —
#  est dans tests/test_lexos_terminal_pty.sh, et c'est elle qui a trouvé que
#  /api/flux ne vérifiait NI le jeton NI l'origine : la route la plus
#  sensible des quatre, celle qui ouvre le shell. Ici on garde le contrôle
#  qui ne dépend d'aucune route : sur quoi le serveur écoute.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : l'écoute du pont n'a PAS été éprouvée"
else
	SORTIE_S="$(LEXOS_TERMINAL_PRO_WEB="$BANC" python3 - "$BACKEND" <<'PY' 2>/dev/null | grep -E '^(OK|NON|FIN)\|' || true
import sys, importlib.util
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

def dit(bon, m): print(("OK|" if bon else "NON|") + m)

try:
    serveur, port, jeton = tp.demarrer_serveur()
    #  Un terminal exécute n'importe quoi, exprès : SEUL compte qui peut
    #  l'atteindre. Écouter 0.0.0.0 offrirait un shell au réseau entier.
    dit(serveur.socket.getsockname()[0] == "127.0.0.1", "le serveur n'écoute QUE 127.0.0.1")
    #  Le jeton est tiré à CHAQUE lancement : deux fenêtres ouvertes en même
    #  temps ne doivent jamais partager le même.
    serveur2, _, jeton2 = tp.demarrer_serveur()
    dit(jeton != jeton2 and len(jeton) >= 32, "le jeton est neuf à chaque lancement, et assez long")
    serveur.shutdown(); serveur2.shutdown()
except Exception as e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(e).__name__, e))
print("FIN|")
PY
)"
	if [ -z "$SORTIE_S" ]; then
		non "le pont n'a rien rendu sur son écoute"
	elif ! grep -q '^FIN|' <<< "$SORTIE_S"; then
		non "le banc de sécurité s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_S
EOF
	fi
fi

# =============================================================================
titre "3. LE FRONT-END — la page ne réimplémente toujours RIEN"
# =============================================================================
#  ══ CE QUE CETTE SECTION SURVEILLE DEPUIS LE DÉBUT ══
#  La page d'origine simulait un système de fichiers ENTIER en mémoire, et
#  réimplémentait ls, cd, cat, mkdir, rm, grep, find, wc, tree, whoami,
#  uname, env, ps, neofetch en JavaScript contre cet arbre fictif. Si un seul
#  de ces noms redevenait un « built-in » de la page, taper « ls » ne
#  montrerait plus JAMAIS le vrai dossier — un bogue invisible tant qu'on ne
#  cherche pas un fichier qu'on sait pourtant présent.
#
#  ══ CE QUI A CHANGÉ, ET POURQUOI LE CONTRÔLE DEVIENT PLUS SIMPLE ══
#  La page n'a plus de ligne de commande du tout : elle ne LIT plus ce qu'on
#  tape, elle le transmet au pty octet par octet (xterm.onData → /api/saisie).
#  Il n'y a donc plus rien à intercepter, ni aucun tableau de commandes où
#  une commande fictive pourrait se cacher. On vérifie exactement ça.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : la page n'a PAS été relue"
else
	#  ON LIT LE CODE, PAS LES COMMENTAIRES. Ce fichier PARLE de « ls », de
	#  « COMMANDES » et de l'ancien journal pour expliquer ce qui a disparu ;
	#  un grep naïf serait rouge à jamais — ou pire, on l'émousserait pour le
	#  faire taire. Piège déjà payé deux fois dans ce dépôt.
	python3 - "$PAGE" > "$BANC/page-code.js" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<script>(.*)</script>", s, re.S)
js = m.group(1) if m else ""
js = re.sub(r"/\*.*?\*/", "", js, flags=re.S)
js = "\n".join(l for l in js.splitlines() if not l.lstrip().startswith("//"))
sys.stdout.write(js)
PY
	CODE="$(cat "$BANC/page-code.js")"
	if [ -z "$CODE" ]; then
		non "impossible d'extraire le code de la page"
	else
		if grep -qE "\bCOMMANDES\b" <<< "$CODE"; then
			non "un tableau de commandes de la page est revenu : il masquerait de vrais programmes"
		else
			ok "aucun tableau de commandes dans la page — rien ne peut masquer un vrai programme"
		fi

		#  Le chemin de la frappe, en entier. Si « onData » disparaissait,
		#  plus rien ne partirait au shell : une fenêtre belle et morte.
		if grep -q "onData" <<< "$CODE" && grep -q "/api/saisie" <<< "$CODE"; then
			ok "ce qu'on tape va de xterm.js au pty sans être relu par la page (onData → /api/saisie)"
		else
			non "le chemin de la frappe est cassé : ni onData ni /api/saisie"
		fi

		#  EventSource ne sait pas poser d'en-tête personnalisé : s'en servir
		#  pour le flux ferait tomber le jeton, donc 403, donc un terminal
		#  muet — et la panne serait à un endroit (la sécurité) très loin du
		#  symptôme (rien ne s'affiche). La consigne l'interdit nommément.
		if grep -q "EventSource" <<< "$CODE"; then
			non "le flux passe par EventSource : il ne peut pas porter le jeton (403 garanti)"
		else
			ok "le flux est lu par fetch + getReader, pas par EventSource"
		fi

		if grep -q "X-Lexos-Jeton" <<< "$CODE"; then
			ok "la page envoie le jeton dans un en-tête sur ses appels au pont"
		else
			non "la page n'envoie plus le jeton : le pont refusera tout"
		fi
	fi

	#  ═══ RIEN NE VIENT D'INTERNET ═══
	#  Mesuré dans un vrai navigateur : les polices allaient chez Google à
	#  CHAQUE ouverture et échouaient (ERR_CONNECTION_RESET). Le terminal
	#  principal du système doit s'ouvrir sur un portable sans réseau.
	if grep -qE "https?://(cdn|unpkg|jsdelivr|fonts\.google|fonts\.gstatic)" "$PAGE"; then
		non "la page va chercher un fichier sur Internet : elle ne marchera pas hors ligne"
	else
		ok "aucune ressource distante : tout vient de l'ISO (vendor/ et les polices Debian)"
	fi
fi

# =============================================================================
titre "4. TOUT EST BRANCHÉ — dispatcheur, aide, complétion, dock, panneau"
# =============================================================================
#  ═══ IL N'Y A PLUS DE COMMANDE DE DÉMARRAGE, ET C'EST LE CORRECTIF ═══
#  La page demandait « printf "%s\\n" "$HOME"; whoami » au pont avant d'ouvrir
#  la première fenêtre, pour dessiner une invite crédible. Sans le « \\n », les
#  deux sorties se collaient (« /rootroot ») : nom d'utilisateur ET dossier
#  personnel faux, en silence — trouvé en chargeant la vraie page dans un vrai
#  navigateur contre un vrai pont.
#
#  La vraie correction n'est pas le « \\n » : c'est qu'il n'y a plus DEUX
#  sources de vérité. Le shell écrit sa propre invite, avec son vrai nom
#  d'utilisateur et son vrai dossier. Ce contrôle veille donc à ce que la
#  page ne se remette pas à deviner ce que bash sait déjà.
if grep -qF 'whoami' "$PAGE"; then
	non "la page redemande le nom d'utilisateur au pont : c'est au shell de l'écrire"
else
	ok "la page ne devine plus ni le dossier personnel ni l'utilisateur — bash les écrit"
fi
bash -n "$LANCEUR" 2>/dev/null && ok "lexos-pro-terminal : syntaxe bash valide" \
	|| non "lexos-pro-terminal : erreur de syntaxe"
#  La CHAÎNE « --classique » apparaît aussi dans l'aide : on vérifie la
#  vraie BRANCHE du case, pas seulement sa mention en commentaire ou en aide.
grep -qE -- '--classique\|classique\)[[:space:]]*classique[[:space:]]*;;' "$LANCEUR" \
	&& ok "le Terminal classique reste atteignable (branche --classique du case)" \
	|| non "aucun repli vers un vrai terminal"
grep -q 'QtWebEngineWidgets' "$LANCEUR" \
	&& ok "PySide6 WebEngine est vérifié avant de lancer la fenêtre" \
	|| non "aucune vérification de PySide6 avant le lancement"

grep -qE '(^|[^a-z-])terminal-pro[^a-z-].*exec lexos-pro-terminal' "$DISPATCH" \
	&& ok "« lexos terminal-pro » mène à l'outil" \
	|| non "aucune branche « terminal-pro » dans le dispatcheur"
sed 's/${[A-Z]*}//g' "$DISPATCH" | awk '/^cmd_help\(\)/,0' > "$BANC/aide-nue"
grep -qE '(^|[[:space:]])terminal-pro([[:space:]]|$)' "$BANC/aide-nue" \
	&& ok "…et l'aide en parle" \
	|| non "« terminal-pro » n'apparaît pas dans l'aide"
grep -q 'terminal-pro' "$COMPLETION" \
	&& ok "…et la touche Tab la propose" \
	|| non "« terminal-pro » manque à la complétion"

EXEC_PROG="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$BUREAU" | head -1)"
[ "$EXEC_PROG" = "lexos-pro-terminal" ] \
	&& ok "le .desktop appelle bien lexos-pro-terminal" \
	|| non "le .desktop appelle « $EXEC_PROG », pas lexos-pro-terminal"
grep -q '^Icon=lexos-pro-terminal' "$BUREAU" \
	&& ok "…avec sa propre icône" \
	|| non "aucune icône déclarée pour le .desktop"
grep -q 'Terminal classique' "$BUREAU" \
	&& ok "…et une action secondaire mène au Terminal classique" \
	|| non "aucune action « Terminal classique » sur le .desktop"

grep -q 'lexos-pro-terminal.desktop' "$DOCKITEM" \
	&& ok "le dock ouvre maintenant LexOS Pro Terminal" \
	|| non "le dock pointe encore ailleurs"
grep -q 'lexos-pro-terminal.desktop' "$PANNEAU" \
	&& ok "…et les favoris du panneau aussi" \
	|| non "les favoris du panneau n'ont pas changé"
grep -q 'value="lexos-pro-terminal"' "$RACCOURCIS" \
	&& ok "Super+Retour et Super+T ouvrent LexOS Pro Terminal" \
	|| non "les raccourcis clavier n'ont pas changé"

#  ═══ LE TERMINAL CLASSIQUE N'A PAS DISPARU ═══
#  Rien de ce qui vient d'être câblé ne doit avoir RETIRÉ xfce4-terminal :
#  Claude Code, OpenCode, les scripts qui demandent une confirmation tapée,
#  l'enregistrement vidéo (--hold) en ont toujours besoin.
#  On vise la ligne « exec » elle-même, pas n'importe quelle mention du nom
#  (un commentaire suffirait sinon à garder ce contrôle vert par accident).
for USAGE in 'lexos-claude-terminal' 'lexos-opencode'; do
	F2="$RACINE/config/includes.chroot/usr/bin/$USAGE"
	if [ -r "$F2" ] && grep -qE 'exec (x-terminal-emulator|xfce4-terminal)' "$F2"; then
		ok "$USAGE garde son vrai terminal (pty complet)"
	else
		non "$USAGE ne référence plus aucun terminal réel"
	fi
done

grep -q 'ICONES_HICOLOR' "$HOOK" \
	&& ok "le hook 0455 rend l'icône aux huit tailles, comme les autres" \
	|| non "le hook 0455 ne suit pas le patron des autres icônes LexOS"
grep -q 'VDIR=.*scalable' "$HOOK" && grep -q 'rm -f "\$VDIR' "$HOOK" \
	&& ok "…et retire toute version scalable (le dock ne changerait pas de dessin au survol)" \
	|| non "une version scalable pourrait rester et changer de dessin au survol du dock"

# =============================================================================
titre "LE TERMINAL PRINCIPAL DU SYSTÈME"
# =============================================================================
#  ALEX : « je voudrais juste que le terminal principal du système soit le
#  terminal LexOS Pro ».
#
#  Trois branchements, et le troisième est un piège documenté : terminal-pro.py
#  NE TRAITE AUCUN ARGUMENT. Brancher le lanceur directement sur l'alternative
#  « x-terminal-emulator » ferait ouvrir une fenêtre VIDE, sans rien lancer, à
#  chaque fois qu'un programme du système fait « x-terminal-emulator -e
#  commande » — une panne muette, la pire espèce.
PONT="$RACINE/config/includes.chroot/usr/bin/lexos-pro-terminal.wrapper"
AIDE="$RACINE/config/includes.chroot/usr/share/xfce4/helpers/lexos-pro-terminal.desktop"

if [ -r "$AIDE" ]; then
	ok "l'assistant XFCE existe (sans lui, « Applications par défaut » ne le propose pas)"
	grep -q '^X-XFCE-Category=TerminalEmulator' "$AIDE" \
		&& ok "…et il se déclare bien comme émulateur de terminal" \
		|| non "l'assistant ne porte pas X-XFCE-Category=TerminalEmulator"
	grep -q '^X-XFCE-Binaries=lexos-pro-terminal;' "$AIDE" \
		&& ok "…et il nomme le bon programme" \
		|| non "l'assistant ne nomme pas lexos-pro-terminal"
else
	non "aucun assistant XFCE : la page « Applications par défaut » ne verra pas LexOS Pro Terminal"
fi

if [ -x "$PONT" ]; then
	ok "le pont x-terminal-emulator existe et est exécutable"
	#  ═══ ET IL TRANSMET POUR DE VRAI ═══
	#  On le fait tourner avec un faux LexOS Pro Terminal qui répète ses
	#  arguments, et on regarde ce qui arrive. Lire le fichier ne suffirait
	#  pas : c'est le comportement qui compte.
	#
	#  CE CONTRÔLE A CHANGÉ DE SENS, ET VOICI POURQUOI. Le pont renvoyait
	#  vers le Terminal classique TOUT ce qui demandait d'exécuter une
	#  commande (« -e », « -x », « --working-directory »…), parce que
	#  terminal-pro.py ne lisait aucun argument : brancher l'alternative
	#  Debian dessus aurait ouvert une fenêtre VIDE, en silence, chaque fois
	#  qu'un programme du système demande un terminal pour lancer quelque
	#  chose. LexOS Pro Terminal lit maintenant ses arguments ET a un vrai
	#  pty : le détournement n'a plus lieu d'être, et le laisser en place
	#  voudrait dire que la moitié du système continue d'ouvrir l'ancien
	#  terminal sans que personne ne s'en aperçoive.
	PB="$(mktemp -d)"
	printf '#!/bin/sh\necho CLASSIQUE\n' > "$PB/xfce4-terminal.wrapper"
	printf '#!/bin/sh\necho "PRO:$*"\n'  > "$PB/lexos-pro-terminal"
	chmod +x "$PB"/*
	sed -e "s|/usr/bin/xfce4-terminal.wrapper|$PB/xfce4-terminal.wrapper|" \
	    -e "s|/usr/bin/lexos-pro-terminal|$PB/lexos-pro-terminal|" \
	    "$PONT" > "$PB/pont"
	chmod +x "$PB/pont"
	MAUVAIS=0
	for A in "" "--title=Truc" "-e ls" "-x htop" "--command=top" \
	         "--hold -e ls" "--working-directory=/tmp"; do
		# shellcheck disable=SC2086
		R="$(bash "$PB/pont" $A 2>/dev/null)"
		case "$R" in
			PRO:*) : ;;
			*) non "« $A » n'arrive pas à LexOS Pro Terminal (reçu : $R)"; MAUVAIS=1 ;;
		esac
	done
	[ "$MAUVAIS" = 0 ] && ok "toutes les formes d'appel arrivent à LexOS Pro Terminal, sans détour"
	#  ET LES ARGUMENTS ARRIVENT ENTIERS. Un pont qui les avalerait ouvrirait
	#  un terminal sans rien lancer : la fenêtre vide, autrement.
	R="$(bash "$PB/pont" --working-directory=/tmp -e "ls -la" 2>/dev/null)"
	if [ "$R" = "PRO:--working-directory=/tmp -e ls -la" ]; then
		ok "les arguments traversent le pont intacts (dossier de départ et commande)"
	else
		non "le pont abîme les arguments (reçu : $R)"
	fi

	#  ═══ ET LE PONT SAIT VRAIMENT LES LIRE, DE L'AUTRE CÔTÉ ═══
	#  Le pont peut bien tout transmettre : si terminal-pro.py ne comprend
	#  pas ces options, on retombe sur la fenêtre vide et muette qu'on
	#  voulait justement éviter. On interroge donc lire_arguments() sur les
	#  DEUX conventions — celle de xfce4-terminal (« -e "ls -la" », un seul
	#  argument) et celle de Debian (« -e ls -la », déjà découpé).
	if command -v python3 >/dev/null 2>&1; then
		SORTIE_A="$(python3 - "$BACKEND" <<'PY' 2>/dev/null | grep -E '^(OK|NON)\|' || true
import sys, importlib.util
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
def dit(b, m): print(("OK|" if b else "NON|") + m)
dit(tp.lire_arguments(["--working-directory=/tmp"]) == ("/tmp", None, False),
    "--working-directory= : « Ouvrir un terminal ici » de Thunar arrive au bon dossier")
dit(tp.lire_arguments(["--working-directory", "/etc"]) == ("/etc", None, False),
    "--working-directory séparé du dossier : compris aussi")
dit(tp.lire_arguments(["-e", "ls -la"]) == (None, "ls -la", False),
    "-e « ls -la » (xfce4-terminal : UN argument) : la ligne entière")
dit(tp.lire_arguments(["-e", "ls", "-la", "/tmp"]) == (None, "ls -la /tmp", False),
    "-e ls -la /tmp (Debian : déjà découpé) : recollé sans perdre d'argument")
dit(tp.lire_arguments(["-e", "echo", "deux mots"]) == (None, "echo 'deux mots'", False),
    "un argument qui contient une espace est protégé au recollage")
dit(tp.lire_arguments(["--hold", "-x", "lexos", "capture", "video"]) == (None, "lexos capture video", True),
    "--hold : le volet reste ouvert après la commande (lanceur 11 du panneau)")
dit(tp.lire_arguments([]) == (None, None, False),
    "sans argument : un shell ordinaire, rien de plus")
PY
)"
		if [ -z "$SORTIE_A" ]; then
			non "lire_arguments() n'existe pas : les options seraient ignorées en silence"
		else
			while IFS='|' read -r V M; do
				case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
			done <<EOF
$SORTIE_A
EOF
		fi
	fi
	rm -rf "$PB"
else
	non "aucun pont x-terminal-emulator : brancher le lanceur nu ouvrirait des fenêtres vides"
fi

#  Le hook doit poser les deux, et ne PAS toucher au lanceur 11 du panneau,
#  qui a besoin d'un vrai pty et de « --hold ».
grep -q 'update-alternatives --install /usr/bin/x-terminal-emulator' "$HOOK" \
	&& ok "le hook 0455 branche l'alternative Debian" \
	|| non "le hook 0455 ne branche pas x-terminal-emulator"
grep -q 'TerminalEmulator=lexos-pro-terminal' "$HOOK" \
	&& ok "…et le helpers.rc du squelette dit le même choix" \
	|| non "le squelette ne nomme pas LexOS Pro Terminal comme émulateur"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
