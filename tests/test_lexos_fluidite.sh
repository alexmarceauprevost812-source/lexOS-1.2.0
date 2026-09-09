#!/usr/bin/env bash
# =============================================================================
#  Les Paramètres répondent tout de suite — et ne mentent jamais
# =============================================================================
#  ALEX : « je sais qu'il y a des problèmes de fluidité, mais il faudrait au
#  moins que les Paramètres soient fluides quand on change les couleurs et
#  qu'on prend des options — qu'elles soient bien sélectionnées. »
#
#  ═══ CE QUE COÛTAIT UN CLIC, MESURÉ ═══
#  Chaque action passait par rafraichir(), qui relit TOUT : trente-huit
#  collecteurs, soixante-dix appels de commandes externes — le Wi-Fi, le
#  Bluetooth, les imprimantes, les sorties audio, les écrans, les comptes,
#  les mises à jour — avant de redessiner. Sur un décor où chaque outil
#  répond en 0,25 s : 14,55 s pour changer une couleur.
#  Le réglage prenait tout de suite ; c'est l'affichage qui attendait.
#
#  ═══ CE QUE CE BANC EXIGE ═══
#  1. LE BOUTON S'ALLUME AU CLIC. vu() rend la valeur choisie avant même que
#     la machine ait répondu.
#  2. ET SI L'ACTION ÉCHOUE, LA PAGE REVIENT EN ARRIÈRE. C'est la moitié qui
#     compte le plus : un bouton resté allumé sur un réglage qui n'a pas pris
#     est exactement le mensonge du bogue du dock — la page qui affirmait
#     « c'est à droite » sans le savoir. On montre vite, on ne ment pas.
#  3. UN COLLECTEUR QUI N'ABOUTIT PAS REND « INCONNU » SANS BLOQUER LES
#     AUTRES. Une imprimante réseau éteinte ne doit pas figer les trente-six
#     autres sections.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$PAGE" "$MOTEUR"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
titre "1. LE BOUTON S'ALLUME AU CLIC, ET REVIENT SI L'ACTION ÉCHOUE"
# =============================================================================
if ! command -v node >/dev/null 2>&1; then
	saute "node absent : l'affichage optimiste n'a PAS été éprouvé"
else
	cat > "$BANC/optimiste.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
//  On charge la VRAIE page, puis on remplace ce qui touche au navigateur et
//  au pont. Rien de la logique éprouvée n'est réécrit ici.
const source = fs.readFileSync(process.argv[2], "utf8")
  + "\n;globalThis.__banc = {"
  + " vu, montre, tranche, choisir,"
  + " etat: () => etat, pose: e => { etat = e; },"
  + " attente: () => attente,"
  + " brancheApi: f => { api = f; },"
  + " brancheRafraichir: f => { rafraichir = f; } };\n";
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

(async () => {
  try {
    //  ═══ LE CAS QUI MARCHE ═══
    T.pose({accent:"orange", theme:"sombre", police:"defaut", dock:"droite"});
    let appels = 0;
    T.brancheApi(async () => { appels++; return {ok:true}; });

    //  Avant tout aller-retour : la page montre déjà le choix.
    T.montre("accent", "bleu");
    dit(T.vu("accent") === "bleu",
        "vu() rend le choix TOUT DE SUITE, avant la réponse de la machine");
    dit(T.etat().accent === "orange",
        "…sans toucher à l'état réel tant que la machine n'a pas répondu");
    T.tranche("accent");
    dit(T.vu("accent") === "orange",
        "et quand la machine tranche, c'est son mot qui reprend la main");

    //  ═══ LE CAS QUI MARCHE, EN ENTIER ═══
    let pendant = null;
    T.brancheApi(async () => { pendant = T.vu("accent"); return {ok:true}; });
    await T.choisir("accent", "vert", "accent");
    dit(pendant === "vert",
        "pendant l'aller-retour, le bouton choisi est DÉJÀ allumé");
    dit(T.etat().accent === "vert", "…et l'état réel suit quand ça réussit");
    dit(Object.keys(T.attente()).length === 0,
        "…et rien ne reste en attente après coup");

    //  ═══ LE CAS QUI ÉCHOUE — CELUI QUI COMPTE ═══
    T.pose({accent:"orange", theme:"sombre", police:"defaut", dock:"droite"});
    let rafraichi = 0;
    T.brancheRafraichir(async () => { rafraichi++; });
    T.brancheApi(async () => ({ok:false, erreur:"commande refusée"}));
    await T.choisir("accent", "rouge", "accent");
    dit(T.vu("accent") === "orange",
        "ÉCHEC : le bouton revient à la valeur RÉELLE, il ne reste pas allumé");
    dit(T.etat().accent === "orange",
        "…et l'état réel n'a pas été modifié en douce");
    dit(Object.keys(T.attente()).length === 0,
        "…et la valeur optimiste est bien jetée");
    dit(rafraichi === 1,
        "…et la page relit la machine, au cas où l'échec l'aurait laissée ailleurs");

    //  ═══ LE MÊME PATRON POUR LE DOCK ═══
    //  C'est le réglage sur lequel Alex s'est plaint deux fois.
    T.pose({dock:"droite"});
    T.brancheApi(async () => ({ok:true}));
    let vuPendant = null;
    T.brancheApi(async () => { vuPendant = T.vu("dock"); return {ok:true}; });
    await T.choisir("dock", "bas", "dock");
    dit(vuPendant === "bas", "le dock aussi s'allume au clic");
    console.log("FIN|");
  } catch (e) {
    console.log("NON|le banc a levé : " + (e && e.message));
    console.log("FIN|");
  }
})();
JS
	SORTIE="$(timeout 60 node "$BANC/optimiste.js" "$PAGE" 2>&1 | grep -E '^(OK|NON|FIN)\|' || true)"
	grep -q '^FIN|' <<< "$SORTIE" || non "l'épreuve de l'affichage optimiste n'est pas allée au bout"
	while IFS='|' read -r V M; do
		case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
	done <<< "$SORTIE"
fi

# =============================================================================
titre "2. LA PAGE LIT vu(), PAS etat, LÀ OÙ ELLE MONTRE UN CHOIX"
# =============================================================================
#  Un seul bouton oublié suffit à ramener l'attente : celui-là resterait
#  éteint jusqu'au retour de la machine, au milieu de ses voisins allumés.
JS_NU="$BANC/app.nu.js"
sed -e 's#^\s*//.*##' "$PAGE" > "$JS_NU"
OUBLIS=0
#  ═══ CE CONTRÔLE A LAISSÉ PASSER SA MUTATION AU PREMIER JET ═══
#  Il cherchait « etat.CLE » SUIVI d'une comparaison. Or la page écrit
#  « n===etat.accent?"sel" » : la comparaison est AVANT. Remettre un bouton
#  sur etat.accent ne le faisait donc pas rougir — le défaut même qu'il doit
#  attraper. On vise maintenant la CO-PRÉSENCE, sur une ligne de code, de
#  « etat.<clé> » et du mot « sel » : c'est la forme de toutes les
#  sélections de ce fichier, quel que soit le sens de la comparaison.
for CLE in theme accent police dock; do
	#  Pas de tuyau vers « grep -q » : sous pipefail, la course fait perdre
	#  le verdict (garde-fou de la CI). La substitution de processus sort le
	#  producteur du tuyau.
	if grep -q '"sel"' < <(grep -nE "etat\.${CLE}\b" "$JS_NU"); then
		non "le bouton de « $CLE » compare encore etat.$CLE : il resterait éteint pendant l'aller-retour"
		OUBLIS=1
	fi
done
[ "$OUBLIS" = 0 ] && ok "les quatre réglages (thème, accent, police, dock) montrent vu()"

grep -q 'function vu(' "$JS_NU" && grep -q 'function choisir(' "$JS_NU" \
	&& ok "vu() et choisir() existent — le patron est écrit une fois, pas recopié" \
	|| non "l'affichage optimiste n'est plus branché"

# =============================================================================
titre "3. UN COLLECTEUR QUI N'ABOUTIT PAS NE BLOQUE PAS LES AUTRES"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le moteur n'a PAS été éprouvé"
else
	SORTIE="$(cd "$RACINE" && timeout 300 python3 - "$RACINE/config/includes.chroot/usr/lib/lexos" <<'PY' 2>&1 | grep -E '^(OK|NON|FIN)\|' || true
import sys, time
sys.path.insert(0, sys.argv[1])
import settings
def dit(bon, m): print(("OK|" if bon else "NON|") + m)

#  UN OUTIL QUI NE RÉPOND JAMAIS. On remplace _sortie par une version qui
#  dort plus longtemps que le délai autorisé : c'est exactement bluetoothctl
#  sans adaptateur, ou une imprimante réseau éteinte.
vrai = settings._sortie
def lent(argv, **kw):
    time.sleep(kw.get("timeout", 10) + 0.5)
    return ""
settings._sortie = lent
t0 = time.perf_counter()
try:
    e = settings.etat()
finally:
    settings._sortie = vrai
duree = time.perf_counter() - t0

dit(isinstance(e, dict) and len(e) > 10,
    "avec TOUS les outils muets, etat() rend quand même un état complet")
#  LE PLAFOND EST LE DÉLAI ANNONCÉ, PAS UN CHIFFRE CONFORTABLE.
#  Première version : « < 120 s ». Elle passait au vert sur une
#  implémentation qui mettait 63 s — la fermeture du pool attendait les
#  fils qu'on venait d'abandonner, et le délai ne tenait pas. Un plafond
#  trop généreux ne mesure rien.
plafond = settings._ETAT_DELAI + 3
dit(duree < plafond,
    "…et il tient son délai : %.1f s (plafond %.0f s), au lieu d'attendre "
    "chaque outil bout à bout" % (duree, plafond))
inconnues = [k for k, v in e.items() if v is None]
dit(len(inconnues) > 0,
    "…et ce qu'il n'a pas pu lire vaut « inconnu » (%d clés), jamais une "
    "valeur inventée" % len(inconnues))
#  CE QUI NE DÉPEND D'AUCUN OUTIL DOIT TOUJOURS ÊTRE LÀ. C'est ce qui
#  permet à la page de se dessiner même quand la machine ne répond à rien :
#  le thème, l'accent, la police, le nom de la machine. Compter « au moins
#  N clés lues » ne voulait rien dire — avec TOUS les outils muets, il est
#  normal que la plupart soient inconnues.
socle = ["perf", "theme", "accent", "police", "hote", "version"]
manquant = [k for k in socle if e.get(k) in (None, "")]
dit(not manquant,
    "…et ce qui ne dépend d'aucun outil est toujours là : la page peut se "
    "dessiner (%s)" % ", ".join(socle))

#  ═══ ET ON NE RELIT QUE CE QU'ON DEMANDE ═══
settings._sortie = vrai
t0 = time.perf_counter(); une = settings.etat(cles=["dock"]); d1 = time.perf_counter() - t0
t0 = time.perf_counter(); tout = settings.etat();             d2 = time.perf_counter() - t0
dit(len(une) < len(tout),
    "etat(cles=[…]) rend moins que tout (%d clés contre %d)" % (len(une), len(tout)))
dit("dock" in une, "…et la clé demandée en fait partie")
dit(d1 <= d2 + 0.05,
    "…et ça ne coûte pas plus cher (%.3f s contre %.3f s)" % (d1, d2))
print("FIN|")
PY
)"
	grep -q '^FIN|' <<< "$SORTIE" || non "l'épreuve du collecteur muet n'est pas allée au bout"
	while IFS='|' read -r V M; do
		case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
	done <<< "$SORTIE"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
