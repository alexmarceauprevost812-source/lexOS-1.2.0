"use strict";
/* Paramètres LexOS — la même barre latérale que la démo (SETTINGS_NAV),
   branchée sur l'API locale servie par settings.py. */

/*  LE PICTOGRAMME WI-FI DIT SON ÉTAT PAR SA COULEUR.
    Photo des Paramètres de l'ISO 76, colonne de gauche : à côté de « Wi-Fi »,
    un carré jaune. C'est l'émoji 📶 rendu sans police d'émojis couleur — le
    caractère de remplacement. Dans la démo, à la même place, une antenne
    verte. Alex : « wi-fi, utiliser lui la 2e image ».

    C'est donc le glyphe de la démo qui vient ici, avec sa règle : vert
    connecté · orange connecté mais rien ne passe · rouge pas de connexion.
    Un émoji ne dit rien de l'état, et n'est même pas garanti de s'afficher.

    « pic » peut désormais être une FONCTION : l'état change (on éteint le
    Wi-Fi, on perd internet) et le dessin doit changer avec lui. Une chaîne
    figée serait juste au premier affichage et fausse ensuite. */
function wifiGlyph(){
  const w = etat.wifi || {};
  let s = "gly-off", t = "Wi-Fi non connecté";
  if(w.radio === "absent"){ t = "Aucune carte Wi-Fi"; }
  else if(w.radio !== "enabled"){ t = "Wi-Fi éteint"; }
  else if(w.reseau){
    if(w.internet === "full"){ s = "gly-ok"; t = "Connecté à " + w.reseau; }
    else { s = "gly-warn"; t = "Connecté à " + w.reseau + ", mais rien ne passe"; }
  }
  return `<i class="gly gly-wifi ${s}" title="${esc(t)}"></i>`;
}

const NAV = [
  {grp:"Réseau", items:[
    ["wifi",wifiGlyph,"Wi-Fi"], ["reseau","🌐","Réseau"], ["bluetooth","🅱","Bluetooth"]]},
  {grp:"Matériel", items:[
    ["ecrans","🖥","Écrans"], ["son","🔊","Son"], ["energie","🔋","Énergie"],
    ["usb","🔌","Appareils USB"], ["mac","🍎","Mac (Apple)"],
    ["diagnostic","🩺","Diagnostic"]]},
  {grp:"Personnalisation", items:[
    ["apparence","🎨","Apparence"], ["bureau","🖼","Bureau LexOS"],
    ["multitaches","🗔","Multi-tâches"], ["applications","🧩","Applications"],
    ["notifications","🔔","Notifications"], ["recherche","🔍","Recherche"],
    ["terminal","🖥","Terminal jour/nuit"]]},
  {grp:"Comptes", items:[
    ["comptes","👤","Comptes en ligne"], ["partage","📤","Partage"],
    ["bienetre","🌱","Bien-être numérique"], ["session","⏻","Fermer la session"]]},
  {grp:"Périphériques", items:[
    ["souris","🖱","Souris et pavé tactile"], ["couleurs","🌈","Gestion des couleurs"],
    ["imprimantes","🖨","Imprimantes"], ["amovibles","💾","Supports amovibles"],
    ["tablette","🖊","Tablette graphique"]]},
  {grp:"Système", items:[
    ["confidentialite","🛡","Confidentialité et sécurité"], ["maj","⬆","Mises à jour"],
    ["accessibilite","♿","Accessibilité"], ["utilisateurs","🧑‍💻","Utilisateurs"],
    ["region","🌍","Région et langue"], ["clavier","⌨","Clavier"],
    ["datetime","🕒","Date et heure"], ["defaut","🧭","Applications par défaut"],
    ["distant","🖥","Bureau à distance"],
    ["tiers","⚖","Logiciels tiers"], ["apropos","◆","À propos"]]},
];

const ACCENTS = {orange:"#E8590C", "orange-rouge":"#D97757", bleu:"#1A5FB4",
                 rouge:"#C4211E", vert:"#1F8F4E", gris:"#8A8A8A",
                 violet:"#8B5CF6", neon:"#39FF14"};

/*  Les DEUX styles mis en avant, en haut de la section Apparence. Les sept
    pastilles restent en dessous pour qui veut fouiller, mais l'immense
    majorité du temps le choix se résume à ces deux-là — et une rangée de
    pastilles sans nom ne dit pas laquelle est laquelle. */
const STYLES = [
  ["orange",       "Classique",      "L'orange franc de LexOS"],
  ["orange-rouge", "Orange et rouge","Du terracotta au rouge brique"],
];

/*  Les polices sont montrées DANS leur propre police : lire le mot
    « Manuscrite » écrit à la main dit en un coup d'oeil ce que ça donnera,
    là où une liste de noms tous rendus pareil ne dit rien du tout.
    « Patrick Hand » est la seule embarquée par LexOS (OFL, dans
    /usr/share/fonts/truetype/lexos) — les autres sont des alias génériques
    que fontconfig sait toujours résoudre. */
const POLICES = [
  ["defaut",     "Défaut",     "system-ui,sans-serif"],
  ["classique",  "Classique",  "'Noto Serif',Georgia,serif"],
  ["mono",       "Machine",    "ui-monospace,monospace"],
];
/*  LES ÉCRITURES À LA MAIN. Douze, embarquées par LexOS (licence OFL, dans
    /usr/share/fonts/truetype/lexos) — donc présentes même sur une machine
    qui n'a aucune police manuscrite installée, et lisibles hors ligne.

    Le libellé est en français et décrit le GESTE (bulle, crayon, marqueur…),
    pas le nom de la fonderie : « Gloria Hallelujah » ne dit rien à personne,
    « Tableau noir » dit tout. Le vrai nom reste en infobulle, pour qui veut
    la retrouver ailleurs.

    Chacune est écrite DANS SA PROPRE POLICE dans la liste : c'est la seule
    façon de choisir sans essayer une par une. */
const ECRITURES = [
  ["manuscrite", "Manuscrite",  "Patrick Hand"],
  ["bulle",      "Bulle",       "Comic Neue"],
  ["carnet",     "Carnet",      "Delius"],
  ["ronde",      "Ronde",       "Short Stack"],
  ["crayon",     "Crayon",      "Neucha"],
  ["plume",      "Plume",       "Handlee"],
  ["marqueur",   "Marqueur",    "Kalam"],
  ["architecte", "Architecte",  "Architects Daughter"],
  ["fleur",      "Fleur",       "Indie Flower"],
  ["cursive",    "Cursive",     "Caveat"],
  ["tableau",    "Tableau noir","Gloria Hallelujah"],
  ["craie",      "Craie",       "Shantell Sans"],
];
//  Les deux listes réunies, sous la forme qu'attend appliqueApparence() :
//  [clé, libellé, famille CSS]. Écrit une fois plutôt que recopié.
const TOUTES_POLICES = POLICES.concat(
  ECRITURES.map(([cle, titre, fam]) => [cle, titre, `'${fam}',cursive`]));
const LANGUES = [
  ["fr_CA.UTF-8","Français (Québec)"], ["fr_FR.UTF-8","Français (France)"],
  ["en_US.UTF-8","English (US)"], ["en_CA.UTF-8","English (Canada)"],
  ["en_GB.UTF-8","English (UK)"], ["es_ES.UTF-8","Español (España)"],
  ["es_MX.UTF-8","Español (México)"], ["de_DE.UTF-8","Deutsch"],
  ["it_IT.UTF-8","Italiano"], ["pt_BR.UTF-8","Português (Brasil)"],
  ["ru_RU.UTF-8","Русский"], ["zh_CN.UTF-8","中文（简体）"],
  ["ja_JP.UTF-8","日本語"], ["ko_KR.UTF-8","한국어"], ["ar_SA.UTF-8","العربية"],
];

let etat = {perf:"medium", theme:"sombre", accent:"orange", police:"defaut",
            avion:"off", hote:"", version:"", noyau:""};
let sectionActive = "wifi";

/*  Le protocole choisi pour aller voir ailleurs vit ICI et pas dans la page :
    rendSection() réécrit tout le panneau à chaque rafraîchissement, et un
    choix rangé dans le HTML disparaîtrait à la première relecture d'état. */
let distantProto = "auto";

/*  Le réseau Wi-Fi qu'on est en train de choisir. Comme le protocole du
    bureau à distance, il vit ICI : rendSection() réécrit tout le panneau à
    chaque relecture d'état, et un choix rangé dans le HTML disparaîtrait. */
let wifiChoisi = "";

/* --- API ------------------------------------------------------------------ */
async function api(action, arg){
  try{
    const r = await fetch("/api/action", {method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({action, arg})});
    const j = await r.json();
    if(!j.ok && j.erreur) toast("✗ " + j.erreur);
    return j;
  }catch(e){ toast("✗ Le pont local ne répond pas"); return {ok:false}; }
}
async function chargeEtat(){
  try{ etat = Object.assign(etat, await (await fetch("/api/etat")).json()); }
  catch(e){}
}

let toastT = null;
function toast(msg){
  const t = document.getElementById("toast");
  t.textContent = msg; t.hidden = false;
  clearTimeout(toastT); toastT = setTimeout(()=>{ t.hidden = true; }, 2600);
}

/*  ═══ LE FLASH DU CLIC, POSÉ EN UN SEUL ENDROIT ═══
    ALEX : « beaucoup de boutons ne changent pas de couleur en orange quand
    on clique dessus. » Le style du flash vit dans style.css (.btn.ghost.press) ;
    ici on se contente de poser la classe et de la retirer.

    POURQUOI UN ÉCOUTEUR DÉLÉGUÉ, ET PAS 47 GESTIONNAIRES. Les boutons sont
    écrits avec des attributs « onclick » en ligne, et chaque section se
    redessine entièrement à chaque changement d'état : accrocher quoi que ce
    soit bouton par bouton serait à refaire à chaque rendu, et on en
    oublierait. Un seul écouteur sur le document, en phase de CAPTURE, voit
    tous les boutons — y compris ceux qui n'existaient pas encore.

    POURQUOI « pointerdown » ET PAS « click ». On veut le retour au moment où
    le doigt appuie, comme « :active », pas au relâchement. Et pointerdown
    couvre la souris comme le tactile.

    POURQUOI 160 ms. « :active » ne dure que le temps de l'appui : un clic
    vif dure 40 ms et le flash serait invisible. 160 ms est le plancher qui
    rend le retour perceptible sans le faire traîner.

    ═══ ON NE FLASHE PAS UN BOUTON DÉJÀ CHOISI ═══
    Les boutons de CHOIX portent « sel » quand leur choix est actif : ils
    sont déjà accentués en permanence, et y ajouter « press » ferait se
    battre deux règles pour le même fond.

    MESURÉ, ET C'EST UNE LIMITE À CONNAÎTRE : un bouton de choix NON
    sélectionné s'écrit « class="btn ghost" », exactement comme un bouton
    d'action — le dépôt écrit « btn ${x ? "sel" : "ghost"} ». Rien dans le
    DOM ne les distingue à ce moment-là. Il flashera donc lui aussi, et
    c'est le bon comportement : il est en train de DEVENIR le choix actif,
    le flash accentué enchaîne sur l'accent permanent que le rendu suivant
    lui donnera. La règle utile est donc bien « ne pas flasher ce qui est
    déjà sel », pas « deviner la famille ».

    ═══ « .btn » ET NON PLUS « .btn.ghost » ═══
    Ce sélecteur ne voyait que les boutons d'action. Les boutons PLEINS — le
    premier de chaque rangée, celui qu'on regarde en premier — n'étaient donc
    jamais couverts par le plancher de 160 ms : leur retour de couleur, une
    fois ajouté dans style.css, n'aurait duré que le temps de l'appui, soit
    40 ms sur un clic vif. Invisible, exactement le défaut qu'on venait de
    corriger, sur l'autre famille de boutons.
    Les deux gardes ci-dessous suffisent à écarter ce qu'il ne faut pas
    flasher — « sel » est déjà accentué en permanence, et « disabled » ne
    répond plus du tout. */
document.addEventListener("pointerdown", ev => {
  const b = ev.target && ev.target.closest ? ev.target.closest(".btn") : null;
  if(!b || b.classList.contains("sel") || b.disabled) return;
  b.classList.add("press");
  setTimeout(() => b.classList.remove("press"), 160);
}, true);

/* --- Briques d'interface -------------------------------------------------- */
const esc = s => String(s).replace(/[&<>"]/g,
  c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

/*  ═══ UNE VALEUR DU SYSTÈME DANS UN onclick="f('…')" ═══
    esc() protège le HTML. Elle n'échappe PAS l'apostrophe — et c'est
    l'apostrophe qui ferme la chaîne JavaScript à l'intérieur de l'attribut.

    MESURÉ, PAS SUPPOSÉ. Un compte nommé « o'brien » produisait
    onclick="utilGeste('motdepasse','o'brien')" : le navigateur décode les
    entités de l'attribut, PUIS lit le JavaScript, et trouve « missing ) after
    argument list ». Le bouton s'affiche, se clique, et il ne se passe RIEN —
    l'erreur va dans une console que personne n'ouvre. C'est exactement le
    défaut des trois sélecteurs morts de l'écran de connexion, sous une autre
    forme.

    ET « &#39; » NE RÉPARE RIEN. Le Wi-Fi le faisait déjà pour les noms de
    réseau : le navigateur décode &#39; EN apostrophe avant de lire le
    JavaScript, donc la chaîne se ferme quand même. Un réseau « Chez Léa's »
    avait un bouton « Se connecter » mort. Vérifié en rendant la page et en
    passant l'attribut décodé à new Function().

    L'ORDRE COMPTE : l'antislash d'abord (sinon on doublerait celui qu'on vient
    de poser), l'apostrophe ensuite, l'échappement HTML en dernier. */
const jsq = s => esc(String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'"));

function srow(titre, desc, droite){
  return `<div class="srow"><div><div class="t">${titre}</div>
    ${desc?`<div class="d">${desc}</div>`:""}</div>${droite||""}</div>`;
}
function sw(on, onclick){
  return `<div class="sw${on?" on":""}" onclick="${onclick}"><i></i></div>`;
}
/*  LE COMPTE-TOURS DE PERFORMANCE, repris TEL QUEL de la démo web.
    C'est le même dessin, le même cadran, la même aiguille : la démo est le
    cahier des charges, et un réglage qui n'a pas la même tête des deux
    côtés n'est pas le même réglage aux yeux de celui qui s'en sert. */
const PERF_LABEL = {petit:"Petit — machine modeste, autonomie maximale",
  medium:"Médium — équilibre, réglage par défaut",
  vif:"Vif — processeur à fond, aucune fioriture",
  performant:"Performant — priorité à la vitesse",
  max:"Performance max — tout à fond, secteur recommandé"};

/* --- Compte-tours de performance ----------------------------------------
   Un vrai cadran plutôt qu'une image figée : seule l'aiguille tourne, et la
   transition CSS la fait BALAYER jusqu'à la nouvelle valeur au lieu de sauter.
   Échelle 0-9, comme un compte-tours : petit 2 · medium 4 · vif 7 ·
   performant 6 · max 9, zone rouge à partir de 8.
   LE 7 DE « vif » N'EST PAS UNE COQUILLE, ET IL DÉPASSE EXPRÈS CELUI DE
   « performant ». Les deux emploient le même gouverneur, mais « vif » ne
   laisse RIEN redessiner l'écran : ni compositing, ni zoom du dock, ni
   vignettes. Il pousse donc le processeur plus fort, tout en restant sous
   « max », qui débride aussi le disque et la mémoire. Ne le « corrigez »
   pas en 5. */
const PERF_RPM = {petit:2, medium:4, vif:7, performant:6, max:9};
const G_A0 = -125, G_A1 = 125, G_VMAX = 9;
function gaugeAngle(v){ return G_A0 + (G_A1-G_A0)*(v/G_VMAX); }
function gaugePt(a, r){
  const t=(a-90)*Math.PI/180;
  return [256+r*Math.cos(t), 256+r*Math.sin(t)];
}
function gaugeArc(v0, v1, r){
  const [x0,y0]=gaugePt(gaugeAngle(v0),r), [x1,y1]=gaugePt(gaugeAngle(v1),r);
  return `M ${x0.toFixed(1)} ${y0.toFixed(1)} A ${r} ${r} 0 0 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`;
}
function gaugeDial(){
  let tk="", nb="";
  for(let i=0;i<=9;i++){
    const a=gaugeAngle(i);
    const [x0,y0]=gaugePt(a,126), [x1,y1]=gaugePt(a,152);
    tk+=`<line x1="${x0.toFixed(1)}" y1="${y0.toFixed(1)}" x2="${x1.toFixed(1)}" y2="${y1.toFixed(1)}" stroke-width="13"/>`;
    const [mx,my]=gaugePt(a,100);
    nb+=`<text x="${mx.toFixed(1)}" y="${(my+13).toFixed(1)}" text-anchor="middle">${i}</text>`;
    if(i<9){
      const a2=gaugeAngle(i+0.5);
      const [u0,v0]=gaugePt(a2,139), [u1,v1]=gaugePt(a2,152);
      tk+=`<line x1="${u0.toFixed(1)}" y1="${v0.toFixed(1)}" x2="${u1.toFixed(1)}" y2="${v1.toFixed(1)}" stroke-width="7"/>`;
    }
  }
  return `<path d="${gaugeArc(0,9,150)}" fill="none" stroke="currentColor" stroke-width="11" stroke-linecap="round" opacity=".35"/>`+
         `<path d="${gaugeArc(8,9,150)}" fill="none" stroke="#FF3B30" stroke-width="11" stroke-linecap="round"/>`+
         `<g stroke="currentColor" stroke-linecap="round" opacity=".85">${tk}</g>`+
         `<g fill="currentColor" opacity=".85" font-family="ui-monospace,monospace" font-weight="700" font-size="38">${nb}</g>`;
}
//  size : côté en pixels. profil : clé de PERF_RPM (défaut : profil courant).
//
//  « state » N'EXISTE PAS DANS CE FICHIER — l'état s'appelle « etat ». La
//  ligne ci-dessous levait donc une ReferenceError… mais seulement quand
//  « profil » est vide, c'est-à-dire quand etat.perf ne répond pas. Sur une
//  machine où lexos-perf va bien, l'unique appel passe etat.perf et le défaut
//  ne se voyait jamais. Il attendait le jour où l'outil manquerait — et ce
//  jour-là, la page Énergie n'aurait rien affiché du tout, sans message :
//  rendSection() fait « content.innerHTML = contenu(...) », et quand contenu()
//  lève, l'écran garde la section précédente. Même mécanique que « Diagnostic ».
function perfGauge(size, profil){
  const v = PERF_RPM[profil || etat.perf] ?? 4;
  return `<svg class="gauge" viewBox="0 0 512 512" width="${size}" height="${size}" aria-hidden="true">`+
    gaugeDial()+
    `<g class="needle" style="transform:rotate(${gaugeAngle(v)}deg)">`+
      `<line x1="256" y1="284" x2="256" y2="138" stroke="currentColor" stroke-width="17" stroke-linecap="round"/>`+
    `</g>`+
    `<circle cx="256" cy="256" r="25" fill="currentColor"/>`+
    `<circle cx="256" cy="256" r="10" fill="var(--bg)"/>`+
  `</svg>`;
}

/*  Deux indicateurs qui valent mieux qu'un nombre seul : on lit une force
    de signal ou une charge d'un coup d'oeil, sans convertir mentalement.
    Pas d'image ni de police d'icônes — quatre <i> et un peu de CSS. */
function barres(force){
  const n = force >= 75 ? 4 : force >= 50 ? 3 : force >= 25 ? 2 : force > 0 ? 1 : 0;
  return `<div class="barres" title="${force} %">` +
    [1,2,3,4].map(i=>`<i class="${i<=n?"on":""}"></i>`).join("") + `</div>`;
}
function jauge(pct){
  const p = Math.max(0, Math.min(100, pct));
  return `<div class="jauge" title="${p} %"><span style="width:${p}%"></span></div>`;
}

/*  ═══ LA PILE D'ALEX, DESSINÉE PLUTÔT QUE COLLÉE ═══
    Ses deux images : quatre piles côte à côte — verte pleine (4 barres),
    jaune aux trois quarts (3), orange à moitié (2), rouge presque vide (1) —
    et le même dessin isolé, contour foncé, quatre barres vertes.
    « utiliser ces images pour les utiliser dans les paramètres de la
    batterie. »

    POURQUOI UN TRACÉ ET PAS LES FICHIERS. Ces images sont des PNG sur fond
    BLANC, à quatre états figés. Une batterie réelle passe par tous les
    pourcentages, et la page s'affiche aussi bien en mode clair qu'en mode
    sombre : un PNG blanc y ferait une tache, et il faudrait quatre fichiers
    pour dire ce qu'une seule règle dit mieux. Le dessin reprend donc la
    GRAMMAIRE de ses images — corps arrondi à contour épais, borne au-dessus,
    barres empilées, couleur qui dit l'état — en SVG : net à toutes les
    tailles, et la couleur suit la charge en continu.

    LES QUATRE SEUILS SONT LES SIENS, relevés sur son image :
      4 barres, vert    au-dessus de 75 %
      3 barres, jaune   de 50 à 75
      2 barres, orange  de 25 à 50
      1 barre,  rouge   en dessous de 25
    Ces couleurs PORTENT LE SENS — elles ne suivent pas l'accent choisi. Une
    batterie à plat reste rouge sur une ISO montée en bleu, comme l'antenne
    Wi-Fi reste rouge quand elle est coupée.

    Branché sur le secteur, l'éclair passe par-dessus : « en charge » n'est
    pas un niveau, et la teinte seule ne saurait pas le dire. */
const BAT_PALIERS = [
  [75, 4, "var(--ok)"],      // plein
  [50, 3, "var(--warn)"],    // jaune
  [25, 2, "#E8590C"],        // orange — le même que l'accent LexOS par défaut
  [-1, 1, "var(--off)"],     // rouge
];
function batGlyph(pct, secteur, taille){
  const p = Math.max(0, Math.min(100, Number(pct)));
  const h = taille || 34;
  const [, barres, couleur] = BAT_PALIERS.find(([seuil]) => p > seuil) || BAT_PALIERS[3];
  //  Le corps : 34 de large sur 56 de haut dans un viewBox de 44x64, borne
  //  comprise. Les quatre barres occupent l'intérieur, du bas vers le haut —
  //  on empile depuis le BAS parce qu'une batterie se vide par le haut.
  const L = [];
  for(let i = 0; i < barres; i++){
    L.push(`<rect x="12" y="${44 - i * 10}" width="20" height="7" rx="1" fill="${couleur}"/>`);
  }
  const titre = `${p} %` + (secteur ? " — en charge" : "");
  return `<svg viewBox="0 0 44 64" width="${h * 44 / 64}" height="${h}"
     role="img" aria-label="Batterie : ${titre}"><title>${titre}</title>
    <rect x="17" y="2" width="10" height="6" rx="2" fill="${couleur}"/>
    <rect x="4" y="8" width="36" height="54" rx="6"
          fill="none" stroke="${couleur}" stroke-width="4"/>
    ${L.join("")}
    ${secteur ? `<path d="M25 20 L15 36 h7 l-3 12 L34 30 h-7 z"
          fill="var(--bg)" stroke="${couleur}" stroke-width="2.5"
          stroke-linejoin="round"/>` : ""}
  </svg>`;
}
/*  Un menu déroulant, avec le même habillage que le reste. La valeur part
    vers la machine au changement ; « 0 » veut dire « jamais ». */
/*  Le disque dur, d'après l'image fournie par Alex. Même dessin que la démo
    web — la démo est le cahier des charges, et une icône qui n'a pas la même
    tête des deux côtés n'est pas la même icône pour celui qui la regarde.
    viewBox serré sur le dessin : sinon l'icône flotte dans un carré vide et
    paraît deux fois plus petite que sa boîte. */
/*  La clé USB — même famille de dessin que le disque dur : silhouette pleine,
    trait noir franc, deux gris. Elles se ressemblent assez pour aller
    ensemble, et diffèrent assez pour qu'on ne les confonde pas d'un coup
    d'oeil — ce qui compte quand le bouton d'à côté formate. */
function usbGlyph(size){
  return `<svg viewBox="60 150 392 212" width="${size}" height="${size}" aria-hidden="true">`+
    `<g stroke="#111827" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">`+
      `<rect x="150" y="176" width="286" height="160" rx="30" fill="#E8590C"/>`+
      `<rect x="76" y="212" width="80" height="88" rx="12" fill="#94A3B8"/>`+
      `<rect x="176" y="206" width="150" height="100" rx="16" fill="#F1F5F9"/>`+
    `</g>`+
  `</svg>`;
}
function diskGlyph(size){
  return `<svg viewBox="96 18 320 476" width="${size}" height="${size}" aria-hidden="true">`+
    `<g stroke="#111827" stroke-width="16" stroke-linejoin="round" stroke-linecap="round">`+
      `<rect x="104" y="26" width="304" height="460" rx="40" fill="#6B7280"/>`+
      `<circle cx="252" cy="188" r="132" fill="#CBD5E1"/>`+
      `<path d="M 120 258 L 120 464 L 336 464 Z" fill="#CBD5E1"/>`+
      `<path d="M 306 206 L 176 300 L 214 344 Z" fill="#F1F5F9"/>`+
      `<circle cx="252" cy="188" r="44" fill="#94A3B8"/>`+
    `</g>`+
    `<g fill="#111827">`+
      `<circle cx="252" cy="166" r="8.5"/><circle cx="252" cy="210" r="8.5"/>`+
      `<circle cx="230" cy="188" r="8.5"/><circle cx="274" cy="188" r="8.5"/>`+
      `<circle cx="196" cy="322" r="11"/><circle cx="156" cy="426" r="11"/>`+
    `</g>`+
  `</svg>`;
}
function menu(quoi, valeur, choix){
  return `<select onchange="setMinutes('${quoi}', this.value)"
    style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
           border-radius:6px;padding:6px 8px;font:inherit">` +
    choix.map(([v,t])=>`<option value="${v}"${String(v)===String(valeur)?" selected":""}>${t}</option>`).join("") +
    `</select>`;
}
function btnOuvrir(section, libelle){
  return `<div class="row"><button class="btn" onclick="ouvrir('${section}')">
    ${libelle || "Ouvrir l'outil complet"}</button></div>`;
}

/* --- Actions déclenchées par la page ------------------------------------- */
/*  ═══ UNE FENÊTRE QUI NE S'OUVRE PAS DOIT LE DIRE ═══
    ALEX : « regarde bien pour que tous les boutons et les fenêtres ouvrent
    fluidement. »

    Cette fonction JETAIT la réponse. Quand l'outil manquait, le moteur
    renvoyait pourtant le motif exact — « Outil absent : … » — et personne ne
    le lisait : on cliquait, rien ne s'ouvrait, aucun message. Un bouton mort
    et muet, impossible à distinguer d'un bouton lent.

    C'est ainsi que deux fenêtres (« Applications par défaut » et
    « Applications ») sont restées mortes sans que rien ne le signale : elles
    appelaient exo-preferred-applications, retiré de XFCE depuis longtemps.
    Le programme manquait ; le silence, lui, était de notre fait.

    Même faute et même correctif que le curseur de luminosité et le bouton du
    dock — on lit la réponse. */
async function ouvrir(section){
  const r = await api("ouvrir", section);
  if(!r.ok) toast("Impossible d'ouvrir : " + (r.erreur || "refusé"));
}
async function ouvreBoost(){
  const r = await api("ouvrir", "boost");
  if(r.ok) toast("LexOS Boost s'ouvre dans sa fenêtre");
}

/*  Après chaque changement on RELIT l'état depuis la machine au lieu de le
    deviner. Un interrupteur qui bascule à l'écran alors que la commande a
    échoué est un mensonge — et c'est comme ça qu'on croit avoir éteint le
    Wi-Fi sans l'avoir éteint. */
async function rafraichir(msg){
  await chargeEtat();
  //  ═══ ET L'APPARENCE AVEC. ALEX : « dans les Paramètres les boutons
  //  fonctionnent tous, mais c'est la couleur orange qui ne change pas dans
  //  les Paramètres — pour le dock surtout. » ═══
  //
  //  chargeEtat() vient de relire l'accent, la police et le mode SUR LA
  //  MACHINE. Sans cette ligne, la page les recevait et n'en faisait rien :
  //  seul rend() posait les variables CSS, et rend() ne tourne qu'au
  //  démarrage. Une fenêtre déjà ouverte gardait donc son orange quoi qu'il
  //  arrive — même après un changement d'accent fait ailleurs (le volet des
  //  Paramètres rapides, « lexos accent bleu » au terminal), même après un
  //  simple rafraîchissement.
  //
  //  Le dock est l'endroit où ça sautait aux yeux, comme Alex l'a vu : la
  //  rangée Droite · Gauche · Bas · Haut montre en permanence un bouton
  //  sélectionné, donc un aplat de couleur qui aurait dû suivre l'accent.
  //
  //  ENCORE UN CORRECTIF À MOITIÉ, LE TROISIÈME DE LA SEMAINE. Le
  //  commentaire de setTheme() plus haut raconte le premier round : on avait
  //  ajouté appliqueApparence() aux TROIS boutons qui changent l'apparence,
  //  « et seulement ici ». Personne n'avait regardé le chemin par lequel la
  //  page se resynchronise avec la machine — c'est-à-dire tous les autres
  //  boutons, et toutes les modifications venues du dehors.
  appliqueApparence();
  //  LA BARRE LATÉRALE AUSSI. Le pictogramme Wi-Fi dit l'état par sa
  //  couleur : si on ne redessine que la page, on éteint le Wi-Fi et
  //  l'antenne reste verte à gauche — un interrupteur qui ment, exactement
  //  ce que le commentaire ci-dessus s'emploie à éviter.
  rendNav();
  rendSection();
  if(msg) toast(msg);
}
async function basculeWifi(){
  const r = await api("wifi-radio", "toggle");
  await rafraichir(r.ok ? "Wi-Fi basculé" : "Échec : " + (r.erreur || "commande refusée"));
}
/*  CONNEXION AUTOMATIQUE AUX RÉSEAUX OUVERTS.
    L'AVERTISSEMENT N'EST PAS DÉCORATIF, et il n'est pas supprimé : en ligne
    de commande, « lexos net auto on » fait taper OUI. Depuis une fenêtre il
    n'y a pas de terminal pour répondre — on pose donc la même question ici,
    puis on passe « --confirme » côté machine pour dire qu'elle a été posée.
    Éteindre ne demande rien : revenir au réglage sûr n'a pas à se mériter. */
async function basculeWifiAuto(){
  const actif = !!((etat.wifi || {}).auto);
  if(!actif){
    const d = "Un réseau ouvert n'a pas de mot de passe, donc pas de "
      + "chiffrement.\n\n"
      + "· Toute personne à portée peut lire ce qui circule en clair.\n"
      + "· N'importe qui peut créer un faux point d'accès portant le nom "
      + "d'un réseau connu.\n"
      + "· Les sites en HTTPS restent chiffrés ; le reste, non.\n\n"
      + "À éviter pour la banque, les courriels et les mots de passe.\n\n"
      + "Activer quand même la connexion automatique ?";
    if(!window.confirm(d)) return;
  }
  const r = await api("wifi-auto", actif ? "off" : "on");
  await rafraichir(r.ok
    ? (actif ? "Connexion automatique désactivée" : "Connexion automatique activée")
    : "Échec : " + (r.erreur || "commande refusée"));
}
async function setFondFichier(i){
  /*  ═══ AUCUN NOM DE FICHIER DANS LE HTML ═══
      Ce gestionnaire recevait le nom en clair, interpolé dans un attribut
      onclick délimité par une APOSTROPHE. JSON.stringify n'échappe que le
      guillemet double et la barre oblique inverse — pas l'apostrophe, ni
      « < ». Un fichier nommé  x'><img src=x onerror=…>.png  déposé dans
      ~/Téléchargements sortait donc de l'attribut et faisait exécuter son
      nom dans la page des Paramètres. Et un nom de fichier téléchargé n'est
      PAS choisi par l'utilisateur : le site d'en face le dicte par
      Content-Disposition. Le trou était ouvert par la porte qu'on venait
      d'ouvrir.

      Le correctif ne consiste pas à mieux échapper — c'est de ne RIEN
      mettre de textuel dans le HTML. Le gestionnaire ne reçoit qu'un ENTIER
      (coercé à l'écriture ET relu ici), et le nom se retrouve dans l'état,
      qui n'a jamais transité par du HTML. Une chaîne qu'on n'écrit pas est
      une chaîne qu'on n'a pas à échapper. */
  const i0 = Number(i) | 0;
  const f = (etat.fonds_perso || []).find(x => Number(x.i) === i0);
  if(!f) return toast("Cette image n'est plus dans la galerie");
  const nom = f.nom;
  const r = await api("fond-fichier", {i: i0, nom});
  await rafraichir(r.ok ? "Fond d'écran appliqué : " + nom
                        : "Échec : " + (r.erreur || "commande refusée"));
}
/*  Voir l'image EN GRAND, dans un vrai visionneur (ristretto) — pas
    seulement la vignette 96x56. Alex : « ouvrir directement image sur une
    fenetre pour voir image en plus gros ». MÊME RÈGLE que setFondFichier,
    juste au-dessus : aucun nom de fichier interpolé dans le HTML, l'indice
    seul traverse l'attribut onclick, le nom se relit dans l'état déjà
    chargé. */
async function ouvreFondFichier(i){
  const i0 = Number(i) | 0;
  const f = (etat.fonds_perso || []).find(x => Number(x.i) === i0);
  if(!f) return toast("Cette image n'est plus dans la galerie");
  const r = await api("fond-ouvrir", {i: i0, nom: f.nom});
  if(!r.ok) toast(r.erreur || "Impossible d'ouvrir l'image");
}
async function basculeMuet(){
  const r = await api("son-muet", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
/*  Le nombre à côté du curseur suit le doigt SANS parler à la machine :
    envoyer une commande à chaque pixel de glissement noierait pactl sous les
    appels. On n'agit qu'au relâchement (onchange), et l'aperçu garde l'écran
    vivant entre-temps. */
function apercuVolume(v){
  const z = document.getElementById("volVal");
  if(z) z.textContent = v + " %";
}
function apercuLum(v){
  const z = document.getElementById("lumVal");
  if(z) z.textContent = v + " %";
}
async function setDefinition(sortie, mode){
  const r = await api("ecran-definition", sortie + "|" + mode);
  await rafraichir(r.ok ? "Définition : " + mode
                        : "Échec : " + (r.erreur || "refusé"));
}
async function setEchelle(v){
  const r = await api("echelle", v);
  await rafraichir(r.ok ? "Affichage à " + v + " % — rouvre les fenêtres"
                        : "Échec : " + (r.erreur || "refusé"));
}
async function setCaptureFormat(v){
  const r = await api("capture-format", v);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "refusé"));
}
async function btBranche(adresse){
  toast("Connexion en cours…");
  const r = await api("bt-connecter", adresse);
  await rafraichir(r.ok ? "Connecté — va dans Son pour y envoyer le son" : null);
}
async function btCoupe(adresse){
  const r = await api("bt-deconnecter", adresse);
  await rafraichir(r.ok ? "Déconnecté" : null);
}
/*  La recherche dure douze secondes CÔTÉ MACHINE : le bouton le dit et se
    désactive pendant ce temps, sinon on clique trois fois et on empile trois
    balayages. */
async function btCherche(){
  const b = document.getElementById("btCherche");
  if(b){ b.disabled = true; b.textContent = "Recherche en cours…"; }
  const r = await api("bt-chercher");
  await rafraichir(r.ok ? "Recherche terminée" : null);
}
//  ALEX : « pas capable d'écrire le mot de passe » du Wi-Fi — le champ
//  affichait bien le contour orange du focus (CSS), mais aucune touche
//  n'entrait dedans. rendSection() REMPLACE tout #content par du neuf
//  (innerHTML) et .focus() était appelé sur ce nœud flambant neuf DANS LA
//  MÊME PASSE SYNCHRONE — exactement le cas que QtWebEngine (le moteur de
//  cette fenêtre, PySide6) documente comme instable : le focus DOM peut
//  « prendre » visuellement avant que le moteur de rendu n'ait fini
//  d'accepter le nouveau nœud, et les frappes clavier continuent d'aller
//  nulle part jusqu'au clic suivant. Un requestAnimationFrame (déjà
//  l'idiome du volet pour un problème de synchronisation voisin) repousse
//  le focus au prochain repaint, une fois le nouveau champ vraiment prêt.
function choisitWifi(ssid){ wifiChoisi = ssid; rendSection();
  requestAnimationFrame(() => {
    const c = document.getElementById("wifiMdp"); if(c) c.focus();
  });
}
/*  ALEX : « quand je suis connecté sur le wi-fi, il dit pas de déconnecter
    une fois connecté ». La ligne du réseau actif portait une pastille
    « connecté » et RIEN à cliquer — se déconnecter demandait le terminal,
    alors que le Bluetooth, dans la même fenêtre, a son btCoupe() depuis
    toujours. AUCUN ARGUMENT N'EST ENVOYÉ : la machine sait déjà quelle
    connexion Wi-Fi est active (nmcli device status), et ne rien envoyer
    vaut mieux que valider une chaîne — la page ne peut désigner ni le
    câble, ni un VPN. */
async function coupeWifi(){
  const r = await api("wifi-deconnecter");
  await rafraichir(r.ok ? "Déconnecté du Wi-Fi"
                        : "Échec : " + (r.erreur || "commande refusée"));
}
async function chercheWifi(){
  toast("Recherche des réseaux…");
  await api("wifi-rechercher");
  await rafraichir("Recherche terminée");
}
/*  Le mot de passe est lu au moment de l'envoi et n'est JAMAIS rangé dans une
    variable qui survivrait au rendu : il fait l'aller simple champ → pont
    local → gestionnaire de réseau. */
async function brancheWifi(){
  const ssid = wifiChoisi;
  if(!ssid) return;
  const c = document.getElementById("wifiMdp");
  const r = await api("wifi-connecter", {ssid, mot_de_passe: c ? c.value : ""});
  if(c) c.value = "";
  if(r.ok){ wifiChoisi = ""; await rafraichir("Connecté à " + ssid); }
  else await rafraichir(null);
}
function setDistantProto(p){
  if(["auto","rdp","vnc","ssh"].includes(p)){ distantProto = p; rendSection(); }
}
async function setDistantPartage(){
  const on = !!(etat.distant && etat.distant.actif);
  const r = await api("distant-partage", on ? "off" : "on");
  await rafraichir(r.ok
    ? (on ? "Partage arrêté"
          : "Une fenêtre s'ouvre : elle demande le mot de passe à donner")
    : "Échec : " + (r.erreur || "refusé"));

  /*  ═══ POURQUOI ON RELIT ENCORE, PLUS TARD ═══
      ALEX : « le bouton ne devient pas à droite pour dire qu'il est activé,
      dans Bureau à distance. »

      LE PARTAGE NE DÉMARRE PAS QUAND ON CLIQUE. Il ouvre un TERMINAL qui
      demande un mot de passe — c'est voulu, et le commentaire de
      act_distant_partage() explique pourquoi : un partage sans mot de passe
      ouvrirait la machine au réseau. x11vnc ne tourne donc PAS encore au
      moment où on relit l'état, et l'interrupteur reste à gauche à juste
      titre… puis n'a plus jamais l'occasion de bouger, parce que rien ne
      relit la machine une fois le mot de passe tapé.

      L'interrupteur ne mentait pas : il était en retard. On relit donc
      quelques secondes plus tard, le temps que le mot de passe soit saisi et
      que x11vnc s'installe.

      TROIS RELECTURES ESPACÉES plutôt qu'une seule : taper un mot de passe
      prend le temps qu'il prend. On s'arrête dès que l'état est devenu
      « actif », pour ne pas redessiner la page sous les doigts de quelqu'un
      qui lit déjà l'adresse à dicter.

      Rien de tout cela à l'ARRÊT : « lexos-distant arreter » ne demande
      rien, il a déjà agi quand il rend la main. */
  if(r.ok && !on){
    for(const delai of [2500, 6000, 12000]){
      setTimeout(async () => {
        if(sectionActive !== "distant") return;          // on a changé de page
        if(etat.distant && etat.distant.actif) return;   // déjà rattrapé
        await rafraichir();
      }, delai);
    }
  }
}
/*  Pas de rafraichir() ici : relire l'état réécrirait le panneau et effacerait
    l'adresse qu'on vient de taper, juste au moment où on voudrait la corriger
    parce que la connexion a raté. */
async function distantVers(){
  const c = document.getElementById("distAdr");
  const adresse = (c ? c.value : "").trim();
  if(!adresse){ toast("Il faut l'adresse de l'autre machine"); return; }
  const r = await api("distant-vers", {protocole: distantProto, adresse});
  if(r.ok) toast("Connexion à " + adresse + " …");
}
async function setSortieSon(nom){
  const r = await api("son-sortie", nom);
  await rafraichir(r.ok ? "Le son sort maintenant par là"
                        : "Échec : " + (r.erreur || "sortie refusée"));
}
async function setVolume(v){
  const r = await api("son-volume", String(v));
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
/*  ═══ CETTE FONCTION ÉTAIT DÉFINIE DEUX FOIS, ET C'EST TOUT LE BOGUE ═══
    ALEX : « quand je clique sur le bouton pour changer le dock de position,
    il change de position, mais dans les paramètres il change pas — il reste
    à droite ».

    Les deux moitiés du symptôme s'expliquent d'un coup. Une SECONDE
    définition de setDock() vivait 190 lignes plus bas, et se contentait d'un
    toast : ni mise à jour de l'état, ni nouveau rendu. En JavaScript, deux
    déclarations de fonction du même nom dans la même portée ne cohabitent
    pas — LA DERNIÈRE ÉCRASE LA PREMIÈRE. Celle-ci, la bonne, ne s'exécutait
    donc jamais : du code mort qui avait l'air vivant.

    Le dock bougeait quand même (l'appel « api("dock", …) » partait bien dans
    les deux versions), mais le bouton en surbrillance suit « etat.dock », que
    seule cette version-ci met à jour — via rafraichir(), qui relit l'état de
    la MACHINE au lieu de le supposer. D'où « il change de position mais dans
    les paramètres il reste à droite », mot pour mot.

    setLangue() portait exactement le même doublon, avec la même conséquence
    invisible : la langue changeait, le bouton sélectionné ne bougeait pas.
    Les deux doublons sont retirés ; un contrôle de la CI refuse désormais
    qu'une fonction de cette page soit déclarée deux fois. */
async function setDock(d){
  const r = await api("dock", d);
  await rafraichir(r.ok ? "Dock : " + d : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeBarre(){
  const r = await api("barre-cachee", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeCrt(){
  const r = await api("crt", "toggle");
  //  « À la prochaine ouverture de session » était vrai du temps de Compiz.
  //  picom démarre et s'arrête dans la session en cours : on le dit.
  await rafraichir(r.ok ? "C'est réglé — ferme une fenêtre pour voir"
                        : "Échec : " + (r.erreur || "commande refusée"));
}
async function setBureaux(sens){
  const r = await api("bureaux", sens);
  await rafraichir(r.ok ? null : (r.erreur || "commande refusée"));
}
/*  LA VUE D'ENSEMBLE. Trois commandes : l'ouvrir tout de suite, et armer
    ses deux déclencheurs. On relit l'état après chaque bascule — « super »
    peut échouer si xcape manque, et l'interrupteur doit alors REVENIR, pas
    rester allumé sur une promesse. */
async function poseAutocollant(quoi){
  const r = await api("autocollant", quoi);
  await rafraichir(r.ok
    ? (quoi === "enlever" ? "Fond d'origine retrouvé" : "Posé sur le fond d'écran")
    : "Échec : " + (r.erreur || "commande refusée"));
}
async function ouvreApercu(){
  const r = await api("apercu");
  if(!r.ok) toast("Échec : " + (r.erreur || "aucun outil de vue d'ensemble"));
}
async function basculeCoin(){
  const r = await api("coin", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
/*  Le geste « C + appui long ». On rafraîchit dans les deux cas : l'échec le
    plus probable est « python3-xlib manquant », et il doit se voir sur
    l'interrupteur, pas seulement dans un message qui s'efface. */
async function basculeGesteAutocollant(){
  const r = await api("geste-autocollant", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeSuperApercu(){
  const r = await api("super_apercu", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "xcape n'est pas installé"));
}
async function vaBureau(n){
  const r = await api("bureau-va", String(n));
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function setLangue(l){
  const r = await api("langue", l);
  await rafraichir(r.ok ? "À la prochaine ouverture de session" : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeNotif(){
  const r = await api("notif", "silence");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeAmovible(quoi){
  const r = await api("amovibles", quoi);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeAccess(quoi){
  const r = await api("access", quoi);
  if(quoi === "orca" || quoi === "onboard"){
    if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
    return;
  }
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function actionSecu(quoi){
  const r = await api("securite", quoi);
  if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
}
/*  ALEX : « fais en sorte que tout se mette à jour au fur et à mesure en
    cliquant sur mise à jour ». Avant : un clic ouvrait le terminal et la
    page n'en savait plus rien — les boutons restaient figés que ce soit
    fini, raté, ou encore en train de tourner, jusqu'à fermer et rouvrir les
    Paramètres à la main.

    settings.py laisse maintenant une trace (etat.maj.progres[quoi]) que le
    terminal détaché met à jour en arrière-plan. On la relit à intervalles
    courts tant que « en_cours » est vrai — c'est ÇA, le « au fur et à
    mesure » : la page change TOUTE SEULE, sans qu'on ait besoin de rien
    refaire pour voir où ça en est. */
/*  Le bouton LUI-MÊME dit où en est le geste — pas seulement un message
    éphémère (toast) qu'on peut manquer en ayant le dos tourné. « en cours »
    le désactive et change son libellé ; une fois fini, un petit badge
    « fait »/« échec » reste à côté, même après un rafraîchissement normal
    de la page (etat.maj.progres survit, lui, tant que le fichier de fin
    n'a pas été effacé). */
function boutonMaj(cle, classe, libelle){
  const p = (etat.maj && etat.maj.progres && etat.maj.progres[cle]) || null;
  if(p && p.en_cours){
    return `<button class="${classe}" disabled>${esc(libelle)} — en cours…</button>`;
  }
  let badge = "";
  if(p && !p.en_cours && p.ok !== null && p.ok !== undefined){
    badge = ` <span class="etat ${p.ok ? "ok" : "off"}">${p.ok ? "fait" : "échec"}</span>`;
  }
  return `<button class="${classe}" onclick="actionMaj('${cle}')">${esc(libelle)}</button>${badge}`;
}

let majSondage = null;
async function actionMaj(quoi){
  const r = await api("maj", quoi);
  if(!r.ok){ toast("Échec : " + (r.erreur || "commande refusée")); return; }
  await rafraichir();
  suitMaj(quoi);
}
function suitMaj(quoi){
  if(majSondage) clearInterval(majSondage);
  let tours = 0;
  majSondage = setInterval(async () => {
    tours++;
    await chargeEtat();
    rendSection();
    const p = (etat.maj && etat.maj.progres && etat.maj.progres[quoi]) || null;
    //  400 tours à 1,5 s ≈ 10 minutes : largement de quoi laisser un « apt
    //  upgrade » se terminer. Sans plafond, un terminal fermé à la croix
    //  (donc jamais de fichier de fin) ferait tourner ce minuteur pour
    //  toujours — silencieusement, en tâche de fond, à chaque session.
    if(!p || !p.en_cours || tours > 400){
      clearInterval(majSondage);
      majSondage = null;
      if(p && !p.en_cours){
        toast(p.ok === false ? "Terminé avec des erreurs — voir le terminal"
                              : "Terminé");
      }
    }
  }, 1500);
}
async function actionUsb(quoi){
  const r = await api("usb", quoi);
  if(!r.ok) toast("Échec : " + (r.erreur || "commande refusée"));
}
async function ejecte(dev){
  const r = await api("usb", "ejecter:" + dev);
  await rafraichir(r.ok ? "Tu peux débrancher" : "Échec : " + (r.erreur || "appareil occupé"));
}
async function basculeBluetooth(){
  const r = await api("bluetooth-radio", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeDimBat(){
  const r = await api("energie-dim-batterie", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function setMinutes(quoi, v){
  const r = await api("energie-delai", quoi + ":" + v);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeSouris(quoi){
  const r = await api("souris", quoi);
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
/*  L'HORLOGE DE LA BARRE. Les trois réglages — 12/24 h, secondes, jour —
    ne sont qu'une seule chaîne de format côté XFCE ; c'est le Python qui la
    recompose. On relit l'état ensuite : si xfconf-query manque, l'écran ne
    doit pas montrer un réglage qui n'a pas pris. */
async function setHorloge(quoi){
  const r = await api("horloge", quoi);
  await rafraichir(r.ok ? "L'horloge de la barre suit"
                        : "Échec : " + (r.erreur || "commande refusée"));
}
async function basculeFuseauAuto(){
  const r = await api("fuseau-auto", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "commande refusée"));
}
//  MÊME LISTE que FUSEAUX_CANADA dans settings.py (act_fuseau) et LIEUX_CANADA
//  dans lexos-datetime — les trois doivent rester d'accord, sinon un bouton
//  posé ici serait refusé côté Python, ou l'inverse. Treize provinces et
//  territoires, onze fuseaux IANA : le Nouveau-Brunswick et l'Île-du-Prince-
//  Édouard partagent celui des Maritimes, le Nunavut (trois fuseaux à lui
//  seul) est représenté par sa capitale, Iqaluit.
const FUSEAUX_CANADA = [
  ["America/Vancouver",   "Colombie-Britannique (Vancouver)"],
  ["America/Whitehorse",  "Yukon (Whitehorse)"],
  ["America/Edmonton",    "Alberta (Edmonton)"],
  ["America/Yellowknife", "Territoires du Nord-Ouest (Yellowknife)"],
  ["America/Regina",      "Saskatchewan (Regina)"],
  ["America/Winnipeg",    "Manitoba (Winnipeg)"],
  ["America/Iqaluit",     "Nunavut (Iqaluit)"],
  ["America/Toronto",     "Ontario (Toronto)"],
  ["America/Montreal",    "Québec (Montréal)"],
  ["America/Halifax",     "Maritimes (Halifax)"],
  ["America/St_Johns",    "Terre-Neuve (St. John's)"],
];
async function setFuseau(zone){
  const r = await api("fuseau", zone);
  await rafraichir(r.ok ? "Fuseau horaire réglé" : "Échec : " + (r.erreur || "mot de passe refusé"));
}
/*  LE CLAVIER. Quatre gestes, tous rendus par lexos-clavier via l'action
    « clavier » du moteur. On rafraichit apres chaque geste : la liste des
    dispositions vient de changer, et une page qui montre l'ancien etat
    ferait croire que le clic n'a rien fait. */
function nomBascule(bascules, cle){
  const b = (bascules || []).find(x => x.cle === cle);
  return b ? b.nom : (cle || "");
}
/*  La recherche. Les résultats vont dans un terminal, donc on ne rafraîchit
    pas la page : rien n'y change. On dit seulement ce qui se passe. */
async function lancerRecherche(quoi){
  const c = document.getElementById("rechMot");
  const mot = (c && c.value || "").trim();
  const r = await api("recherche", quoi + ":" + mot);
  if(r.ok){
    toast(quoi === "fenetre" ? "La fenêtre de recherche s'ouvre"
                             : "Un terminal s'ouvre avec les résultats");
  } else {
    toast("Refusé : " + (r.erreur || "impossible"));
  }
}
/*  Les comptes en ligne. « ajouter » et « retirer » ouvrent un terminal — on
    ne rafraîchit donc pas derrière, rien n'a encore changé au moment où la
    réponse revient. « monter » et « demonter », eux, agissent tout de suite. */
async function setCompte(quoi, nom){
  if(!nom) return;
  const r = await api("comptes", quoi + ":" + nom);
  if(quoi === "ajouter" || quoi === "retirer"){
    toast(r.ok ? "Un terminal s'ouvre : la suite s'y passe"
               : "Refusé : " + (r.erreur || "impossible"));
    return;
  }
  await rafraichir(r.ok ? (quoi === "monter" ? "Compte ouvert" : "Compte refermé")
                        : "Échec : " + (r.erreur || "refusé"));
}
/*  Le bien-être numérique. On rafraîchit après coup : allumer le compteur ou
    poser une limite change ce que la page affiche juste au-dessus. */
async function setBienetre(quoi, valeur){
  const v = valeur === true ? "on" : (valeur === false ? "off" : valeur);
  const r = await api("bienetre", quoi + ":" + v);
  await rafraichir(r.ok ? "C'est réglé" : "Échec : " + (r.erreur || "refusé"));
}
async function setBienetreLimite(){
  const c = document.getElementById("bienLimite");
  const v = (c && c.value || "").trim();
  if(!v){ toast("Donne un nombre de minutes"); return; }
  const r = await api("bienetre", "limite:" + v);
  await rafraichir(r.ok ? "Limite enregistrée" : "Échec : " + (r.erreur || "refusé"));
}
/*  Effacer l'historique est le seul geste de cette page qui DÉTRUIT quelque
    chose, et il passe par un terminal : lexos-bienetre fait taper le mot
    « effacer » avant de supprimer. On ne double pas cette confirmation d'une
    boîte de dialogue — demander deux fois la même chose apprend à répondre
    oui sans lire. Et on n'annonce PAS « effacé » : au moment où la réponse
    revient, le terminal vient de s'ouvrir et rien n'est encore fait. */
async function oublierBienetre(){
  const r = await api("bienetre", "oublier:");
  toast(r.ok ? "Un terminal s'ouvre : il faudra y taper « effacer »"
             : "Refusé : " + (r.erreur || "impossible"));
}
/*  Le terminal de jour et le terminal de nuit. On rafraîchit après coup : le
    mode effectif vient de changer, et une page qui montre l'ancien ferait
    croire que le clic n'a rien fait. */
async function setTerminalMode(mode){
  const r = await api("terminal-mode", "mode:" + mode);
  await rafraichir(r.ok ? "Terminal : " + mode : "Échec : " + (r.erreur || "refusé"));
}
async function setTerminalHoraire(){
  const d = document.getElementById("termDebut"), f = document.getElementById("termFin");
  const r = await api("terminal-mode",
                      "horaire:" + ((d && d.value) || "") + "-" + ((f && f.value) || ""));
  await rafraichir(r.ok ? "Heures du jour enregistrées"
                        : "Échec : " + (r.erreur || "refusé"));
}
/*  Le nom de la machine. Comme pour les comptes, le geste ouvre un terminal :
    il touche à /etc/hostname ET à /etc/hosts, et il demande les droits
    d'administrateur. On ne rafraîchit pas derrière — au moment où la réponse
    revient, le terminal vient de s'ouvrir et rien n'a encore changé. */
async function setNomMachine(){
  const c = document.getElementById("partageNom");
  const nom = (c && c.value || "").trim();
  if(!nom){ toast("Il faut un nom de machine"); return; }
  const r = await api("partage-nom", "nom:" + nom);
  toast(r.ok ? "Un terminal s'ouvre : la commande y est écrite en clair"
             : "Refusé : " + (r.erreur || "nom impossible"));
}
/*  LES COMPTES. Chaque geste ouvre un terminal — c'est là que se tapent les
    mots de passe et les confirmations — donc on ne rafraîchit PAS derrière :
    au moment où la réponse revient, le terminal vient tout juste de s'ouvrir
    et rien n'a encore changé. Une page rafraîchie à cet instant afficherait
    l'ancien état, ce qui ferait croire que le clic n'a rien fait. On dit ce
    qui se passe, et la page se remet à jour à son rythme habituel. */
async function utilGeste(quoi, nom){
  if(!nom) return;
  const r = await api("utilisateur", quoi + ":" + nom);
  toast(r.ok ? "Un terminal s'ouvre : la commande y est écrite en clair"
             : "Refusé : " + (r.erreur || "geste impossible"));
}
async function utilAjouter(){
  const c = document.getElementById("utilNouveau");
  const nom = (c && c.value || "").trim();
  if(!nom){ toast("Il faut un nom de compte"); return; }
  const r = await api("utilisateur", "ajouter:" + nom);
  if(r.ok && c) c.value = "";
  toast(r.ok ? "Un terminal s'ouvre : adduser va poser ses questions"
             : "Refusé : " + (r.erreur || "nom impossible"));
}
async function utilNomComplet(nom){
  const c = document.getElementById("nomAff-" + nom);
  const plein = (c && c.value || "").trim();
  if(!plein){ toast("Il faut un nom à afficher"); return; }
  const r = await api("utilisateur", "nom-complet:" + nom + ":" + plein);
  toast(r.ok ? "Un terminal s'ouvre pour changer le nom affiché"
             : "Refusé : " + (r.erreur || "nom impossible"));
}
/*  Le choix d'une application par défaut. On rafraîchit après coup : régler
    une catégorie peut en changer une autre (choisir un navigateur déplace
    aussi http et https), et une page qui montre l'ancien état ferait croire
    que le clic n'a rien fait. */
async function setDefautAppli(categorie, appli){
  if(!appli) return;
  const r = await api("defaut-appli", categorie + ":" + appli);
  await rafraichir(r.ok ? "Application par défaut changée"
                        : "Échec : " + (r.erreur || "refusé"));
}
async function clavierDabord(cle){
  const r = await api("clavier", "dabord:" + cle);
  await rafraichir(r.ok ? "Disposition changée" : "Échec : " + (r.erreur || "refusé"));
}
async function clavierAjouter(cle){
  if(!cle) return;
  const r = await api("clavier", "ajouter:" + cle);
  await rafraichir(r.ok ? "Disposition ajoutée" : "Échec : " + (r.erreur || "refusé"));
}
async function clavierRetirer(cle){
  const r = await api("clavier", "retirer:" + cle);
  await rafraichir(r.ok ? "Disposition retirée" : "Échec : " + (r.erreur || "refusé"));
}
async function clavierBascule(cle){
  const r = await api("clavier", "bascule:" + cle);
  await rafraichir(r.ok ? "Touches de bascule changées" : "Échec : " + (r.erreur || "refusé"));
}
async function basculeHeureAuto(){
  const r = await api("heure-auto", "toggle");
  await rafraichir(r.ok ? null : "Échec : " + (r.erreur || "mot de passe refusé"));
}
async function basculeAvion(){
  const r = await api("avion", "toggle");
  if(r.ok){ etat.avion = etat.avion === "on" ? "off" : "on"; rendSection(); }
}
async function setPerf(p){
  const r = await api("perf", p);
  if(r.ok){ etat.perf = p; rendSection(); toast("Profil : " + p); }
}
/*  ALEX : « les outils pour la luminosité fonctionnent, mais pas dans les
    Paramètres. » Cette fonction JETAIT la réponse. Quand le réglage était
    refusé — droits manquants sur le rétroéclairage, le cas d'Alex — la page
    ne disait RIEN : le curseur glissait, l'écran ne bougeait pas, et aucun
    motif nulle part. Le moteur, lui, renvoie déjà la raison exacte dans
    « erreur » ; personne ne la lisait.

    Même faute que le bouton du dock, et même correctif : on lit la réponse,
    et on rafraîchit pour que le curseur retombe sur la valeur RÉELLE de la
    machine plutôt que de rester là où le doigt l'a laissé. */
async function setLum(n){
  const r = await api("lumiere", n);
  if(!r.ok){ await rafraichir("Luminosité : " + (r.erreur || "refusé")); }
}
async function setTheme(t){
  const r = await api("theme", t);
  //  appliqueApparence() manquait ICI, et seulement ici : setPolice et
  //  setAccent l'appellent tous les deux depuis toujours. C'est ce qui rendait
  //  le mode clair invisible dans cette fenêtre — le bureau changeait, les
  //  Paramètres restaient noirs.
  if(r.ok){ etat.theme = t; appliqueApparence(); rendSection(); toast("Thème : " + t); }
}
async function setPolice(p){
  const r = await api("police", p);
  if(r.ok){ etat.police = p; appliqueApparence(); rendSection(); toast("Police : " + p); }
}
async function setAccent(a){
  const r = await api("accent", a);
  if(r.ok){ etat.accent = a; appliqueApparence(); rendSection(); toast("Accent : " + a); }
}
async function setFond(f){
  const r = await api("fond", f);
  await rafraichir(r.ok ? "Fond d'écran appliqué" : "Échec : " + (r.erreur || "commande refusée"));
}
async function fondPerso(){
  const r = await api("fond-perso", "remplir");
  await rafraichir(r.ok ? "Fond d'écran appliqué" : "Échec : " + (r.erreur || "commande refusée"));
}
/* Capture d'écran → fond d'écran, en un seul geste. */
async function fondCapture(mode){
  const r = await api("fond-capture", mode);
  if(r.ok) toast(mode === "zone" ? "Cadre la zone à la souris…" : "Capture en cours…");
}
async function capture(mode){ await api("capture", mode); }

/* --- Sections ------------------------------------------------------------- */
function contenu(cle){
  switch(cle){
    case "wifi": {
      //  On montre l'ÉTAT avant les boutons : allumé ou non, sur quel réseau,
      //  avec quelle force. C'est ce qu'on vient vérifier neuf fois sur dix.
      const w = etat.wifi || {};
      const absent = w.radio === "absent";
      const allume = w.radio === "enabled";
      return `<h2>Wi-Fi</h2><div class="sub">Réseaux, connexion, mots de passe</div>
      ${absent
        ? `<p class="notice">Aucune carte Wi-Fi détectée sur cette machine.</p>`
        : srow("Wi-Fi", allume ? "Carte radio allumée" : "Carte radio éteinte",
               sw(allume, "basculeWifi()"))}
      ${allume && w.reseau
        ? srow("Réseau connecté", `${esc(w.reseau)} — signal ${w.signal} %`, barres(w.signal))
        : (allume ? srow("Réseau connecté", "Aucun — choisis-en un ci-dessous") : "")}

      ${/*  LES OUTILS QUI MANQUAIENT.
             Alex, les deux pages côte à côte : « il manque des outils, regarde
             la 2e image — la 2e image a plus d'outils sur le mode wi-fi ». La
             démo portait cette bascule, l'ISO ne l'avait pas — alors que c'est
             ICI qu'elle fait quelque chose de réel : lexos-net-autoconnect et
             son minuteur existent depuis longtemps, mais on ne pouvait les
             allumer qu'en ligne de commande.

             CE QUI N'EST PAS REPRIS, ET POURQUOI. La démo a aussi « Simuler
             une panne d'accès à internet ». C'est un accessoire de démo : il
             sert à FAIRE VOIR l'orange sur une page qui n'a pas de vraie
             carte réseau. Sur l'ISO, l'orange vient de la machine elle-même
             (nmcli networking connectivity) — un interrupteur pour mentir sur
             son propre état n'y aurait aucun sens. */""}
      ${absent ? "" : srow("Connexion auto. aux réseaux ouverts",
             "Désactivée par défaut pour ta sécurité — demande confirmation",
             sw(!!w.auto, "basculeWifiAuto()"))}

      ${absent ? "" : `<p class="notice">L'icône Wi-Fi dit son état par sa couleur :
        <b style="color:var(--ok)">vert</b> connecté ·
        <b style="color:var(--warn)">orange</b> connecté mais sans accès à internet ·
        <b style="color:var(--off)">rouge</b> pas de connexion.</p>`}

      ${allume ? (() => {
        /*  LA LISTE QUI MANQUAIT. Le panneau savait dire « connecté » ou
            « aucun », et rien d'autre : sans réseau, il fallait deviner
            qu'un bouton ouvrait un autre outil. Or au premier démarrage il
            n'y a JAMAIS de réseau — et sans réseau, ni météo, ni catalogue,
            ni mises à jour. C'est le premier geste qu'on fait sur une
            machine neuve, et c'était le seul qu'on ne pouvait pas faire ici. */
        const rs = w.reseaux || [];
        if(!rs.length) return `<h3 class="cpt-h3">Réseaux à portée</h3>
          <p class="notice">Aucun réseau trouvé pour l'instant.
            <button class="btn ghost" onclick="chercheWifi()">Chercher encore</button></p>`;
        return `<h3 class="cpt-h3">Réseaux à portée</h3>
        ${rs.map(r => `<div class="srow wifi-l">
          <div style="flex:1;min-width:0">
            <div class="t">${esc(r.ssid)}
              ${r.protege ? `<span class="cadenas" title="${esc(r.securite)}">🔒</span>`
                          : `<span class="cadenas ouvert" title="Réseau ouvert — tout le monde peut lire ce qui y passe">⚠</span>`}
            </div>
            <div class="d">${r.actif ? "Connecté" : (r.protege ? esc(r.securite) : "Ouvert, sans mot de passe")} — signal ${r.signal} %</div>
          </div>
          ${barres(r.signal)}
          ${r.actif
            ? `<span class="etat ok">connecté</span>
               <button class="btn ghost" onclick="coupeWifi()">Déconnecter</button>`
            : `<button class="btn ghost" onclick="choisitWifi('${jsq(r.ssid)}')">Se connecter</button>`}
        </div>
        ${wifiChoisi === r.ssid && !r.actif ? `<div class="srow" style="display:block">
          ${r.protege
            ? `<div class="t" style="margin-bottom:8px">Mot de passe de « ${esc(r.ssid)} »</div>
               <div class="row" style="align-items:center">
                 <input class="champ" id="wifiMdp" type="password" autocomplete="off"
                        placeholder="mot de passe du réseau"
                        onkeydown="if(event.key==='Enter')brancheWifi()">
                 <button class="btn" onclick="brancheWifi()">Se connecter</button>
                 <button class="btn ghost" onclick="choisitWifi('')">Annuler</button>
               </div>
               <div class="sub" style="margin-top:8px">Le mot de passe reste sur
                 cette machine : il part au gestionnaire de réseau et n'est
                 écrit dans aucun journal.</div>`
            : `<div class="row"><button class="btn" onclick="brancheWifi()">Se connecter sans mot de passe</button>
               <button class="btn ghost" onclick="choisitWifi('')">Annuler</button></div>
               <div class="sub" style="margin-top:8px">Réseau ouvert : ce qui
                 y passe peut être lu par n'importe qui autour. À éviter pour
                 les mots de passe et les paiements.</div>`}
        </div>` : ""}`).join("")}
        <div class="row"><button class="btn ghost" onclick="chercheWifi()">Chercher encore</button></div>`;
      })() : ""}

      ${btnOuvrir("wifi","Ouvrir l'outil réseau")}
      <p class="notice">En ligne de commande : <code>lexos wifi</code> ·
      <code>lexos net password "&lt;réseau&gt;"</code> pour un mot de passe oublié.</p>`;
    }
    case "reseau": {
      const n = etat.reseau || {};
      return `<h2>Réseau</h2><div class="sub">Filaire, mode avion, VPN</div>
      ${srow("Mode avion","Coupe Wi-Fi, Bluetooth et données",
             sw(etat.avion==="on","basculeAvion()"))}
      ${n.filaire === null || n.filaire === undefined
        ? ""
        : srow("Câble Ethernet",
               n.filaire ? "Branché" + (n.ip ? " — " + esc(n.ip) : "") : "Débranché",
               `<span class="etat ${n.filaire?"ok":"off"}">${n.filaire?"connecté":"absent"}</span>`)}
      ${/*  « on ne voit pas sur quel réseau on est connecté ». Vrai : cette
             page dit le filaire, le mode avion, jamais le Wi-Fi — pour voir
             le SSID il fallait ouvrir la section Wi-Fi À CÔTÉ. Cette page-ci,
             « Réseau », est justement celle qu'on ouvre en premier pour
             savoir « sur quoi je suis ». etat.wifi est déjà chargé pour
             cette page-là ; pas de nouvel appel, juste l'afficher ici aussi. */""}
      ${(() => {
        const w = etat.wifi || {};
        if(w.radio === "absent") return "";
        let texte, classe, mot;
        if(w.radio !== "enabled"){ texte = "Éteinte"; classe = "off"; mot = "éteinte"; }
        else if(w.reseau){
          texte = `Connecté à ${esc(w.reseau)} — signal ${w.signal} %`;
          classe = w.internet === "full" ? "ok" : "att";
          mot = classe === "ok" ? "connecté" : "sans internet";
        } else {
          texte = "Aucun réseau"; classe = "off"; mot = "aucun";
        }
        return srow("Wi-Fi", texte, `<span class="etat ${classe}">${mot}</span>`);
      })()}
      ${btnOuvrir("reseau","Ouvrir l'outil réseau")}
      <p class="notice">VPN : <code>lexos vpn import fichier.ovpn</code> (OpenVPN) ou un
      <code>.conf</code> WireGuard, puis <code>lexos vpn connect "&lt;nom&gt;"</code>.</p>`;
    }
    case "bluetooth": {
      /*  LA LISTE QUI MANQUAIT, comme pour le Wi-Fi et pour la même barre de
          son : le panneau disait « prêt à appairer » sans jamais montrer QUOI.
          Le cinéma maison d'Alex était introuvable, faute d'une liste où le
          voir. Appairés d'abord, puis ce que la recherche a entendu. */
      const bt = etat.bluetooth || {};
      const radio = bt.radio;
      const app = bt.appareils || [];
      const GENRES = {"audio-card":"🔊","audio-headset":"🎧","audio-headphones":"🎧",
                      "input-keyboard":"⌨","input-mouse":"🖱","phone":"📱",
                      "computer":"💻","input-gaming":"🎮"};
      return `<h2>Bluetooth</h2><div class="sub">Enceintes, cinéma maison, casques, manettes</div>
      ${radio === null || radio === undefined
        ? `<p class="notice">Aucun contrôleur Bluetooth sur cette machine.</p>`
        : srow("Bluetooth", radio ? "Allumé" : "Éteint",
               sw(radio, "basculeBluetooth()"))}
      ${radio ? `<h3 class="cpt-h3">Appareils</h3>
        ${app.length ? app.map(d => srow(
            `${GENRES[d.genre] || "·"} ${esc(d.nom)}`,
            d.connecte ? "Connecté — le son peut sortir ici"
                       : (d.appaire ? "Appairé, pas connecté" : "À portée, jamais appairé"),
            d.connecte
              ? `<button class="btn ghost" onclick="btCoupe('${jsq(d.adresse)}')">Déconnecter</button>`
              : `<button class="btn ghost" onclick="btBranche('${jsq(d.adresse)}')">${d.appaire ? "Connecter" : "Appairer"}</button>`
          )).join("")
          : `<p class="notice">Aucun appareil connu. Mets ton enceinte ou ta
             barre de son en <b>mode appairage</b> (souvent un bouton Bluetooth
             à tenir enfoncé), puis lance la recherche.</p>`}
        <div class="row"><button class="btn ghost" id="btCherche" onclick="btCherche()">Rechercher (12 s)</button></div>
        <p class="notice">Une fois l'enceinte connectée, elle apparaît dans
          <b>Son → Sortie audio</b> — c'est là qu'on lui envoie le son.</p>`
        : ""}
      ${btnOuvrir("bluetooth","L'outil complet (lexos bt)")}`;
    }
    case "ecrans": {
      //  La question qu'on se pose devant cette section est « qu'est-ce qui
      //  est branché, et en quelle définition ? ». On y répond tout de suite.
      const ec = etat.ecrans || [];
      return `<h2>Écrans</h2><div class="sub">Disposition multi-écrans</div>
      ${ec.length
        ? ec.map(e=>srow(esc(e.nom) + (e.principal ? " — principal" : ""),
                         e.definition ? esc(e.definition) : "branchée, aucune image")).join("")
        : `<p class="notice">${esc(etat.ecrans_probleme
             || "Aucune sortie vidéo branchée.")}</p>`}
      ${/*  « xrandr absent OU session Wayland » mettait les deux causes dans
             le même sac, et laissait le lecteur choisir. Ce ne sont pas les
             mêmes remèdes : l'un s'installe, l'autre se choisit à la
             connexion. Le pont dit maintenant LAQUELLE des deux (ou une
             troisième : pas de session graphique du tout), et la page se
             contente de la recopier. Quand tout va bien, la chaîne est vide
             et on retombe sur la phrase neutre — parce qu'une machine peut
             aussi n'avoir vraiment aucun écran branché. */""}
      ${srow("Étendre, dupliquer, écran principal","Résolution et disposition de chaque écran")}
      ${(() => {
        const ec = etat.ecrans || [];
        const av = (etat.echelle && etat.echelle.pourcent) || "100";
        let h = "";
        //  Une définition par écran : chaque dalle a SA liste, et proposer
        //  celle du voisin donnerait un écran noir.
        for(const e of ec){
          if(!e.modes || e.modes.length < 2) continue;
          h += `<div class="srow" style="display:block">
            <div class="t" style="margin-bottom:8px">Définition — ${esc(e.nom)}${
              e.principal ? " (écran principal)" : ""}</div>
            <div class="row">${e.modes.slice(0,8).map(m =>
              `<button class="btn ${m===e.definition?"sel":"ghost"}"
                 onclick="setDefinition('${jsq(e.nom)}','${jsq(m)}')">${esc(m)}</button>`
              ).join("")}</div>
          </div>`;
        }
        h += `<div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Taille de l'affichage</div>
          <div class="row">${["100","125","150","175","200"].map(v =>
            `<button class="btn ${v===av?"sel":"ghost"}"
               onclick="setEchelle('${v}')">${v} %</button>`).join("")}</div>
          <div class="sub" style="margin-top:8px">Agrandit le texte et les
            boutons <b>sans rendre l'image floue</b> : les applications
            dessinent plus grand dès le départ, au lieu qu'on étire l'image
            une fois dessinée. Les fenêtres déjà ouvertes suivent après
            réouverture.</div>
        </div>`;
        return h;
      })()}
      ${btnOuvrir("ecrans","Ouvrir Écrans")}`;
    }
    case "son": {
      const so = etat.son || {};
      const connu = so.volume >= 0;
      return `<h2>Son</h2><div class="sub">Volume, périphériques</div>
      ${connu ? srow("Sourdine", so.muet ? "Le son est coupé" : "Le son passe",
                     sw(so.muet, "basculeMuet()")) : ""}
      ${connu ? `<div class="srow"><div class="t">Volume de sortie</div>
        <div style="display:flex;align-items:center;gap:12px;flex:1;max-width:420px">
          <input type="range" min="0" max="100" value="${so.volume}"
                 style="flex:1;accent-color:var(--ac)"
                 oninput="apercuVolume(this.value)" onchange="setVolume(this.value)">
          <span id="volVal" style="min-width:44px;text-align:right;font-weight:600">${so.volume} %</span>
        </div></div>`
        : `<p class="notice">Volume illisible : pactl est absent.</p>`}
      ${so.casque ? srow("Casque audio","Branché — le son sort dans le casque") : ""}
      ${(() => {
        const so = (etat.son && etat.son.sorties) || [];
        if(!so.length) return "";
        //  Une enceinte Bluetooth appairée apparaît ici TOUTE SEULE : PipeWire
        //  en fait une sortie comme les autres. Pas de liste séparée pour le
        //  sans-fil — deux listes finiraient par ne plus dire la même chose.
        return `<div class="sub" style="margin-top:20px">Où sort le son</div>
        <div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Sortie audio</div>
          <div class="row">${so.map(x =>
            `<button class="btn ${x.actif?"sel":"ghost"}"
               onclick="setSortieSon('${jsq(x.nom)}')"
               title="${esc(x.nom)}">${esc(x.titre)}</button>`).join("")}</div>
          <div class="sub" style="margin-top:8px">Haut-parleurs, casque, télé en
            HDMI, cinéma maison, enceinte Bluetooth — ce qui joue déjà suit
            aussitôt. Une enceinte sans fil apparaît ici dès qu'elle est
            appairée dans <b>Bluetooth</b>.</div>
        </div>`;
      })()}
      ${btnOuvrir("son","Ouvrir le mélangeur")}
      <p class="notice">En ligne de commande : <code>lexos son</code> —
      volume, sortie, profils, tout au clavier.</p>`;
    }
    case "energie": return `<h2>Énergie</h2><div class="sub">Profil de performance</div>
      ${(etat.batterie && etat.batterie.niveau >= 0)
        ? `<div class="srow">
             <div style="display:flex;align-items:center;gap:14px;flex:1;min-width:0">
               ${batGlyph(etat.batterie.niveau, etat.batterie.secteur, 46)}
               <div style="min-width:0">
                 <div class="t">Batterie — ${etat.batterie.niveau} %</div>
                 <div class="d">${etat.batterie.secteur
                    ? "Branché sur le secteur — en charge"
                    : "Sur batterie"}</div>
               </div>
             </div>
             ${jauge(etat.batterie.niveau)}
           </div>`
        : srow("Alimentation","Aucune batterie — machine de bureau")}
      <div class="row">${["petit","medium","vif","performant","max"].map(p=>
        `<button class="btn ${p===etat.perf?"sel":"ghost"}" onclick="setPerf('${p}')">${p}</button>`).join("")}</div>
      <div style="display:flex;align-items:center;gap:18px;margin-top:12px">
        <span style="color:var(--ac)">${perfGauge(132, etat.perf)}</span>
        <div><div class="t" style="font-weight:600">${etat.perf} — ${(PERF_RPM[etat.perf]||4)}000 tr/min</div>
        <div class="d">${PERF_LABEL[etat.perf] || ""}</div></div>
      </div>
      <p class="notice">Chaque profil règle vraiment le gouverneur du processeur, zram,
      le compositing et les services (<code>lexos perf</code>).</p>

      <div class="srow" style="display:block;margin-top:16px">
        <div class="t" style="margin-bottom:6px">Luminosité de l'écran</div>
        <div style="display:flex;align-items:center;gap:12px">
          <input type="range" min="5" max="100" value="${etat.lumiere ?? 70}"
                 style="flex:1;accent-color:var(--ac)"
                 oninput="apercuLum(this.value)" onchange="setLum(this.value)">
          <span id="lumVal" style="min-width:44px;text-align:right;font-weight:600">${etat.lumiere ?? 70} %</span>
        </div>
      </div>
      ${srow("Baisser la luminosité sur batterie","Quand le secteur est débranché",
             sw(etat.energie && etat.energie.dimBat, "basculeDimBat()"))}

      <h3 class="cpt-h3">Scan matériel</h3>
      ${srow("LexOS Boost",
             "Inventaire de la machine, mesures, optimisations — dans sa fenêtre",
             `<button class="btn ghost" onclick="ouvreBoost()">Ouvrir</button>`)}
      ${srow("Éteindre l'écran après","L'écran s'éteint, la machine continue de tourner",
             menu("ecranOff", (etat.energie && etat.energie.ecranOff) || "10",
                  [["1","1 min"],["5","5 min"],["10","10 min"],["30","30 min"],["0","jamais"]]))}
      ${srow("Mise en veille après","La machine s'endort pour de bon",
             menu("veille", (etat.energie && etat.energie.veille) || "30",
                  [["15","15 min"],["30","30 min"],["60","60 min"],["120","120 min"],["0","jamais"]]))}
      <p class="notice">La luminosité est réglée pour de vrai —
      <code>lexos lumiere 60</code>, <code>lexos lumiere eco</code>, ou
      <code>lexos lumiere +10</code>. LexOS pilote le rétroéclairage quand la
      machine en a un ; sinon il assombrit l'image et le dit clairement, parce
      que ça n'économise alors aucune batterie.</p>
      ${btnOuvrir("energie","État détaillé (terminal)")}`;
    case "usb": {
      const app = etat.usb || [];
      return `<h2>Appareils USB</h2><div class="sub">Branchements détectés</div>
      ${app.length ? app.map(a=>`
        <div class="srow">
          <span style="width:56px;height:56px;display:flex;align-items:center;
                       justify-content:center;flex:none">${
            a.disque ? diskGlyph(46) : usbGlyph(44)}</span>
          <div style="flex:1">
            <div class="t">${esc(a.nom)} — ${esc(a.taille)}</div>
            <div class="d">${a.monte ? "Monté sur " + esc(a.monte)
                                     : "Branché, pas encore ouvert"} · ${esc(a.dev)}</div>
          </div>
          <button class="btn ghost" onclick="ejecte('${jsq(a.dev)}')">Éjecter</button>
        </div>`).join("")
        : `<p class="notice">Aucun support amovible branché. Branche une clé ou un
           disque : il apparaîtra ici. Le disque système n'est jamais listé —
           le bouton d'à côté s'appelle « Formater ».</p>`}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Actions sur l'appareil</div>
        <div class="row">
          <button class="btn" onclick="actionUsb('vide-memoire')">Vide mémoire +</button>
          <button class="btn ghost" onclick="actionUsb('terminal')">Terminal de l'appareil</button>
          <button class="btn ghost" onclick="actionUsb('formater')">⚠ Formater…</button>
        </div>
      </div>
      <p class="notice"><code>lexos vide-memoire</code> copie en un clic tout le contenu
      d'un téléphone (MTP/iPhone) ou d'une clé. <code>lexos usb terminal</code> ouvre un
      terminal <b>sur le téléphone</b> (adb, débogage USB requis).
      <code>lexos format</code> formate une clé ou un téléphone — jamais le disque
      système, et seulement après confirmation explicite.</p>
      ${/*  ═══ UNE CIBLE SERVIE PAR LE MOTEUR, JAMAIS PROPOSÉE PAR LA PAGE ═══
            act_ouvrir déclare 38 fenêtres ; la page n'en offrait que 35.
            « usb », « confidentialite » et « maj » étaient écrites, testées
            par le banc des boutons… et impossibles à déclencher depuis
            l'écran. Le banc vérifiait donc du code que personne ne pouvait
            atteindre. */""}
      ${btnOuvrir("usb","Ouvrir l'outil complet (terminal)")}`;
    }
    case "mac": {
      const m = etat.mac || {};
      return `<h2>Mac (Apple)</h2><div class="sub">Wi-Fi Broadcom, ventilateurs, touches F1-F12</div>
      ${srow("Cette machine",
             m.apple ? "Matériel Apple — " + esc(m.modele || "modèle inconnu")
                     : "Ce n'est pas un Mac" + (m.modele ? " — " + esc(m.modele) : ""),
             `<span class="etat ${m.apple?"ok":"abs"}">${m.apple?"Apple":"autre"}</span>`)}
      ${btnOuvrir("mac","Outils Mac (terminal)")}
      <p class="notice">${m.apple
        ? "Wi-Fi Broadcom, pilotage des ventilateurs et touches F1-F12 : <code>lexos mac</code> s'en occupe."
        : "Ces réglages ne servent que sur du matériel Apple. Ils restent là au cas où tu déplacerais ce disque."}</p>`;
    }
    case "apparence": return `<h2>Apparence</h2><div class="sub">Thème, accent, barre d'outils</div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Thème du bureau</div>
        <div class="row">
          <button class="btn ${etat.theme==="sombre"?"sel":"ghost"}" onclick="setTheme('sombre')">🌑 Sombre — LexOS Noir</button>
          <button class="btn ${etat.theme==="clair"?"sel":"ghost"}" onclick="setTheme('clair')">☀ Clair — thème de jour</button>
        </div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Couleur de l'interface</div>
        <div class="row">${STYLES.map(([n,titre,desc])=>
          `<button class="btn ${n===etat.accent?"sel":"ghost"}" onclick="setAccent('${n}')"
             title="${desc}"><span class="pastille" style="background:${ACCENTS[n]}"></span>${titre}</button>`
          ).join("")}</div>
        <div class="sub" style="margin-top:6px">${
          STYLES.map(([,t,d])=>`${t} — ${d}`).join(" · ")}</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Autres couleurs</div>
        <div class="row">${Object.entries(ACCENTS).map(([n,c])=>
          `<button class="swatch${n===etat.accent?" sel":""}" style="background:${c}"
             title="${n}" onclick="setAccent('${n}')"></button>`).join("")}</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Police d'écriture</div>
        <div class="row">${POLICES.map(([n,titre,fam])=>
          `<button class="btn ${n===etat.police?"sel":"ghost"}" style="font-family:${fam}"
             onclick="setPolice('${n}')">${titre}</button>`).join("")}</div>
        <div class="t" style="margin:16px 0 8px">Écritures à la main</div>
        <div class="row">${ECRITURES.map(([n,titre,fam])=>
          `<button class="btn ${n===etat.police?"sel":"ghost"}"
             style="font-family:'${fam}',cursive;font-size:16px"
             title="${fam}" onclick="setPolice('${n}')">${titre}</button>`).join("")}</div>
        <div class="sub" style="margin-top:8px">Douze écritures livrées avec LexOS —
          chacune s'affiche ici dans sa propre police. Les fenêtres déjà ouvertes
          gardent l'ancienne : ferme-les et rouvre-les.</div>
      </div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Position du dock</div>
        <div class="row">${["droite","gauche","bas","haut"].map(d=>
          `<button class="btn ${d===etat.dock?"sel":"ghost"}" onclick="setDock('${d}')">${
            d.charAt(0).toUpperCase()+d.slice(1)}</button>`).join("")}</div>
      </div>
      ${srow("Masquer la barre d'outils","Elle glisse hors de l'écran ; la poignée du bord la ramène",
             sw(etat.barreCachee, "basculeBarre()"))}
      ${(() => {
        /*  ═══ L'INTERRUPTEUR QUI NE COMMANDAIT PLUS RIEN ═══
            ALEX : « l'effet d'animation n'est pas là quand je ferme des
            fenêtres ». Il avait raison, et ce n'était pas un réglage de
            travers : ces effets étaient rendus par COMPIZ, retiré de Debian
            trixie. lexos-wm ne le trouvait plus et se repliait sur xfwm4, qui
            n'a AUCUNE animation. L'interrupteur restait là, se cliquait, et
            ne commandait rien.

            C'est picom qui fait le travail maintenant. Et cette ligne DIT ce
            qui manque quand il manque quelque chose : un interrupteur qui
            revient tout seul à sa place sans un mot est le geste le plus
            déroutant qu'une page puisse offrir. */
        const c = etat.crt || {};
        if(!c.dispo){
          return srow("Effets d'ouverture/fermeture (TV 1980)",
            "lexos-crt n'a pas répondu — en ligne de commande : <code>lexos crt</code>",
            `<span class="etat abs">indisponible</span>`);
        }
        const manque = !c.picom
            ? "picom n'est pas installé — <code>lexos install picom</code>"
            : (c.picom_version && c.picom_version < c.picom_min
                ? `picom v${c.picom_version} est trop ancien : les animations arrivent à la v${c.picom_min}`
                : (!c.accel3d
                    ? "pas d'accélération 3D réelle sur cette machine — les effets resteraient saccadés"
                    : ""));
        const desc = manque
          ? manque
          : (c.tourne ? "En marche — la fenêtre s'écrase vers une ligne, puis s'éteint"
                      : "La fenêtre s'écrase vers une ligne, la ligne se referme en un point");
        return srow("Effets d'ouverture/fermeture (TV 1980)", desc,
          manque ? `<span class="etat abs">impossible ici</span>`
                 : sw(c.voulu === "on", "basculeCrt()"));
      })()}
      ${btnOuvrir("apparence","Réglages fins (XFCE)")}
      <p class="notice">L'extinction « téléviseur » est jouée par picom, et
      elle exige une vraie accélération 3D — sur du rendu logiciel, mettre une
      fenêtre à l'échelle soixante fois par seconde rendrait la machine
      collante. <code>lexos crt status</code> dit ce qui manque, le cas
      échéant. Le changement s'applique tout de suite : pas besoin de fermer
      la session.</p>`;
    case "bureau": return `<h2>Bureau LexOS</h2><div class="sub">Fond d'écran</div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Fond d'écran</div>
        <div class="row">
          ${/*  ═══ LE CHOIX COURANT SE VOIT — ALEX : « POUR CHANGER DE
                   COULEUR SUR LE BOUTON SÉLECTIONNÉ » ═══
                Ces cinq boutons étaient écrits en dur « btn ghost », sans la
                moindre condition : le fond posé ressemblait aux quatre
                autres. C'était le seul choix de toute la page dans ce cas,
                avec la galerie juste en dessous — partout ailleurs (thème,
                accent, police, dock, définition d'écran, profil de
                performance) le dépôt écrit déjà « btn ${x ? "sel" : "ghost"} ».
                La classe .sel existe depuis toujours dans style.css:52.
                Ce qui manquait était de l'autre côté : etat() ne disait pas
                quel fond est posé. */""}
          ${(() => { const F = (etat.fond || {}).cle; const c = k => F === k ? "sel" : "ghost"; return `
          <button class="btn ${c("secu")}" onclick="setFond('secu')">Sécurité</button>
          <button class="btn ${c("demon")}" onclick="setFond('demon')">LexOS 1.0</button>
          <button class="btn ${c("keyart")}" onclick="setFond('keyart')">Explorateur</button>
          <button class="btn ${c("nomad")}" onclick="setFond('nomad')">Nomad</button>`; })()}
        </div>
        <h3 style="margin-top:18px">Étiquettes des dossiers</h3>
        <p class="d">Les dossiers standards portent déjà leurs trois lettres
        (DOC, IMG, MUS…). Pour ceux que tu crées ou renommes, cette commande
        les écrit aussi — relance-la après un renommage.</p>
        <div class="row">
          <button class="btn" onclick="ouvrir('etiquettes')">Étiqueter mes dossiers</button>
        </div>
        <h3 style="margin-top:18px">Applications sur le dock</h3>
        <p class="d">Pour en ajouter une : clic droit sur son icône (bureau ou
        Fichiers) → « Épingler au dock ». Pour en retirer une : clic droit sur
        elle DANS le dock → décocher « Garder dans le dock ».</p>
        <div class="row">
          <button class="btn ghost" onclick="ouvrir('dock-epingles')">Voir ce qui est épinglé</button>
          <button class="btn" onclick="fondPerso()">🖼 Une image à moi…</button>
        </div>
      </div>

      ${(() => {
        /*  ═══ MES IMAGES — LA GALERIE ═══
            « fais que les images qu'on télécharge, on peut les utiliser
            comme fond d'écran aussi. » Le bouton au-dessus ouvrait un
            sélecteur AVEUGLE : il fallait se rappeler du nom du fichier.
            Ici, les images de Téléchargements et d'Images en vignettes,
            les plus récentes d'abord — celle qu'on vient de télécharger
            arrive en tête — et un clic la pose.

            Les vignettes viennent de /api/fond-vignette?i=N : la page ne
            connaît AUCUN chemin, seulement des indices que la machine
            revalide. Et chaque vignette est posée sur NOIR avec
            object-fit:contain — « fais les images sur un fond noir avec
            les images » : l'aperçu montre exactement ce que le bureau
            montrera, une photo verticale comprise. */
        const fp = etat.fonds_perso || [];
        if(!fp.length) return `<div class="srow" style="display:block">
          <div class="t" style="margin-bottom:4px">Mes images</div>
          <div class="d">Aucune image dans Téléchargements ni dans Images pour
          l'instant — tout ce que tu y déposeras apparaîtra ici.</div></div>`;
        return `<div class="srow" style="display:block">
          <div class="t" style="margin-bottom:4px">Mes images</div>
          <div class="d" style="margin-bottom:10px">Téléchargements et Images,
            les plus récentes d'abord. Un clic : l'image entière, sur fond
            noir, sur tous les écrans.</div>
          <div class="row" style="gap:10px">
            ${fp.map(f => `<div class="wall-item">
               <button class="wall-swatch${((etat.fond||{}).i === f.i) ? " sel" : ""}" title="${esc(f.nom)}"
                  onclick="setFondFichier(${Number(f.i) | 0})"
                  style="width:96px;height:56px;background:#000 url('/api/fond-vignette?i=${Number(f.i) | 0}') center/contain no-repeat"></button>
               <button class="wall-voir" title="Voir en grand"
                  onclick="event.stopPropagation();ouvreFondFichier(${Number(f.i) | 0})">🔍</button>
              </div>`).join("")}
          </div>
        </div>`;
      })()}

      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Autocollants sur le fond</div>
        <div class="sub" style="margin-bottom:8px">Un personnage posé sur ton
        fond d'écran, comme dans la démo. Ils s'empilent ; « Enlever »
        retrouve le fond d'origine tel quel.</div>
        <div class="row">
          <button class="btn ghost" onclick="poseAutocollant('rock')">🤘 Lex — bebeilles</button>
          <button class="btn ghost" onclick="poseAutocollant('salut')">👋 Lex — salut</button>
          <button class="btn ghost" onclick="poseAutocollant('prevost')">🛡 Badge PREVOST</button>
          <button class="btn" onclick="poseAutocollant('enlever')">Enlever</button>
        </div>
      </div>

      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Depuis une capture d'écran</div>
        <div class="sub" style="margin-bottom:8px">Prend une image de l'écran et
        la pose aussitôt en fond.</div>
        <div class="row">
          <button class="btn ghost" onclick="fondCapture('plein')">📷 Tout l'écran</button>
          <button class="btn ghost" onclick="fondCapture('zone')">✂ Une zone</button>
        </div>
      </div>

      <p class="notice">Aussi : clic droit sur une image dans Fichiers →
      « Définir comme fond d'écran », ou <code>lexos wallpaper ~/Images/photo.jpg</code>.</p>
      ${(() => {
        //  Les captures n'ont pas de section à elles, et en créer une pour un
        //  seul réglage donnerait une page presque vide. Elles vivent donc
        //  ici, sous le même titre que l'autre qualité d'image : c'est ainsi
        //  qu'Alex les a demandées, ensemble.
        const f = (etat.image && etat.image.capture) || "png";
        return `<div class="sub" style="margin-top:20px">Qualité des captures d'écran</div>
        <div class="srow" style="display:block">
          <div class="t" style="margin-bottom:8px">Format des images</div>
          <div class="row">
            <button class="btn ${f==="png"?"sel":"ghost"}"
              onclick="setCaptureFormat('png')">PNG — sans perte</button>
            <button class="btn ${f==="jpeg"?"sel":"ghost"}"
              onclick="setCaptureFormat('jpeg')">JPEG — plus léger</button>
          </div>
          <div class="sub" style="margin-top:8px">Une capture sert souvent à
            <b>montrer du texte</b> : le PNG le garde parfaitement net. Le JPEG
            pèse deux à quatre fois moins — pratique pour envoyer par message,
            au prix d'un texte très légèrement adouci.</div>
          ${/*  ═══ TROIS BOUTONS QUI N'EXISTAIENT PAS ═══
                La fonction capture() était écrite (app.js), l'action
                « capture » était dans la table ACTIONS, act_capture était
                implémentée et acceptait photo|zone|fenetre — et AUCUN bouton,
                aucun onclick, aucune autre fonction ne l'appelait. Du code
                complet, relié des deux côtés, et injoignable depuis l'écran.
                Le réglage du format était là, juste au-dessus, sans le geste
                qu'il règle. */""}
          <div class="t" style="margin:16px 0 8px">Prendre une capture</div>
          <div class="row">
            <button class="btn" onclick="capture('photo')">Tout l'écran</button>
            <button class="btn ghost" onclick="capture('zone')">Une zone…</button>
            <button class="btn ghost" onclick="capture('fenetre')">Une fenêtre</button>
          </div>
          <div class="sub" style="margin-top:8px">Aussi au clavier :
            <b>Impr. écran</b> pour tout l'écran, <b>Maj + Impr. écran</b> pour
            une zone. Les images vont dans <b>Images/Captures</b>.</div>
        </div>`;
      })()}
      ${btnOuvrir("bureau","Réglages fins (XFCE)")}`;
    case "multitaches": {
      const b = etat.bureaux || {nb:1, courant:0, fenetres:[]};
      const ap = etat.apercu || {moteur:"", coin:false, super:false, xcape:false};
      return `<h2>Multi-tâches</h2><div class="sub">Bureaux virtuels</div>
      ${srow("Bureaux virtuels",
             `${b.nb} bureau${b.nb>1?"x":""} en ce moment, 5 au maximum — ` +
             `plusieurs écrans sur le même écran. Tu es sur le bureau <b>${b.courant+1}</b>.`,
             `<div class="row" style="flex:none">` +
             Array.from({length:b.nb},(_,n)=>
               `<button class="btn ${n===b.courant?"sel":"ghost"}" onclick="vaBureau(${n})">${n+1}</button>`).join("") +
             (b.nb < 5 ? `<button class="btn ghost" title="Ajouter un bureau" onclick="setBureaux('plus')">+</button>` : "") +
             (b.nb > 1 ? `<button class="btn ghost" title="Enlever un bureau" onclick="setBureaux('moins')">−</button>` : "") +
             `</div>`)}
      ${b.fenetres && b.fenetres.length
        ? srow("Fenêtres par bureau",
               b.fenetres.map((n,i)=>`Bureau ${i+1} : ${n}`).join(" · "))
        : ""}
      <div class="sub">Vue d'ensemble</div>
      ${srow("Voir tous mes bureaux",
             ap.moteur
               ? `Tout s'écarte : les bureaux en rangée, les fenêtres du bureau
                  courant en aperçus. On clique un bureau pour y aller, une
                  fenêtre pour l'ouvrir.` +
                 (ap.moteur === "xfdashboard" ? "" :
                  ` <b>xfdashboard n'est pas installé</b> — on ouvre la liste
                    des fenêtres, qui montre les mêmes bureaux sans les
                    vignettes.`)
               : `Aucun outil de vue d'ensemble n'est installé sur cette
                  machine — il n'y a rien à ouvrir.`,
             ap.moteur
               ? `<button class="btn" onclick="ouvreApercu()">Ouvrir</button>`
               : `<span class="etat abs">absent</span>`)}
      ${srow("Touche Super seule",
             ap.xcape
               ? `Relâcher <b>Super</b> sans rien taper d'autre ouvre la vue,
                  comme sous Ubuntu. <b>Super+1</b> à <b>Super+${b.nb}</b>
                  continuent d'aller aux bureaux.`
               : `Demande <code>xcape</code>, qui n'est pas installé :
                  lui seul sait reconnaître une touche Super relâchée seule.`,
             ap.xcape ? sw(ap.super, "basculeSuperApercu()")
                      : `<span class="etat abs">absent</span>`)}
      ${srow("Coin actif",
             `Pousser la souris dans le coin <b>haut-gauche</b> ouvre la vue.
              Il faut y rester un court instant : viser le logo Applications,
              qui habite ce coin, ne déclenche rien.`,
             sw(ap.coin, "basculeCoin()"))}
      ${srow("Autocollant par appui long",
             ap.geste && ap.geste.xlib
               ? `Dans le gestionnaire de fichiers, tenir la touche <b>C</b> et
                  le bouton gauche <b>trois secondes</b> sur une photo découpe
                  son sujet et range le PNG transparent dans
                  <code>Images/Autocollants</code>.<br>
                  Tant que le geste est armé, <b>C</b> n'ouvre plus la recherche
                  au clavier du gestionnaire de fichiers — partout ailleurs elle
                  reste une lettre ordinaire.`
               : `Demande <code>python3-xlib</code>, qui n'est pas installé :
                  sans lui le veilleur ne peut pas reconnaître la touche.`,
             ap.geste && ap.geste.xlib
               ? sw(ap.geste.actif, "basculeGesteAutocollant()")
               : `<span class="etat abs">absent</span>`)}
      ${btnOuvrir("multitaches","Ouvrir les réglages de bureaux")}
      <div class="sub" style="margin-top:20px">Partager l'écran entre plusieurs fenêtres</div>
      ${srow("Placer une fenêtre où on veut",
             `Huit positions, au clavier ou en glissant la fenêtre vers un bord.
              Les touches <b>Début</b>, <b>Fin</b>, <b>Page↑</b> et <b>Page↓</b>
              forment un carré sur le clavier, à la même place que les quatre
              coins de l'écran — le geste est le dessin de ce qu'on veut.`,
             `<div class="tuiles" aria-hidden="true">
                <i class="hg"></i><i class="hd"></i><i class="bg"></i><i class="bd"></i>
              </div>`)}
      <div class="srow" style="display:block">
        <div class="raccourcis">
          <div><kbd>Super</kbd>+<kbd>Début</kbd><span>coin haut-gauche</span></div>
          <div><kbd>Super</kbd>+<kbd>Page↑</kbd><span>coin haut-droit</span></div>
          <div><kbd>Super</kbd>+<kbd>Fin</kbd><span>coin bas-gauche</span></div>
          <div><kbd>Super</kbd>+<kbd>Page↓</kbd><span>coin bas-droit</span></div>
          <div><kbd>Super</kbd>+<kbd>←</kbd><span>moitié gauche</span></div>
          <div><kbd>Super</kbd>+<kbd>→</kbd><span>moitié droite</span></div>
          <div><kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>↑</kbd><span>moitié haute</span></div>
          <div><kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>↓</kbd><span>moitié basse</span></div>
          <div><kbd>Super</kbd>+<kbd>↑</kbd><span>plein écran</span></div>
          <div><kbd>Super</kbd>+<kbd>↓</kbd><span>rendre sa taille</span></div>
        </div>
        <div class="sub" style="margin-top:8px">À la souris : glisse la fenêtre
          vers un bord pour la moitié, vers un coin pour le quart.</div>
      </div>
      <p class="notice"><b>Ctrl+Alt+←</b> et <b>Ctrl+Alt+→</b> passent au bureau
      précédent ou suivant, <b>Super+1</b> à <b>Super+${b.nb}</b> vont directement
      à l'un d'eux. Rien n'est fermé en changeant de bureau — les fenêtres sont
      mises de côté et retrouvées telles quelles.</p>`;
    }
    case "applications": {
      /*  ═══ CETTE PAGE ÉTAIT UNE DEUXIÈME PAGE D'APPLICATIONS PAR DÉFAUT ═══
          Elle affichait « Navigateur, courrier, gestionnaire de fichiers —
          quelle application ouvre quoi », et son bouton ouvrait le dialogue
          des types de fichiers de XFCE. C'est mot pour mot le sujet de la
          section « Applications par défaut », qui, elle, le fait pour de
          vrai. Deux pages pour la même chose, et la moins complète des deux
          arrivait la première dans le menu.

          CE QU'UBUNTU MET ICI, ET CE QU'ON PEUT HONNÊTEMENT EN REPRENDRE.
          Sa page « Applications » liste les logiciels installés et, pour
          chacun, ses PERMISSIONS : appareil photo, micro, notifications,
          accès aux fichiers. Ces permissions n'existent que parce que ses
          applications tournent en bac à sable (Flatpak, snap) et passent par
          des portails qui savent dire non.

          LexOS est un système Debian classique : un programme installé a les
          droits de la personne qui le lance, point. Fabriquer ici des
          interrupteurs « micro » ou « appareil photo » donnerait des boutons
          qui ne commanderaient RIEN — la pire chose qu'une page de réglages
          puisse faire. On le dit, et on renvoie là où il y a de vrais
          réglages. */
      return `<h2>Applications</h2><div class="sub">Installer, retirer, et qui a le droit de quoi</div>
      ${srow("Ajouter ou retirer un logiciel",
             "La logithèque LexOS : installer, mettre à jour, désinstaller",
             `<button class="btn" onclick="ouvrir('applications')">Ouvrir la logithèque</button>`)}
      ${srow("Un logiciel téléchargé sur le web",
             "Un paquet .deb, une AppImage, un script : double-clique dessus et LexOS l'installe. Il te montre d'abord ce que c'est et ce qui va se passer — et rien ne part sans ton accord. C'est « lexos-ouvrir » qui répond au double-clic.",
             `<button class="btn" onclick="ouvrir('fichier-telecharge')">Installer un fichier</button>`)}
      ${srow("Applications par défaut",
             "Quel logiciel ouvre les images, les PDF, les liens…",
             `<button class="btn ghost" onclick="allerA('defaut')">Y aller</button>`)}
      ${srow("Réglages d'une application",
             "Le bouton vert d'une fenêtre — ou Super + virgule — ouvre les réglages de CETTE application, pas ceux de l'ordinateur",
             `<span class="etat ok">Super + ,</span>`)}
      ${srow("Permissions par application",
             "Sur un système Debian classique, un programme a les droits de qui le lance : il n'y a pas de bac à sable par application à régler ici",
             `<button class="btn ghost" onclick="allerA('confidentialite')">Confidentialité</button>`)}
      <p class="notice">Firefox et Chromium sont installés. Google Chrome, lui,
      n'est pas libre : il ne peut pas être livré dans l'ISO. Son icône est
      quand même dans le dock — le premier clic l'installe depuis le dépôt
      officiel de Google (aussi : <code>lexos chrome</code>, ou
      <code>lexos install chrome</code>).</p>`;
    }
    case "notifications": {
      const n = etat.notif || {};
      return `<h2>Notifications</h2><div class="sub">Ce qui apparaît, et combien de temps</div>
      ${srow("Ne pas déranger", n.silence ? "Les notifications sont mises de côté"
                                          : "Les notifications s'affichent",
             sw(n.silence, "basculeNotif()"))}
      ${n.duree ? srow("Durée d'affichage", n.duree + " secondes") : ""}
      ${btnOuvrir("notifications","Réglages fins")}
      <p class="notice">En « ne pas déranger », rien n'est perdu : les
      notifications s'empilent et se relisent après.</p>`;
    }
    case "recherche": {
      /*  ═══ CHERCHER DEPUIS ICI, ET SAVOIR AVEC QUOI ═══
          La page disait une chose vraie — « LexOS n'indexe pas le disque en
          tâche de fond » — et s'arrêtait là. Elle ne disait donc pas ce qui
          en découle : la recherche par NOM lit l'index de plocate, qui n'est
          pas livré, et ne fonctionne pas tant qu'on ne l'installe pas ; la
          recherche par CONTENU, elle, marche tout de suite. Deux recherches,
          deux états, et un seul mot pour les deux.

          Les résultats s'affichent dans un TERMINAL, et c'est voulu : une
          recherche rend des dizaines de chemins qu'on veut relire, copier,
          faire défiler. Les recopier dans un panneau de réglages serait
          refaire un terminal en moins bien. Cette page sert à lancer la
          bonne commande sans avoir à la connaître. */
      const r = etat.recherche || {};
      if(!r.dispo){
        return `<h2>Recherche</h2><div class="sub">Trouver un fichier ou une application</div>
        <p class="notice">lexos-recherche n'a pas répondu. En ligne de
        commande : <code>lexos recherche</code>.</p>`;
      }
      const ageIndex = r.index_jours < 0 ? "jamais construit"
        : (r.index_jours === 0 ? "refait aujourd'hui"
          : (r.index_jours === 1 ? "refait hier" : `vieux de ${r.index_jours} jours`));
      return `<h2>Recherche</h2><div class="sub">Trouver un fichier ou une application</div>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Chercher un fichier</div>
        <div class="row" style="align-items:center;flex-wrap:wrap">
          <input class="champ" id="rechMot" type="text" autocomplete="off"
                 placeholder="un mot du nom, ou du texte à trouver"
                 onkeydown="if(event.key==='Enter')lancerRecherche('contenu')"
                 style="min-width:220px">
          <button class="btn" onclick="lancerRecherche('nom')">Par nom</button>
          <button class="btn" onclick="lancerRecherche('contenu')">Dans le contenu</button>
          ${r.catfish ? `<button class="btn ghost" onclick="lancerRecherche('fenetre')">Fenêtre</button>` : ""}
        </div>
        <div class="d" style="margin-top:6px">Par nom : instantané, mais lit un
        index. Dans le contenu : lit les fichiers, plus lent, toujours à jour.</div>
      </div>
      ${srow("Index des noms (plocate)",
             !r.plocate ? "Pas installé — la recherche par nom ne peut pas fonctionner"
                        : (r.index ? `Index ${ageIndex} — un fichier créé depuis n'y figure pas`
                                   : "plocate est là, mais l'index n'a jamais été construit"),
             (!r.plocate
               ? `<span class="etat abs">absent</span>`
               : `<span class="etat ${r.index && r.index_jours <= 7 ? "ok" : "warn"}">${
                   r.index ? ageIndex : "aucun index"}</span>
                  <button class="btn ghost" onclick="lancerRecherche('index')">Reconstruire</button>`))}
      ${r.plocate ? "" : `<p class="notice">Pour la recherche par nom :
      <code>lexos install plocate</code>. LexOS ne le livre pas d'office, et
      c'est un choix : un index se reconstruit en lisant TOUT le disque, à
      intervalle régulier, pour un service qu'on utilise trois fois par
      semaine.</p>`}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Faire le ménage</div>
        <div class="row" style="flex-wrap:wrap">
          <button class="btn ghost" onclick="lancerRecherche('gros')">Les plus gros fichiers</button>
          <button class="btn ghost" onclick="lancerRecherche('recent')">Modifiés récemment</button>
          <button class="btn ghost" onclick="lancerRecherche('doublons')">Fichiers en double</button>
        </div>
        <div class="d" style="margin-top:6px">Les résultats s'ouvrent dans un
        terminal — ${r.max} lignes au plus, avec le compte exact au-dessus.</div>
      </div>
      ${srow("Chercher une application", "Le menu Applications filtre à la frappe",
             "")}
      ${btnOuvrir("recherche","Ouvrir la recherche d'applications")}
      <p class="notice">Rien ne tourne en permanence à lire tes fichiers tant
      que plocate n'est pas installé : la recherche parcourt au moment où on la
      demande.</p>`;
    }
    case "comptes": {
      /*  ═══ RELIER, OUVRIR, REFERMER — DEPUIS ICI ═══
          ALEX : « le contenu comme Ubuntu ». La page « Comptes en ligne »
          d'Ubuntu sert à AJOUTER un compte, et à voir ceux qui sont là.
          Ici, on affichait une liste et « rclone : prêt ».

          ET IL MANQUAIT LA SEULE CHOSE QUI COMPTE VRAIMENT quand on cherche
          ses documents : un compte CONFIGURÉ n'est pas un compte OUVERT.
          Tant qu'il n'est pas monté, ses fichiers ne sont nulle part sur
          cette machine — et rien ne le disait.

          Monter et démonter agissent tout de suite. Relier et retirer
          ouvrent un terminal : « rclone config » pose des questions et
          ouvre le navigateur pour l'autorisation, « retirer » exige une
          confirmation. Ni l'un ni l'autre n'a où poser sa question ici. */
      const c = etat.comptes || {};
      if(!c.dispo){
        return `<h2>Comptes en ligne</h2><div class="sub">Drive, OneDrive, Nextcloud, Dropbox…</div>
        <p class="notice">lexos-comptes n'a pas répondu : les comptes ne
        peuvent pas être réglés d'ici. En ligne de commande :
        <code>lexos comptes</code>.</p>`;
      }
      const relies = c.comptes || [];
      return `<h2>Comptes en ligne</h2><div class="sub">Drive, OneDrive, Nextcloud, Dropbox…</div>
      ${relies.length ? relies.map(l => srow(
          esc(l.nom),
          l.monte ? `Ouvert dans ${esc(c.nuage)}/${esc(l.nom)} — visible dans Fichiers`
                  : "Configuré, mais pas ouvert : ses fichiers ne sont pas sur cette machine",
          `<span class="etat ${l.monte?"ok":"abs"}">${l.monte?"ouvert":"fermé"}</span>` +
          (l.monte
            ? ` <button class="btn ghost" onclick="setCompte('demonter','${jsq(l.nom)}')">Refermer</button>`
            : ` <button class="btn ghost" onclick="setCompte('monter','${jsq(l.nom)}')">Ouvrir</button>`) +
          ` <button class="btn ghost" onclick="setCompte('retirer','${jsq(l.nom)}')">Retirer</button>`
        )).join("")
        : srow("Comptes reliés", "Aucun pour l'instant", `<span class="etat abs">aucun</span>`)}
      ${c.rclone
        ? srow("Relier un compte", "L'autorisation se fait dans le navigateur ; aucun mot de passe n'est conservé",
            `<select onchange="setCompte('ajouter', this.value)"
               style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
                      border-radius:6px;padding:6px 8px;font:inherit">
               <option value="">Choisir un service…</option>` +
             (c.services || []).map(x => `<option value="${esc(x.cle)}">${esc(x.nom)}</option>`).join("") +
            `</select>`)
        : srow("rclone", "Pas installé — c'est lui qui parle aux services de nuage",
            `<span class="etat abs">absent</span>`)}
      ${c.rclone ? "" : `<p class="notice">Pour relier un compte :
      <code>lexos install rclone</code>.</p>`}
      ${srow("GVFS", c.gvfs ? "Les comptes s'ouvrent aussi depuis Fichiers"
                            : "Absent (paquet gvfs-backends)",
             `<span class="etat ${c.gvfs?"ok":"abs"}">${c.gvfs?"prêt":"absent"}</span>`)}
      ${btnOuvrir("comptes","Ouvrir le panneau")}
      <p class="notice">Deux façons de faire, qui ne se valent pas :
      <b>monter</b> le compte l'ouvre dans le gestionnaire de fichiers sans rien
      copier — pratique, mais inutilisable hors ligne ; <b>synchroniser</b> en
      garde une copie sur le disque, disponible même sans réseau. LexOS propose
      les deux, et le dit avant de choisir pour toi.</p>
      <p class="notice">Aucun mot de passe de compte n'est conservé : chaque
      service remet un jeton révocable. Le révoquer chez le fournisseur suffit
      à tout couper.</p>`;
    }
    case "partage": {
      /*  ═══ LE CONTENU D'UBUNTU, LES MOYENS DE LexOS ═══
          ALEX : « le contenu comme Ubuntu ». Sa page « Partage » commence par
          le NOM DE L'ORDINATEUR — celui que les autres appareils voient —
          puis dit ce qui est partagé et comment. Ici, il n'y avait qu'une
          ligne : « serveur actif » ou « au repos ».

          Ce que LexOS partage n'est pas ce que partage Ubuntu, et on ne
          l'invente pas : pas de dossier public Samba, pas de serveur SSH
          livré. Ce qu'il y a — QR code, KDE Connect, Bluetooth — est dit
          avec ce qui manque, parce qu'un moyen absent présenté comme
          disponible envoie cliquer dans le vide. */
      const p = etat.partage || {};
      if(!p.dispo){
        return `<h2>Partage</h2><div class="sub">Ce que les autres appareils voient</div>
        <p class="notice">lexos-share n'a pas répondu : le partage ne peut pas
        être réglé d'ici. En ligne de commande : <code>lexos share</code>.</p>`;
      }
      const moyen = (la, titre, quoi, absent) => srow(titre, la ? quoi : absent,
        `<span class="etat ${la?"ok":"abs"}">${la?"prêt":"absent"}</span>`);
      return `<h2>Partage</h2><div class="sub">Ce que les autres appareils voient</div>
      ${srow("Nom de cet ordinateur",
             "C'est ce nom qui s'affiche sur le téléphone, sur le réseau et dans le terminal",
             `<input class="champ" id="partageNom" type="text" autocomplete="off"
                value="${esc(p.nom)}" placeholder="nom de la machine"
                onkeydown="if(event.key==='Enter')setNomMachine()"
                style="max-width:200px">
              <button class="btn ghost" onclick="setNomMachine()">Renommer</button>`)}
      ${srow("Serveur de partage",
             p.actif ? `En marche — il s'arrête tout seul après ${p.minutes} minutes`
                     : "Arrêté — il démarre quand tu partages quelque chose",
             `<span class="etat ${p.actif?"ok":"abs"}">${p.actif?"actif":"au repos"}</span>`)}
      ${moyen(p.qr, "QR code", "Marche avec n'importe quel téléphone, sans rien y installer",
              "Le serveur de partage manque sur cette machine")}
      ${moyen(p.kde, "KDE Connect", "Appareils appairés, transfert direct",
              "kdeconnect-cli n'est pas installé")}
      ${moyen(p.bt, "Bluetooth", "Quand il n'y a pas de réseau du tout",
              "bluetoothctl n'est pas installé")}
      ${srow("Fichiers reçus", "Où arrivent les fichiers envoyés depuis le téléphone",
             `<span class="etat abs">${esc(p.recus)}</span>`)}
      ${srow("Connexion à distance (SSH)",
             p.ssh_serveur
               ? "Un serveur SSH est installé : on peut ouvrir un terminal sur cette machine depuis ailleurs"
               : "LexOS ne livre que le client SSH — rien n'écoute sur cette machine",
             `<span class="etat ${p.ssh_serveur?"ok":"abs"}">${p.ssh_serveur?"installé":"non installé"}</span>`)}
      ${btnOuvrir("partage","Ouvrir le partage")}
      ${p.ssh_serveur ? "" : `<p class="notice">Pour ouvrir cette machine à
      distance en ligne de commande : <code>lexos install openssh-server</code>.
      Tant qu'il n'est pas installé, personne ne peut s'y connecter — c'est
      voulu, et c'est plus sûr ainsi.</p>`}
      <p class="notice">Le partage montre un QR code et sert une page locale :
      ça marche avec <b>n'importe quel</b> téléphone, sans rien y installer.
      Le serveur ne tourne que le temps du transfert.</p>`;
    }
    case "bienetre": {
      /*  ═══ TROIS INTERRUPTEURS, ET TROIS DISTINCTIONS QU'ILS RESPECTENT ═══
          Cette page affichait trois lignes sans un seul réglage : le temps
          d'écran, « workrave est là », « redshift est là ». Pour démarrer le
          compteur ou poser une limite, il fallait le terminal.

          Et elle confondait ce qu'il ne faut pas confondre :
            · « zéro minute » n'est pas « le compteur est arrêté ». Le
              compteur est ARRÊTÉ par défaut — mesurer le temps de quelqu'un
              ne se décide pas à sa place — et « 0 h 00 » laisserait croire
              qu'on n'a pas touché à la machine.
            · « workrave n'est pas installé » n'est pas « les rappels sont
              arrêtés ». Un interrupteur pour un programme absent ne
              commande rien : on affiche alors la commande qui l'installe,
              pas une bascule qui reviendrait toute seule à sa place. */
      const b = etat.bienetre || {};
      if(!b.dispo){
        return `<h2>Bien-être numérique</h2><div class="sub">Temps d'écran, pauses, lumière du soir</div>
        <p class="notice">lexos-bienetre n'a pas répondu : rien ne peut être
        réglé d'ici. En ligne de commande : <code>lexos bienetre</code>.</p>`;
      }
      const hm = m => `${Math.floor((m||0)/60)} h ${String((m||0)%60).padStart(2,"0")}`;
      const sem = b.semaine || [];
      const maxi = Math.max(1, ...sem.map(j => j.minutes || 0));

      /*  Une bascule pour un programme absent ne commande rien. On met la
          commande d'installation à la place — c'est ça, l'information utile. */
      const confort = (cle, titre, quoi, prog, installe, actif) => srow(titre,
        installe ? quoi : `${prog} n'est pas installé — <code>lexos install ${prog}</code>`,
        installe ? sw(actif, `setBienetre('${cle}', ${actif ? "false" : "true"})`)
                 : `<span class="etat abs">absent</span>`);

      return `<h2>Bien-être numérique</h2><div class="sub">Temps d'écran, pauses, lumière du soir</div>
      ${srow("Compter le temps d'écran",
             b.tourne ? "Une minute comptée par minute d'usage RÉEL — un ordinateur laissé ouvert la nuit ne compte pas"
                      : "À l'arrêt : rien n'est mesuré tant qu'on ne le demande pas",
             sw(!!b.tourne, `setBienetre('compteur', ${b.tourne ? "false" : "true"})`))}
      ${srow("Aujourd'hui",
             b.tourne ? (b.limite ? (b.minutes >= b.limite
                          ? `Limite de ${hm(b.limite)} dépassée de ${hm(b.minutes - b.limite)}`
                          : `Il reste ${hm(b.limite - b.minutes)} avant la limite`)
                        : "Aucune limite posée")
                      : "Le compteur est arrêté — ce n'est pas « zéro », c'est « on ne sait pas »",
             `<span class="etat ${b.tourne ? (b.limite && b.minutes >= b.limite ? "warn" : "ok") : "abs"}">${
               b.tourne ? hm(b.minutes) : "arrêté"}</span>`)}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Limite du jour</div>
        <div class="row" style="align-items:center;flex-wrap:wrap">
          <input class="champ" id="bienLimite" type="number" min="1" max="1440" step="15"
                 value="${b.limite || ""}" placeholder="minutes" style="max-width:130px">
          <button class="btn" onclick="setBienetreLimite()">Enregistrer</button>
          ${b.limite ? `<button class="btn ghost" onclick="setBienetre('limite','off')">Retirer la limite</button>` : ""}
        </div>
        <div class="d" style="margin-top:6px">Une notification prévient au-delà.
        La limite n'éteint rien et ne bloque rien : elle avertit.</div>
      </div>
      ${confort("pauses", "Rappels de pause",
                "Micro-pauses, pauses longues, limite quotidienne (workrave)",
                "workrave", b.pauses_installe, b.pauses_actif)}
      ${confort("nuit", "Lumière du soir",
                "Réchauffe l'écran au coucher du soleil (redshift)",
                "redshift", b.nuit_installe, b.nuit_actif)}
      ${sem.length ? `<div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Les sept derniers jours —
          ${hm(b.total_semaine)} en tout</div>
        ${sem.map(j => `<div class="row" style="align-items:center;gap:8px">
          <span class="d" style="width:38px">${esc(j.nom)}</span>
          <span style="flex:1;background:var(--bg-hi);border-radius:4px;height:10px;overflow:hidden">
            <span style="display:block;height:100%;width:${Math.round((j.minutes||0)*100/maxi)}%;background:var(--ac)"></span>
          </span>
          <span class="d" style="width:64px;text-align:right">${hm(j.minutes)}</span>
        </div>`).join("")}
      </div>` : ""}
      ${srow("Effacer l'historique", "Les relevés sont des fichiers texte, un par jour",
             `<button class="btn ghost" onclick="oublierBienetre()">Tout effacer</button>`)}
      ${btnOuvrir("bienetre","Ouvrir le détail")}
      <p class="notice">Rien ne quitte cette machine : un fichier texte par
      jour, et pas une ligne de code qui ouvre une connexion.</p>`;
    }
    case "souris": {
      const m = etat.souris || {};
      return `<h2>Souris et pavé tactile</h2><div class="sub">Vitesse, boutons, défilement</div>
      ${m.pave ? `
        ${srow("Taper pour cliquer","Une tape sur le pavé vaut un clic",
               sw(m.tape, "basculeSouris('tape')"))}
        ${srow("Défilement naturel","Le contenu suit le doigt, comme sur un téléphone",
               sw(m.inverse, "basculeSouris('inverse')"))}`
        : `<p class="notice">Aucun pavé tactile détecté — ces réglages ne
           concernent que les portables.</p>`}
      ${srow("Pointeur","Vitesse, gaucher/droitier, thème du curseur")}
      ${btnOuvrir("souris")}`;
    }
    case "couleurs": {
      const c = etat.couleurs || {};
      return `<h2>Gestion des couleurs</h2><div class="sub">Profils des écrans</div>
      ${!c.dispo
        ? `<p class="notice">colord n'est pas là : les profils de couleur ne
           peuvent pas être gérés.</p>`
        : (c.ecrans && c.ecrans.length
            ? c.ecrans.map(e=>srow(esc(e.nom),
                e.profil ? "Profil : " + esc(e.profil) : "Aucun profil — couleurs par défaut",
                `<span class="etat ${e.profil?"ok":"abs"}">${e.profil?"calibré":"non calibré"}</span>`)).join("")
            : `<p class="notice">Aucun écran connu de colord pour l'instant.</p>`)}
      ${btnOuvrir("couleurs","Ouvrir la gestion des couleurs")}
      <p class="notice">Un profil de couleur sert surtout à celui qui imprime ou
      retouche des photos : il fait correspondre ce qu'on voit à l'écran et ce
      qui sort de l'imprimante.</p>`;
    }
    case "imprimantes": {
      const im = etat.imprimantes || {};
      return `<h2>Imprimantes</h2><div class="sub">Ajouter et gérer les imprimantes</div>
      ${!im.dispo
        ? `<p class="notice">CUPS n'est pas là : aucune imprimante ne peut être gérée.</p>`
        : (im.liste && im.liste.length
            ? im.liste.map(i=>srow(esc(i.nom) + (i.defaut ? " — par défaut" : ""), esc(i.etat),
                `<span class="etat ${i.etat==="prête"?"ok":"abs"}">${esc(i.etat)}</span>`)).join("")
            : `<p class="notice">Aucune imprimante installée. Branche-la ou ajoute-la
               par le réseau : LexOS trouve seul la plupart des modèles récents
               (pilotes sans pilote, via IPP).</p>`)}
      ${btnOuvrir("imprimantes","Ajouter une imprimante")}`;
    }
    case "amovibles": {
      const v = etat.amovibles || {};
      return `<h2>Supports amovibles</h2><div class="sub">Ce que LexOS fait quand tu branches quelque chose</div>
      ${srow("Monter automatiquement","La clé est prête sans rien demander",
             sw(v.monter, "basculeAmovible('monter')"))}
      ${srow("Ouvrir le gestionnaire de fichiers","Une fenêtre s'ouvre sur le contenu",
             sw(v.ouvrir, "basculeAmovible('ouvrir')"))}
      ${srow("Proposer d'importer les photos","Quand c'est un appareil photo ou un téléphone",
             sw(v.photos, "basculeAmovible('photos')"))}
      ${srow("Lancer la musique","Quand c'est un disque audio",
             sw(v.musique, "basculeAmovible('musique')"))}
      ${btnOuvrir("amovibles","Réglages fins (XFCE)")}
      <p class="notice">Ces réglages sont ceux de thunar-volman : ils s'appliquent
      tout de suite, sans rouvrir la session.</p>`;
    }
    case "tablette": {
      const t = etat.tablette || {};
      return `<h2>Tablette graphique</h2><div class="sub">Stylet, pression, zones</div>
      ${t.branchee
        ? t.noms.map(n=>srow(esc(n), "Reconnue et prête",
            `<span class="etat ok">branchée</span>`)).join("")
        : srow("Tablette", "Aucune tablette branchée",
               `<span class="etat abs">absente</span>`)}
      ${btnOuvrir("tablette","Réglages du stylet")}
      <p class="notice">Le pilote Wacom est déjà embarqué : une tablette
      branchée est reconnue sans rien installer.</p>`;
    }
    case "confidentialite": {
      const q = etat.securite || {};
      //  Trois états et non deux : « en marche », « installé mais arrêté »,
      //  et « pas installé ». Un pare-feu éteint et un pare-feu absent
      //  n'appellent pas le même geste.
      const dit = (v, oui, non) =>
        v === null || v === undefined ? "Pas installé" : (v ? oui : non);
      const pastille = v =>
        `<span class="etat ${v===null||v===undefined?"abs":(v?"ok":"off")}">${
          v===null||v===undefined?"absent":(v?"actif":"arrêté")}</span>`;
      return `<h2>Confidentialité et sécurité</h2><div class="sub">Pare-feu, chiffrement, autodéfense</div>
      ${srow("Chiffrement du disque (LUKS2)",
             q.chiffre ? "Ce disque est chiffré" : "Ce disque n'est pas chiffré — proposé à l'installation",
             `<span class="etat ${q.chiffre?"ok":"off"}">${q.chiffre?"actif":"non"}</span>`)}
      ${srow("Pare-feu (ufw)", dit(q.pareFeu,"Refuse tout entrant, laisse sortir","Installé, mais éteint"),
             pastille(q.pareFeu))}
      ${srow("Antivirus (ClamAV)", dit(q.antivirus,"Base de signatures à jour","Installé, mise à jour arrêtée"),
             pastille(q.antivirus))}
      ${srow("Anti-intrusion (fail2ban)", dit(q.intrusion,"Bannit les tentatives répétées","Installé, mais arrêté"),
             pastille(q.intrusion))}
      ${srow("Cloisonnement (AppArmor)", dit(q.apparmor,"Les applications sont cloisonnées","Installé, mais arrêté"),
             pastille(q.apparmor))}
      ${srow("Anti-rootkit", q.rootkit ? "rkhunter et chkrootkit sont là" : "Pas installé",
             pastille(q.rootkit ? true : null))}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Vérifier maintenant</div>
        <div class="row">
          <button class="btn" onclick="actionSecu('etat')">État complet</button>
          <button class="btn ghost" onclick="actionSecu('pare-feu')">Pare-feu</button>
          <button class="btn ghost" onclick="actionSecu('antivirus')">Analyser</button>
          <button class="btn ghost" onclick="actionSecu('rootkit')">Anti-rootkit</button>
        </div>
      </div>
      ${srow("Fichiers privés",
             "Un coffre chiffré (gocryptfs) pour ce qui ne regarde personne",
             /*  ═══ CE BOUTON ANNONÇAIT LE SUCCÈS MÊME QUAND L'OUVERTURE
                        ÉCHOUAIT ═══
                 Il était le SEUL des 38 boutons d'ouverture à ne pas passer
                 par ouvrir(). Il écrivait :
                     api('ouvrir','prive').then(()=>toast('… s'ouvre'))
                 Or api() affiche déjà « ✗ » et le motif quand l'action
                 échoue ; le .then() s'exécute ensuite QUOI QU'IL ARRIVE et
                 REMPLACE ce message par « Fichiers privés s'ouvre ». Sans
                 gocryptfs installé, ou sans coffre créé, on lisait donc un
                 succès et il ne se passait rien.
                 ouvrir() fait exactement ce qu'il faut, et le dit quand ça
                 rate (app.js, fonction ouvrir()). */
             `<button class="btn ghost" onclick="ouvrir('prive')">Ouvrir</button>`)}
      <p class="notice">Ces outils demandent les droits d'administration et posent
      des questions : ils s'ouvrent dans un terminal, pour qu'on puisse LIRE ce
      qu'ils font. Les lancer en silence derrière un interrupteur cacherait
      justement ce qu'il faut voir. En ligne de commande :
      <code>lexos secure</code> · <code>lexos prive</code>.</p>
      ${btnOuvrir("confidentialite","Tout vérifier d'un coup (terminal)")}`;
    }
    case "maj": {
      const m = etat.maj || {};
      const prog = m.progres || {};
      //  On revient sur cette page pendant qu'un geste tourne encore ailleurs
      //  (Paramètres refermés puis rouverts pendant un « apt upgrade »,
      //  par exemple) : on reprend le sondage au lieu de laisser un bouton
      //  dire « en cours » sans plus jamais se mettre à jour tout seul.
      if(!majSondage){
        const enCours = Object.keys(prog).find(k => prog[k] && prog[k].en_cours);
        if(enCours) suitMaj(enCours);
      }
      return `<h2>Mises à jour</h2><div class="sub">${esc(etat.version || "LexOS")}</div>
      ${srow("Version installée", esc(etat.version || "") + " · noyau " + esc(etat.noyau || ""))}
      ${srow("Mises à jour de sécurité automatiques",
             m.secu ? "Appliquées toutes seules" : "Désactivées",
             `<span class="etat ${m.secu?"ok":"off"}">${m.secu?"actif":"arrêté"}</span>`)}
      ${srow("Tout mettre à jour automatiquement",
             m.tout ? "Y compris les mises à jour ordinaires" : "Seule la sécurité est automatique",
             `<span class="etat ${m.tout?"ok":"off"}">${m.tout?"actif":"non"}</span>`)}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Maintenant</div>
        <div class="row">
          ${boutonMaj("verifier", "btn", "Vérifier")}
          ${boutonMaj("tout", "btn ghost", "Tout mettre à jour")}
          ${m.fwupd ? boutonMaj("firmware", "btn ghost", "Micrologiciel (BIOS, SSD)") : ""}
        </div>
      </div>
      <p class="notice">Les mises à jour de sécurité s'installent seules ; le reste
      attend que tu le demandes. Une mise à jour pose des questions et prend du
      temps : elle s'ouvre dans un terminal pour qu'on voie ce qui se passe — et
      cette page se met à jour toute seule pendant que ça tourne.</p>
      ${btnOuvrir("maj","Diagnostic complet du système (terminal)")}`;
    }
    case "accessibilite": {
      const a = etat.access || {};
      return `<h2>Accessibilité</h2><div class="sub">Voir, entendre, taper</div>
      ${srow("Contraste élevé","Couleurs franches, bordures nettes",
             sw(a.contraste, "basculeAccess('contraste')"))}
      ${srow("Curseur large","Un pointeur qu'on retrouve du premier coup d'oeil",
             sw(a.curseurLarge, "basculeAccess('curseur')"))}
      ${srow("Lecteur d'écran (Orca)",
             a.orca ? "Lit à voix haute ce qui est à l'écran" : "Pas installé",
             a.orca ? `<button class="btn ghost" onclick="basculeAccess('orca')">Lancer</button>` : "")}
      ${srow("Clavier visuel (Onboard)",
             a.onboard ? "Taper à la souris ou au doigt, sans clavier physique" : "Pas installé",
             a.onboard ? `<button class="btn ghost" onclick="basculeAccess('onboard')">Lancer</button>` : "")}
      ${btnOuvrir("accessibilite","Réglages fins (XFCE)")}
      <p class="notice">En ligne de commande : <code>lexos access</code>.</p>
      <p class="notice">Un système sans lecteur d'écran n'est pas utilisable par
      tout le monde : Orca est embarqué d'office, pas en option.</p>`;
    }
    case "utilisateurs": {
      /*  ═══ ON AGIT ICI, ON NE FAIT PLUS QUE LIRE ═══
          ALEX : « le contenu comme Ubuntu ». La page d'Ubuntu permet
          d'ajouter un compte, d'en changer le nom affiché, de donner ou
          retirer les droits d'administrateur, de changer le mot de passe et
          d'allumer la connexion automatique. Ici, on affichait une liste et
          une phrase disant d'aller au terminal.

          CHAQUE GESTE OUVRE UN TERMINAL, ET C'EST LE BON CHOIX, PAS UN PIS-
          ALLER. adduser pose des questions, passwd lit un mot de passe qui ne
          s'affiche pas, et supprimer un compte fait RECOPIER son nom avant
          d'effacer. Rien de tout ça ne tient dans une fenêtre sans clavier.
          Et lexos-utilisateurs ne s'élève jamais tout seul : la commande est
          écrite en toutes lettres, sous les yeux de qui tape son mot de
          passe. Ce que la page apporte, c'est de ne plus avoir à connaître
          ni la commande, ni le nom du compte, ni la syntaxe.

          Les comptes, les droits et l'état des mots de passe viennent de
          lexos-utilisateurs : cette page ne lit ni /etc/passwd ni /etc/group. */
      const u = etat.utilisateurs || {};
      const gens = u.comptes || [];
      if(!u.dispo){
        return `<h2>Utilisateurs</h2><div class="sub">Comptes de cette machine</div>
        <p class="notice">lexos-utilisateurs n'a pas répondu : les comptes ne
        peuvent pas être lus d'ici. En ligne de commande :
        <code>lexos utilisateurs</code>.</p>`;
      }

      /*  L'ÉTAT DU MOT DE PASSE N'EST LISIBLE QUE PAR root. On le dit au lieu
          d'afficher « actif » par défaut : un compte verrouillé qu'on croit
          ouvert, c'est une porte qu'on pense fermée. */
      const ETAT_MDP = {actif:["ok","mot de passe actif"],
                        verrouille:["abs","verrouillé"],
                        "sans-mot-de-passe":["warn","AUCUN mot de passe"],
                        inconnu:["abs","état inconnu"]};

      const lignes = gens.map(p => {
        const seul = p.admin && (u.nb_admins || 0) <= 1;
        const [cl, mot] = ETAT_MDP[p.verrou] || ETAT_MDP.inconnu;
        /*  Le DERNIER administrateur ne peut être ni rétrogradé, ni verrouillé,
            ni supprimé — c'est la seule interdiction dure de l'outil, et une
            machine sans administrateur ne se répare plus depuis le bureau. On
            n'affiche donc pas des boutons qui ne peuvent que refuser. */
        const gestes =
          `<button class="btn ghost" onclick="utilGeste('motdepasse','${jsq(p.nom)}')">Mot de passe</button>` +
          (seul ? ""
                : ` <button class="btn ghost" onclick="utilGeste('${p.admin?"admin-off":"admin-on"}','${jsq(p.nom)}')">` +
                  `${p.admin ? "Retirer l'admin" : "Rendre admin"}</button>` +
                  ` <button class="btn ghost" onclick="utilGeste('${p.verrou==="verrouille"?"deverrouiller":"verrouiller"}','${jsq(p.nom)}')">` +
                  `${p.verrou === "verrouille" ? "Déverrouiller" : "Verrouiller"}</button>` +
                  (p.moi ? "" : ` <button class="btn ghost" onclick="utilGeste('supprimer','${jsq(p.nom)}')">Supprimer</button>`));
        return `<div class="srow" style="display:block">
          <div class="t">${esc(p.complet || p.nom)}${p.moi ? " — c'est toi" : ""}
            <span class="etat ${p.admin?"ok":"abs"}" style="margin-left:8px">${p.admin?"admin":"normal"}</span>
            <span class="etat ${cl}" style="margin-left:6px">${mot}</span></div>
          <div class="d">${esc(p.nom)} · ${esc(p.groupes)} · dernière connexion : ${esc(p.derniere)}</div>
          <div class="row" style="margin-top:8px;flex-wrap:wrap">
            <input class="champ" id="nomAff-${esc(p.nom)}" type="text" autocomplete="off"
                   placeholder="nom affiché" value="${esc(p.complet)}"
                   onkeydown="if(event.key==='Enter')utilNomComplet('${jsq(p.nom)}')"
                   style="max-width:220px">
            <button class="btn ghost" onclick="utilNomComplet('${jsq(p.nom)}')">Renommer</button>
            ${gestes}
          </div>
          ${seul ? `<div class="sub" style="margin-top:6px">Seul administrateur de
            cette machine : ses droits ne peuvent être ni retirés, ni verrouillés,
            ni supprimés tant qu'il n'y en a pas un autre.</div>` : ""}
        </div>`;
      }).join("");

      /*  « Choisir… » n'est pas une option de la connexion automatique : il y a
          toujours une réponse — désactivée, ou un compte. */
      const auto = srow("Connexion automatique",
        u.lightdm
          ? "Ouvre la session au démarrage sans demander de mot de passe"
          : "LightDM n'est pas installé : ce réglage ne s'applique pas ici",
        u.lightdm
          ? `<select onchange="utilGeste('auto', this.value)"
               style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
                      border-radius:6px;padding:6px 8px;font:inherit">
               <option value="off"${u.auto ? "" : " selected"}>Désactivée</option>` +
             gens.map(p => `<option value="${esc(p.nom)}"${p.nom===u.auto?" selected":""}>${esc(p.complet || p.nom)}</option>`).join("") +
            `</select>`
          : `<span class="etat abs">indisponible</span>`);

      return `<h2>Utilisateurs</h2><div class="sub">Comptes de cette machine</div>
      ${lignes || `<p class="notice">Aucun compte de personne trouvé (UID ≥ 1000).</p>`}
      ${srow("Ajouter un compte",
             "Minuscules, chiffres, « - » et « _ », en commençant par une lettre",
             `<input class="champ" id="utilNouveau" type="text" autocomplete="off"
                placeholder="nom du compte" style="max-width:200px"
                onkeydown="if(event.key==='Enter')utilAjouter()">
              <button class="btn" onclick="utilAjouter()">Créer</button>`)}
      ${auto}
      ${u.auto ? `<p class="notice">La connexion automatique est active pour
      « ${esc(u.auto)} » : cette machine s'ouvre sans mot de passe. Le trousseau
      de clés, lui, redemandera le vôtre — il n'a plus la connexion pour se
      déverrouiller.</p>` : ""}
      ${btnOuvrir("utilisateurs","Détail (terminal)")}
      <p class="notice">Chaque geste ouvre un terminal où la commande est écrite
      en clair, et demande le mot de passe d'administration. En ligne de
      commande : <code>lexos utilisateurs</code>.</p>`;
    }
    case "terminal": {
      /*  ═══ ON CHOISIT ICI, ON NE RECOPIE PLUS DES COMMANDES ═══
          Cette page listait quatre commandes à taper dans un terminal — pour
          régler… le terminal. Elle ne disait ni ce qui est choisi, ni ce qui
          s'applique en ce moment.

          ET CES DEUX-LÀ DIFFÈRENT. « auto » et « suivre » ne sont pas des
          couleurs, ce sont des règles : en « auto », le terminal est clair le
          jour et noir le soir. Une page qui n'afficherait que le mode choisi
          laisserait quelqu'un se demander pourquoi son terminal est noir à
          quatorze heures ; une page qui n'afficherait que la couleur du
          moment lui ferait croire qu'il a choisi « nuit ». On montre les
          deux, et l'écart entre les deux est justement l'explication.

          Rien ici ne demande les droits d'administrateur — lexos-terminal
          n'écrit que dans le dossier de la personne connectée — donc pas de
          terminal à ouvrir : on agit, et c'est instantané. */
      const t = etat.terminal || {};
      if(!t.dispo){
        return `<h2>Terminal jour / nuit</h2><div class="sub">Deux palettes, la même règle de couleur</div>
        <p class="notice">lexos-terminal n'a pas répondu : le mode du terminal
        ne peut pas être réglé d'ici. En ligne de commande :
        <code>lexos terminal</code>.</p>${btnOuvrir("terminal","Ouvrir")}`;
      }
      const MODES = [["suivre","Suivre le bureau","Le terminal change avec le thème du bureau"],
                     ["jour","Toujours clair","Fond crème, écriture foncée"],
                     ["nuit","Toujours noir","LexOS Noir"],
                     ["auto","L'heure décide","Clair le jour, noir le soir"]];
      const courant = MODES.find(m => m[0] === t.mode) || MODES[0];
      return `<h2>Terminal jour / nuit</h2><div class="sub">Deux palettes, la même règle de couleur</div>
      ${srow("En ce moment",
             t.mode === "suivre"
               ? `Suit le bureau, qui est en « ${esc(t.bureau || "?")} »`
               : (t.mode === "auto"
                   ? `L'heure décide : jour de ${esc(t.debut)} à ${esc(t.fin)}`
                   : esc(courant[2])),
             `<span class="etat ${t.effectif==="jour"?"warn":"ok"}">${esc(t.effectif || "?")}</span>`)}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Mode du terminal</div>
        <div class="row" style="flex-wrap:wrap">${MODES.map(([v,titre]) =>
          `<button class="btn ${v===t.mode?"sel":"ghost"}" onclick="setTerminalMode('${v}')">${titre}</button>`
        ).join("")}</div>
        <div class="d" style="margin-top:6px">${esc(courant[2])}</div>
      </div>
      ${t.mode === "auto" ? `<div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Heures du jour</div>
        <div class="row" style="align-items:center;flex-wrap:wrap">
          <input class="champ" id="termDebut" type="time" value="${esc(t.debut)}" style="max-width:130px">
          <span class="d">à</span>
          <input class="champ" id="termFin" type="time" value="${esc(t.fin)}" style="max-width:130px">
          <button class="btn" onclick="setTerminalHoraire()">Enregistrer</button>
        </div>
        ${t.minuterie ? "" : `<div class="d" style="margin-top:6px">La minuterie n'est
          pas armée : le mode changera à la prochaine ouverture de session, pas à
          l'heure dite.</div>`}
      </div>` : ""}
      ${btnOuvrir("terminal","Ouvrir")}
      <p class="notice">Le changement est instantané : les fenêtres déjà
      ouvertes se repeignent, l'invite change à la ligne suivante. Rien à rouvrir.</p>
      <p class="notice">La règle de couleur ne change pas d'un mode à l'autre :
      vert = la machine, orange = ce que vous tapez, rouge = ce qui a échoué.</p>`;
    }
    case "session": {
      /*  Le bouton rouge de la barre du haut ouvre exactement cette fenêtre.
          Cette section ne la double pas : elle la RETROUVE. Un geste du
          système qui n'existe qu'à un seul endroit de l'écran disparaît le
          jour où cet endroit change — et il change, on vient de le déplacer. */
      return `<h2>Fermer la session</h2><div class="sub">Éteindre, changer d'utilisateur, se déconnecter</div>
      <p class="notice">Le bouton rouge, tout à droite de la barre du haut,
      ouvre la même fenêtre. Veille et redémarrage sont juste à sa gauche,
      dans la barre.</p>
      ${btnOuvrir("session","Ouvrir")}`;
    }
    case "region": {
      return `<h2>Région et langue</h2><div class="sub">Langue, formats, clavier</div>
      ${srow("Langue du système", esc(etat.langue || "inconnue"))}
      ${srow("Fuseau horaire", esc((etat.heure && etat.heure.fuseau) || "inconnu"))}
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Changer la langue</div>
        <div class="row">${[["fr_CA.UTF-8","Français (Québec)"],["fr_FR.UTF-8","Français (France)"],
                            ["en_CA.UTF-8","English (Canada)"],["en_US.UTF-8","English (US)"]].map(([v,t])=>
          `<button class="btn ${v===etat.langue?"sel":"ghost"}" onclick="setLangue('${v}')">${t}</button>`).join("")}</div>
      </div>
      <p class="notice">Le changement s'applique à la prochaine ouverture de session :
      les applications lisent leur langue au démarrage, pas en cours de route.</p>`;
    }
    /*  ═══ LE CLAVIER SE CHANGE ICI, ET PLUS SEULEMENT SE REGARDE ═══
        ALEX : « dans les paramètres de clavier, une fois installé, on n'est
        pas capable de changer de clavier », et « comme pour le @, je suis
        pas capable de le faire ».

        CETTE PAGE NE SAVAIT QUE LIRE. Elle affichait les dispositions et
        renvoyait au dialogue de XFCE pour en changer — lequel s'ouvre TOUT
        GRISÉ tant que « Utiliser les réglages système » est actif, ce qui
        est son défaut. Vérifié dans le GtkBuilder du binaire lui-même :
        « xkb_use_system_default_switch », active=True. Deux impasses, et
        rien à l'écran pour l'expliquer.

        Le catalogue et les gestes viennent de lexos-clavier, qui les portait
        déjà : on ne recopie pas vingt dispositions dans cette page. */
    case "clavier": {
      const k = etat.clavier || {};
      const act = k.actives || [];
      const cat = k.catalogue || [];
      const bas = k.bascules || [];
      const dejaLa = new Set(act.map(a => a.cle));
      const reste = cat.filter(c => !dejaLa.has(c.cle));
      const plein = act.length >= (k.max || 4);

      if(!cat.length){
        return `<h2>Clavier</h2><div class="sub">Dispositions et raccourcis</div>
        <p class="notice">lexos-clavier n'a pas répondu : les dispositions ne
        peuvent pas être changées d'ici. En ligne de commande :
        <code>lexos clavier</code>.</p>${btnOuvrir("clavier","Réglages du clavier")}`;
      }

      /*  La PREMIÈRE de la liste est celle du démarrage : c'est la règle de
          lexos-clavier, et on la dit plutôt que de la laisser deviner. */
      const lignes = act.map((a, i) => srow(
        esc(a.nom),
        i === 0 ? "Celle du démarrage" : "Bascule : " + esc(nomBascule(bas, k.bascule)),
        (i === 0 ? `<span class="etat ok">active</span>`
                 : `<button class="btn" onclick="clavierDabord('${jsq(a.cle)}')">Mettre en premier</button>`) +
        (act.length > 1
          ? ` <button class="btn" onclick="clavierRetirer('${jsq(a.cle)}')">Retirer</button>`
          : "")
      )).join("");

      const ajout = plein
        ? `<p class="notice">Quatre dispositions au maximum — c'est la limite de X,
           pas la nôtre.</p>`
        : srow("Ajouter une disposition",
               "Elle s'ajoute à la suite ; la bascule permet de passer de l'une à l'autre",
               `<select onchange="clavierAjouter(this.value)"
                  style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
                         border-radius:6px;padding:6px 8px;font:inherit">
                  <option value="">Choisir…</option>` +
                reste.map(c => `<option value="${esc(c.cle)}">${esc(c.nom)}</option>`).join("") +
               `</select>`);

      const bascule = act.length > 1
        ? srow("Passer d'une disposition à l'autre", "Les touches qui font la bascule",
               `<select onchange="clavierBascule(this.value)"
                  style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
                         border-radius:6px;padding:6px 8px;font:inherit">` +
                bas.map(b => `<option value="${esc(b.cle)}"${b.cle===k.bascule?" selected":""}>${esc(b.nom)}</option>`).join("") +
               `</select>`)
        : "";

      /*  CE QUE X APPLIQUE VRAIMENT, quand ça diffère de notre réglage. Un
          écart se voit alors au lieu de laisser croire à une panne. */
      const ecart = (k.x_applique && act.length &&
                     k.x_applique !== act.map(a=>a.cle).join(",") )
        ? `<p class="notice">X applique en ce moment : <code>${esc(k.x_applique)}</code>.
           Le réglage ci-dessus prend effet tout de suite ; s'il ne bouge pas,
           il s'appliquera à la prochaine ouverture de session.</p>`
        : "";

      return `<h2>Clavier</h2><div class="sub">Dispositions et raccourcis</div>
      ${lignes}${ajout}${bascule}${ecart}
      ${btnOuvrir("clavier","Réglages du clavier (XFCE)")}
      <p class="notice">En ligne de commande : <code>lexos clavier</code>.</p>`;
    }
    case "datetime": {
      const h = etat.heure || {};
      return `<h2>Date et heure</h2><div class="sub">Fuseau, format, synchronisation</div>
      ${h.maintenant ? srow("Maintenant", esc(h.maintenant)) : ""}
      ${srow("Mise à l'heure automatique",
             h.auto ? "L'heure se règle seule sur internet (NTP)"
                    : "L'heure ne se règle pas toute seule",
             sw(h.auto, "basculeHeureAuto()"))}
      ${srow("Fuseau horaire automatique",
             h.lieu_connu
               ? `D'après la ville que tu as choisie pour la météo. LexOS ne
                  cherche jamais ta position par ton adresse internet.`
               : `Aucun lieu connu — choisis ta ville une fois avec
                  <code>lexos meteo ville Toronto</code> et le fuseau suivra.
                  LexOS ne devine pas ta position.`,
             h.lieu_connu ? sw(h.fuseau_auto, "basculeFuseauAuto()")
                          : `<span class="etat abs">aucun lieu</span>`)}
      ${h.fuseau ? srow("Fuseau horaire", esc(h.fuseau)) : ""}

      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Choisir son lieu (Canada)</div>
        <div class="row" style="flex-wrap:wrap">${FUSEAUX_CANADA.map(([z,t])=>
          `<button class="btn ${z===h.fuseau?"sel":"ghost"}" onclick="setFuseau('${z}')">${t}</button>`).join("")}</div>
      </div>
      <p class="notice">Treize provinces et territoires, onze fuseaux — le Nouveau-Brunswick et
      l'Île-du-Prince-Édouard partagent celui des Maritimes, et le Nunavut (trois fuseaux à lui
      seul) est représenté par sa capitale, Iqaluit. Choisir ici règle le fuseau tout de suite ;
      si le fuseau automatique est actif (au-dessus), il pourra le reprendre à sa prochaine
      vérification.</p>

      <div class="sub" style="margin-top:20px">Horloge de la barre du haut</div>
      ${srow("Format de l'heure",
             `Ce que montre l'horloge, au milieu de la barre.`,
             `<div class="row" style="flex:none">
                <button class="btn ${h.h12?"ghost":"sel"}" onclick="setHorloge('24h')">24 heures</button>
                <button class="btn ${h.h12?"sel":"ghost"}" onclick="setHorloge('12h')">12 heures</button>
              </div>`)}
      ${srow("Afficher les secondes", "Dans la barre du haut",
             sw(!!h.secondes, "setHorloge('secondes')"))}
      ${srow("Afficher le jour de la semaine", "Dans la barre du haut",
             sw(!!h.jour, "setHorloge('jour')"))}
      ${btnOuvrir("datetime","État complet (timedatectl)")}`;
    }
    case "defaut": {
      /*  ═══ ON CHOISIT ICI, ON NE FAIT PLUS QUE LIRE ═══
          ALEX : « le contenu comme Ubuntu », « commence par applications par
          défaut ». La page affichait cinq lignes sans rien à cliquer et
          renvoyait à l'outil de XFCE pour en changer.

          UBUNTU EN OFFRE SIX (web, courriel, agenda, musique, vidéo, photos),
          LexOS en a DIX — on n'en retire aucun pour « faire comme » : le
          lecteur audio, l'éditeur de texte, le gestionnaire de fichiers, les
          archives et le terminal ne sont pas dans la page d'Ubuntu, et les
          enlever d'ici n'aiderait personne.

          Les catégories, les applications candidates et le choix courant
          viennent de lexos-defaut : cette page ne connaît aucun type MIME. */
      const d = etat.defaut || {};
      const cats = d.categories || [];
      if(!cats.length){
        return `<h2>Applications par défaut</h2><div class="sub">Quel logiciel ouvre quoi</div>
        <p class="notice">lexos-defaut n'a pas répondu : les applications par
        défaut ne peuvent pas être changées d'ici. En ligne de commande :
        <code>lexos defaut</code>.</p>${btnOuvrir("defaut","Ouvrir l'outil de XFCE")}`;
      }
      const lignes = cats.map(c => {
        /*  Une catégorie sans aucune application capable de l'ouvrir : on le
            DIT, au lieu d'afficher une liste vide qui laisserait croire à une
            panne. Le terminal est toujours dans ce cas — il n'a aucun type
            MIME, XFCE le range dans son propre réglage. */
        if(!c.choix || !c.choix.length){
          return srow(esc(c.titre),
            c.cle === "terminal"
              ? "Le terminal n'a pas de type de fichier — il se règle dans l'outil de XFCE"
              : "Aucune application installée ne sait ouvrir ces fichiers",
            `<span class="etat abs">${esc(c.courant_nom || "aucune")}</span>`);
        }
        /*  « Choisir… » en tête quand rien n'est réglé : sans cette entrée, la
            liste afficherait la première application comme si elle était le
            choix en place, ce qui serait faux. */
        const rien = c.courant ? "" : `<option value="" selected>Choisir…</option>`;
        return srow(esc(c.titre), "",
          `<select onchange="setDefautAppli('${jsq(c.cle)}', this.value)"
             style="background:var(--bg-hi);color:var(--fg);border:1px solid var(--bd);
                    border-radius:6px;padding:6px 8px;font:inherit;max-width:60%">${rien}` +
          c.choix.map(x =>
            `<option value="${esc(x.id)}"${x.id===c.courant?" selected":""}>${esc(x.nom)}</option>`
          ).join("") + `</select>`);
      }).join("");
      return `<h2>Applications par défaut</h2><div class="sub">Quel logiciel ouvre quoi</div>
      ${lignes}
      ${btnOuvrir("defaut","Réglages fins (XFCE)")}
      <p class="notice">Autre façon de faire, souvent plus rapide : clic droit sur
      un fichier → <b>Ouvrir avec</b> → <b>Définir par défaut</b>. En ligne de
      commande : <code>lexos defaut</code>.</p>`;
    }
    case "distant": {
      const r = etat.distant || {};
      const PROTOS = [["auto","Deviner"], ["rdp","RDP"], ["vnc","VNC"], ["ssh","SSH"]];
      /*  Ce qu'on affiche quand le partage tourne, c'est L'ADRESSE À DICTER
          au téléphone : « tape ça chez toi ». Sans elle, un partage allumé ne
          sert à rien — l'autre bout ne sait pas où frapper. On donne l'IP de
          chaque carte réseau, port compris, parce qu'un portable branché en
          Wi-Fi ET en câble n'a pas la même adresse des deux côtés. */
      const port = (r.ports || "").split(/[\s,]+/).filter(Boolean)[0] || "";
      const adresses = r.adresses || [];
      return `<h2>Bureau à distance</h2>
      <div class="sub">Montrer cet écran à quelqu'un, ou aller voir une autre machine</div>

      <h3 class="cpt-h3">Montrer cet écran</h3>
      ${r.outil
        ? srow("Partager mon bureau",
               r.actif ? `En marche — ${esc(r.outil)} montre cet écran sur le réseau local`
                       : `Arrêté. À l'allumage, ${esc(r.outil)} demande un mot de passe : c'est celui-là qu'on donne à l'autre.`,
               sw(r.actif, "setDistantPartage()"))
        : srow("Partager mon bureau", "Aucun serveur installé sur cette machine",
               `<span class="etat abs">absent</span>`)}
      ${(r.actif && adresses.length)
        ? `<div class="srow" style="display:block">
             <div class="t" style="margin-bottom:8px">L'adresse à donner</div>
             <div class="row">${adresses.map(a =>
               `<span class="adr" title="${esc(a.interface)}">${esc(a.ip)}${port?":"+esc(port):""}</span>`
             ).join("")}</div>
             <div class="sub" style="margin-top:8px">Une adresse par carte réseau.
               Si l'autre est dans la même maison, n'importe laquelle marche ;
               de l'extérieur, il faut passer par un VPN — jamais ouvrir ce
               port sur la box.</div>
           </div>`
        : ""}
      ${r.actif
        ? `<p class="notice">Le partage s'arrête tout seul à l'extinction. Il ne
             revient pas au démarrage suivant : il faut le rallumer à la main,
             exprès, chaque fois.</p>`
        : ""}

      <h3 class="cpt-h3">Aller voir une autre machine</h3>
      <div class="srow" style="display:block">
        <div class="t" style="margin-bottom:8px">Adresse de l'autre machine</div>
        <div class="row" style="gap:8px;align-items:center">
          <input class="champ" id="distAdr" type="text" spellcheck="false"
                 autocomplete="off" placeholder="192.168.1.42  ou  compte@machine"
                 onkeydown="if(event.key==='Enter')distantVers()">
          <button class="btn" onclick="distantVers()">Se connecter</button>
        </div>
        <div class="row" style="margin-top:10px">${PROTOS.map(([v,t]) =>
          `<button class="btn ${distantProto===v?"sel":"ghost"}"
             onclick="setDistantProto('${v}')">${t}</button>`).join("")}</div>
        <div class="sub" style="margin-top:8px">« Deviner » essaie RDP puis VNC
          d'après le port qui répond en face — c'est le bon choix neuf fois sur
          dix. SSH ouvre un terminal, pas une image.</div>
      </div>
      ${srow("Visionneuse (RDP / VNC)",
             r.remmina ? "Remmina est installé" : "Remmina n'est pas installé",
             `<span class="etat ${r.remmina?"ok":"abs"}">${r.remmina?"prête":"absente"}</span>`)}
      ${srow("Terminal à distance (SSH)",
             r.ssh ? "Le client SSH est installé" : "Le client SSH n'est pas installé",
             `<span class="etat ${r.ssh?"ok":"abs"}">${r.ssh?"prêt":"absent"}</span>`)}
      ${btnOuvrir("distant","Détail (terminal)")}
      <p class="notice">${r.outil
        ? "Un bureau à distance ouvre ta machine au réseau : il ne démarre jamais tout seul, et jamais sans mot de passe."
        : "Pour se laisser voir, il faut d'abord un serveur : <code>lexos install x11vnc</code>. Pour aller voir ailleurs, il faut Remmina : <code>lexos install remmina</code>."}</p>`;
    }
    case "diagnostic": {
      /*  LexOS Diagnostic : le panneau en direct — matériel, santé, disques.
          Il arrive comme module séparé (usr/lib/lexos/diagnostic) et avait
          son icône, son .desktop et sa branche « lexos diagnostic », mais
          AUCUN chemin depuis les Paramètres : le contrôle 16 l'a nommé, tout
          comme il avait nommé LexOS Boost avant lui. C'est cette page-ci qui
          le branche.

          Elle n'essaie pas de refaire le panneau en petit : elle dit ce
          qu'il montre et l'ouvre. Dupliquer ses mesures ici donnerait deux
          endroits où un bogue pourrait un jour raconter deux choses
          différentes — la même raison qui garde la liste des réseaux Wi-Fi
          hors du volet. */
      /*  ═══ CETTE PAGE NE S'AFFICHAIT PAS DU TOUT ═══
          Elle écrivait « corps.innerHTML = … » puis « break », alors que
          toutes les autres RENDENT une chaîne. Deux fautes d'un coup :
          « corps » n'existe nulle part dans ce fichier — une ReferenceError
          à chaque clic — et la fonction ne rendait rien.

          Et le symptôme ne ressemblait pas à une erreur : rendSection() fait
          « content.innerHTML = contenu(...) ». Quand contenu() lève, la
          droite n'est jamais évaluée, l'affectation n'a pas lieu, et l'écran
          GARDE LA SECTION PRÉCÉDENTE. On cliquait « Diagnostic », et il ne
          se passait rien — pas de page blanche, pas de message : rien.
          Aucun banc ne rendait les sections une par une ; il y en a un
          maintenant, et il les rend TOUTES. */
      return `<h2>Diagnostic</h2>
        <p class="d">La machine en direct : processeur, mémoire, carte
        graphique, températures, ventilateurs, réseau, batterie — puis un
        bilan de santé et l'état des disques (SMART, NVMe, espace).</p>
        ${btnOuvrir("diagnostic","Ouvrir LexOS Diagnostic")}
        <p class="d" style="margin-top:14px">Les mêmes réponses en terminal,
        sans fenêtre : <code>lexos materiel</code>, <code>lexos medecin</code>,
        <code>lexos disques</code>.</p>`;
    }
    case "tiers": {
      /*  LexOS dit « 100 % Linux », et c'est vrai. Mais « libre » et
          « gratuit » ne sont pas la même chose, et une distribution qui se
          réclame du libre doit pouvoir montrer SA propre liste d'exceptions
          plutôt que de la laisser deviner. Cette page la montre — et elle
          REGARDE la machine : « Steam est installé » et « Steam pourrait
          être installé » ne sont pas la même phrase. */
      const t = etat.tiers || {livres:[], absents:[]};
      const carte = x => `<div class="srow tr" style="display:block">
        <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
          <span class="t">${esc(x.nom)}</span>
          <span class="etat ${x.libre?"ok":"att"}">${x.libre?"libre":"propriétaire"}</span>
          <span class="lic">${esc(x.licence)}</span>
          <span class="etat ${x.present?"ok":"abs"}" style="margin-left:auto">${
            x.present ? "sur cette machine" : (x.livre?"pas installé":"pas téléchargé")}</span>
        </div>
        <div class="d" style="margin-top:6px">${esc(x.role)}</div>
        <div class="d" style="margin-top:4px;opacity:.75">Vient de : ${esc(x.origine)}</div>
      </div>`;

      return `<h2>Logiciels tiers</h2>
      <div class="sub">Ce qui, dans LexOS, n'est pas du Debian ordinaire — et sous quelle licence</div>

      <div class="verite">
        <div class="v-l"><span class="v-oui">Libre ≠ gratuit.</span>
          <b>Libre</b> veut dire qu'on peut lire le code, le modifier et le
          redistribuer. <b>Propriétaire</b> veut dire qu'on peut s'en servir,
          et c'est tout — même quand ça ne coûte rien. Les deux sont sur cette
          page, nommés.</div>
        <div class="v-l"><span class="v-oui">LexOS lui-même est libre.</span>
          Le système, ses outils, cette fenêtre : tout est lisible dans le
          dépôt, copiable et modifiable. Ce qui est fermé ci-dessous vient
          d'ailleurs, et on dit d'où.</div>
      </div>

      <h3 class="cpt-h3">Dans l'ISO</h3>
      ${t.livres.map(carte).join("")}

      <h3 class="cpt-h3">Pas dans l'ISO — téléchargé seulement si tu le demandes</h3>
      <p class="notice">LexOS ne distribue rien de tout ça, donc n'endosse
        aucune de ces licences. Chacun arrive de chez son éditeur, à ta
        demande, et jamais en silence.</p>
      ${t.absents.map(carte).join("")}

      <h3 class="cpt-h3">Ce qui n'est pas là du tout</h3>
      <div class="verite">
        <div class="v-l"><span class="v-oui">Zéro Windows.</span>
          Aucun composant Microsoft, aucune licence Microsoft, rien de Windows
          n'est démarré. Wine, ci-dessus, est une réécriture libre — il ne
          contient pas une ligne de Windows.</div>
        <div class="v-l"><span class="v-oui">Aucun mouchard.</span>
          LexOS n'envoie pas de statistiques d'usage, ne compte pas les
          démarrages et n'a pas de compte. Ce qui parle au réseau le fait
          parce que tu le lances : le navigateur, la Logithèque, les mises à
          jour Debian.</div>
      </div>

      ${btnOuvrir("apropos","La fenêtre À propos complète")}`;
    }
    case "apropos": {
      const lb = etat.libre || {firmwares:0, steam:false, broadcom:false};
      return `<h2>À propos de LexOS</h2><div class="sub">2.0.0 « Nomad »</div>
      ${srow("Système", esc(etat.version))}
      ${srow("Nom de la machine", esc(etat.hote))}
      ${srow("Noyau", esc(etat.noyau))}

      <h3 class="cpt-h3">100 % Linux</h3>
      <div class="verite">
        <div class="v-l"><span class="v-oui">Zéro Windows.</span>
          LexOS n'a besoin d'aucun composant Microsoft, d'aucune licence, et ne
          démarre jamais rien de Windows. Le système entier est assemblé à partir
          des paquets Debian.</div>
        <div class="v-l"><span class="v-oui">Wine non plus.</span>
          Beaucoup croient que Wine réclame une copie de Windows. C'est faux :
          <b>Wine Is Not an Emulator</b> — c'est une réécriture libre des
          fonctions de Windows, faite de zéro, qui tourne nativement sur Linux.
          Pas une ligne de code Microsoft, pas de licence à posséder. Un jeu
          Windows lancé par Wine s'exécute sur du Linux, du début à la fin.</div>
      </div>

      <h3 class="cpt-h3">Ce qui n'est pas libre, et pourquoi</h3>
      <p class="notice">Dire « 100 % Linux » serait malhonnête sans préciser
        ceci. Trois choses peuvent ne pas être du logiciel libre, et voici ce
        qu'il en est <b>sur cette machine</b> :</p>
      ${srow("Micrologiciels (<code>non-free-firmware</code>)",
             `Des petits fichiers chargés <b>dans le matériel</b> — carte Wi-Fi,
              carte graphique — pas des programmes qui tournent sur ton
              processeur. Sans eux, beaucoup de portables n'ont tout simplement
              pas de Wi-Fi. C'est le compromis que fait Debian elle-même depuis
              la version 12.`,
             lb.firmwares
               ? `<span class="etat ok">${lb.firmwares} paquet${lb.firmwares>1?"s":""}</span>`
               : `<span class="etat off">aucun</span>`)}
      ${srow("Steam",
             `Le client de Valve est propriétaire. Il n'est installé que si tu
              le demandes — <code>lexos logitheque install jeux</code>.`,
             lb.steam ? `<span class="etat ok">installé</span>`
                      : `<span class="etat off">non installé</span>`)}
      ${srow("Pilote Wi-Fi Broadcom",
             `Certaines cartes n'ont pas de pilote libre qui fonctionne.
              <code>lexos mac wifi</code> ne le propose que quand la carte
              l'exige vraiment.`,
             lb.broadcom ? `<span class="etat ok">présent</span>`
                         : `<span class="etat off">absent</span>`)}
      <p class="notice">Tout le reste — noyau, bureau, navigateur, outils LexOS —
        est du logiciel libre. Le code de LexOS lui-même est sous licence MIT,
        lisible et modifiable, le branding TI-LEX-AL excepté. Construit avec
        <code>make build</code> depuis le dépôt GitHub.</p>
      ${btnOuvrir("apropos","La fenêtre À propos complète")}`;
    }
    default: return `<h2>Paramètres</h2><div class="sub">Choisis une section à gauche</div>`;
  }
}

/* --- Rendu ---------------------------------------------------------------- */
function rendNav(){
  const nav = document.getElementById("sidebar");
  nav.innerHTML = NAV.map(g =>
    `<div class="grp">${g.grp}</div>` +
    g.items.map(([cle,pic,label]) =>
      `<button class="nav-item${cle===sectionActive?" sel":""}" data-cle="${cle}">
         <span class="pic">${typeof pic === "function" ? pic() : pic}</span>
         <span>${label}</span></button>`).join("")
  ).join("");
  nav.querySelectorAll(".nav-item").forEach(b =>
    b.onclick = () => { sectionActive = b.dataset.cle;
                        location.hash = sectionActive; rend(); });
}
function rendSection(){
  document.getElementById("content").innerHTML = contenu(sectionActive);
}
/*  LA FENÊTRE DOIT OBÉIR À CE QU'ON Y CHOISIT.
    Défaut trouvé en essayant pour de vrai : on choisissait « Manuscrite »,
    tout le bureau passait à l'écriture à la main… et CETTE fenêtre-ci
    restait en Noto Sans. Pareil pour l'accent : on prenait « Bleu », les
    boutons des Paramètres restaient orange. La feuille de style codait les
    deux en dur.

    C'est le pire endroit où rater ça : c'est ici qu'on fait le choix, donc
    ici qu'on regarde pour voir s'il a pris. Une fenêtre qui montre autre
    chose que ce qu'elle vient d'appliquer fait douter du réglage entier.

    On pose donc les deux en variables CSS sur la racine, à chaque rendu.
    « rendu » et pas « au chargement » : après setPolice(), la page doit
    changer TOUT DE SUITE, sans attendre une réouverture. */
function appliqueApparence(){
  const r = document.documentElement.style;
  const pol = TOUTES_POLICES.find(([n]) => n === etat.police);
  //  Repli sur la famille par défaut si l'état nomme une police inconnue —
  //  mieux qu'une page sans police déclarée du tout.
  r.setProperty("--police", pol ? pol[2] : TOUTES_POLICES[0][2]);
  //  ═══ L'ACCENT VIENT MAINTENANT DE ui.css, PAS D'UN CALCUL ICI ═══
  //  On posait « --ac » à la main et on DÉDUISAIT le ton de survol en
  //  éclaircissant. Deux défauts à cela.
  //
  //  1. Le volet des Paramètres rapides, lui, ne posait rien du tout : il
  //     restait orange à vie. Une couleur d'accent qui ne vaut que pour une
  //     fenêtre sur deux n'est pas une couleur d'accent.
  //  2. Le ton de survol calculé n'était PAS celui du bureau.
  //     lexos-theme-gen porte un triplet par accent, choisi à la main ; un
  //     éclaircissement mécanique tombait à côté, et la fenêtre où l'on
  //     choisit la couleur était la seule à ne pas la porter exactement.
  //
  //  ui.css porte désormais la table complète, recopiée de lexos-theme-gen,
  //  avec la couleur de TEXTE qui va sur chaque fond (le noir en dur donnait
  //  3,34:1 sur le bleu — illisible). Poser l'attribut suffit, et les trois
  //  surfaces web de LexOS y puisent la même chose.
  if(etat.accent) document.documentElement.dataset.accent = etat.accent;
  //  LE MODE, À CHAUD. La page reçoit déjà le mode par ?mode= au démarrage
  //  (le lanceur lit ~/.config/lexos/mode). Mais c'est ICI qu'on en change :
  //  cliquer « ☀ Clair » sans cette ligne repeignait tout le bureau et
  //  laissait CETTE fenêtre-là noire, la seule qu'Alex regardait à ce
  //  moment précis. etat.theme vient de /api/etat, qui l'expose depuis
  //  toujours sous cette clé — rien de nouveau à brancher.
  if(etat.theme === "clair"){ document.documentElement.dataset.mode = "clair"; }
  else { delete document.documentElement.dataset.mode; }
}
/*  « eclaircir() » VIVAIT ICI ET N'A PLUS D'APPELANT.
    Elle calculait le ton de survol en éclaircissant l'accent, faute de table.
    ui.css porte maintenant le triplet complet de chaque accent, recopié de
    lexos-theme-gen — celui qui peint réellement le bureau. Le calcul tombait
    à côté de ces valeurs-là, et la fenêtre où l'on choisit la couleur était
    la seule à ne pas la porter exactement.

    On la RETIRE au lieu de la laisser dormir : une fonction sans appelant qui
    se lit très bien est exactement ce que ce dépôt paie le plus cher — on la
    croit vivante et on cherche le défaut ailleurs. Elle est dans git. */

/*  ALLER À UNE AUTRE SECTION DEPUIS UNE PAGE.
    Certaines pages renvoient à une autre — « Applications » vers
    « Applications par défaut », par exemple. Sans ce geste, elles ne
    pouvaient que NOMMER la section, à charge d'aller la chercher dans le
    menu de gauche : c'est ce qui a fait de « Applications » une deuxième
    page d'applications par défaut, à moitié.
    On repose le « hash » comme le fait le menu, pour que le bouton Retour du
    navigateur continue de fonctionner. */
function allerA(cle){
  if(!NAV.some(g => g.items.some(([c]) => c === cle))) return;
  sectionActive = cle;
  location.hash = cle;
  rend();
}
function rend(){ appliqueApparence(); rendNav(); rendSection(); }

/* --- Démarrage ------------------------------------------------------------ */
(async function(){
  const h = location.hash.replace("#","");
  if(h && NAV.some(g=>g.items.some(([c])=>c===h))) sectionActive = h;
  await chargeEtat();
  rend();
})();
