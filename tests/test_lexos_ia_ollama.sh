#!/usr/bin/env bash
# =============================================================================
#  Le panneau IA voit un Ollama qu'il n'a pas installé — et le terminal Pro aussi
# =============================================================================
#  ALEX : « ollama est invisible dans le terminal Pro ». Il l'avait posé à la
#  main, par le script officiel, qui l'écrit dans /usr/local/bin.
#
#  ══ LA MESURE QUI A TRANCHÉ, ET QU'ON GÈLE ICI ══
#  L'hypothèse de départ était le PATH : le pont du terminal Pro lance
#  « bash --noprofile --norc », xfce4-terminal lance un bash ordinaire ; on a
#  supposé que le premier perdait /usr/local/bin en route.
#
#  C'EST FAUX, et c'est mesuré : --noprofile --norc ne touche PAS au PATH.
#  Ces deux options empêchent bash de LIRE des fichiers (/etc/profile,
#  ~/.bashrc) ; elles ne réinitialisent aucune variable. bash n'invente un
#  PATH que si l'environnement n'en porte aucun — et ce PATH-là de secours
#  contient /usr/local/bin lui aussi. Aucun fichier du dépôt n'écrit « PATH= »
#  dans /etc/environment ni dans /etc/profile.d/lexos.sh.
#
#  Les deux chemins mènent donc au même PATH, et un ollama de /usr/local/bin
#  est trouvé par les DEUX. Les contrôles 1 à 3 gèlent cette mesure : si un
#  jour quelqu'un « corrige » le PATH en croyant tenir le coupable, il verra
#  ici que le coupable était ailleurs.
#
#  ══ CE QUI NE MARCHE VRAIMENT PAS, ET QUI N'EST PAS UN PROBLÈME DE PATH ══
#  « ollama run » et « ollama serve » veulent un vrai terminal : le premier
#  lit le clavier (stdin est fermé ici, il rend la main aussitôt), le second
#  ne s'arrête jamais (il meurt au délai). C'est le chantier du pty, séparé.
#  Les sous-commandes qui répondent et rendent la main — list, ps, --version,
#  pull — marchent déjà. Le contrôle 9 garde le fait qu'« ollama » n'est PAS
#  refusé d'avance comme un programme plein écran.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
PANNEAU="$RACINE/config/includes.chroot/usr/lib/lexos/ia-locale.py"
APPJS="$RACINE/config/includes.chroot/usr/share/lexos/ia/web/app.js"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$BACKEND" "$PANNEAU" "$APPJS"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# --- Le faux Ollama, posé comme le pose le script officiel : /usr/local/bin,
#     un répertoire que LexOS n'a pas rempli lui-même. -----------------------
mkdir -p "$BANC/usr/local/bin"
cat > "$BANC/usr/local/bin/ollama" <<'FAUX'
#!/bin/sh
case "$1" in
  --version) echo "ollama version is 0.12.3" ;;
  list) printf 'NAME\tID\tSIZE\nllama3:8b\tabc123\t4.7 GB\n' ;;
  *) echo "Usage: ollama [command]" ;;
esac
FAUX
chmod +x "$BANC/usr/local/bin/ollama"

#  Le PATH d'une session XFCE ordinaire : celui que /etc/login.defs (ENV_PATH)
#  donne à un compte non-root sur trixie. /usr/local/bin y est, en tête.
PATH_SESSION="$BANC/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games"

#  Et son contraire : une ferme de liens qui porte de quoi faire tourner bash
#  et python, mais AUCUN ollama. On ne vide jamais le PATH — python lui-même
#  deviendrait introuvable et le contrôle passerait au vert pour rien.
mkdir -p "$BANC/vide"
for C in bash sh env printf cat; do
	P="$(command -v "$C" 2>/dev/null)" && ln -sf "$P" "$BANC/vide/$C"
done
PATH_SANS="$BANC/vide"

# =============================================================================
titre "1. LA MESURE : les deux PATH sont identiques"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : la mesure du PATH n'a PAS été refaite"
else
	cat > "$BANC/mesure.py" <<'PY'
import importlib.util, os, shutil, sys

def charge(nom, chemin):
    s = importlib.util.spec_from_file_location(nom, chemin)
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    return m

tp = charge("tp", sys.argv[1])
ia = charge("ia", sys.argv[2])
def dit(bon, m): print(("OK|" if bon else "NON|") + m)

attendu = os.path.join(sys.argv[3], "usr", "local", "bin", "ollama")

# --- 1. le pont Python (ce que le panneau IA emploie) ---
dit(shutil.which("ollama") == attendu,
    "shutil.which trouve l'ollama de /usr/local/bin (c'est la détection du panneau IA)")

# --- 2. le bash du terminal Pro, avec SES options ---
html, _ = tp.executer("command -v ollama", "/tmp")
dit(attendu in html,
    "le bash du terminal Pro (--noprofile --norc) trouve le MÊME ollama")

# --- 3. les deux PATH, comparés caractère par caractère ---
html, _ = tp.executer('printf %s "$PATH"', "/tmp")
vu = html.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").strip()
dit(vu == os.environ["PATH"],
    "…parce que --noprofile --norc ne retire rien du PATH : il est identique")

# --- 4. le panneau IA le déclare présent ---
m = ia._moteurs()
dit(m.get("ollama") is True,
    "le panneau IA déclare Ollama présent, sans l'avoir installé lui-même")

# --- 6. « présent » et « en marche » sont deux questions séparées ---
ia.OLLAMA_HOTE = "127.0.0.1:1"          # rien n'écoute là, jamais
m = ia._moteurs()
dit(m.get("ollama") is True and m.get("ollama_actif") is False,
    "un Ollama installé mais à l'arrêt reste « présent » (ollama_actif seul tombe)")
print("FIN|")
PY
	SORTIE="$(PATH="$PATH_SESSION" python3 "$BANC/mesure.py" "$BACKEND" "$PANNEAU" "$BANC" 2>/dev/null | grep -E '^(OK|NON|FIN)\|' || true)"
	if ! grep -q '^FIN|' <<< "$SORTIE"; then
		non "la mesure du PATH n'est pas allée au bout (le pont a rendu la main trop tôt)"
	fi
	while IFS='|' read -r VERDICT TEXTE; do
		case "$VERDICT" in
			OK)  ok "$TEXTE" ;;
			NON) non "$TEXTE" ;;
		esac
	done <<< "$SORTIE"

	# --- 5. le contraire : vraiment absent, le panneau ne l'invente pas ---
	#  python3 est appelé par son chemin ABSOLU : le PATH fabriqué ne le
	#  porte pas, et un « python3 » nu rendrait ce contrôle vert sans jamais
	#  avoir tourné. C'est le même piège que la ferme de liens évite.
	PY3="$(command -v python3)"
	ABS="$(PATH="$PATH_SANS" "$PY3" -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("ia", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.OLLAMA_HOTE = "127.0.0.1:1"
print(m._moteurs()["ollama"])' "$PANNEAU" 2>/dev/null || echo ERREUR)"
	[ "$ABS" = "False" ] \
		&& ok "…et quand ollama est vraiment absent du PATH, le panneau dit non" \
		|| non "le panneau annonce Ollama présent alors qu'il ne l'est pas ($ABS)"
fi

# =============================================================================
titre "2. L'INTERFACE : « installé, à l'arrêt » n'est pas « pas installé »"
# =============================================================================
#  Le piège que ce contrôle garde : brancher le bouton « Installer » sur
#  ollama_actif au lieu de ollama. Un Ollama posé à la main mais pas démarré
#  proposerait alors de le réinstaller — c'est exactement ce qui ferait dire
#  « il ne le voit pas ».
JS_NU="$BANC/app.nu.js"
sed -e 's#//.*##' -e 's#/\*.*\*/##' "$APPJS" > "$JS_NU"

#  CE CONTRÔLE A ÉTÉ SANS DENTS AU PREMIER JET. Il cherchait « m.ollama ? »
#  n'importe où dans le fichier : la ligne du TEXTE en porte un, alors la
#  vraie régression — le BOUTON rebranché sur m.ollama_actif — passait au
#  vert. On vise maintenant la condition qui mène à poseOllama(), et elle
#  seule : c'est la dernière ternaire ouverte avant le bouton.
if python3 - "$JS_NU" <<'SONDE'
import re, sys
lignes = open(sys.argv[1], encoding="utf-8").read().splitlines()
bouton = next((n for n, l in enumerate(lignes) if "poseOllama()" in l), -1)
if bouton < 0:
    sys.exit(2)
#  On remonte jusqu'à la ligne qui OUVRE la ternaire du bouton. On lit le
#  DÉBUT de ligne, pas le fil du texte : les ${…?…} imbriqués dans le
#  gabarit portent tous « m.ollama_actif », et une recherche au fil du
#  texte tomberait sur eux — c'est ce qui rendait ce contrôle muet.
for l in reversed(lignes[:bouton]):
    m = re.match(r"\s*m\.ollama(_actif)?\s*\?", l)
    if m:
        sys.exit(1 if m.group(1) else 0)
sys.exit(1)
SONDE
then
	ok "le bouton « Installer » se décide sur la présence (m.ollama), pas sur l'état"
else
	non "le bouton « Installer » se décide sur m.ollama_actif : un Ollama posé à la main mais à l'arrêt se ferait proposer une réinstallation"
fi

grep -q "Installé, à l'arrêt" "$JS_NU" \
	&& ok "…et le dit en toutes lettres : « Installé, à l'arrêt »" \
	|| non "la formulation qui distingue « installé » de « en marche » a disparu"

grep -q 'poseOllama()' "$JS_NU" \
	&& ok "la proposition d'installation existe toujours pour qui n'a rien" \
	|| non "plus aucun bouton d'installation d'Ollama dans le panneau"

# =============================================================================
titre "3. LE TERMINAL PRO NE REFUSE PAS « ollama » D'AVANCE"
# =============================================================================
PY_NU="$BANC/tp.nu.py"
sed -e 's/#.*//' "$BACKEND" > "$PY_NU"

python3 - "$PY_NU" <<'PY' >/dev/null 2>&1
import re, sys
src = open(sys.argv[1]).read()
bloc = re.search(r"LISTE_TUI\s*=\s*frozenset\((.*?)\)\)", src, re.S)
sys.exit(0 if bloc and '"ollama"' not in bloc.group(1) else 1)
PY
if [ $? -eq 0 ]; then
	ok "« ollama » n'est pas dans LISTE_TUI : la commande part vraiment dans bash"
else
	non "« ollama » est refusé d'avance comme programme plein écran (ou LISTE_TUI est illisible)"
fi

# =============================================================================
titre "4. LE GARDE-FOU : personne ne « corrige » le PATH du pont"
# =============================================================================
#  La mesure dit que le PATH n'est pas le coupable. Ces deux contrôles
#  empêchent qu'on aille quand même y toucher — dans un sens ou dans l'autre.
grep -q 'env=' "$PY_NU" \
	&& non "le pont impose un env= à bash : il pourrait perdre le PATH de la session" \
	|| ok "le pont ne remplace pas l'environnement de bash (le PATH de la session passe)"

grep -qE '^\s*os\.environ\["PATH"\]\s*=' "$PY_NU" \
	&& non "le pont réécrit os.environ[\"PATH\"] : la mesure ci-dessus ne vaut plus" \
	|| ok "le pont ne réécrit pas le PATH du processus"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
