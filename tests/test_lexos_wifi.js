/* =============================================================================
 *  Éprouver la page Wi-Fi des Paramètres LexOS — celle qu'Alex a comparée
 * =============================================================================
 *  CE QU'ALEX A DEMANDÉ, LES DEUX PAGES CÔTE À CÔTE
 *    « wi-fi, utiliser lui la 2e image »
 *    « il manque des outils, regarde la 2e image — la 2e image a plus
 *      d'outils sur le mode wi-fi »
 *
 *  Deux choses, donc : le PICTOGRAMME de la colonne de gauche (un carré jaune
 *  sur l'ISO, une antenne verte dans la démo) et les OUTILS de la page.
 *
 *  POURQUOI CE BANC EXISTE PLUTÔT QU'UNE RELECTURE
 *  « node --check » ne dit qu'une chose : que le fichier se parse. Il ne dit
 *  pas si l'antenne devient rouge quand la carte est éteinte, ni si la
 *  bascule apparaît. Ici on CHARGE app.js pour de vrai, on lui donne des
 *  états inventés, et on regarde le HTML qu'il rend. C'est ce qu'Alex voit.
 *
 *  On charge le fichier en lui ajoutant une dernière ligne qui expose ses
 *  fonctions : « etat » est un « let » de portée fichier, donc invisible du
 *  dehors — mais visible d'une ligne ajoutée DANS le même fichier.
 * ========================================================================== */
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const RACINE = path.join(__dirname, "..");
const APP = path.join(RACINE, "config/includes.chroot/usr/share/lexos/settings/web/app.js");
const CSS = path.join(RACINE, "config/includes.chroot/usr/share/lexos/ui.css");

let reussis = 0, echoues = 0;
const ok  = m => { console.log("  \x1b[32m✅\x1b[0m " + m); reussis++; };
const non = m => { console.log("  \x1b[31m❌\x1b[0m " + m); echoues++; };
const titre = m => console.log("\n\x1b[1m═══ " + m + " ═══\x1b[0m");

/* --- Le décor minimal : ce que la page touche au chargement --------------- */
//  #wifiMdp EST UN OBJET STABLE, PAS UN GÉNÉRIQUE JETABLE — c'est justement
//  celui que le test du focus différé (section 4) doit pouvoir espionner
//  après coup. requestAnimationFrame FILE la fonction au lieu de l'exécuter
//  tout de suite : c'est ce qui permet au banc de vérifier qu'aucune touche
//  ne serait perdue avant le prochain repaint (le bogue d'Alex, « pas
//  capable d'écrire le mot de passe »).
const wifiMdpEspion = { valeurFocus: 0, focus(){ this.valeurFocus++; } };
const rafFile = [];
function faux() {
  const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                      classList:{add(){}, remove(){}, toggle(){}},
                      querySelectorAll:() => [], appendChild(){}, focus(){} });
  return {
    document: { getElementById: id => id === "wifiMdp" ? wifiMdpEspion : el(),
                querySelectorAll: () => [], body: el(),
                documentElement: { style:{ setProperty(){} }, dataset:{} },
                addEventListener(){} },
    location: { hash:"" },
    window: { confirm: () => true },
    fetch: () => Promise.reject(new Error("pas de pont dans le banc")),
    requestAnimationFrame: cb => { rafFile.push(cb); return rafFile.length; },
    setTimeout, clearTimeout, console,
  };
}

const source = fs.readFileSync(APP, "utf8")
  + "\n;globalThis.__banc = { wifiGlyph, contenu, pose: e => { etat = e; },"
  + "  nav: NAV, choisitWifi };\n";
const bac = vm.createContext(faux());
bac.globalThis = bac;
vm.runInContext(source, bac, { filename: "app.js" });
const T = bac.__banc;

/* ========================================================================== */
titre("1. Le pictogramme dit l'état par sa couleur");
/* ========================================================================== */
const cas = [
  ["carte allumée, réseau, internet", {radio:"enabled", reseau:"BELL507", internet:"full"},
   "gly-ok",   "vert"],
  ["connecté mais rien ne passe",     {radio:"enabled", reseau:"BELL507", internet:"limited"},
   "gly-warn", "orange"],
  ["allumé, aucun réseau",            {radio:"enabled", reseau:"", internet:"none"},
   "gly-off",  "rouge"],
  ["carte éteinte",                   {radio:"disabled", reseau:"", internet:"none"},
   "gly-off",  "rouge"],
  ["aucune carte",                    {radio:"absent"},
   "gly-off",  "rouge"],
];
for (const [nom, w, classe, couleur] of cas) {
  T.pose({ wifi: w });
  const h = T.wifiGlyph();
  if (h.includes(classe) && h.includes("gly-wifi")) ok(`${nom} → ${couleur}`);
  else non(`${nom} : attendu ${classe}, obtenu « ${h} »`);
}
T.pose({ wifi: {radio:"enabled", reseau:"BELL507", internet:"full"} });
if (!/📶/.test(T.wifiGlyph())) ok("plus d'émoji : un masque, qui s'affiche partout");
else non("l'émoji 📶 est toujours là");

/* --- Et la barre latérale sait l'appeler --------------------------------- */
const entree = T.nav[0].items.find(i => i[0] === "wifi");
if (typeof entree[1] === "function") ok("la barre latérale porte une FONCTION (le dessin suit l'état)");
else non("le pictogramme du menu est figé : il ne changera jamais de couleur");

/* ========================================================================== */
titre("2. Les outils qui manquaient");
/* ========================================================================== */
T.pose({ wifi: {radio:"enabled", reseau:"", signal:0, internet:"none",
                auto:false, reseaux:[]} });
let page = T.contenu("wifi");

if (page.includes("Connexion auto. aux réseaux ouverts"))
  ok("« Connexion auto. aux réseaux ouverts » est là, comme dans la démo");
else non("la bascule de connexion automatique manque toujours");

if (page.includes("basculeWifiAuto()"))
  ok("et elle est branchée sur une vraie commande");
else non("la bascule n'appelle rien");

if (/vert<\/b> connecté/.test(page) && /orange<\/b> connecté mais sans accès/.test(page)
    && /rouge<\/b> pas de connexion/.test(page))
  ok("la légende des trois couleurs est là (sinon le orange ne veut rien dire)");
else non("la légende des couleurs manque");

if (!/Simuler une panne/.test(page))
  ok("l'accessoire de démo (« simuler une panne ») n'est PAS repris sur l'ISO");
else non("un interrupteur pour mentir sur son propre état a été copié depuis la démo");

/* --- L'interrupteur reflète la machine, il ne se souvient pas de lui-même - */
if (/class="sw"/.test(page)) ok("désactivée, la bascule est bien montrée éteinte");
else non("la bascule ne montre pas l'état « off »");

T.pose({ wifi: {radio:"enabled", reseau:"", signal:0, internet:"none",
                auto:true, reseaux:[]} });
page = T.contenu("wifi");
if (/class="sw on"/.test(page)) ok("activée, elle est montrée allumée");
else non("la bascule ne suit pas l'état « on »");

/* --- Sans carte Wi-Fi, on ne propose rien -------------------------------- */
T.pose({ wifi: {radio:"absent"} });
page = T.contenu("wifi");
if (!/basculeWifiAuto/.test(page))
  ok("sans carte Wi-Fi, aucun outil n'est proposé (rien à régler)");
else non("une bascule Wi-Fi est proposée sur une machine sans carte Wi-Fi");
if (/Aucune carte Wi-Fi/.test(page)) ok("et on le DIT");
else non("aucune carte, et rien qui l'explique");

/* --- La liste des réseaux, elle, reste ----------------------------------- */
T.pose({ wifi: {radio:"enabled", reseau:"BELL507", signal:100, internet:"full",
                auto:false,
                reseaux:[{ssid:"BELL507", signal:100, protege:true,
                          securite:"WPA2", actif:true}]} });
page = T.contenu("wifi");
//  UNE SEULE BORNE À PORTÉE, ET C'EST CELLE OÙ L'ON EST. La liste des AUTRES
//  est donc vide — et on ne montre pas un titre suivi de rien : on écrit ce
//  que ça veut dire, et on garde le bouton pour chercher encore.
if (/BELL507/.test(page) && /Autres réseaux à portée/.test(page))
  ok("ce que l'ISO avait en plus (la vraie liste des réseaux) n'a pas été perdu");
else non("la liste des réseaux a disparu en ajoutant les outils");
if (/Aucun autre réseau en vue/.test(page))
  ok("…et une liste vide dit pourquoi, au lieu de rester blanche");
else non("liste vide sans explication — on croirait le balayage cassé");
if (/chercheWifi\(\)/.test(page))
  ok("…avec le bouton « Chercher encore »");
else non("plus moyen de relancer un balayage depuis une liste vide");

/* ========================================================================== */
titre("3. La feuille de style porte bien le masque");
/* ========================================================================== */
const css = fs.readFileSync(CSS, "utf8");
for (const [nom, motif] of [
  ["le tracé de l'antenne", /--m-wifi:url\("data:image\/svg\+xml/],
  ["la classe .gly", /\.gly\{[^}]*mask-size:contain/],
  ["le vert", /\.gly-ok\{background-color:var\(--ok\)\}/],
  ["l'orange", /\.gly-warn\{background-color:var\(--warn\)\}/],
  ["le rouge", /\.gly-off\{background-color:var\(--off\)\}/],
]) {
  if (motif.test(css)) ok(nom + " est dans ui.css");
  else non(nom + " manque dans ui.css — le pictogramme serait un carré vide");
}

/* ========================================================================== */
titre("4. « pas capable d'écrire le mot de passe » — le focus arrive après le repaint");
/* ========================================================================== */
//  ALEX : le champ montrait bien le contour orange du focus, mais aucune
//  touche n'y entrait. rendSection() remplace tout #content par du neuf
//  (innerHTML) ; appeler .focus() sur le nouveau champ DANS LA MÊME PASSE
//  SYNCHRONE est justement le cas que QtWebEngine — le moteur de cette
//  fenêtre — documente comme instable : le focus DOM « prend » à l'écran
//  avant que le moteur de rendu n'ait fini d'accepter le nœud, et les
//  frappes se perdent jusqu'au clic suivant. choisitWifi() doit donc
//  DIFFÉRER l'appel à .focus() d'un repaint (requestAnimationFrame),
//  jamais l'appeler tout de suite.
T.pose({ wifi: {radio:"enabled", reseau:"", signal:0, internet:"none",
                auto:false,
                reseaux:[{ssid:"BELL507", signal:100, protege:true,
                          securite:"WPA2", actif:false}]} });
rafFile.length = 0;
wifiMdpEspion.valeurFocus = 0;
T.choisitWifi("BELL507");
if (wifiMdpEspion.valeurFocus === 0)
  ok("choisitWifi() ne fixe pas le focus tout de suite (synchrone)");
else non("le focus est posé dans la même passe que le rendu — le bogue d'Alex reviendrait");
if (rafFile.length === 1)
  ok("…mais file exactement un rappel pour le prochain repaint");
else non("aucun requestAnimationFrame en attente — le focus ne serait jamais posé");
if (rafFile.length > 0) {
  rafFile.shift()();
  if (wifiMdpEspion.valeurFocus >= 1)
    ok("une fois le repaint passé, le champ reçoit bien le focus");
  else non("le rappel différé n'a pas focus le champ du mot de passe");
} else {
  non("pas de rappel en file — le focus ne se posera jamais (rien à rejouer)");
}

/* ========================================================================== */
titre("5. Le réseau connecté ne s'écrit QU'UNE FOIS, et son bouton est en haut");
/* ========================================================================== */
//  DEUX DEMANDES D'ALEX, À UN MOIS D'INTERVALLE, SUR LA MÊME LIGNE.
//
//  D'ABORD : « quand je suis connecté sur le wi-fi, il dit pas de déconnecter
//  une fois connecté — là je suis connecté à BELL507 mais il dit pas
//  déconnecter ». Le bouton a été ajouté sur la ligne du réseau actif, dans
//  la liste du bas.
//
//  PUIS : « j'aimerais que ce ne soit pas visible en bas, qu'on le voie juste
//  une fois en haut, une fois connecté ». BELL507 s'écrivait alors à DEUX
//  endroits de la même page — la rangée « Réseau connecté » en haut, et la
//  première ligne de « Réseaux à portée » en bas, avec son badge et son
//  bouton.
//
//  LES DEUX DEMANDES TIENNENT ENSEMBLE : le réseau actif quitte la liste, et
//  le bouton REMONTE avec lui. Ce banc exige les deux à la fois — sortir le
//  réseau sans déménager le bouton retirerait le seul moyen de se déconnecter
//  depuis la page, et remettrait le bogue d'avant.
T.pose({ wifi: {radio:"enabled", reseau:"BELL507", signal:100, internet:"full",
                auto:false,
                reseaux:[{ssid:"BELL507", signal:100, protege:true,
                          securite:"WPA2", actif:true},
                         {ssid:"dlink-4538", signal:37, protege:true,
                          securite:"WPA2", actif:false}]} });
page = T.contenu("wifi");

//  ═══ LE CŒUR DE LA DEMANDE : UNE SEULE FOIS ═══
//  On COMPTE les occurrences du SSID au lieu de chercher sa présence : le
//  doublon d'Alex serait passé au vert sur un simple test de présence, et
//  c'est précisément ce doublon qu'on répare.
const fois = (page.match(/BELL507/g) || []).length;
if (fois === 1)
  ok("« BELL507 » n'apparaît qu'une seule fois sur la page");
else non(`« BELL507 » apparaît ${fois} fois — Alex le veut une seule`);

//  Et il ne reste PAS dans la liste du bas.
const lignes = page.split(/<div class="srow wifi-l">/).slice(1);
if (!lignes.some(l => /BELL507/.test(l)))
  ok("le réseau connecté a quitté la liste des autres réseaux");
else non("le réseau connecté est encore listé en bas");
if (lignes.some(l => /dlink-4538/.test(l)))
  ok("…et les autres réseaux y sont toujours");
else non("le filtre a emporté les autres réseaux avec lui");

//  ═══ LE BOUTON A SUIVI, IL N'A PAS DISPARU ═══
if (/coupeWifi\(\)/.test(page))
  ok("un bouton appelle toujours coupeWifi()");
else non("plus aucun moyen de se déconnecter depuis la page — le bogue d'avant revient");
if (/Déconnecter/.test(page))
  ok("…et il est écrit « Déconnecter », en toutes lettres");
else non("le mot « Déconnecter » n'apparaît nulle part dans la page");

//  IL EST EN HAUT, PAS DANS LA LISTE. C'est la moitié de la demande qu'un
//  contrôle de présence seul laisserait passer.
const avecCoupe = lignes.filter(l => /coupeWifi\(\)/.test(l)).length;
if (avecCoupe === 0)
  ok("aucune ligne de la liste ne porte « Déconnecter » — il est remonté en haut");
else non(`${avecCoupe} ligne(s) de la liste portent encore « Déconnecter »`);

//  ET IL N'Y EN A QU'UN. Deux boutons « Déconnecter » sur la même page, c'est
//  le doublon sous une autre forme.
const nbCoupe = (page.match(/coupeWifi\(\)/g) || []).length;
if (nbCoupe === 1)
  ok("il n'y a qu'un seul bouton « Déconnecter » sur toute la page");
else non(`${nbCoupe} boutons « Déconnecter » — attendu exactement 1`);

//  ═══ LE TITRE DIT CE QUE LA LISTE CONTIENT ═══
//  « Réseaux à portée » au-dessus d'une liste qui EXCLUT le réseau où l'on
//  est se lirait comme une liste incomplète.
if (/Autres réseaux à portée/.test(page))
  ok("le titre annonce « les autres », puisque c'est ce qu'on montre");
else non("le titre promet tous les réseaux à portée alors qu'il en manque un");

/* ========================================================================== */
//  ALEX, photo à l'appui : « quand je suis connecté sur le wi-fi, il dit pas
//  de déconnecter une fois connecté — là je suis connecté à BELL507 mais il
//  dit pas déconnecter ». La ligne du réseau actif ne portait qu'une pastille
//  « connecté » : rien à cliquer. Couper le Wi-Fi demandait le terminal,
//  alors que le Bluetooth, DANS LA MÊME FENÊTRE, a son bouton « Déconnecter »
//  depuis toujours (btCoupe). Deux poids, deux mesures dans une seule page.
//  Aucun réseau connecté : personne ne doit proposer de déconnecter.
T.pose({ wifi: {radio:"enabled", reseau:"", signal:0, internet:"none",
                auto:false,
                reseaux:[{ssid:"dlink-4538", signal:37, protege:true,
                          securite:"WPA2", actif:false}]} });
if (!/coupeWifi\(\)/.test(T.contenu("wifi")))
  ok("sans réseau connecté, aucun bouton « Déconnecter » n'est proposé");
else non("un bouton de déconnexion apparaît alors que rien n'est connecté");

//  LE GESTIONNAIRE N'ENVOIE AUCUN NOM, et c'est le fond du correctif : la
//  machine sait déjà quelle connexion couper (nmcli device status). Ne rien
//  envoyer vaut mieux que valider une chaîne — la page ne peut désigner ni
//  le câble, ni un VPN.
if (/coupeWifi\(\)"/.test(page))
  ok("coupeWifi() est appelée SANS argument (rien de la page n'atteint la commande)");
else non("coupeWifi() reçoit un argument — la page pourrait désigner autre chose");

console.log(`\n\x1b[1m${reussis} réussis, ${echoues} échoués\x1b[0m`);
process.exit(echoues === 0 ? 0 : 1);
