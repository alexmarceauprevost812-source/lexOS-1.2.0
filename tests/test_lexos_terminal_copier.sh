#!/usr/bin/env bash
# =============================================================================
#  LexOS Pro Terminal — le copier-coller
# =============================================================================
#  ALEX : « le copier-coller ne fonctionne pas ». DEUX causes distinctes, et
#  c'est ce qui rendait la panne difficile à lire : corriger l'une seule
#  aurait laissé le symptôme presque entier.
#
#  CAUSE 1 — Ctrl+C ÉTAIT AVALÉ. Le gestionnaire de touches ne regardait que
#  la sélection DANS LE CHAMP DE SAISIE (« !this.champ.selectionEnd »). Quand
#  on sélectionne du texte dans la SORTIE — le cas normal, on veut copier le
#  résultat d'une commande — la condition restait vraie, preventDefault()
#  s'exécutait, et on obtenait « ^C » à la place du texte dans le
#  presse-papier. Le test était faux même pour le champ : selectionEnd vaut 0
#  quand le curseur est au DÉBUT sans rien sélectionner.
#
#  CAUSE 2 — QtWebEngine INTERDIT LE PRESSE-PAPIER PAR DÉFAUT. Tant que
#  JavascriptCanAccessClipboard et JavascriptCanPaste ne sont pas posés, la
#  page ne peut ni écrire ni lire, quoi qu'elle tente.
#
#  ═══ CE QUE CE BANC NE PEUT PAS FAIRE, ET CE QU'IL FAIT À LA PLACE ═══
#  Il ne peut pas ouvrir une vraie fenêtre QtWebEngine ni presser Ctrl+C :
#  la machine de construction n'a ni écran ni PySide6. Il éprouve donc les
#  DEUX conditions nécessaires — les réglages posés au bon endroit et sous
#  filet, la condition de touche corrigée — et il exécute pour de vrai la
#  logique de sélection extraite du fichier, sur les cas qui ont produit la
#  panne.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTML="$RACINE/config/includes.chroot/usr/share/lexos/terminal-pro/web/index.html"
PY="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$HTML" "$PY"; do
	if [ ! -r "$F" ]; then
		non "fichier introuvable : $F"
		printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
		exit 1
	fi
done

# =============================================================================
titre "1. QtWebEngine a le droit d'écrire ET de lire le presse-papier"
# =============================================================================
#  LES DEUX, SÉPARÉMENT. JavascriptCanAccessClipboard autorise l'ÉCRITURE
#  (copier), JavascriptCanPaste la LECTURE (coller). N'en poser qu'un donne
#  un copier-coller à moitié réparé — plus long à diagnostiquer qu'une panne
#  franche, parce que le symptôme devient « ça marche des fois ».
#  ═══ ON CHERCHE LA FORME COMPLÈTE, ET C'EST UNE LEÇON PAYÉE ICI ═══
#  Une première version cherchait « JavascriptCanPaste » tout court. Le nom
#  apparaît AUSSI dans le commentaire qui explique le réglage, quelques
#  lignes plus haut : le banc trouvait le commentaire et croyait avoir trouvé
#  le code. Pire, le repérage par numéro de ligne s'en servait ensuite pour
#  situer le try/except — et se trompait de bloc. On exige donc la forme
#  qualifiée « QWebEngineSettings.WebAttribute.… », qui n'existe que dans
#  l'appel réel.
CODE_COPIE='QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard'
CODE_COLLE='QWebEngineSettings.WebAttribute.JavascriptCanPaste'
if grep -q "$CODE_COPIE" "$PY"; then
	ok "JavascriptCanAccessClipboard est posé — la page peut COPIER"
else
	non "JavascriptCanAccessClipboard absent : la copie restera impossible"
fi
if grep -q "$CODE_COLLE" "$PY"; then
	ok "JavascriptCanPaste est posé — la page peut COLLER"
else
	non "JavascriptCanPaste absent : le collage restera impossible"
fi

#  ═══ AVANT LE CHARGEMENT, PAS APRÈS ═══
#  Un réglage posé après vue.load() peut ne pas s'appliquer à la page déjà
#  en cours : le terminal s'ouvrirait avec les anciens droits, et le
#  correctif ne se verrait qu'au deuxième lancement — ou jamais.
L_REGL="$(grep -n "$CODE_COPIE" "$PY" | head -1 | cut -d: -f1)"
L_LOAD="$(grep -n 'vue.load(' "$PY" | head -1 | cut -d: -f1)"
if [ -n "$L_REGL" ] && [ -n "$L_LOAD" ] && [ "$L_REGL" -lt "$L_LOAD" ]; then
	ok "les réglages sont posés AVANT vue.load() (ligne $L_REGL < $L_LOAD)"
else
	non "les réglages arrivent après le chargement (réglages=$L_REGL load=$L_LOAD) : la page garderait les anciens droits"
fi

#  ═══ L'ASSERTION LA PLUS IMPORTANTE DU BANC ═══
#  Si une version de PySide6 renomme ou déplace ces attributs, la fenêtre
#  doit s'ouvrir QUAND MÊME, sans presse-papier. Un presse-papier absent est
#  un désagrément ; un TERMINAL qui refuse de s'ouvrir laisse un système où
#  Alex ne peut plus rien lancer du tout. C'est la règle écrite en tête du
#  lanceur, et c'est celle-ci qu'il faut tenir.
#
#  On ne se contente pas de « il y a un try quelque part » : on vérifie que
#  le try OUVRE avant les réglages et que le except ferme après.
L_PASTE="$(grep -n "$CODE_COLLE" "$PY" | head -1 | cut -d: -f1)"
#  Le dernier « try: » AVANT l'appel, et le premier « except » APRÈS : c'est
#  celui-là qui enveloppe les réglages, et pas un autre bloc du fichier.
BLOC="$(awk -v n="${L_REGL:-0}" 'NR<n && /^    try:/{d=NR} END{print d}' "$PY")"
EXC="$(awk -v n="${L_PASTE:-0}" 'NR>n && /^    except /{print NR; exit}' "$PY")"
if [ -n "$BLOC" ] && [ -n "$EXC" ] && [ -n "$L_PASTE" ] \
   && [ "$BLOC" -lt "$L_REGL" ] && [ "$EXC" -gt "$L_PASTE" ]; then
	ok "les réglages sont sous try/except (try l.$BLOC, except l.$EXC) — le terminal s'ouvre même si PySide6 change"
else
	non "les réglages ne sont pas protégés : un PySide6 qui renomme un attribut empêcherait le terminal de s'ouvrir"
fi

#  ET L'ÉCHEC SE DIT. Un except muet, c'est un presse-papier qui disparaît
#  sans que rien ne l'explique.
if grep -q 'presse-papier non activé' < <(awk -v d="${EXC:-0}" 'NR>=d && NR<=d+3' "$PY"); then
	ok "un échec d'activation est journalisé, pas avalé"
else
	non "l'except est muet : le presse-papier disparaîtrait sans un mot"
fi

if command -v python3 >/dev/null 2>&1; then
	if python3 -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read(), sys.argv[1])" "$PY" 2>/dev/null; then
		ok "terminal-pro.py reste un Python valide"
	else
		non "terminal-pro.py ne se compile plus"
	fi
else
	saut "python3 absent : la syntaxe du lanceur n'a PAS été vérifiée"
fi

# =============================================================================
titre "2. Ctrl+C ne mange plus la copie — et interrompt POUR DE VRAI"
# =============================================================================
#  ══ CE QUE CE CONTRÔLE PROTÈGE, ET CE QUI A CHANGÉ SOUS LUI ══
#
#  ALEX : le copier-coller ne fonctionnait pas. La cause n'était pas le
#  presse-papier mais une question mal posée : le gestionnaire de Ctrl+C ne
#  regardait que la sélection DANS LE CHAMP DE SAISIE. Quand on sélectionne
#  dans la SORTIE — le cas normal, on veut copier le résultat d'une commande
#  — la copie était avalée et on obtenait « ^C » à la place du texte.
#
#  IL N'Y A PLUS DE CHAMP DE SAISIE. Le volet est un vrai terminal : c'est
#  xterm.js qui tient la sélection, et lui seul. La question devient donc
#  « y a-t-il une sélection DANS LE TERMINAL », ce qui est exactement la
#  bonne question — celle qu'on essayait d'approcher avec deux mesures
#  séparées, dont l'une se trompait.
#
#  ET LE « ^C » N'EST PLUS UNE IMITATION. L'ancienne page ÉCRIVAIT le texte
#  « ^C » à l'écran et vidait sa ligne : une mise en scène, rien n'était
#  interrompu, puisqu'il n'y avait aucun programme en cours à interrompre.
#  Maintenant, Ctrl+C sans sélection descend au pty comme n'importe quelle
#  frappe, et c'est la discipline de ligne du noyau qui envoie un VRAI
#  SIGINT au groupe de processus au premier plan. C'est éprouvé par
#  tests/test_lexos_terminal_pty.sh (« Ctrl+C interrompt la commande et la
#  session survit »), avec un vrai « sleep 40 ».
#
#  ══ ET ON EXÉCUTE LA LOGIQUE, ON NE LA LIT PAS ══
#  Un grep dit que le gestionnaire est là ; il ne dit pas qu'il répond juste.
#  On extrait le vrai gestionnaire du fichier et on le fait tourner sur les
#  quatre cas qui comptent.
if ! command -v node >/dev/null 2>&1; then
	saut "node absent : la logique du presse-papier n'a PAS été exécutée"
else
	CORPS="$(awk '
		/attachCustomKeyEventHandler\(e => \{/ { d = 1 }
		d { print }
		d && /^    \}\);$/ { exit }
	' "$HTML")"
	if [ -z "$CORPS" ]; then
		non "le gestionnaire de touches est introuvable — rien à exécuter"
	else
		{
			printf 'let COPIES = 0, COLLES = 0;\n'
			printf 'let SELECTION = false, PREFIXE = false;\n'
			printf 'const Terminal = { get prefixe(){ return PREFIXE; } };\n'
			printf 'const objet = {\n'
			printf '  term: { hasSelection: () => SELECTION,\n'
			printf '          attachCustomKeyEventHandler(f){ this.h = f; } },\n'
			printf '  copier(){ COPIES++; }, coller(){ COLLES++; },\n'
			printf '  poser(){\n'
			printf '%s\n' "$CORPS"
			printf '  }\n'
			printf '};\n'
			cat <<'JS'
let handler = null;
objet.term.attachCustomKeyEventHandler = f => { handler = f; };
objet.poser.call(objet);
function cas(nom, e, sel, prefixe, attenduRendu, attenduCopies, attenduColles){
  SELECTION = sel; PREFIXE = prefixe;
  const c0 = COPIES, v0 = COLLES;
  const rendu = handler(Object.assign({type:"keydown", ctrlKey:false, shiftKey:false, altKey:false}, e));
  const ok = rendu === attenduRendu && (COPIES - c0) === attenduCopies && (COLLES - v0) === attenduColles;
  console.log((ok ? "OK   " : "RATE ") + nom +
    " -> rendu=" + rendu + " copies=+" + (COPIES-c0) + " colles=+" + (COLLES-v0));
}
//  rendu=false : xterm N'ENVOIE PAS la touche au pty (on l'a traitée).
//  rendu=true  : xterm l'envoie — c'est ce qu'on veut pour un vrai Ctrl+C.
cas("Ctrl+C AVEC selection (la panne d'Alex) : copie, rien au shell",
    {ctrlKey:true, key:"c"}, true,  false, false, 1, 0);
cas("Ctrl+C SANS selection : descend au pty, donc VRAI SIGINT",
    {ctrlKey:true, key:"c"}, false, false, true,  0, 0);
cas("Ctrl+Maj+C : copie toujours, meme sans selection",
    {ctrlKey:true, shiftKey:true, key:"C"}, false, false, false, 1, 0);
cas("Ctrl+Maj+V : colle",
    {ctrlKey:true, shiftKey:true, key:"V"}, false, false, false, 0, 1);
cas("une frappe ordinaire descend au pty",
    {key:"a"}, false, false, true, 0, 0);
//  Le mode prefixe (Ctrl+B) doit garder la main : sinon « Ctrl+B puis D »
//  taperait un « d » dans le shell en plus de diviser le volet.
cas("en mode prefixe, rien ne descend au shell",
    {key:"d"}, false, true, false, 0, 0);
JS
		} > "$BANC/touches.js"
		SORTIE="$(node "$BANC/touches.js" 2>&1)"
		if grep -q 'RATE' <<< "$SORTIE"; then
			non "le gestionnaire de touches se trompe :"
			printf '%s\n' "$SORTIE" | sed 's/^/       /'
		else
			ok "le gestionnaire de touches répond juste sur les six cas (dont la panne d'Alex)"
			printf '%s\n' "$SORTIE" | sed 's/^/       /'
		fi
	fi
fi

#  ═══ LA SÉLECTION VIENT DU TERMINAL, PAS D'AILLEURS ═══
#  Si la copie retournait lire window.getSelection(), elle rendrait « rien »
#  dans un terminal : xterm.js dessine son texte sur une toile, la sélection
#  du navigateur n'y voit pas grand-chose.
if grep -q 'this.term.getSelection()' "$HTML"; then
	ok "la copie prend le texte sélectionné DANS le terminal (term.getSelection)"
else
	non "la copie ne lit pas la sélection du terminal : elle copierait du vide"
fi

# =============================================================================
titre "3. Les autres chemins vers le presse-papier"
# =============================================================================
#  ═══ LE MENU DU CLIC DROIT RESTE ═══
#  C'est le chemin qu'utilisent les gens qui ne connaissent pas les
#  raccourcis — et le seul qui reste si les deux autres tombent.
if grep -qi 'contextmenu\|NoContextMenu\|setContextMenuPolicy' "$HTML" "$PY"; then
	non "quelque chose touche au menu contextuel : le clic droit pourrait ne plus proposer Copier/Coller"
else
	ok "rien ne désactive le menu contextuel — le clic droit garde Copier/Coller"
fi

#  ═══ LE CLIC DU MILIEU COLLE, COMME PARTOUT SOUS X ═══
if grep -q 'auxclick' "$HTML" && grep -q 'e.button === 1' "$HTML"; then
	ok "le clic du milieu colle, comme dans tous les terminaux X"
else
	non "le clic du milieu ne colle pas — un geste que tout le monde a dans les doigts"
fi

#  ═══ L'ÉCRAN DOIT RESTER SÉLECTIONNABLE ═══
#  Des « user-select:none » existent dans le fichier : ils visent la barre
#  d'onglets, l'en-tête de fenêtre et la barre d'état — c'est voulu. Aucun ne
#  doit atteindre le corps du volet, sinon on ne pourrait plus rien copier.
#  ON DÉCOUPE LA RÈGLE SUR SES ACCOLADES, PAS SUR LES FINS DE LIGNE. Une
#  première version cherchait la fin d'une règle sur une ligne « } » toute
#  seule — mais « .ecran{position:absolute;inset:0} » tient sur UNE ligne :
#  le balayage ne s'arrêtait jamais et ramassait les règles suivantes, dont
#  la barre d'onglets qui a bel et bien un « user-select:none » voulu. Le
#  contrôle accusait donc un correctif parfaitement correct.
MAUVAIS="$(python3 - "$HTML" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
css = "\n".join(re.findall(r"<style>(.*?)</style>", s, re.S))
mauvais = []
for sel in (".ecran", ".fen-corps"):
    #  Toutes les règles dont le sélecteur EST exactement celui-ci (pas
    #  « .fen:not(.actif) .ecran », qui est une autre règle).
    for m in re.finditer(r"(?m)^\s*" + re.escape(sel) + r"\s*\{([^}]*)\}", css):
        if re.search(r"user-select\s*:\s*none", m.group(1)):
            mauvais.append(sel)
print(" ".join(sorted(set(mauvais))))
PY
)"
if [ -n "$MAUVAIS" ]; then
	non "« user-select: none » s'applique à $MAUVAIS — on ne pourrait plus copier"
else
	ok "aucun « user-select: none » n'atteint l'écran du terminal"
fi

# =============================================================================
titre "4. L'aide ne ment pas"
# =============================================================================
#  Une aide qui ment coûte plus cher qu'une aide absente : elle envoie
#  chercher la panne au mauvais endroit.
#  L'aide doit dire les DEUX comportements de Ctrl+C. Une première version
#  de ce contrôle refusait la chaîne « annuler la ligne » — mais la bonne
#  description la contient (« copier si… sinon annuler la ligne »). On exige
#  donc ce qui manquait : le mot « copier » dans la ligne de Ctrl+C.
LIGNE_CTRLC="$(grep -o '\["Ctrl+C[^"]*", *"[^"]*"\]' "$HTML" | head -1)"
if [ -z "$LIGNE_CTRLC" ]; then
	non "aucune entrée « Ctrl+C » dans l'aide"
elif grep -qi 'copie' <<< "$LIGNE_CTRLC" && grep -qi 'interrom' <<< "$LIGNE_CTRLC"; then
	ok "l'aide dit les DEUX comportements de Ctrl+C (copier, et interrompre)"
else
	non "l'aide réduit Ctrl+C à $LIGNE_CTRLC — elle doit dire les deux"
fi
for R in 'Ctrl+Maj+C' 'Ctrl+Maj+V'; do
	if grep -q "$R" "$HTML"; then
		ok "l'aide annonce $R"
	else
		non "l'aide ne dit rien de $R — un raccourci qui existe et que personne ne connaît"
	fi
done

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mCopier, coller, et Ctrl+C qui interrompt encore.\033[0m\n'
