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
titre "1. LE BACKEND : exécution réelle, cwd suivi, stdin fermé, délai"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le backend n'a PAS été éprouvé"
else
	cat > "$BANC/b1.py" <<'PY'
import sys, time, importlib.util
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

def dit(bon, m): print(("OK|" if bon else "NON|") + m)

try:
    # --- exécution réelle ---
    html, cwd = tp.executer("printf 'reel:%s' 42", "/tmp")
    dit("reel:42" in html, "une commande imprime pour de vrai, pas une réponse inventée")

    # --- cd suivi, y compris chaîné ---
    html, cwd = tp.executer("cd / && pwd", "/tmp")
    dit(cwd == "/", "« cd / && pwd » change bien le dossier suivi (%s)" % cwd)
    html, cwd = tp.executer("pwd", "/etc")
    dit(cwd == "/etc" and "/etc" in html, "sans cd, le dossier ne bouge pas")

    #  ═══ LA COMMANDE DE DÉMARRAGE DE LA PAGE, REJOUÉE POUR DE VRAI ═══
    #  Repéré en chargeant la vraie page dans un vrai navigateur, contre un
    #  vrai pont — pas dans un bac à sable au fetch simulé : « printf "%s"
    #  "$HOME" » sans « \\n » collait sa sortie à celle de « whoami » qui
    #  suit (« /rootroot » au lieu de deux lignes). Le nom d'utilisateur ET
    #  le dossier personnel affichés étaient FAUX tous les deux — silencieux,
    #  rien ne plantait.
    html, cwd = tp.executer('printf "%s\\n" "$HOME"; whoami', "/")
    lignes = html.strip().split("\n")
    #  Le bogue donnait UNE seule ligne collée (« /rootroot ») : la longueur
    #  suffit à le prouver — deux lignes non vides, pas une de plus.
    dit(len(lignes) == 2 and all(lignes),
        "la commande de démarrage rend bien DEUX lignes distinctes (%r)" % (lignes,))

    #  ═══ STDIN FERMÉ, ÉPROUVÉ POUR DE VRAI ═══
    #  Ce script est lui-même nourri par un « yes | » (voir plus bas) : SA
    #  PROPRE entrée standard a donc toujours une ligne prête. Si executer()
    #  n'imposait pas stdin=DEVNULL, la commande hériterait de cette même
    #  entrée et « read » lirait « y » — le contenu le prouve, pas la
    #  vitesse (une minuterie peut mentir si l'environnement du banc a,
    #  par hasard, sa propre entrée déjà tarie).
    t0 = time.time()
    html, cwd = tp.executer("read -r x; echo apres:$x fin", "/tmp")
    dt = time.time() - t0
    dit(dt < 3 and "apres: fin" in html,
        "une commande qui lit l'entrée reçoit EOF tout de suite (stdin fermé), pas la vraie entrée du banc")

    # --- le délai maximal coupe ---
    tp.DELAI_MAX = 1.0
    t0 = time.time()
    html, cwd = tp.executer("sleep 5; echo trop-tard", "/tmp")
    dt = time.time() - t0
    dit(dt < 3 and "trop-tard" not in html, "une commande qui dort trop longtemps est coupée (%.1fs)" % dt)

    # --- programmes plein écran reconnus AVANT exécution ---
    for prog in ("vim", "nano", "htop", "less", "man"):
        html, cwd = tp.executer(prog + " x", "/tmp")
        dit("Terminal classique" in html, "« %s » est reconnu et renvoie au Terminal classique" % prog)
    html, cwd = tp.executer("sudo vim /etc/passwd", "/tmp")
    dit("Terminal classique" in html, "« sudo vim » est reconnu à travers sudo")
    html, cwd = tp.executer("ls", "/tmp")
    dit("Terminal classique" not in html, "« ls » n'est PAS pris pour un programme plein écran")

    # --- ANSI -> HTML : couleurs rendues, curseur retiré, progression compressée ---
    html = tp.ansi_vers_html("\x1b[31mrouge\x1b[0m <script>")
    dit('class="r"' in html and "&lt;script&gt;" in html,
        "une couleur ANSI devient une classe CSS, et le contenu reste échappé")
    html = tp.ansi_vers_html("\x1b[2J\x1b[Hbonjour")
    dit(html == "bonjour", "le déplacement du curseur et l'effacement d'écran sont retirés, jamais montrés")
    html = tp.ansi_vers_html("un\rdeux\rtrois")
    dit(html == "trois", "une ligne réécrite au \\r ne garde que son dernier état")
    #  « \\x1b[?25l » (cacher le curseur) a un paramètre PRIVÉ (le « ? ») —
    #  quasi tous les programmes interactifs l'émettent. Une regex qui ne
    #  reconnaît que « ESC[ chiffres m » le laisse passer tel quel, en clair.
    html = tp.ansi_vers_html("\x1b[?25lcache\x1b[?25h")
    dit(html == "cache", "« \\x1b[?25l » (curseur caché, très courant) est retiré, pas montré en clair")
    #  Un échappement HORS CSI (pas de « [ » après ESC) : sauvegarde/rappel
    #  du curseur (DECSC/DECRC) et reset complet (RIS). Chemin de code
    #  différent des séquences CSI ci-dessus — à éprouver séparément.
    html = tp.ansi_vers_html("\x1b7sauve\x1b8restaure")
    dit(html == "sauverestaure", "« \\x1b7 »/« \\x1b8 » (sauver/rappeler le curseur, hors CSI) sont retirés")
    html = tp.ansi_vers_html("\x1bcreset")
    dit(html == "reset", "« \\x1bc » (reset complet du terminal, hors CSI) est retiré")
    #  GRAS ET COULEUR ENSEMBLE (« \\x1b[1;32m », git/grep --color/npm le
    #  font tout le temps) : un span par code, jamais refermé, laissait la
    #  moitié de la ligne suivante en gras.
    html = tp.ansi_vers_html("\x1b[1;32mvert gras\x1b[0m normal")
    dit(html == '<span class="gras g">vert gras</span> normal',
        "gras ET couleur dans le même code tiennent dans UN span correctement refermé")

except Exception as e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(e).__name__, e))
print("FIN|")
PY
	#  « yes | » donne à CE SCRIPT une entrée toujours prête — c'est ce qui
	#  rend le contrôle « stdin fermé » ci-dessus capable de mentir si
	#  DEVNULL disparaissait, au lieu de rester vrai par accident de
	#  l'environnement du banc.
	SORTIE_B="$(yes 2>/dev/null | python3 "$BANC/b1.py" "$BACKEND" 2>/dev/null | grep -E '^(OK|NON|FIN)\|' || true)"
	if [ -z "$SORTIE_B" ]; then
		non "le backend n'a rien rendu"
	elif ! grep -q '^FIN|' <<< "$SORTIE_B"; then
		non "le banc du backend s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_B
EOF
	fi
fi

# =============================================================================
titre "2. SÉCURITÉ — le jeton et l'Origine, pas seulement dans le code lu"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : la sécurité du pont n'a PAS été éprouvée pour de vrai"
else
	SORTIE_S="$(LEXOS_TERMINAL_PRO_WEB="$BANC" python3 - "$BACKEND" <<'PY' 2>/dev/null | grep -E '^(OK|NON|FIN)\|' || true
import sys, json, importlib.util, urllib.request, urllib.error
spec = importlib.util.spec_from_file_location("tp", sys.argv[1])
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

def dit(bon, m): print(("OK|" if bon else "NON|") + m)

try:
    serveur, port, jeton = tp.demarrer_serveur()
    base = "http://127.0.0.1:%d" % port

    def poste(cmd, entetes=None, origine=None):
        corps = json.dumps({"cmd": cmd, "cwd": "/tmp"}).encode()
        req = urllib.request.Request(base + "/api/exec", data=corps, method="POST")
        req.add_header("Content-Type", "application/json")
        for k, v in (entetes or {}).items():
            req.add_header(k, v)
        if origine is not None:
            req.add_header("Origin", origine)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    dit(serveur.socket.getsockname()[0] == "127.0.0.1", "le serveur n'écoute QUE 127.0.0.1")

    code, rep = poste("echo x")
    dit(code == 403 and rep["ok"] is False, "aucun jeton -> refusé (403), rien n'est exécuté")

    code, rep = poste("echo x", entetes={"X-Lexos-Jeton": "un-faux-jeton"})
    dit(code == 403, "un mauvais jeton -> refusé (403)")

    code, rep = poste("echo x", entetes={"X-Lexos-Jeton": jeton}, origine="http://site-hostile.example")
    dit(code == 403, "le bon jeton mais une Origine étrangère -> refusé (403)")

    code, rep = poste("echo cava", entetes={"X-Lexos-Jeton": jeton}, origine=base)
    dit(code == 200 and rep["ok"] is True and "cava" in rep["sortie"], "le bon jeton et la bonne Origine -> exécuté")

    code, rep = poste("echo cava", entetes={"X-Lexos-Jeton": jeton})
    dit(code == 200 and rep["ok"] is True, "le bon jeton sans aucune Origine -> exécuté (tous les navigateurs n'en posent pas)")

    serveur.shutdown()
except Exception as e:
    print("NON|le banc s'est arrêté : %s: %s" % (type(e).__name__, e))
print("FIN|")
PY
)"
	if [ -z "$SORTIE_S" ]; then
		non "le banc de sécurité n'a rien rendu"
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
titre "3. LE FRONT-END — aucune commande fictive ne masque plus une vraie"
# =============================================================================
if ! command -v node >/dev/null 2>&1; then
	saute "node absent : le front-end n'a PAS été éprouvé"
else
	python3 - "$PAGE" <<'PY' > "$BANC/tp.js"
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<script>(.*)</script>', s, re.S)
sys.stdout.write(m.group(1) if m else "")
PY
	SORTIE_J="$(node - "$BANC/tp.js" <<'NODEJS' 2>&1 | grep -E '^(OK|NON|FIN)\|' || true
const vm = require("vm");
const fs = require("fs");
const source = fs.readFileSync(process.argv[2] || process.argv[1], "utf8");

function el(){
  let _html = "";
  return { style:{}, classList:{add(){},remove(){},toggle(){},contains(){return false}},
    addEventListener(){}, appendChild(){}, querySelector:()=>el(), querySelectorAll:()=>[],
    setAttribute(){}, getAttribute(){return null}, dataset:{}, children:[],
    getBoundingClientRect:()=>({width:800,height:600,left:0,top:0}),
    focus(){}, remove(){}, closest:()=>null,
    set innerHTML(v){ _html = v; }, get innerHTML(){ return _html; },
    get textContent(){ return _html.replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&amp;/g,"&"); } };
}
const appels = [];
const bac = vm.createContext({
  __BANC_NE_PAS_DEMARRER__: true,
  document:{ getElementById:()=>el(), createElement:()=>el(), querySelector:()=>el(),
             querySelectorAll:()=>[], body:el(), fonts:{ready:Promise.resolve()}, documentElement:{style:{}} },
  window:{}, location:{search:"?port=54321&jeton=LE-JETON", hash:""},
  localStorage:{getItem(){return null}, setItem(){}},
  fetch: (url, opts) => { appels.push({url, opts}); return Promise.resolve({json: async () => ({ok:true, sortie:"x\n", cwd:"/tmp"})}); },
  URLSearchParams, requestAnimationFrame:()=>0, setTimeout, clearTimeout, setInterval, console,
  getComputedStyle:()=>({font:"12px monospace"}),
});
bac.globalThis = bac;
const dit = (bon, m) => console.log((bon?"OK|":"NON|") + m);
try {
  vm.runInContext(source, bac, {filename:"terminal-pro.js"});
  const B = bac.__banc;
  dit(!!B, "le crochet de banc existe");

  const chrome = ["split","tab","zoom","exit","clear","aide","help","history","backend","about"];
  const manquantes = chrome.filter(n => !B.COMMANDES[n]);
  dit(manquantes.length === 0, "les commandes de fenêtre (chrome de l'appli) sont toutes là");

  //  LE CŒUR DE CE BANC : si un seul de ces noms redevient un built-in
  //  local, il masquerait le VRAI programme du même nom pour toujours.
  const fictives = ["ls","cd","pwd","cat","mkdir","touch","rm","grep","find",
                     "wc","tree","echo","lex","ps","whoami","uname","env","neofetch"];
  const restantes = fictives.filter(n => !!B.COMMANDES[n]);
  dit(restantes.length === 0,
      restantes.length ? ("ENCORE FICTIVES : " + restantes.join(",")) :
      "aucune des " + fictives.length + " anciennes commandes fictives n'est un built-in local");

  (async () => {
    const rep = await B.appelBackend("ls -la", {cwd:"/tmp"});
    dit(appels.length === 1 && appels[0].opts.headers["X-Lexos-Jeton"] === "LE-JETON",
        "chaque appel au vrai système porte le jeton de l'URL");
    dit(JSON.parse(appels[0].opts.body).cmd === "ls -la",
        "la ligne tapée part ENTIÈRE vers bash — jamais redécoupée à la main");
    console.log("FIN|");
  })();
} catch(e) {
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
  console.log("FIN|");
}
NODEJS
)"
	if [ -z "$SORTIE_J" ]; then
		non "le front-end n'a rien rendu"
	elif ! grep -q '^FIN|' <<< "$SORTIE_J"; then
		non "le rendu du front-end s'est arrêté avant la fin"
	else
		while IFS='|' read -r V M; do
			case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
		done <<EOF
$SORTIE_J
EOF
	fi
fi

# =============================================================================
titre "4. TOUT EST BRANCHÉ — dispatcheur, aide, complétion, dock, panneau"
# =============================================================================
#  Repéré en chargeant la vraie page dans un vrai navigateur, contre un vrai
#  pont : sans « \n », la sortie de $HOME et celle de whoami se collaient
#  (« /rootroot ») — nom d'utilisateur ET dossier personnel faux, en silence.
grep -qF 'printf "%s\\n" "$HOME"; whoami' "$PAGE" \
	&& ok "la commande de démarrage garde son « \\n » entre les deux lignes" \
	|| non "le « \\n » entre \$HOME et whoami a disparu — les deux colleraient de nouveau"
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
	#  ═══ ET IL AIGUILLE POUR DE VRAI ═══
	#  On le fait tourner avec de faux terminaux, et on regarde où il va.
	#  Lire le « case » ne suffirait pas : c'est le comportement qui compte.
	PB="$(mktemp -d)"
	printf '#!/bin/sh\necho CLASSIQUE\n' > "$PB/xfce4-terminal.wrapper"
	printf '#!/bin/sh\necho PRO\n'       > "$PB/lexos-pro-terminal"
	chmod +x "$PB"/*
	sed -e "s|/usr/bin/xfce4-terminal.wrapper|$PB/xfce4-terminal.wrapper|" \
	    -e "s|/usr/bin/lexos-pro-terminal\$|$PB/lexos-pro-terminal|" \
	    "$PONT" > "$PB/pont"
	chmod +x "$PB/pont"
	MAUVAIS=0
	#  Sans argument, et avec un argument qui ne demande PAS d'exécution :
	#  c'est « ouvre-moi un terminal », et c'est pour LexOS Pro Terminal.
	for A in "" "--title=Truc"; do
		# shellcheck disable=SC2086
		[ "$(bash "$PB/pont" $A 2>/dev/null)" = "PRO" ] \
			|| { non "« $A » n'ouvre pas LexOS Pro Terminal"; MAUVAIS=1; }
	done
	[ "$MAUVAIS" = 0 ] && ok "« ouvre-moi un terminal » va bien à LexOS Pro Terminal"
	#  Et tout ce qui demande d'EXÉCUTER part au Terminal classique, tant que
	#  LexOS Pro Terminal n'a pas de pty. C'est la moitié qui évite la fenêtre
	#  vide et muette.
	MAUVAIS=0
	for A in "-e ls" "-x htop" "--command=top" "--hold -e ls" "--working-directory=/tmp"; do
		# shellcheck disable=SC2086
		[ "$(bash "$PB/pont" $A 2>/dev/null)" = "CLASSIQUE" ] \
			|| { non "« $A » n'est pas renvoyé au Terminal classique — fenêtre vide garantie"; MAUVAIS=1; }
	done
	[ "$MAUVAIS" = 0 ] && ok "tout ce qui demande d'EXÉCUTER part au Terminal classique (pas encore de pty)"
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
