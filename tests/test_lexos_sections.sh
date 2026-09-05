#!/usr/bin/env bash
# =============================================================================
#  Éprouver TOUTES les sections des Paramètres — une par une, rendues pour de vrai
# =============================================================================
#  CE BANC EXISTE À CAUSE D'UNE PAGE QUI NE S'AFFICHAIT PAS DU TOUT.
#
#  « Diagnostic » écrivait « corps.innerHTML = … » puis « break », alors que
#  toutes les autres sections RENDENT une chaîne. Deux fautes d'un coup :
#  « corps » n'existe nulle part dans le fichier — une ReferenceError à chaque
#  clic — et la fonction ne rendait rien.
#
#  ET LE SYMPTÔME NE RESSEMBLAIT PAS À UNE ERREUR. rendSection() fait
#  « content.innerHTML = contenu(...) » : quand contenu() lève, la droite
#  n'est jamais évaluée, l'affectation n'a pas lieu, et l'écran GARDE LA
#  SECTION PRÉCÉDENTE. On cliquait « Diagnostic » et il ne se passait rien —
#  pas de page blanche, pas de message : rien. « node --check » ne dit que
#  ceci : le fichier se parse. Il se parsait très bien.
#
#  Trente-six sections, et aucun banc ne les rendait une par une. Il y en a un
#  maintenant, et il éprouve quatre choses pour CHACUNE :
#
#    1. elle ne lève pas ;
#    2. elle rend quelque chose (pas « undefined », pas du vide) ;
#    3. chaque bouton vise une fonction QUI EXISTE — un gestionnaire mort est
#       un bouton muet, et ce dépôt en a déjà eu trois d'un coup sur l'écran
#       de connexion ;
#    4. chaque entrée du menu de gauche a bien une section derrière elle.
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

[ -r "$PAGE" ] || { echo "introuvable : $PAGE"; exit 1; }
command -v node >/dev/null 2>&1 || { saute "node absent : rien n'a été rendu"; exit 0; }

cat > "$BANC/rendu.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  + "\n;globalThis.__banc = { contenu, pose: e => { etat = e; }, nav: NAV };\n";
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
  /*  DEUX ÉTATS, ET LES DEUX COMPTENT.
      « rien » est l'état d'une machine qui ne répond à aucune question : une
      page doit tenir DEBOUT là-dessus, parce que c'est ce que voit quelqu'un
      dont l'outil manque ou plante. « plein » est l'état réel de la machine
      qui fait tourner le banc, tel que settings.py le rend. */
  const plein = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  const sections = [];
  for (const g of T.nav) for (const it of g.items) sections.push(it);

  dit(sections.length >= 30,
      `le menu de gauche annonce ${sections.length} sections`);

  for (const [nom, etat] of [["sans rien", {}], ["état réel", plein]]) {
    T.pose(etat);
    const casses = [], vides = [];
    for (const [cle, , label] of sections) {
      let h;
      try { h = T.contenu(cle); }
      catch (e) { casses.push(`${cle} (${e.message})`); continue; }
      if (typeof h !== "string" || h.trim().length < 20) vides.push(cle);
    }
    dit(casses.length === 0,
        `${nom} : aucune section ne lève (${casses.join(", ") || "36/36"})`);
    dit(vides.length === 0,
        `${nom} : aucune section ne rend du vide (${vides.join(", ") || "toutes rendent"})`);
  }

  /*  CHAQUE BOUTON VISE UNE FONCTION QUI EXISTE.
      Un gestionnaire mort ne se voit pas : le bouton s'affiche, se clique, et
      la console — que personne n'ouvre — dit « x is not defined ». */
  T.pose(plein);
  const manquantes = new Set();
  const vues = new Set();
  for (const [cle] of sections) {
    let h = "";
    try { h = T.contenu(cle) || ""; } catch (e) { continue; }
    for (const m of h.matchAll(/on(?:click|change|input|keydown)="([^"]*)"/g)) {
      for (const f of m[1].matchAll(/\b([A-Za-z_$][\w$]*)\s*\(/g)) {
        const nom = f[1];
        //  Les mots-clés et les méthodes ne sont pas des fonctions de la page.
        if (["if", "for", "while", "return", "typeof", "event"].includes(nom)) continue;
        if (m[1].includes("." + nom + "(")) continue;
        vues.add(nom);
        if (typeof bac[nom] !== "function") manquantes.add(`${nom} (${cle})`);
      }
    }
  }
  dit(vues.size >= 20, `${vues.size} fonctions différentes sont appelées par les boutons`);
  dit(manquantes.size === 0,
      `chaque bouton vise une fonction qui existe (${[...manquantes].join(", ") || "aucune manquante"})`);

  /*  ═══ CHAQUE ATTRIBUT DOIT ÊTRE DU JAVASCRIPT VALIDE ═══
      Un bouton mort ne se voit pas : il s'affiche, se clique, et l'erreur va
      dans une console que personne n'ouvre.

      LE CAS RÉEL QUI A AMENÉ CE CONTRÔLE : un compte nommé « o'brien »
      produisait onclick="utilGeste('motdepasse','o'brien')". Le navigateur
      décode les entités de l'attribut, PUIS lit le JavaScript, et trouve
      « missing ) after argument list ». Le Wi-Fi avait le même défaut depuis
      plus longtemps, avec un remède qui n'en était pas un : « &#39; » se
      décode EN apostrophe avant que le JavaScript soit lu, donc la chaîne se
      ferme quand même — un réseau « Chez Léa's » avait un bouton mort.

      ON EMPOISONNE TOUT L'ÉTAT et on rend tout. Chaque chaîne de l'état reçoit
      une apostrophe, un antislash, un guillemet, un chevron et une esperluette ;
      puis chaque attribut rendu est décodé comme le ferait le navigateur et
      passé à new Function(). C'est la seule façon de couvrir les valeurs qui
      viennent du système — noms de comptes, de réseaux, de sorties audio,
      d'écrans, de comptes en nuage — sans écrire un décor par section. */
  const POISON = "a'b\\c\"d<e&f";
  /*  ON N'EMPOISONNE QUE LES CHAMPS DE NOM, ET C'EST UNE CORRECTION.
      La première version empoisonnait TOUTES les chaînes de l'état. Elle
      changeait alors le contrôle du programme autant que ses données : w.radio
      ne valait plus « enabled », donc la page Wi-Fi n'affichait plus aucun
      réseau, donc le bouton qu'on voulait éprouver n'était pas rendu. Mesuré :
      en remettant le faux remède « &#39; » du Wi-Fi, le banc restait VERT.

      On empoisonne donc les clés qui portent un NOM ou un IDENTIFIANT — celles
      qui finissent dans un onclick — et on laisse intactes celles qui décident
      de ce qui s'affiche. */
  const CLES_NOM = ["ssid", "adresse", "nom", "dev", "cle", "id", "complet"];
  const empoisonne = (v, cle) => {
    if (typeof v === "string") return CLES_NOM.includes(cle) ? v + POISON : v;
    if (Array.isArray(v)) return v.map((x) => empoisonne(x, cle));
    if (v && typeof v === "object") {
      const o = {};
      for (const k of Object.keys(v)) o[k] = empoisonne(v[k], k);
      return o;
    }
    return v;
  };
  const decodeHtml = (x) => x.replace(/&quot;/g, '"').replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">").replace(/&#39;/g, "'").replace(/&amp;/g, "&");

  /*  ON COMPLÈTE L'ÉTAT AVANT DE L'EMPOISONNER, ET C'EST NÉCESSAIRE.
      L'état réel vient de la machine qui fait tourner le banc : ni réseau
      Wi-Fi, ni appareil Bluetooth, ni sortie audio, ni compte en nuage. Les
      boutons de ces listes ne sont donc JAMAIS rendus, et le poison ne les
      atteint pas. Mesuré : en remettant le faux remède « &#39; » du Wi-Fi, le
      banc restait vert — il ne rendait aucun réseau.

      On pose donc une liste de chaque sorte, avec les clés que la page lit
      vraiment. Ces valeurs ne servent qu'à faire NAÎTRE les boutons ; ce sont
      les caractères du poison, ajoutés juste après, qui les éprouvent. */
  const OVERLAY = {
    wifi: {radio:"enabled", reseau:"Reseau", internet:"full", auto:true,
           reseaux:[{ssid:"Reseau", actif:false, protege:true, force:70},
                    {ssid:"Autre", actif:true, protege:false, force:40}]},
    bluetooth: {radio:true, appareils:[{nom:"Casque", adresse:"AA:BB:CC:DD:EE:FF",
                 genre:"audio-headset", connecte:false, appaire:true},
                {nom:"Souris", adresse:"11:22:33:44:55:66", connecte:true, appaire:true}]},
    son: {muet:false, volume:55, sorties:[{nom:"Haut-parleurs", actif:true},
                                          {nom:"Casque", actif:false}]},
    //  « ecrans » est une LISTE, pas un objet : la forme vient de
    //  _ecrans_etat(), pas d'une supposition. Un décor de la mauvaise forme
    //  fait lever la section et donne un rouge qui ne parle pas du code.
    ecrans: [{nom:"eDP-1", principal:true, definition:"1920x1080",
              modes:["1920x1080","1280x720"]}],
    amovibles: {monter:true, ouvrir:true, photos:false, musique:false},
    //  Les supports branchés vivent sous « usb », pas sous « amovibles » :
    //  relevé dans la page, pas supposé. Sans cette liste, le bouton
    //  « Éjecter » n'est jamais rendu et le poison ne l'atteint pas.
    usb: [{nom:"Clé", taille:"32 Go", dev:"/dev/sdb1", monte:"/media/x", disque:false}],
    comptes: {dispo:true, rclone:true, gvfs:true, nuage:"/home/x/Nuage",
              comptes:[{nom:"drive", monte:true},{nom:"photos", monte:false}],
              services:[{cle:"google", type:"drive", nom:"Google Drive", note:""}]},
    utilisateurs: {dispo:true, nb_admins:2, auto:"", lightdm:true,
      comptes:[{nom:"un", complet:"Un", uid:1000, admin:true, moi:false,
                verrou:"actif", derniere:"jamais", groupes:"sudo"},
               {nom:"deux", complet:"Deux", uid:1001, admin:false, moi:true,
                verrou:"verrouille", derniere:"hier", groupes:"aucun"}]},
    defaut: {categories:[{cle:"images", titre:"Images", courant:"a.desktop",
              courant_nom:"A", choix:[{id:"a.desktop", nom:"A"},{id:"b.desktop", nom:"B"}]}]},
    clavier: {liste:"ca,us", bascule:"alt-maj", max:4,
      actives:[{cle:"ca-fr", nom:"Canadien"},{cle:"us", nom:"US"}],
      catalogue:[{cle:"fr", nom:"Français"}], bascules:[{cle:"alt-maj", nom:"Alt+Maj"}]},
    partage: {dispo:true, nom:"poste", nom_regex:"^x$", actif:true, recus:"/r",
              minutes:15, kde:true, bt:true, qr:true, ssh_serveur:false},
    terminal: {dispo:true, mode:"auto", effectif:"nuit", bureau:"sombre",
               debut:"07:00", fin:"19:00", minuterie:true},
    bienetre: {dispo:true, tourne:true, minutes:60, limite:120,
               pauses_installe:true, pauses_actif:true,
               nuit_installe:true, nuit_actif:false,
               semaine:[{jour:"2026-01-01", nom:"lun", minutes:30}], total_semaine:30},
    recherche: {dispo:true, plocate:true, index:true, index_jours:3,
                catfish:true, max:30},
    imprimantes: {dispo:true, liste:[{nom:"HP", etat:"prête", defaut:true}]},
    couleurs: {dispo:true, ecrans:[{nom:"eDP-1", profil:"sRGB"}]},
    tablette: {branchee:true, noms:["Wacom"]},
    mac: {apple:true, modele:"MacBookPro11,1"},
    distant: {outil:"x11vnc", actif:true, adresses:["192.168.1.2"], ports:"5900",
              remmina:true, ssh:true},
  };
  const complet = Object.assign({}, plein, OVERLAY);
  T.pose(empoisonne(complet));
  const casses2 = [], mauvais = [];
  for (const [cle] of sections) {
    let h;
    try { h = T.contenu(cle) || ""; }
    catch (e) { casses2.push(`${cle} (${e.message})`); continue; }
    for (const m of h.matchAll(/\son(?:click|change|input|keydown)="([^"]*)"/g)) {
      const code = decodeHtml(m[1]);
      try { new Function(code); }
      catch (e) { mauvais.push(`${cle} : ${code.slice(0, 70)}`); }
    }
  }
  dit(casses2.length === 0,
      `état empoisonné : aucune section ne lève (${casses2.join(", ") || "36/36"})`);
  dit(mauvais.length === 0,
      `état empoisonné : chaque attribut reste du JavaScript valide (${
        mauvais.length ? mauvais.slice(0, 3).join(" | ") : "tous"})`);

  /*  ET CHAQUE SECTION A UN TITRE. Une page sans <h2> est une page dont on ne
      sait pas où l'on est. */
  T.pose(plein);
  const sansTitre = [];
  for (const [cle] of sections) {
    let h = "";
    try { h = T.contenu(cle) || ""; } catch (e) { continue; }
    if (!/<h2[ >]/.test(h)) sansTitre.push(cle);
  }
  dit(sansTitre.length === 0,
      `chaque section a un titre (${sansTitre.join(", ") || "toutes"})`);

  /*  L'INVENTAIRE, pour mémoire — pas un contrôle : une section sans réglage
      n'est pas forcément un défaut (« À propos » n'a rien à régler), et
      figer ces nombres empêcherait la page d'évoluer. */
  const compte = [];
  for (const [cle, , label] of sections) {
    let h = "";
    try { h = T.contenu(cle) || ""; } catch (e) { continue; }
    const sansOuvrir = h.replace(/onclick="ouvrir\('[^']*'\)"/g, "");
    const n = (sansOuvrir.match(/on(?:click|change|input|keydown)=/g) || []).length;
    if (n === 0) compte.push(label);
  }
  console.log("INFO|sections sans réglage sur CETTE machine : " +
              (compte.join(", ") || "aucune"));
} catch (e) {
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS

# =============================================================================
titre "Les 36 sections, rendues une par une"
# =============================================================================
#  L'état réel de la machine vient de settings.py lui-même : c'est ce que la
#  page reçoit vraiment. S'il n'est pas lisible ici (python3 absent, outils
#  manquants), on se rabat sur un état vide — les contrôles « sans rien »
#  restent joués, ceux « état réel » se répètent dessus.
ETAT="$BANC/etat.json"
if command -v python3 >/dev/null 2>&1; then
	( cd "$RACINE" && PATH="$RACINE/config/includes.chroot/usr/bin:$PATH" \
		timeout 180 python3 -c "
import sys, json
sys.path.insert(0, 'config/includes.chroot/usr/lib/lexos')
import settings
print(json.dumps(settings.etat(), ensure_ascii=False, default=str))
" > "$ETAT" 2>/dev/null ) || : > "$ETAT"
fi
[ -s "$ETAT" ] || printf '{}' > "$ETAT"

SORTIE="$(node "$BANC/rendu.js" "$PAGE" "$ETAT" 2>&1 | grep -E '^(OK|NON|INFO|FIN)\|' || true)"
if [ -z "$SORTIE" ]; then
	non "rien n'a été rendu — app.js n'a pas pu être chargé"
elif ! grep -q '^FIN|' <<< "$SORTIE"; then
	non "le rendu s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
	printf '%s\n' "$SORTIE" | while IFS='|' read -r V M; do
		[ "$V" = "NON" ] && printf '  \033[31m❌\033[0m %s\n' "$M"
	done
	ECHOUES=$((ECHOUES + 1))
else
	while IFS='|' read -r V M; do
		case "$V" in
			OK)   ok "$M" ;;
			NON)  non "$M" ;;
			INFO) saute "$M" ;;
		esac
	done <<EOF
$SORTIE
EOF
fi

# =============================================================================
titre "Aucune section ne se rend en écrivant dans le document"
# =============================================================================
#  C'est la forme exacte du défaut de « Diagnostic ». contenu() RENVOIE du
#  HTML ; une section qui écrit dans le document au lieu de rendre laisse la
#  page précédente à l'écran, sans erreur visible.
#  On greppe un FICHIER, commentaires retirés — l'explication du correctif
#  cite justement « corps.innerHTML », et elle est dans un bloc /* … */, pas
#  derrière un « // ». Retirer les deux formes, donc : un contrôle rouge à
#  cause du texte qui explique le correctif est le pire des faux positifs.
python3 - "$PAGE" > "$BANC/page.js" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
src = re.sub(r"(?m)//.*$", "", src)
sys.stdout.write(src)
PY
if grep -nE '\bcorps\.innerHTML' "$BANC/page.js"; then
	non "une section écrit encore dans « corps », qui n'existe pas"
else
	ok "aucune section n'écrit dans « corps »"
fi
if grep -q . < <(grep -nE '^\s+break;\s*$' "$BANC/page.js"); then
	non "un « break » traîne dans contenu() : la section rendrait « undefined »"
else
	ok "aucun « break » ne remplace un « return » dans contenu()"
fi

# =============================================================================
titre "Les boutons d'action répondent au clic"
# =============================================================================
#  ALEX : « beaucoup de boutons ne changent pas de couleur en orange quand on
#  clique dessus. » Ce n'était pas un problème de JavaScript — les boutons
#  marchaient, ils ne le DISAIENT pas. Le survol posait « var(--bg-hi) »,
#  #141416 sur un fond #0B0B0C : invisible. Et au clic, le seul retour était
#  un rétrécissement de 5 %, qu'on ne remarque pas.
#
#  POURQUOI CE BLOC EST ICI ET PAS DANS UN TROISIÈME BANC. La consigne
#  nommait test_lexos_app_settings.sh et test_verifier_parametres.sh — mais
#  MESURÉ, le premier éprouve « lexos-app-settings » (les réglages de LA
#  FENÊTRE, un autre outil) et le second le contrôle 16 du vérificateur.
#  Ni l'un ni l'autre ne lit la feuille des Paramètres. Celui-ci, si : il
#  charge app.js pour de vrai. C'est le banc des Paramètres, c'est ici que ça
#  va.
STYLE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/style.css"
if [ ! -r "$STYLE" ]; then
	non "feuille des Paramètres introuvable : $STYLE"
else
	#  On isole chaque règle par son sélecteur : trouver la bonne valeur dans
	#  la mauvaise règle serait un faux vert.
	regle() { awk -v c="$1" 'index($0, c)==1 { d=1 } d { print; if (/}/) exit }' "$STYLE"; }

	SURVOL="$(regle '.btn.ghost:hover')"
	if grep -q 'border-color:var(--ac)' <<< "$SURVOL" ; then
		ok "le survol accentue la BORDURE — plus seulement un gris invisible"
	else
		non "le survol ne change pas la bordure : « c'est cliquable » ne se lit toujours pas"
	fi

	#  ═══ LES DEUX SÉLECTEURS PARTAGENT LE MÊME BLOC ═══
	#  « :active » ne dure que le temps de l'appui — 40 ms pour un clic vif,
	#  invisible. « press » est posée par app.js et retirée après 160 ms.
	#  S'ils divergeaient, le flash d'un clic rapide n'aurait pas la même
	#  allure que celui d'un clic maintenu, et personne ne comprendrait
	#  pourquoi. On exige donc qu'ils soient déclarés ENSEMBLE.
	if grep -q '^\.btn\.ghost:active,$' "$STYLE" \
	   && grep -q '^\.btn\.ghost\.press{' "$STYLE"; then
		ok ":active et .press partagent le même bloc — même flash au clic vif et au clic tenu"
	else
		non ":active et .press ne sont pas déclarés ensemble : deux flashs différents"
	fi

	PRESSE="$(regle '.btn.ghost:active,')"
	if grep -q 'background:var(--ac)' <<< "$PRESSE" ; then
		ok "le clic pose l'accent en fond — « c'est parti » se voit"
	else
		non "le clic ne pose pas de fond accentué : aucun retour de couleur"
	fi

	#  ═══ L'ASSERTION QUI COMPTE ═══
	#  --ac et ses variantes sont réécrites À CHAUD quand Alex change
	#  d'accent. Une couleur écrite en dur ne suivrait pas : les boutons
	#  resteraient orange sur un thème bleu. Ça ne casse pas bruyamment — ça
	#  ne se voit qu'en changeant d'accent, ce que personne ne fait en
	#  vérifiant un correctif.
	#  ═══ ON DÉCOMMENTE D'ABORD, ET CE N'EST PAS UNE COMPLAISANCE ═══
	#  Ce contrôle a rougi sur SA PROPRE JUSTIFICATION : le commentaire qui
	#  explique le choix de la couleur d'appui cite la mesure — « #FF7A33 ->
	#  #E8590C » — et le contrôle lisait le fichier brut. La feuille, elle,
	#  n'avait aucune couleur en dur.
	#
	#  C'est la famille d'erreur la plus fréquente de ce dépôt, prise ici pour
	#  la neuvième fois. Et la mauvaise réponse serait de retirer les chiffres
	#  du commentaire : dans cette maison, une décision se justifie par sa
	#  mesure, et un commentaire qui n'ose plus citer une couleur ne vaut plus
	#  rien. C'est le contrôle qui doit lire du CSS, pas de la prose.
	#
	#  awk plutôt que sed : un commentaire CSS s'étend sur plusieurs lignes,
	#  et « s|/\*.*\*/||g » ne verrait que ceux qui tiennent sur une seule.
	CODE_STYLE="$(awk '
		{ ligne = $0; sortie = ""
		  while (length(ligne) > 0) {
		    if (dedans) { i = index(ligne, "*/")
		                  if (i == 0) { ligne = "" } else { dedans = 0; ligne = substr(ligne, i + 2) } }
		    else        { i = index(ligne, "/*")
		                  if (i == 0) { sortie = sortie ligne; ligne = "" }
		                  else { sortie = sortie substr(ligne, 1, i - 1); dedans = 1; ligne = substr(ligne, i + 2) } } }
		  print sortie }' "$STYLE")"
	#  Garde contre le vert sur du vide : si le décommentage rendait un fichier
	#  quasi nul, l'absence ci-dessous ne prouverait plus rien.
	if [ "$(grep -c . <<< "$CODE_STYLE")" -lt 60 ]; then
		non "le décommentage de la feuille n'a presque rien laissé — contrôle invalide"
		CODE_STYLE=""
	fi
	DUR="$(grep -n '#E8590C\|#FF7A33\|#A84007\|232, 89, 12' <<< "$CODE_STYLE" || true)"
	if [ -z "$DUR" ]; then
		ok "aucune couleur d'accent écrite en dur dans la feuille"
	else
		non "couleur d'accent en dur — les boutons ne suivraient pas « lexos accent » :"
		printf '%s\n' "$DUR" | sed 's/^/       /'
	fi

	#  Sans ces deux propriétés en transition, le retour du flash au gris
	#  serait brutal : la couleur sauterait pendant que la taille revient en
	#  douceur.
	TRANS="$(regle '.btn{transition:')"
	if grep -q 'background-color' <<< "$TRANS" \
	   && grep -q 'border-color' <<< "$TRANS" ; then
		ok "background-color et border-color sont en transition — le retour est doux"
	else
		non "la couleur n'est pas en transition : le retour au gris serait brutal"
	fi

	#  ═══ LA COULEUR SURVIT À prefers-reduced-motion ═══
	#  Pour qui demande moins d'animation, le flash de couleur est le SEUL
	#  retour disponible. Le supprimer aussi laisserait ces gens-là sans
	#  aucun signe que le clic a été pris.
	#  ON DÉCOUPE LE BON BLOC, ET C'EST UNE LEÇON PAYÉE ICI. La feuille
	#  contient DEUX « @media (prefers-reduced-motion » : celui de l'aiguille
	#  du cadran, écrit sur UNE SEULE LIGNE, et celui des boutons. Une
	#  première version partait du premier et, faute de « } » en début de
	#  ligne, avalait cent lignes jusqu'à la fermeture du SECOND — en
	#  ramassant au passage la règle « .btn{transition:…background-color…} »
	#  qui vit en dehors de toute media query. Le contrôle trouvait donc
	#  « background-color » quoi qu'il arrive : une mutation qui vidait le
	#  vrai bloc restait verte.
	#  On ne retient donc que les blocs OUVERTS EN FIN DE LIGNE — le
	#  une-ligne ne peut plus être pris pour un début — et on garde le
	#  dernier, celui qui porte les boutons.
	RM="$(awk '
		/^@media \(prefers-reduced-motion[^}]*\{$/ { d = 1; buf = "" }
		d { buf = buf $0 "\n" }
		d && /^}/ { dernier = buf; d = 0 }
		END { printf "%s", dernier }
	' "$STYLE")"
	if grep -q 'transform:none' <<< "$RM" \
	   && grep -q 'background-color' <<< "$RM" ; then
		ok "en mouvement réduit, le transform part mais la COULEUR reste"
	else
		non "le mode « mouvement réduit » emporte la couleur avec le mouvement : plus aucun retour"
	fi

	#  Les boutons de CHOIX gardent leur état permanent : c'est ce qui
	#  distingue un réglage actif d'une commande déjà lancée.
	SEL="$(regle '.btn.sel{')"
	if grep -q 'background:var(--ac)' <<< "$SEL" ; then
		ok ".btn.sel pose toujours l'accent — l'état des boutons de choix est intact"
	else
		non ".btn.sel ne pose plus l'accent : on ne verrait plus quel réglage est actif"
	fi
fi

#  ═══ POSÉE EN UN SEUL ENDROIT, PAS 47 FOIS ═══
#  Les boutons sont écrits avec des « onclick » en ligne et chaque section se
#  redessine entièrement : accrocher quoi que ce soit bouton par bouton
#  serait à refaire à chaque rendu, et on en oublierait.
N_PRESS="$(grep -c 'classList.add("press")' "$PAGE" || true)"
if [ "$N_PRESS" = "1" ]; then
	ok "« press » est posée en UN SEUL endroit (écouteur délégué)"
else
	non "« press » est posée $N_PRESS fois : un écouteur par bouton se perdra au prochain rendu"
fi

#  Et jamais sur un bouton déjà choisi : il est accentué en permanence, les
#  deux règles se battraient pour le même fond.
if grep -q 'classList.contains("sel")' "$PAGE"; then
	ok "un bouton déjà choisi n'est pas flashé"
else
	non "rien n'exclut les boutons déjà choisis du flash"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
