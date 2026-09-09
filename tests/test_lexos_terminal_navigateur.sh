#!/usr/bin/env bash
# =============================================================================
#  Éprouver LexOS Pro Terminal DANS UN VRAI NAVIGATEUR, contre le VRAI pont
# =============================================================================
#  ══ POURQUOI CE BANC EXISTE À CÔTÉ DES AUTRES ══
#
#  test_lexos_terminal_pty.sh éprouve le pont : le pseudo-terminal, les
#  quatre routes, les trois serrures. Il ne peut RIEN dire de l'affichage.
#  Or c'est là qu'était toute la moitié visible du travail : xterm.js, la
#  grille de caractères, les frappes qui partent, la taille qui suit.
#
#  Un bac à sable avec un « fetch » simulé ne l'aurait pas vu — et ce dépôt
#  en a déjà payé le prix : « printf "%s" "$HOME" » sans saut de ligne collait
#  le dossier personnel au nom d'utilisateur (« /rootroot »), et seul le
#  chargement de la VRAIE page dans un VRAI navigateur contre un VRAI pont
#  l'a montré. Alors on charge la vraie page dans Chromium, on TAPE au
#  clavier, et on lit ce que le terminal affiche vraiment.
#
#  ══ CE QUE CE BANC A TROUVÉ EN ÉTANT ÉCRIT ══
#
#  1. « ACCUEIL is not defined » — la déclaration avait disparu en même temps
#     que l'ancien pont. La page ne s'ouvrait pas du tout. Aucune relecture
#     de code ne l'avait attrapé ; le navigateur l'a dit en une ligne.
#  2. Les polices allaient chez Google à CHAQUE ouverture
#     (ERR_CONNECTION_RESET hors ligne). Le terminal principal du système
#     attendait une réponse qui ne vient jamais avant de peindre.
#  3. /favicon.ico réclamé puis 404 à chaque lancement.
#
#  ══ ET ON LIT LE TAMPON, PAS LE DOM ══
#  Première version : les contrôles lisaient « .xterm-rows > div ». Trois
#  d'entre eux étaient rouges alors que le terminal marchait parfaitement —
#  le DOM ne porte que les lignes VISIBLES, et pas sous une forme qu'on lit
#  au texte. Le tampon de xterm.js (buffer.active) est la seule source
#  honnête de ce que le terminal affiche.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$RACINE/config/includes.chroot/usr/share/lexos/terminal-pro/web"
BACKEND="$RACINE/config/includes.chroot/usr/lib/lexos/terminal-pro.py"

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

titre "LexOS Pro Terminal dans un vrai navigateur"

#  ═══ DE QUOI ON A BESOIN, ET CE QU'ON DIT QUAND ÇA MANQUE ═══
#  Ce banc demande trois choses qu'une machine de construction n'a pas
#  forcément. Quand elles manquent on le DIT — « sauté » et non « réussi » :
#  un banc qui s'annonce vert sans avoir rien éprouvé est pire que pas de banc.
NODE="$(command -v node || echo /opt/node22/bin/node)"
PW=""
for D in /opt/node22/lib/node_modules/playwright /usr/lib/node_modules/playwright \
         /usr/local/lib/node_modules/playwright "$RACINE/node_modules/playwright"; do
	[ -f "$D/index.mjs" ] && { PW="$D/index.mjs"; break; }
done

#  ═══ ON DEMANDE À PLAYWRIGHT OÙ IL A MIS CHROMIUM ═══
#  CE QUE ÇA FAISAIT AVANT : on devinait la disposition —
#  « chromium-XXXX/chrome-linux/chrome » — et on cherchait à deux ou trois
#  endroits connus. Ça a tenu jusqu'à ce que playwright change de version.
#  Relevé sur le coureur, journal à l'appui : le navigateur ÉTAIT bien posé
#
#      navigateurs posés dans /home/runner/work/_temp/lexos-navigateurs :
#      chromium-1243
#      chromium_headless_shell-1243
#
#  et le banc disait quand même « absent : chromium », parce que le binaire
#  n'était plus sous « chrome-linux/ ». Deviner la disposition interne d'un
#  outil, c'est se condamner à la corriger à chaque version — le dépôt le
#  dit déjà ailleurs à propos des noms de bibliothèques.
#  playwright, lui, SAIT. « chromium.executablePath() » rend le chemin exact,
#  quelle que soit la version et quel que soit PLAYWRIGHT_BROWSERS_PATH.
CHROME=""
if [ -n "$PW" ] && [ -x "$NODE" ]; then
	CHROME="$("$NODE" --input-type=module -e "
		import('$PW').then(p => console.log(p.chromium.executablePath()))
		  .catch(() => process.exit(1));
	" 2>/dev/null | tail -1)"
	[ -n "$CHROME" ] && [ -x "$CHROME" ] || CHROME=""
fi
#  REPLI : une machine qui a un Chromium de playwright mais pas le paquet
#  playwright lui-même (l'image de ce conteneur, par exemple).
if [ -z "$CHROME" ]; then
	for C in "${PLAYWRIGHT_BROWSERS_PATH:-/nonexistent}"/chromium-*/chrome-linux*/chrome \
	         /opt/pw-browsers/chromium-*/chrome-linux*/chrome \
	         /opt/pw-browsers/chromium/chrome-linux*/chrome \
	         "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome; do
		[ -x "$C" ] && { CHROME="$C"; break; }
	done
fi
XTERM_JS=""; XTERM_CSS=""; XTERM_FIT=""
for R in /usr/share/nodejs /usr/lib/nodejs /tmp/faux/nodejs; do
	[ -f "$R/xterm/lib/xterm.js" ] && XTERM_JS="$R/xterm/lib/xterm.js"
	[ -f "$R/xterm/css/xterm.css" ] && XTERM_CSS="$R/xterm/css/xterm.css"
	[ -f "$R/xterm-addon-fit/lib/xterm-addon-fit.js" ] && XTERM_FIT="$R/xterm-addon-fit/lib/xterm-addon-fit.js"
done

MANQUE=""
[ -x "$NODE" ]        || MANQUE="$MANQUE node"
[ -n "$CHROME" ]      || MANQUE="$MANQUE chromium"
[ -n "$PW" ]          || MANQUE="$MANQUE playwright"
[ -n "$XTERM_JS" ]    || MANQUE="$MANQUE node-xterm"
python3 -c "import os,pty; m,e=pty.openpty(); os.close(m); os.close(e)" 2>/dev/null \
                      || MANQUE="$MANQUE /dev/pts"
if [ -n "$MANQUE" ]; then
	#  ═══ SAUTER EST PERMIS SUR UNE MACHINE, PAS SUR LE COUREUR ═══
	#  CE QUE ÇA FAISAIT AVANT : ce banc se sautait et rendait 0 — donc VERT
	#  — dès qu'il manquait un outil. Sur le coureur GitHub, il manquait
	#  TOUJOURS quelque chose : l'étape de la CI n'installait ni node-xterm,
	#  ni playwright, ni Chromium, et elle ne cherchait le navigateur que
	#  dans /opt, où playwright ne le pose jamais là-bas. Résultat mesurable
	#  dans le journal : l'étape « Le terminal s'affiche pour de vrai » dure
	#  ZÉRO SECONDE à chaque construction depuis qu'elle existe.
	#
	#  Autrement dit : le SEUL banc qui éprouve l'affichage du terminal
	#  principal n'a jamais tourné, et il annonçait vert. C'est exactement le
	#  faux vert que ce dépôt traque partout ailleurs.
	#
	#  Sauter garde son sens sur la machine de quelqu'un qui n'a pas
	#  Chromium. Sur la CI, non : LEXOS_EXIGER_NAVIGATEUR=1 en fait un ROUGE.
	if [ "${LEXOS_EXIGER_NAVIGATEUR:-0}" = "1" ]; then
		non "absent :$MANQUE — et LEXOS_EXIGER_NAVIGATEUR=1 : ici, l'affichage DOIT être éprouvé"
		printf '\n\033[1m═══ TOTAL ═══\033[0m\n  réussis : %d\n  échoués : %d\n' "$REUSSIS" "$ECHOUES"
		exit 1
	fi
	saute "absent :$MANQUE — l'AFFICHAGE du terminal n'a PAS été éprouvé ici"
	saute "  (le pont, lui, l'est par tests/test_lexos_terminal_pty.sh)"
	printf '\n\033[1m═══ TOTAL ═══\033[0m\n  réussis : 0\n  sauté   : ce banc demande un vrai navigateur\n'
	exit 0
fi

#  vendor/ : exactement ce que le hook 0455 pose sur l'ISO.
mkdir -p "$WEB/vendor"
NETTOYER=0
[ -e "$WEB/vendor/xterm.js" ] || NETTOYER=1
ln -sf "$XTERM_JS"  "$WEB/vendor/xterm.js"
ln -sf "$XTERM_CSS" "$WEB/vendor/xterm.css"
ln -sf "$XTERM_FIT" "$WEB/vendor/xterm-addon-fit.js"
if [ "$NETTOYER" = "1" ]; then
	trap 'rm -f "$WEB/vendor/xterm.js" "$WEB/vendor/xterm.css" "$WEB/vendor/xterm-addon-fit.js"; rmdir "$WEB/vendor" 2>/dev/null' EXIT
fi

ESSAI="$(mktemp -d)"
cat > "$ESSAI/page.mjs" <<'JS'
//  « import » ne prend qu'un chemin littéral ; le nôtre vient de
//  l'environnement (playwright n'est pas au même endroit partout).
//  « import() » dynamique, lui, accepte une variable.
import { spawn } from 'node:child_process';
const { chromium } = await import(process.env.LEXOS_PW);

const BACKEND = process.env.LEXOS_BACKEND, WEB = process.env.LEXOS_WEB;
const py = `
import importlib.util, time
spec = importlib.util.spec_from_file_location("tp", "${BACKEND}")
tp = importlib.util.module_from_spec(spec); spec.loader.exec_module(tp)
srv, port, jeton = tp.demarrer_serveur()
print("PRET %d %s" % (port, jeton), flush=True)
time.sleep(240)`;
//  UN PONT = UN PROCESSUS. Les identifiants de volets sont comptés par la
//  PAGE (1, 2, 3…) : deux pages sur le même pont se disputeraient les mêmes
//  numéros de session. Le contrôle de la grille rattrapée ouvre donc une
//  seconde page contre un SECOND pont, à lui.
const pont = async () => {
  const pr = spawn('python3', ['-c', py], {env: {...process.env, LEXOS_TERMINAL_PRO_WEB: WEB}});
  const [, p, j] = await new Promise(r => pr.stdout.on('data', d => {
    const m = String(d).match(/PRET (\d+) (\S+)/); if (m) r(m);
  }));
  return {proc: pr, port: p, jeton: j};
};
const {proc, port, jeton} = await pont();

const nav = await chromium.launch({executablePath: process.env.LEXOS_CHROME, args: ['--no-sandbox']});
const page = await nav.newPage({viewport: {width: 1200, height: 760}});
const ennuis = [];
page.on('pageerror', e => ennuis.push('erreur JS : ' + e.message));
page.on('requestfailed', r => ennuis.push('requête échouée : ' + r.url().slice(0, 70)));
page.on('response', r => { if (!r.ok()) ennuis.push('HTTP ' + r.status() + ' ' + r.url().slice(0, 70)); });

const dit = (b, m) => console.log((b ? 'OK|' : 'NON|') + m);
//  LE TAMPON, PAS LE DOM : voir l'en-tête de ce fichier.
//  ═══ ET UNE LIGNE QUI SE REPLIE EST **UNE** LIGNE ═══
//  MESURÉ, et ça a coûté une construction rouge. xterm.js range une ligne
//  trop longue sur DEUX lignes de tampon, la seconde marquée « isWrapped ».
//  Ce lecteur les recollait avec un saut de ligne au milieu — donc le texte
//  affiché à l'écran, celui qu'un humain lit d'un trait, arrivait coupé en
//  deux au banc.
//  Sur le coureur GitHub, l'invite de bash est « runner@fv-az…:~$ » (24
//  caractères) dans une grille de 80 colonnes. Le contrôle des soixante
//  frappes rapides écrit « echo » + 60 caractères : 89 colonnes, donc la
//  ligne se replie. Le banc ne retrouvait la rafale qu'UNE fois au lieu de
//  deux et criait « frappes mélangées » — alors que le shell avait tout reçu
//  dans l'ordre. Reproduit ici à l'identique en forçant 80 colonnes et cette
//  invite-là : lecture brute 1 / lecture recollée 2.
//  Un banc qui accuse la frappe pour une histoire de largeur de fenêtre ne
//  mesure pas ce qu'il annonce.
const ecran = () => page.evaluate(() => {
  const f = window.LexOS.fenetreActive(); if (!f || !f.term) return '';
  const b = f.term.buffer.active, out = [];
  for (let i = 0; i < b.length; i++) {
    const l = b.getLine(i); if (!l) continue;
    const t = l.translateToString(true);
    if (l.isWrapped && out.length) out[out.length - 1] += t;
    else out.push(t);
  }
  return out.join('\n');
});
//  LE MÊME ÉCRAN, LU BRUTALEMENT : une ligne de tampon = une ligne. Il ne
//  sert qu'à UN contrôle — celui qui prouve que le recollement ci-dessus
//  change vraiment quelque chose. Sans cette seconde lecture, un contrôle
//  « sur une ligne repliée » resterait vert le jour où la ligne cesse de se
//  replier, et ne prouverait plus rien.
const ecranBrut = () => page.evaluate(() => {
  const f = window.LexOS.fenetreActive(); if (!f || !f.term) return '';
  const b = f.term.buffer.active, out = [];
  for (let i = 0; i < b.length; i++) { const l = b.getLine(i); if (l) out.push(l.translateToString(true)); }
  return out.join('\n');
});
//  L'ÉCRAN VISIBLE SEUL, sans l'historique. « clear » efface l'écran mais ne
//  jette pas les lignes derrière : les chercher dans le tampon entier ferait
//  échouer le contrôle de l'effacement pour une raison qui n'a rien à voir.
const vue = () => page.evaluate(() => {
  const f = window.LexOS.fenetreActive(); const b = f.term.buffer.active, out = [];
  for (let i = 0; i < f.term.rows; i++) {
    const l = b.getLine(b.viewportY + i); out.push(l ? l.translateToString(true) : '');
  }
  return out.join('\n');
});
//  ═══ insertText, PAS type() — ET CE N'EST PAS UN DÉTAIL DE CONFORT ═══
//  MESURÉ : « page.keyboard.type("echo APRES=$(tput cols)") » arrivait dans
//  le shell sous la forme « echo APRES=($tput cols) ». Les caractères qui
//  demandent Maj ($ ( _ …) se réordonnent en chemin — une course entre les
//  événements clavier de Playwright et la zone de saisie de xterm.js, du
//  côté du BANC, pas du produit. Quatre contrôles étaient rouges à cause de
//  ça, dont trois qui n'avaient rien à voir avec la frappe.
//  insertText pose le texte d'un coup, sans passer par les touches — et un
//  contrôle plus bas garde exprès la vraie frappe touche par touche, pour
//  que ce chemin-là reste éprouvé lui aussi.
const tape = async (t) => { await page.keyboard.insertText(t); await page.keyboard.press('Enter');
                            await page.waitForTimeout(1100); };

const adresse = `http://127.0.0.1:${port}/index.html?port=${port}&jeton=${jeton}`;
await page.goto(adresse);
await page.waitForTimeout(2500);

dit(await page.evaluate(() => !!document.querySelector('.xterm-rows')),
    'xterm.js a ouvert une vraie grille de caractères dans le volet');

const t0 = await ecran();
dit(/LexOS/.test(t0), 'la bannière est écrite DANS le terminal (séquences ANSI, plus de HTML)');
//  L'invite de bash, avec le VRAI nom d'utilisateur et le VRAI dossier : la
//  page n'en dessine plus aucune, et n'a plus à demander $HOME au démarrage.
dit(/[$#]\s*$/m.test(t0.replace(/\s+$/, '') + '\n'), 'bash a écrit SA propre invite — le shell est vivant');

await page.click('.fen.actif .xterm-screen');
//  ═══ LA VRAIE FRAPPE, TOUCHE PAR TOUCHE ═══
//  Ce contrôle-ci n'utilise PAS insertText : il tape pour de vrai, comme un
//  humain, pour éprouver le chemin clavier complet (keydown → xterm.js →
//  onData → /api/saisie → le pty). Sans lettres accentuées ni caractères qui
//  demandent Maj, pour ne pas retomber sur la course décrite plus haut.
await page.keyboard.type('echo bonjour depuis le navigateur');
await page.keyboard.press('Enter');
await page.waitForTimeout(1200);
const t1 = await ecran();
//  Deux fois : l'écho de la frappe par le pty, puis la sortie de la commande.
dit((t1.match(/bonjour depuis le navigateur/g) || []).length >= 2,
    'une frappe RÉELLE touche par touche part au shell et sa sortie revient');

//  ═══ CE QU'ON TAPE VITE ARRIVE DANS L'ORDRE, ET RIEN NE SE PERD ═══
//  Ces deux contrôles viennent d'un vrai défaut, mesuré ici même : en
//  tapant « echo tres tot » dès l'ouverture, le shell recevait « trse tot ».
//  Deux causes distinctes, chacune suffisante :
//    · ce qui était tapé AVANT que le flux réponde partait vers une session
//      qui n'existait pas encore → 404 → caractères perdus EN SILENCE ;
//    · chaque touche partait dans SA propre requête, sans attendre la
//      précédente → deux requêtes en vol → le serveur les traite dans
//      l'ordre d'arrivée, pas dans celui de la frappe.
//  Mesuré : sans la file d'attente sérialisée, SIX rafales sur six
//  arrivaient mélangées. C'est le genre de panne qu'on met sur le compte du
//  clavier, et qu'on ne trouve jamais.
{
  const RAFALE = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwx';
  await page.evaluate((t) => {
    const f = window.LexOS.fenetreActive();
    f.envoyer('echo ');
    for (const c of t) f.envoyer(c);   // une frappe = un appel, sans attendre
    f.envoyer('\r');
  }, RAFALE);
  await page.waitForTimeout(2000);
  const apres = await ecran();
  dit((apres.match(new RegExp(RAFALE, 'g')) || []).length >= 2,
      'soixante frappes rapides arrivent au shell DANS L\'ORDRE (rien de mélangé)');

  //  ═══ LA MÊME RAFALE, MAIS SUR UNE LIGNE QUI SE REPLIE ═══
  //  C'est la géométrie EXACTE du coureur GitHub : une invite longue
  //  (« runner@fv-az…:~$ ») dans une grille étroite. La ligne tapée dépasse
  //  la largeur et xterm.js la range sur deux lignes de tampon.
  //  Sans le recollement des lignes repliées (voir ecran(), plus haut), ce
  //  contrôle-ci est ROUGE — vérifié en le rejouant sans : rafale trouvée
  //  UNE fois au lieu de deux. Il garde donc la lecture honnête, et il
  //  continue de mesurer l'ORDRE des frappes, pas la largeur de la fenêtre.
  await page.setViewportSize({width: 470, height: 600});
  await page.waitForTimeout(1400);
  const etroit = await page.evaluate(() => window.LexOS.fenetreActive().term.cols);
  await page.evaluate((t) => {
    const f = window.LexOS.fenetreActive();
    f.envoyer('echo ');
    for (const c of t) f.envoyer(c);
    f.envoyer('\r');
  }, RAFALE);
  await page.waitForTimeout(2000);
  const cpt = (t) => (t.match(new RegExp(RAFALE, 'g')) || []).length;
  const nRec = cpt(await ecran()), nBrut = cpt(await ecranBrut());
  //  DEUX EXIGENCES, ET LA SECONDE EST CE QUI DONNE DES DENTS AU CONTRÔLE :
  //   · recollée ≥ 2  → la rafale est bien arrivée dans l'ordre ;
  //   · brute    < 2  → la ligne s'est VRAIMENT repliée, donc la lecture
  //                     naïve (celle du coureur, avant ce correctif) aurait
  //                     échoué ici. Si la géométrie cessait de replier, ce
  //                     contrôle deviendrait rouge au lieu de devenir muet.
  dit(nRec >= 2 && nBrut < 2,
      'et sur une ligne qui SE REPLIE (' + etroit + ' colonnes) : toujours dans l\'ordre '
      + '(lue brute ' + nBrut + ', recollée ' + nRec + ')');
  await page.setViewportSize({width: 1200, height: 760});
  await page.waitForTimeout(1400);
}

await tape("printf 'ACCENTS: éàüç 🙂\\n'");
dit(/ACCENTS: éàüç/.test(await ecran()),
    'accents et emoji traversent le flux base64 et s\'affichent intacts');

//  ═══ LA PREUVE QU'IL S'AGIT D'UNE GRILLE, PAS D'UN JOURNAL ═══
//  Effacer l'écran et placer le curseur en (10,20) : deux ordres que
//  l'ancienne page RETIRAIT en silence, faute de savoir quoi en faire.
await tape('clear; printf "\\033[2J\\033[H\\033[10;20HPLACE_EN_10_20"');
const t2 = await vue();
const ligne10 = t2.split('\n')[9] || '';
dit(/PLACE_EN_10_20/.test(t2) && !/bonjour depuis/.test(t2) && !/ACCENTS/.test(t2),
    'l\'écran s\'efface pour de vrai : une grille, pas un journal qui défile');
//  La colonne exacte, pas seulement « le texte est là » : c'est le
//  déplacement du curseur que l'ancienne page retirait en silence.
dit(ligne10.indexOf('PLACE_EN_10_20') === 19,
    'le curseur se place à la colonne demandée (ligne 10, colonne 20)');

//  ═══ LA TAILLE : ce que la grille montre et ce que le shell croit ═══
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
const c1 = await page.evaluate(() => window.LexOS.fenetreActive().term.cols);
const l1 = await page.evaluate(() => window.LexOS.fenetreActive().term.rows);
await tape('echo TAILLE=$(tput cols)x$(tput lines)');
const vu1 = ((await ecran()).match(/TAILLE=\d+x\d+/g) || []).pop();
dit(vu1 === 'TAILLE=' + c1 + 'x' + l1,
    'le shell voit EXACTEMENT la grille affichée (' + vu1 + ')');

await page.setViewportSize({width: 780, height: 600});
await page.waitForTimeout(1200);
const c2 = await page.evaluate(() => window.LexOS.fenetreActive().term.cols);
await tape('echo APRES=$(tput cols)');
const vu2 = ((await ecran()).match(/APRES=\d+/g) || []).pop();
dit(c2 !== c1 && vu2 === 'APRES=' + c2,
    'redimensionner la fenêtre change ce que le shell voit (' + c1 + ' → ' + c2 + ')');

//  ═══ DEUX VOLETS, DEUX SHELLS — validation n° 10 ═══
await page.click('.fen.actif [data-a="droite"]');
await page.waitForTimeout(2500);
dit(await page.evaluate(() => document.querySelectorAll('.xterm-rows').length) === 2,
    'diviser ouvre un SECOND terminal');
const pids = await page.evaluate(async () => {
  const f = [...document.querySelectorAll('.fen')];
  return f.length;
});
await page.click('.fen:not(.actif) .xterm-screen');
await page.waitForTimeout(300);
await tape('echo VOLET=$$');
const droite = await ecran();
await page.click('.fen:not(.actif) .xterm-screen');
await page.waitForTimeout(300);
await tape('echo VOLET=$$');
const gauche = await ecran();
const pd = (droite.match(/VOLET=(\d+)/) || [])[1];
const pg = (gauche.match(/VOLET=(\d+)/) || [])[1];
dit(pids === 2 && pd && pg && pd !== pg,
    'chaque volet a SON shell, avec son propre pid (' + pg + ' ≠ ' + pd + ')');

dit(ennuis.length === 0,
    'aucune erreur ni requête échouée dans la page' + (ennuis.length ? ' — ' + ennuis.slice(0, 3).join(' | ') : ''));

//  ═══ TAPER TOUT DE SUITE, SUR UNE FENÊTRE NEUVE ═══
//  Le geste le plus banal qui soit : Super+T, et on tape. Une page fraîche,
//  et on frappe dès que le terminal existe — sans laisser le flux s'établir.
//  Répété plusieurs fois, parce que c'est une COURSE : une seule tentative
//  peut passer par chance, et un banc qui passe par chance est pire que pas
//  de banc (il apprend à ignorer les rouges).
{
  let bons = 0;
  const N = 4;
  for (let i = 0; i < N; i++) {
    const neuve = await nav.newPage({viewport: {width: 1000, height: 600}});
    await neuve.goto(adresse);
    await neuve.waitForFunction(() =>
      window.LexOS && window.LexOS.fenetreActive() && window.LexOS.fenetreActive().term);
    await neuve.evaluate(() => window.LexOS.fenetreActive().term.focus());
    await neuve.keyboard.type('echo tres tot');
    await neuve.keyboard.press('Enter');
    await neuve.waitForTimeout(2500);
    const t = await neuve.evaluate(() => {
      const b = window.LexOS.fenetreActive().term.buffer.active, o = [];
      for (let j = 0; j < b.length; j++) { const l = b.getLine(j); if (l) o.push(l.translateToString(true)); }
      return o.join('\n');
    });
    if ((t.match(/tres tot/g) || []).length >= 2) bons++;
    await neuve.close();
  }
  dit(bons === N,
      'ce qu\'on tape AVANT que le shell soit prêt n\'est pas perdu (' + bons + '/' + N + ')');
}

//  ═══ HUIT VOLETS, ET LE TERMINAL RÉPOND TOUJOURS ═══
//  Un navigateur n'accorde que SIX connexions simultanées par origine en
//  HTTP/1.1. Tant que chaque volet tenait SON flux ouvert, le sixième
//  épuisait le quota et TOUT se figeait — plus une frappe, plus un
//  redimensionnement, et rien à l'écran pour le dire. MESURÉ avant le
//  correctif, dans ce même Chromium : 1 à 5 volets → /api/saisie en 3 à
//  6 ms ; 6 volets et au-delà → aucune réponse en 5 secondes.
//  Le pont suit maintenant tous les volets sur UN flux (fens=*), et ouvrir
//  un volet est une requête courte. Ce contrôle le vérifie là où ça se
//  joue : dans un vrai navigateur, avec ses vraies limites.
{
  const r = await page.evaluate(async ({jeton, n}) => {
    const lents = [];
    for (let i = 900; i < 900 + n; i++) {
      await fetch('/api/ouvrir', {method:'POST',
        headers:{'Content-Type':'application/json','X-Lexos-Jeton':jeton},
        body: JSON.stringify({fen:String(i), colonnes:80, lignes:24})});
      const t0 = performance.now();
      try {
        const ctl = new AbortController();
        const m = setTimeout(() => ctl.abort(), 4000);
        await fetch('/api/saisie', {method:'POST', signal: ctl.signal,
          headers:{'Content-Type':'application/json','X-Lexos-Jeton':jeton},
          body: JSON.stringify({fen:String(i), texte:''})});
        clearTimeout(m);
      } catch (e) { lents.push(i - 899); }
      const ms = performance.now() - t0;
      if (ms > 2000 && !lents.includes(i - 899)) lents.push(i - 899);
    }
    for (let i = 900; i < 900 + n; i++)
      fetch('/api/fermer', {method:'POST',
        headers:{'Content-Type':'application/json','X-Lexos-Jeton':jeton},
        body: JSON.stringify({fen:String(i)})});
    return lents;
  }, {jeton, n: 8});
  dit(r.length === 0,
      r.length === 0
        ? 'huit volets ouverts : le terminal répond toujours (le 6e ne fige plus rien)'
        : 'le terminal se fige à partir du volet ' + r[0] + ' — le quota de connexions du navigateur est épuisé');
}

//  ═══ LA GRILLE REMPLIT LA FENÊTRE, MÊME QUAND LA MESURE ARRIVE EN RETARD ═══
//  D'OÙ ÇA VIENT : sur le coureur GitHub, ce banc a mesuré « TAILLE=80x24 »
//  dans une fenêtre de 1200×760 — la grille PAR DÉFAUT de xterm.js. Le shell
//  y voyait 80 colonnes et repliait ses lignes au milieu de l'écran, pour
//  toujours : rien ne réajustait après coup.
//  LA CAUSE : xterm.js ne peut pas mesurer la largeur d'un caractère tant que
//  rien n'est dessiné ; fit() ne fait alors RIEN, et ne le dit pas.
//  ON LE REPRODUIT POUR DE VRAI, dans une seconde page : « body{display:none} »
//  posé AVANT que le script ne construise le terminal, puis retiré. Mesuré
//  avant le correctif — grille 80x24, corps 1198x670, proposé 154x36 : la
//  fenêtre était prête et la grille ne bougeait plus.
{
  const deux = await pont();
  const p2 = await nav.newPage({viewport: {width: 1200, height: 760}});
  await p2.addInitScript(() => {
    const poser = () => {
      if (!document.documentElement) { setTimeout(poser, 0); return; }
      if (document.getElementById('cachette')) return;
      const s = document.createElement('style');
      s.id = 'cachette';
      s.textContent = 'body{display:none !important}';
      document.documentElement.appendChild(s);
    };
    poser();
  });
  await p2.goto(`http://127.0.0.1:${deux.port}/index.html?port=${deux.port}&jeton=${deux.jeton}`);
  await p2.waitForTimeout(1500);
  const cachee = await p2.evaluate(() => {
    const f = window.LexOS.fenetreActive();
    return f && f.term ? f.term.cols : 0;
  });
  await p2.evaluate(() => { const c = document.getElementById('cachette'); if (c) c.remove(); });
  await p2.waitForTimeout(3000);
  const g = await p2.evaluate(() => {
    const f = window.LexOS.fenetreActive();
    let p; try { p = f.ajust.proposeDimensions(); } catch (e) { p = null; }
    return {cols: f.term.cols, rows: f.term.rows, veut: p ? p.cols : 0};
  });
  //  La grille suit ce que la fenêtre permet — et 80 n'est pas une largeur
  //  qu'on choisit, c'est celle qu'on subit quand personne n'a mesuré.
  dit(g.veut > 0 && g.cols === g.veut && g.cols > 80,
      'la grille remplit la fenêtre même si la mesure arrive en retard ('
      + cachee + ' colonnes cachée → ' + g.cols + 'x' + g.rows + ' révélée)');
  //  ET LE SHELL DOIT L'APPRENDRE. Une grille rattrapée dont le pty garde
  //  80 colonnes ne corrige rien : bash replierait toujours au même endroit.
  await p2.click('.fen.actif .xterm-screen');
  //  « stty size » plutôt que « echo …$(tput cols) » : pas une majuscule ni
  //  une parenthèse, donc aucune course entre les touches de Playwright et
  //  la zone de saisie de xterm.js (voir tape(), plus haut). Il rend
  //  « lignes colonnes », c'est-à-dire ce que le PTY croit, pas la page.
  await p2.keyboard.type('stty size');
  await p2.keyboard.press('Enter');
  await p2.waitForTimeout(1800);
  const vuShell = await p2.evaluate(() => {
    const f = window.LexOS.fenetreActive(); const b = f.term.buffer.active, out = [];
    for (let i = 0; i < b.length; i++) {
      const l = b.getLine(i); if (!l) continue;
      const t = l.translateToString(true);
      if (l.isWrapped && out.length) out[out.length - 1] += t; else out.push(t);
    }
    return (out.join('\n').match(/^\d+ \d+$/gm) || []).pop();
  });
  dit(vuShell === g.rows + ' ' + g.cols,
      'et le PTY apprend la nouvelle taille (stty size → ' + vuShell + ')');
  await p2.close(); deux.proc.kill();
}

await nav.close(); proc.kill();
JS

rendu() {
	local vus=0 ligne verdict message
	while IFS='|' read -r verdict message; do
		case "$verdict" in
			OK)  ok  "$message"; vus=$((vus+1)) ;;
			NON) non "$message"; vus=$((vus+1)) ;;
			*)
				ligne="$verdict$message"
				[ -n "$ligne" ] && printf '     %s\n' "$ligne"
				case "$ligne" in Traceback*|*Error:*|*error*) vus=-1000 ;; esac
				;;
		esac
	done
	[ "$vus" -gt 0 ] || non "aucun verdict rendu (l'essai s'est arrêté)"
}

rendu < <(LEXOS_PW="$PW" LEXOS_CHROME="$CHROME" LEXOS_BACKEND="$BACKEND" LEXOS_WEB="$WEB" \
          timeout 240 "$NODE" "$ESSAI/page.mjs" 2>&1)
rm -rf "$ESSAI"

printf '\n\033[1m═══ TOTAL ═══\033[0m\n'
printf '  réussis : \033[32m%d\033[0m\n  échoués : \033[31m%d\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ] || exit 1
