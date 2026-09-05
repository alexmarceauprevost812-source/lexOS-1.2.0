#!/usr/bin/env bash
# =============================================================================
#  Chaque bouton fait quelque chose, chaque fenêtre mène quelque part
# =============================================================================
#  ALEX : « regarde bien pour que tous les boutons et les fenêtres ouvrent
#  fluidement. »
#
#  ═══ CE QUE L'AUDIT A TROUVÉ ═══
#  Deux fenêtres sur trente-cinq étaient MORTES : « Applications » et
#  « Applications par défaut » lançaient toutes deux
#  « exo-preferred-applications ». Vérifié sur les vrais paquets : exo-utils
#  ne livre que exo-open, exo-desktop-item-edit et exo-helper — ce programme
#  n'existe plus. XFCE a déplacé la fenêtre dans xfce4-settings, où le
#  fichier .desktop s'intitule « Default Applications » et lance
#  « xfce4-mime-settings ».
#
#  ET LE SILENCE ÉTAIT DE NOTRE FAIT. Le moteur renvoyait pourtant le motif
#  exact (« Outil absent : … ») ; la page jetait la réponse. On cliquait,
#  rien ne s'ouvrait, aucun message — un bouton mort ne se distinguait pas
#  d'un bouton lent.
#
#  Le commentaire de _xfce() raconte que ce défaut a DÉJÀ tué neuf fenêtres
#  auparavant (son, apparence, bureau, multi-tâches, souris, amovibles,
#  tablette, accessibilité, clavier). C'est le défaut le plus répété de ce
#  dépôt, et rien ne le surveillait.
#
#  ═══ LA QUESTION QUE CE BANC POSE ═══
#  Pas « ce programme est-il installé quelque part » — la réponse serait
#  bruyante et fausse : beaucoup d'appels sont des sondes volontaires. Il
#  pose la question précise et dangereuse : UN BOUTON PEUT-IL NE MENER NULLE
#  PART ? Une fenêtre est acceptée si elle passe par _xfce() (qui garantit un
#  repli), par un terminal (qui s'ouvre toujours), par un outil LexOS présent
#  dans l'ISO, ou par un programme tiers EXPLICITEMENT VÉRIFIÉ ci-dessous.
#  Tout nouveau nom force quelqu'un à vérifier avant de l'ajouter.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SET="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
VOL_JS="$RACINE/config/includes.chroot/usr/share/lexos/volet/web/app.js"
VOL_PY="$RACINE/config/includes.chroot/usr/lib/lexos/volet.py"

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }
#  Un contrôle SAUTÉ n'est ni un succès ni un échec : il se dit, et il ne
#  compte pas. Mieux vaut « je n'ai pas pu mesurer » qu'un vert emprunté.
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }

PY=""
command -v python3 >/dev/null 2>&1 && PY=python3

#  ═══ LES PROGRAMMES TIERS VÉRIFIÉS, UN PAR UN ═══
#  Chaque ligne dit le paquet qui le fournit ET la liste qui l'installe —
#  vérifiés en téléchargeant le paquet et en listant son contenu, jamais de
#  mémoire. Ajouter un nom ici est un engagement ; le banc rougit sinon.
TIERS="
xfce4-appfinder|xfce4-appfinder|lexos-core.list.chroot
system-config-printer|system-config-printer|20-desktop.list
xfce4-notifyd-config|xfce4-notifyd|20-desktop.list
gcm-viewer|gnome-color-manager|56-reglages.list
timedatectl|systemd|toujours présent (init du système)
"

# =============================================================================
titre "1. Aucun bouton n'appelle une fonction qui n'existe pas"
# =============================================================================
RES="$(python3 - "$APP" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
declarees  = set(re.findall(r'^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)', src, re.M))
declarees |= set(re.findall(r'^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=', src, re.M))
appelees = set()
for m in re.finditer(r'onclick="([^"]+)"', src):
    for f in re.findall(r'\b([A-Za-z_$][\w$]*)\s*\(', m.group(1)):
        appelees.add(f)
#  Ce ne sont pas des fonctions de la page : des méthodes et des natifs.
NATIF = {"event","Number","String","confirm","alert","parseInt","replace",
         "stopPropagation","then","preventDefault","encodeURIComponent"}
print("APPELS:%d" % len(appelees))
print("MANQUE:" + ",".join(sorted(appelees - declarees - NATIF)))
PY
)"
NB="$(printf '%s' "$RES" | sed -n 's/^APPELS://p')"
MQ="$(printf '%s' "$RES" | sed -n 's/^MANQUE://p')"
if [[ "$NB" -ge 30 ]]; then
	ok "$NB fonctions appelées depuis un bouton — la page a bien été lue"
else
	non "seulement $NB appels relevés : la lecture a échoué, le reste serait creux"
fi
if [[ -z "$MQ" ]]; then
	ok "toutes existent — aucun bouton ne pointe dans le vide"
else
	non "fonction(s) appelées mais jamais déclarées : $MQ"
fi

# =============================================================================
titre "2. Chaque appel trouve son action dans SON moteur"
# =============================================================================
#  DEUX PAGES, DEUX MOTEURS. Le volet a son propre volet.py ; comparer ses
#  appels à la table des Paramètres crierait au loup pour rien — c'est
#  l'erreur que cet audit a d'abord commise.
verifie_paire() { # verifie_paire <nom> <page.js> <moteur.py>
	local nom="$1" js="$2" py="$3"
	[[ -r "$js" && -r "$py" ]] || { non "$nom : page ou moteur introuvable"; return; }
	local sortie
	sortie="$(python3 - "$js" "$py" <<'PY'
import re, sys
js = open(sys.argv[1], encoding="utf-8").read()
py = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r'^ACTIONS\s*=\s*\{(.*?)^\}', py, re.S | re.M) or \
    re.search(r'ACTIONS\s*=\s*\{(.*?)\n\}', py, re.S)
actions = set(re.findall(r'"([^"]+)"\s*:', m.group(1))) if m else set()
#  LES DEUX SORTES DE GUILLEMETS. Ce motif ne voyait que api("nom") : un
#  appel écrit api('nom') lui échappait complètement. Ce n'est pas
#  théorique — app.js portait « api('ouvrir','prive') » dans un attribut
#  onclick, et ce contrôle ne l'a jamais vu. Un futur api('nom-inexistant')
#  serait passé au vert de la même façon.
appels  = set(re.findall(r'\bapi\(\s*"([^"]+)"', js)) \
        | set(re.findall(r"\bapi\(\s*'([^']+)'", js))
print("N:%d" % len(appels))
print("ORPH:" + ",".join(sorted(appels - actions)))
PY
)"
	local n orph
	n="$(printf '%s' "$sortie" | sed -n 's/^N://p')"
	orph="$(printf '%s' "$sortie" | sed -n 's/^ORPH://p')"
	if [[ "$n" -lt 1 ]]; then
		non "$nom : aucun appel relevé — le contrôle serait creux"
	elif [[ -z "$orph" ]]; then
		ok "$nom : les $n actions appelées existent toutes dans son moteur"
	else
		non "$nom : action(s) appelées sans exister — le bouton appelle dans le vide : $orph"
	fi
}
verifie_paire "Paramètres" "$APP" "$SET"
verifie_paire "Volet"      "$VOL_JS" "$VOL_PY"

# =============================================================================
titre "3. Aucune fenêtre ne mène nulle part"
# =============================================================================
FEN="$(python3 - "$SET" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
deb = s.index("def act_ouvrir(arg):")
fin = s.index("\ndef ", deb + 10)
bloc = re.sub(r'^\s*#.*$', '', s[deb:fin], flags=re.M)
for m in re.finditer(r'"([a-z-]+)":\s*lambda:\s*(.+?)(?=,\s*\n\s*(?:"|\}))', bloc, re.S):
    print(m.group(1) + "\t" + " ".join(m.group(2).split()))
PY
)"
N_FEN="$(printf '%s\n' "$FEN" | grep -c . )"
if [[ "$N_FEN" -ge 30 ]]; then
	ok "$N_FEN fenêtres déclarées — la table a bien été lue"
else
	non "seulement $N_FEN fenêtres lues : le contrôle serait creux"
fi

MORTES=""
while IFS=$'\t' read -r cle corps; do
	[[ -n "$cle" ]] || continue
	#  a) _xfce() : il essaie chaque nom PUIS le gestionnaire général. Il ne
	#     peut pas ne mener nulle part — c'est sa raison d'être.
	case "$corps" in *_xfce*) continue ;; esac
	#  b) _terminal() : la fenêtre est le terminal lui-même, toujours là.
	case "$corps" in *_terminal*) continue ;; esac
	#  c) _run() : le programme DOIT exister. C'est ici qu'étaient les morts.
	PROG="$(printf '%s' "$corps" | sed -n 's/.*_run(\["\([a-z0-9._-]*\)".*/\1/p')"
	[[ -n "$PROG" ]] || { MORTES="$MORTES $cle(illisible)"; continue; }
	#  Un outil LexOS : le fichier doit partir dans l'ISO.
	if [[ "$PROG" == lexos* ]]; then
		[[ -e "$RACINE/config/includes.chroot/usr/bin/$PROG" ]] \
			|| MORTES="$MORTES $cle($PROG absent de l'ISO)"
		continue
	fi
	#  Un programme tiers : il doit être dans la liste vérifiée en tête.
	#  PAS DE TUYAU (même règle qu'écrite dans test_lexos_ouvrir.sh:291-296,
	#  pas reprise ici jusqu'ici) : sous « pipefail », « … | grep -q motif »
	#  peut rendre 141 (SIGPIPE : grep quitte dès la 1re correspondance, avant
	#  que l'amont ait fini d'écrire) MÊME quand le motif est trouvé — un
	#  résultat qui dépend du hasard du minutage plutôt que du contenu. La
	#  comparaison native ne lance aucun sous-processus : rien à intercepter.
	[[ "$TIERS" == *$'\n'"$PROG|"* ]] \
		|| MORTES="$MORTES $cle($PROG non vérifié)"
done <<< "$FEN"

if [[ -z "$MORTES" ]]; then
	ok "les $N_FEN fenêtres mènent toutes quelque part"
else
	non "fenêtre(s) qui n'ouvriraient rien :$MORTES"
fi

#  ═══ LE MORT NOMMÉMENT ═══ Si quelqu'un le remet, le message dit tout de
#  suite de quoi il s'agit au lieu de laisser chercher.
if [[ "$FEN" == *'_run(["exo-preferred-applications"'* ]]; then
	non "« exo-preferred-applications » est de retour en appel direct — ce programme n'existe plus"
else
	ok "« exo-preferred-applications » n'est plus appelé sans repli"
fi

#  ET LE REMPLAÇANT EST LE BON, celui du fichier .desktop « Default
#  Applications » de xfce4-settings.
if grep -q 'xfce4-mime-settings' "$SET"; then
	ok "« xfce4-mime-settings » a pris le relais (le vrai nom, lu dans le paquet)"
else
	non "aucun remplaçant : les deux fenêtres « applications » resteraient mortes"
fi

# =============================================================================
titre "4. Une fenêtre qui refuse de s'ouvrir le DIT"
# =============================================================================
#  Le silence était la moitié du bogue : le moteur donnait déjà le motif.
#  On dépouille les commentaires — celui juste au-dessus de l'appel contient
#  les mêmes mots, et un contrôle qui lit de la prose reste vert pour rien.
CORPS_OUVRIR="$(python3 - "$APP" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^async function ouvrir\(section\)\{[\s\S]*?\n\}', s, re.M)
t = m.group(0) if m else ""
t = re.sub(r'/\*[\s\S]*?\*/', '', t)
t = re.sub(r'^\s*//.*$', '', t, flags=re.M)
print(t)
PY
)"
if [[ "$CORPS_OUVRIR" == *'api('* ]]; then
	ok "ouvrir() a bien été trouvée"
else
	non "ouvrir() introuvable — les contrôles suivants seraient creux"
fi
if [[ "$CORPS_OUVRIR" == *'erreur'* ]]; then
	ok "elle lit le motif du refus au lieu de jeter la réponse"
else
	non "elle jette la réponse : un outil absent resterait totalement muet"
fi


# =============================================================================
titre "5. LE CHOIX COURANT SE VOIT — et aucun bouton n'annonce un faux succès"
# =============================================================================
CSS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/style.css"
BANC5="$(mktemp -d)"
trap 'rm -rf "$BANC5"' EXIT

#  ═══ ALEX : « POUR CHANGER DE COULEUR SUR LE BOUTON SÉLECTIONNÉ, POUR QU'IL
#      CHANGE DE COULEUR » ═══
#  Les cinq fonds d'écran intégrés et les vignettes de « Mes images » étaient
#  les SEULS choix de toute la page à ne jamais montrer lequel était posé :
#  leurs boutons portaient « class="btn ghost" » écrit en dur, sans condition.
#  Et ce n'était pas un oubli d'une ligne — etat() ne DISAIT pas quel fond est
#  posé, il n'y avait rien à comparer.
grep -q '"fond": _fond_etat(' "$SET" \
	&& ok "le moteur publie QUEL fond est posé (sans ça, rien à mettre en couleur)" \
	|| non "etat() ne dit pas quel fond est posé : aucun bouton ne peut se colorer"
#  Le nom EXACT, et son emploi : « def _fond_actuel » tout court laissait
#  passer un « _fond_actuel_retire » — mesuré par mutation.
grep -q '^def _fond_actuel():' "$SET" && grep -q 'chemin = _fond_actuel()' "$SET" \
	&& ok "…et il le lit dans XFCE, il ne le devine pas" \
	|| non "aucun lecteur du fond courant, ou il n'est pas appelé"

#  LA PAGE DOIT S'EN SERVIR POUR LES DEUX LISTES — ÉPROUVÉ PAR UN VRAI RENDU,
#  PAS PAR DU TEXTE. Un contrôle textuel (compter des clés, des motifs
#  « ghost » en dur) reste vert même quand la comparaison qui décide de la
#  couleur est cassée pour de bon — mesuré : « F === k » saboté en
#  « F === k + "zz" » laissait TOUS les anciens contrôles au vert alors
#  qu'AUCUN fond ne peut plus s'allumer. On pose donc l'état et on relit la
#  classe réellement rendue, avec le même bac à sable node/vm que
#  test_lexos_sections.sh.
if command -v node >/dev/null 2>&1; then
	cat > "$BANC5/rendu_fond.js" <<'JS'
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
  fetch:()=>Promise.reject(new Error("pas de pont dans le banc")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
const T = bac.__banc;
const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);
try {
  const mauvais = [];
  for (const pose of ["secu", "demon", "keyart", "nomad"]) {
    T.pose({ fond: { chemin: "/x", cle: pose, i: null }, fonds_perso: [] });
    const h = T.contenu("bureau");
    const sels = [...h.matchAll(/<button class="([^"]*)"\s+onclick="setFond\('(\w+)'\)"/g)]
      .filter(m => /\bsel\b/.test(m[1])).map(m => m[2]);
    if (sels.length !== 1 || sels[0] !== pose) mauvais.push(`${pose}->[${sels.join(",")}]`);
  }
  dit(mauvais.length === 0,
      `chaque fond intégré posé est le SEUL de son groupe à porter « sel » (${mauvais.length ? mauvais.join(" ") : "4/4"})`);
  T.pose({ fond: { cle: "", i: 1 }, fonds_perso: [{ i: 0 }, { i: 1 }, { i: 2 }] });
  const hg = T.contenu("bureau");
  const wsels = [...hg.matchAll(/<button class="wall-swatch([^"]*)"[\s\S]*?onclick="setFondFichier\((\d+)\)"/g)]
    .filter(m => /\bsel\b/.test(m[1])).map(m => Number(m[2]));
  dit(wsels.length === 1 && wsels[0] === 1,
      `la vignette posée (i=1) est la SEULE de la galerie à porter « sel » (${wsels.join(",") || "aucune"})`);
} catch (e) {
  dit(false, "le rendu s'est arrêté : " + e.message);
}
JS
	while IFS='|' read -r V M; do
		case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
	done < <(node "$BANC5/rendu_fond.js" "$APP")
else
	saute "node absent : le rendu du fond posé n'a PAS été éprouvé"
fi
#  CE QUE LE RENDU CI-DESSUS NE PEUT PAS VOIR : il pose etat.fond LUI-MÊME,
#  donc il resterait vert si settings.py et app.js divergeaient sur le NOM du
#  champ (mesuré : "cle" renommé en "key" d'un seul côté). Un contrôle textuel
#  du contrat complète le rendu, il ne le remplace pas.
grep -q '"cle": cle' "$SET" && grep -q '(etat.fond || {}).cle' "$APP" \
	&& ok "le moteur publie « cle » et la page lit « cle » — même contrat" \
	|| non "le nom de la clé publiée par le moteur et celui que la page lit ont divergé"
grep -q '^\.wall-swatch\.sel{' "$CSS" \
	&& ok "…et la feuille de style sait dessiner la vignette sélectionnée" \
	|| non "la classe « sel » est posée sur la vignette mais aucune règle CSS ne la dessine — rien ne changerait à l'écran"

#  ═══ UNE FONCTION QUI N'EST ATTEINTE PAR AUCUN BOUTON N'EXISTE PAS ═══
#  capture() était écrite, l'action « capture » était dans ACTIONS,
#  act_capture était implémentée et acceptait photo|zone|fenetre — et AUCUN
#  onclick ne l'appelait. Du code complet, relié des deux côtés, injoignable.
for M in photo zone fenetre; do
	grep -q "capture('$M')" "$APP" \
		&& ok "un bouton appelle capture('$M')" \
		|| non "capture('$M') n'est atteinte par aucun bouton — l'action est injoignable"
done

#  ═══ AUCUN BOUTON N'ANNONCE UN SUCCÈS QU'IL N'A PAS OBTENU ═══
#  « api('ouvrir','prive').then(()=>toast('… s'ouvre')) » : api() affiche déjà
#  « ✗ » et le motif quand ça rate, puis le .then() s'exécute QUOI QU'IL
#  ARRIVE et REMPLACE ce message par un succès. On lisait « Fichiers privés
#  s'ouvre » alors qu'il ne se passait rien.
python3 - "$APP" > "$BANC5/menteurs" <<'PY2'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
s = re.sub(r'/\*[\s\S]*?\*/', '', s)
#  un api(...) suivi d'un .then( qui ne regarde jamais la réponse
mauvais = re.findall(r'api\([^)]*\)\s*\.then\(\s*\(\s*\)\s*=>', s)
print("MENTEURS:%d" % len(mauvais))
PY2
LU_M="$(sed -n 's/^MENTEURS://p' "$BANC5/menteurs")"
[[ "${LU_M:-1}" -eq 0 ]] \
	&& ok "aucun bouton n'annonce le succès sans regarder la réponse" \
	|| non "$LU_M bouton(s) annoncent le succès quoi qu'il arrive — un échec passerait pour une réussite"

#  ═══ CHAQUE FENÊTRE DÉCLARÉE EST OFFERTE QUELQUE PART ═══
#  L'inverse du contrôle 3 : act_ouvrir servait 38 cibles, la page n'en
#  proposait que 35. « usb », « confidentialite » et « maj » étaient testées
#  ici alors qu'aucun écran ne pouvait les déclencher.
python3 - "$SET" "$APP" > "$BANC5/orphelines" <<'PY2'
import re, sys
py = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read()
deb = py.index("def act_ouvrir(arg):")
bloc = py[deb:py.index("\n\n\ndef ", deb)]
cibles = set(re.findall(r'^\s{8}"([a-z0-9-]+)":\s*lambda', bloc, re.M))
offertes = set(re.findall(r'btnOuvrir\(\s*"([a-z0-9-]+)"', js))
offertes |= set(re.findall(r"ouvrir\(\s*'([a-z0-9-]+)'", js))
offertes |= set(re.findall(r'ouvrir\(\s*"([a-z0-9-]+)"', js))
#  …et l'appel direct api("ouvrir", "x"), que « boost » emploie (app.js:396).
offertes |= set(re.findall(r'api\(\s*"ouvrir"\s*,\s*"([a-z0-9-]+)"', js))
offertes |= set(re.findall(r"api\(\s*'ouvrir'\s*,\s*'([a-z0-9-]+)'", js))
print("CIBLES:%d" % len(cibles))
print("ORPH:" + ",".join(sorted(cibles - offertes)))
PY2
LU_C="$(sed -n 's/^CIBLES://p' "$BANC5/orphelines")"
LU_O="$(sed -n 's/^ORPH://p' "$BANC5/orphelines")"
[[ "${LU_C:-0}" -ge 30 ]] \
	&& ok "les $LU_C fenêtres du moteur ont bien été relues" \
	|| non "la table act_ouvrir n'a pas été relue — le contrôle serait creux"
[[ -z "$LU_O" ]] \
	&& ok "chacune est offerte par au moins un bouton de la page" \
	|| non "fenêtre(s) servies par le moteur mais offertes nulle part : $LU_O"

# =============================================================================
titre "6. LE CLIC SE VOIT SUR TOUS LES BOUTONS — et un bouton grisé a l'air grisé"
# =============================================================================
#  ═══ DEUX DÉFAUTS DE LA MÊME FAMILLE : LE BOUTON NE DIT PAS SON ÉTAT ═══
#
#  · PENDANT UNE RECHERCHE DE MISES À JOUR, app.js pose « disabled » et
#    remplace le libellé par « Recherche en cours… ». Rien dans la feuille ne
#    le disait : le bouton gardait l'orange plein, le halo au survol et le
#    rétrécissement au clic. Il avait l'air cliquable alors qu'il ne
#    répondait plus.
#  · LE CLIC NE COLORAIT QUE LES « ghost ». Les boutons PLEINS — le premier
#    de chaque rangée, celui qu'on regarde en premier — ne faisaient que
#    rapetisser de 5 %.
#
#  ═══ CE BANC MESURE, IL NE RELIT PAS ═══
#  Un contrôle textuel (« la règle :disabled est-elle présente ? ») reste vert
#  quand la règle existe mais ne produit rien de lisible. Or c'est exactement
#  le piège rencontré ici : « opacity:.5 » était la voie évidente et elle FAIT
#  TOMBER le libellé de 5,87:1 à 2,21:1 — on rendrait illisible l'information
#  qu'on vient d'écrire dedans. Le banc résout donc les jetons de ui.css pour
#  les DEUX modes et les HUIT accents, et calcule les contrastes.
CONTRASTE="$RACINE/config/includes.chroot/usr/share/lexos/ui.css"
if [ ! -r "$CONTRASTE" ] || [ ! -r "$CSS" ]; then
	non "ui.css ou style.css introuvable — rien à mesurer"
elif [ -z "$PY" ]; then
	saut "python3 absent : les contrastes ne peuvent pas être mesurés"
else
	MESURE="$("$PY" - "$CONTRASTE" "$CSS" <<'PYEOF'
import re, sys, io

ui  = io.open(sys.argv[1], encoding="utf-8").read()
css = io.open(sys.argv[2], encoding="utf-8").read()

#  ═══ ON RETIRE LES COMMENTAIRES AVANT DE LIRE QUOI QUE CE SOIT ═══
#  Les deux feuilles CITENT des couleurs dans leurs explications — « #141416
#  sur un fond #0B0B0C », « --ac-lo VALAIT #5a2a0c ». Les lire ferait mesurer
#  la prose. C'est la famille d'erreur la plus fréquente de ce dépôt.
sans = lambda t: re.sub(r"/\*.*?\*/", "", t, flags=re.S)
ui, css = sans(ui), sans(css)

def bloc(texte, selecteur):
    m = re.search(re.escape(selecteur) + r"\s*\{([^}]*)\}", texte)
    return dict((k, v.strip()) for k, v in
                re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", m.group(1))) if m else {}

SOMBRE = bloc(ui, ":root")
CLAIR  = dict(SOMBRE); CLAIR.update(bloc(ui, ':root[data-mode="clair"]'))
ACCENTS = {m.group(1): dict((k, v.strip()) for k, v in
           re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", m.group(2)))
           for m in re.finditer(r':root\[data-accent="([^"]+)"\]\s*\{([^}]*)\}', ui)}

def lin(v):
    v /= 255
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
def rgb(h):
    h = h.strip().lstrip("#")
    if len(h) == 3: h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
def lum(h):
    r, g, b = rgb(h)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
def contraste(a, b):
    la, lb = lum(a), lum(b); hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def resous(val, table):
    #  var(--x) -> la valeur du jeton, une seule indirection suffit ici.
    m = re.fullmatch(r"var\((--[\w-]+)\)", val.strip())
    return table.get(m.group(1), "").strip() if m else val.strip()

def regle(motif):
    #  Le premier bloc dont le sélecteur contient ce motif.
    for m in re.finditer(r"([^{}]+)\{([^}]*)\}", css):
        if motif in m.group(1):
            return dict((k.strip(), v.strip()) for k, v in
                        re.findall(r"([\w-]+)\s*:\s*([^;]+)", m.group(2)))
    return {}

sortie = []
dit = lambda ok, txt: sortie.append(("OK|" if ok else "NON|") + txt)

# --- 1. Le bouton désactivé : lisible, et sans accent -----------------------
d = regle(".btn:disabled,")
if not d:
    dit(False, "aucune règle « .btn:disabled » : rien ne dit qu'un bouton est grisé")
elif "opacity" in d:
    #  ═══ ON DIT LE CHIFFRE, PAS « C'EST INTERDIT » ═══
    #  L'opacité est la voie évidente, et un banc qui se contente de la refuser
    #  se fait contourner par la personne suivante, qui la trouvera « jolie et
    #  sans danger ». On recalcule donc la conséquence exacte : l'opacité
    #  s'applique à TOUT l'élément — fond ET texte — et fond le tout dans la
    #  page, si bien que le libellé perd son contraste.
    try:
        alpha = float(d["opacity"].strip().rstrip(";"))
    except ValueError:
        alpha = 0.5
    for nom, table in (("sombre", SOMBRE), ("clair", CLAIR)):
        page = table.get("--bg", "#000000")
        melange = lambda av: "#%02X%02X%02X" % tuple(
            round(alpha * a + (1 - alpha) * b) for a, b in zip(rgb(av), rgb(page)))
        #  Le bouton plein : accent orange, libellé --ac-txt.
        c = contraste(melange(ACCENTS.get("orange", {}).get("--ac", "#E8590C")),
                      melange(ACCENTS.get("orange", {}).get("--ac-txt", "#000")))
        dit(False,
            f"mode {nom} : « opacity:{alpha:g} » fait tomber le libellé à {c:.2f}:1 "
            f"(seuil 4,5). C'est un message d'état — « Recherche en cours… » — "
            f"pas une décoration : retirer l'ACCENT dit « désactivé » sans le rendre illisible")
else:
    for nom, table in (("sombre", SOMBRE), ("clair", CLAIR)):
        fond  = resous(d.get("background", ""), table)
        texte = resous(d.get("color", ""), table)
        if not fond or not texte:
            dit(False, f"mode {nom} : fond ou texte du bouton désactivé introuvable")
            continue
        c = contraste(fond, texte)
        dit(c >= 4.5,
            f"mode {nom} : le libellé d'un bouton grisé reste lisible ({c:.2f}:1, seuil 4,5)")
    #  ET IL DOIT AVOIR PERDU L'ACCENT. C'est ça, « avoir l'air désactivé » :
    #  dans cette palette l'accent est le signe de « ceci répond ».
    brut = (d.get("background", "") + d.get("border-color", "")).replace(" ", "")
    dit("var(--ac)" not in brut and "var(--ac-hi)" not in brut,
        "le bouton grisé a perdu l'accent — il ne promet plus rien")
    dit("none" in d.get("box-shadow", ""), "et il ne garde pas le halo du survol")
    #  « opacity » ferait tomber le libellé à 2,21:1 — mesuré. C'est un
    #  message d'état (« Recherche en cours… »), pas une décoration.
    dit("opacity" not in d,
        "aucune opacité : elle rendrait illisible le message d'état du bouton")

# --- 2. L'appui colore les boutons pleins, et DIFFÉREMMENT du survol --------
survol = regle(".btn:hover{") or regle(".btn:hover")
appui  = regle(".btn:not(.ghost):not(.sel)")
if not appui:
    dit(False, "aucune règle d'appui pour les boutons pleins : le clic ne se verrait pas")
else:
    fs, fa = survol.get("background", "").replace(" ", ""), appui.get("background", "").replace(" ", "")
    dit(bool(fa) and fa != fs,
        f"l'appui d'un bouton plein diffère du survol ({fa or 'rien'} vs {fs or 'rien'})")
    #  Sur les HUIT accents : la couleur d'appui doit rester lisible, et rester
    #  distincte du survol. Un accent ajouté un jour sans y penser tomberait ici.
    mauvais_l, mauvais_d = [], []
    for nom, t in sorted(ACCENTS.items()):
        table = dict(SOMBRE); table.update(t)
        fond  = resous(appui.get("background", ""), table)
        texte = table.get("--ac-txt", "")
        hi    = table.get("--ac-hi", "")
        if not fond or not texte:
            mauvais_l.append(nom); continue
        if contraste(fond, texte) < 4.5: mauvais_l.append(f"{nom}({contraste(fond,texte):.2f})")
        if hi and fond.lower() == hi.lower(): mauvais_d.append(nom)
    dit(not mauvais_l,
        f"le libellé reste lisible sur la couleur d'appui, pour les {len(ACCENTS)} accents"
        + (" — sauf " + " ".join(mauvais_l) if mauvais_l else ""))
    dit(not mauvais_d,
        "la couleur d'appui n'est jamais celle du survol"
        + (" — sauf " + " ".join(mauvais_d) if mauvais_d else ""))

print("\n".join(sortie))
PYEOF
)"
	while IFS= read -r L; do
		[ -z "$L" ] && continue
		case "$L" in
			OK\|*)  ok  "${L#OK|}" ;;
			NON\|*) non "${L#NON|}" ;;
			*)      non "sortie inattendue du mesureur : $L" ;;
		esac
	done <<< "$MESURE"
fi

#  ═══ ET LE FLASH DOIT ATTEINDRE LES BOUTONS PLEINS ═══
#  Le style ne sert à rien si l'écouteur ne pose jamais la classe : « :active »
#  ne dure que le temps de l'appui — 40 ms sur un clic vif, invisible. C'est
#  « press » (160 ms) qui rend le retour perceptible, et il ne visait que les
#  « ghost ». On EXÉCUTE l'écouteur plutôt que de relire son sélecteur.
if command -v node >/dev/null 2>&1; then
	cat > "$BANC5/flash.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
let ecouteur = null;
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}},
             addEventListener:(t,f)=>{ if(t==="pointerdown") ecouteur = f; } },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont dans le banc")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), bac, {filename:"app.js"});
const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);
if (!ecouteur) { dit(false, "aucun écouteur « pointerdown » : rien ne pose le flash"); process.exit(0); }

//  Un faux bouton : il retient ce qu'on lui ajoute comme classe.
const bouton = (classes, desactive) => {
  const set = new Set(String(classes).split(/\s+/).filter(Boolean));
  const b = { disabled: !!desactive,
              classList: { add: c => set.add(c), remove: c => set.delete(c),
                           contains: c => set.has(c) },
              closest: sel => {
                const nom = sel.replace(/^\./, "").split(".");
                return nom.every(n => set.has(n)) ? b : null;
              } };
  b.aFlashe = () => set.has("press");
  return b;
};
const frappe = b => { ecouteur({ target: b }); return b.aFlashe(); };

dit(frappe(bouton("btn")),        "un bouton PLEIN flashe au clic (c'est ce qui manquait)");
dit(frappe(bouton("btn ghost")),  "un bouton d'action « ghost » flashe toujours");
dit(!frappe(bouton("btn sel")),   "un bouton DÉJÀ choisi ne flashe pas — il est déjà accentué");
dit(!frappe(bouton("btn", true)), "un bouton DÉSACTIVÉ ne flashe pas — il ne répond plus");
dit(!frappe(bouton("btn ghost", true)), "…un « ghost » désactivé non plus");
JS
	while IFS= read -r L; do
		[ -z "$L" ] && continue
		case "$L" in
			OK\|*)  ok  "${L#OK|}" ;;
			NON\|*) non "${L#NON|}" ;;
			*)      non "sortie inattendue du bac à sable : $L" ;;
		esac
	done < <(node "$BANC5/flash.js" "$APP" 2>&1)
else
	saut "node absent : le flash du clic n'est pas exécuté"
fi


printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[[ "$echoues" -eq 0 ]]
