"use strict";
/* LexOS Diagnostic — interface. Vanilla JS, aucune dépendance externe :
 * l'outil doit fonctionner hors ligne, sur une machine qui vient d'être
 * installée, avant même que l'utilisateur ait ouvert un navigateur pour
 * autre chose. Même logique que LexOS Studio (index.html autonome). */

const LIMITE_HISTORIQUE = 240; // ~60 s à 250 ms / point (voir INTERVALLE_HISTORIQUE_MS)
const INTERVALLE_HISTORIQUE_MS = 250; // ajout aux courbes détaché du sondage (1,5 s) pour un tracé fluide
const TAUX_LISSAGE = 0.12; // vitesse de rattrapage de l'affichage vers la valeur mesurée, par image (~60 i/s)

const ETAT = {
  historique: { cpu: [], ram: [], gpu: [], envoi: [], reception: [] },
  enLigne: true,
  ongletActif: "materiel",
};

// CIBLE = dernière valeur mesurée (mise à jour à chaque sondage, 1,5 s).
// AFFICHE = valeur réellement peinte à l'écran, rattrapée en douceur vers
// CIBLE à chaque image d'animation (~60 i/s). C'est ce qui remplace le saut
// brut d'une mesure à l'autre par un mouvement fluide — demandé explicitement.
const CIBLE = { cpu: 0, ram: 0, gpu: 0, gpuDisponible: false, batterie: null, coeurs: [], reception: 0, envoi: 0 };
const AFFICHE = { cpu: 0, ram: 0, gpu: 0, batterie: 0, coeurs: [], reception: 0, envoi: 0 };
let lissageAmorce = false; // évite un fondu depuis 0 au premier chargement : la 1re mesure s'affiche d'un coup
let dernierPushHistorique = 0;

/* ---------------------------------------------------------------------- */
/* Formatage                                                              */
/* ---------------------------------------------------------------------- */

function formaterOctets(valeur) {
  if (valeur === null || valeur === undefined) return "—";
  const unites = ["o", "Ko", "Mo", "Go", "To"];
  let v = Number(valeur);
  for (const u of unites) {
    if (Math.abs(v) < 1024) return `${v.toFixed(1).replace(".", ",")} ${u}`;
    v /= 1024;
  }
  return `${v.toFixed(1).replace(".", ",")} Po`;
}

function formaterDebit(octetsParSeconde) {
  if (octetsParSeconde === null || octetsParSeconde === undefined) return "—";
  return `${formaterOctets(octetsParSeconde)}/s`;
}

function formaterDuree(secondes) {
  if (secondes === null || secondes === undefined) return "—";
  secondes = Math.floor(secondes);
  const jours = Math.floor(secondes / 86400);
  const heures = Math.floor((secondes % 86400) / 3600);
  const minutes = Math.floor((secondes % 3600) / 60);
  const parties = [];
  if (jours) parties.push(`${jours} j`);
  if (jours || heures) parties.push(`${heures} h`);
  parties.push(`${minutes} min`);
  return parties.join(" ");
}

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

function pousser(tableau, valeur) {
  tableau.push(valeur);
  if (tableau.length > LIMITE_HISTORIQUE) tableau.shift();
}

/* ---------------------------------------------------------------------- */
/* Courbes de tendance (canvas, sans bibliothèque)                        */
/* ---------------------------------------------------------------------- */

function preparerCanvas(canvas) {
  const ratio = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const largeur = Math.max(1, Math.round(rect.width * ratio));
  const hauteur = Math.max(1, Math.round((rect.height || 46) * ratio));
  if (canvas.width !== largeur) canvas.width = largeur;
  if (canvas.height !== hauteur) canvas.height = hauteur;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, largeur, hauteur);
  return { ctx, largeur, hauteur, ratio };
}

function tracerCourbe(ctx, valeurs, plafond, largeur, hauteur, ratio, couleur) {
  const marge = 3 * ratio;
  const pasX = largeur / (valeurs.length - 1);
  ctx.beginPath();
  valeurs.forEach((v, i) => {
    const x = i * pasX;
    const y = hauteur - marge - (Math.min(v, plafond) / plafond) * (hauteur - marge * 2);
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.strokeStyle = couleur;
  ctx.lineWidth = 2 * ratio;
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.stroke();
  return pasX;
}

function dessinerTendance(canvas, valeurs, couleur, plafondFixe) {
  if (!canvas || valeurs.length < 2) return;
  const { ctx, largeur, hauteur, ratio } = preparerCanvas(canvas);
  // Plafond fixe pour les pourcentages (0-100) : sinon une valeur stable à
  // 10 % remplit tout le graphique (elle EST son propre maximum récent),
  // ce qui a l'air d'une machine à bout de souffle alors qu'elle est calme.
  const plafond = plafondFixe || Math.max(1, ...valeurs);
  tracerCourbe(ctx, valeurs, plafond, largeur, hauteur, ratio, couleur);
  ctx.lineTo(largeur, hauteur);
  ctx.lineTo(0, hauteur);
  ctx.closePath();
  ctx.globalAlpha = 0.12;
  ctx.fillStyle = couleur;
  ctx.fill();
  ctx.globalAlpha = 1;
}

function dessinerTendanceDouble(canvas, reception, envoi) {
  if (!canvas || reception.length < 2) return;
  const { ctx, largeur, hauteur, ratio } = preparerCanvas(canvas);
  const plafond = Math.max(1, ...reception, ...envoi);
  tracerCourbe(ctx, reception, plafond, largeur, hauteur, ratio, "#00AF5F");
  tracerCourbe(ctx, envoi, plafond, largeur, hauteur, ratio, "#FF8C1A");
}

/* ---------------------------------------------------------------------- */
/* Rendu — onglet Matériel                                                */
/* ---------------------------------------------------------------------- */

function disqueMiniHtml(dq) {
  const classe = dq.pourcentage >= 90 ? "rouge" : "";
  return `
    <div style="margin-bottom:10px">
      <div class="ligne-stat"><span>${escapeHtml(dq.point_montage)}</span><b>${dq.pourcentage.toFixed(0)} %</b></div>
      <div class="jauge ${classe}"><i style="width:${Math.min(100, dq.pourcentage)}%"></i></div>
    </div>`;
}

function ligneProcessus(p) {
  return `<tr><td class="pid">${p.pid}</td><td class="nom">${escapeHtml(p.nom)}</td><td>${p.cpu_pct.toFixed(1)}</td><td>${p.ram_pct.toFixed(1)}</td></tr>`;
}

function appliquerGpu(gpu) {
  CIBLE.gpuDisponible = !!gpu.disponible;
  CIBLE.gpu = gpu.disponible ? (gpu.utilisation_pct ?? 0) : 0;
  document.getElementById("gpu-nom").textContent = gpu.disponible ? (gpu.nom || "GPU") : (gpu.message || "indisponible");
  document.getElementById("gpu-vram").textContent = gpu.vram_totale_o
    ? `${formaterOctets(gpu.vram_utilisee_o)} / ${formaterOctets(gpu.vram_totale_o)}` : "—";
  document.getElementById("gpu-temp").textContent = (gpu.temperature_c !== null && gpu.temperature_c !== undefined)
    ? `${gpu.temperature_c.toFixed(0)} °C` : "—";
  document.getElementById("gpu-puissance").textContent = (gpu.puissance_w !== null && gpu.puissance_w !== undefined)
    ? `${gpu.puissance_w.toFixed(0)} W` : "—";
  if (!gpu.disponible) {
    // Pas de pourcentage à animer : on l'indique tout de suite plutôt que
    // de laisser une jauge à 0 % qui suggère (à tort) un GPU présent mais inactif.
    document.getElementById("gpu-pct-txt").textContent = "—";
    document.getElementById("gpu-jauge").style.width = "0%";
    AFFICHE.gpu = 0;
  }
}

function appliquerVentilateurs(ventilateurs, gpu) {
  const conteneur = document.getElementById("ventilos-liste");
  let html = "";
  if (ventilateurs.length) {
    html += ventilateurs.map((v) =>
      `<div class="ligne-stat"><span>${escapeHtml(v.nom)}</span><b>${v.vitesse_rpm ?? "—"} tr/min</b></div>`
    ).join("");
  }
  if (gpu.disponible && gpu.ventilateur_pct !== null && gpu.ventilateur_pct !== undefined) {
    html += `<div class="ligne-stat"><span>GPU</span><b>${gpu.ventilateur_pct.toFixed(0)} %</b></div>`;
  }
  conteneur.innerHTML = html || '<p class="vide">Aucun capteur de ventilateur détecté (lm-sensors).</p>';
}

function appliquerReseau(reseau) {
  const conteneur = document.getElementById("reseau-liste");
  const interfaces = reseau.interfaces || [];
  conteneur.innerHTML = interfaces.length
    ? interfaces.map((i) => {
        const ssid = reseau.ssid_wifi && i.nom.toLowerCase().startsWith("w") ? ` · ${escapeHtml(reseau.ssid_wifi)}` : "";
        return `<div class="ligne-stat">
          <span>${escapeHtml(i.nom)}${i.adresse_ip ? " · " + escapeHtml(i.adresse_ip) : ""}${ssid}</span>
          <b>↓ ${formaterDebit(i.reception_octets_s)} · ↑ ${formaterDebit(i.envoi_octets_s)}</b>
        </div>`;
      }).join("")
    : '<p class="vide">Aucune interface active.</p>';

  // Total tous réseaux confondus : c'est ce que trace la courbe de tendance,
  // lissé comme le reste (le débit texte par interface reste instantané).
  CIBLE.envoi = interfaces.reduce((s, i) => s + (i.envoi_octets_s || 0), 0);
  CIBLE.reception = interfaces.reduce((s, i) => s + (i.reception_octets_s || 0), 0);
}

function appliquerBatterie(bat) {
  const carte = document.getElementById("batterie-carte");
  if (!bat.presente) {
    carte.style.display = "none";
    CIBLE.batterie = null;
    return;
  }
  carte.style.display = "";
  CIBLE.batterie = bat.pourcentage ?? 0;
  const etat = bat.branche ? "en charge" : "sur batterie";
  const reste = bat.secondes_restantes ? ` · ${formaterDuree(bat.secondes_restantes)} restant` : "";
  document.getElementById("batterie-etat").textContent = etat + reste;
}

function appliquerEtat(d) {
  document.getElementById("info-machine").textContent = d.systeme.nom_machine;
  document.getElementById("info-version").textContent = d.systeme.version_lexos;
  document.getElementById("info-noyau").textContent = d.systeme.noyau;
  document.getElementById("info-uptime").textContent = formaterDuree(d.systeme.temps_actif_s);
  document.getElementById("syst-resume").textContent = `${d.systeme.nom_machine} · ${d.systeme.version_lexos}`;

  CIBLE.cpu = d.cpu.utilisation_globale_pct ?? 0;
  CIBLE.coeurs = d.cpu.utilisation_par_coeur_pct || [];
  document.getElementById("cpu-modele").textContent =
    `${d.cpu.modele} · ${d.cpu.coeurs_physiques ?? "?"} cœurs / ${d.cpu.coeurs_logiques ?? "?"} fils`;
  document.getElementById("cpu-freq").textContent = d.cpu.frequence_actuelle_mhz
    ? `${(d.cpu.frequence_actuelle_mhz / 1000).toFixed(2)} GHz` : "—";
  document.getElementById("cpu-charge").textContent = d.cpu.charge_1_5_15
    ? d.cpu.charge_1_5_15.map((v) => v.toFixed(2)).join(" / ") : "—";
  document.getElementById("cpu-temp").textContent = (d.cpu.temperature_c !== null && d.cpu.temperature_c !== undefined)
    ? `${d.cpu.temperature_c.toFixed(0)} °C` : "indisponible";

  CIBLE.ram = d.ram.pourcentage ?? 0;
  document.getElementById("ram-detail").textContent =
    `${formaterOctets(d.ram.utilise_o)} utilisés sur ${formaterOctets(d.ram.total_o)}`;
  document.getElementById("ram-swap").textContent = d.ram.swap_total_o
    ? `${formaterOctets(d.ram.swap_utilise_o)} / ${formaterOctets(d.ram.swap_total_o)}` : "aucune";

  appliquerGpu(d.gpu);
  appliquerVentilateurs(d.ventilateurs || [], d.gpu);
  appliquerReseau(d.reseau);
  appliquerBatterie(d.batterie);

  document.getElementById("disques-espace-mini").innerHTML = d.disques.length
    ? d.disques.map(disqueMiniHtml).join("") : '<p class="vide">Aucune partition détectée.</p>';

  document.getElementById("proc-cpu-corps").innerHTML = d.processus.top_cpu.map(ligneProcessus).join("");
  document.getElementById("proc-ram-corps").innerHTML = d.processus.top_ram.map(ligneProcessus).join("");

  if (!lissageAmorce) {
    // Premier instantané : on peint directement la cible, sans remontée
    // depuis 0 — l'animation ne concerne que les mesures suivantes.
    AFFICHE.cpu = CIBLE.cpu;
    AFFICHE.ram = CIBLE.ram;
    AFFICHE.gpu = CIBLE.gpu;
    AFFICHE.batterie = CIBLE.batterie;
    AFFICHE.coeurs = CIBLE.coeurs.slice();
    AFFICHE.reception = CIBLE.reception;
    AFFICHE.envoi = CIBLE.envoi;
    lissageAmorce = true;
    rendreValeursAnimees();
    dernierPushHistorique = performance.now();
    pousserHistorique();
  }
}

/* ---------------------------------------------------------------------- */
/* Animation — rattrapage image par image vers la dernière mesure         */
/* ---------------------------------------------------------------------- */

function rendreValeursAnimees() {
  document.getElementById("cpu-pct-txt").textContent = `${Math.round(AFFICHE.cpu)} %`;
  document.getElementById("cpu-jauge").style.width = `${Math.min(100, AFFICHE.cpu)}%`;

  const conteneurCoeurs = document.getElementById("cpu-coeurs");
  if (conteneurCoeurs.children.length !== AFFICHE.coeurs.length) {
    conteneurCoeurs.innerHTML = AFFICHE.coeurs.map(() => "<i></i>").join("");
  }
  AFFICHE.coeurs.forEach((v, i) => { conteneurCoeurs.children[i].style.height = `${Math.max(4, v)}%`; });

  document.getElementById("ram-pct-txt").textContent = `${Math.round(AFFICHE.ram)} %`;
  document.getElementById("ram-jauge").style.width = `${Math.min(100, AFFICHE.ram)}%`;

  if (CIBLE.gpuDisponible) {
    document.getElementById("gpu-pct-txt").textContent = `${Math.round(AFFICHE.gpu)} %`;
    document.getElementById("gpu-jauge").style.width = `${Math.min(100, AFFICHE.gpu)}%`;
  }

  if (CIBLE.batterie !== null) {
    document.getElementById("batterie-pct-txt").textContent = `${Math.round(AFFICHE.batterie)} %`;
    document.getElementById("batterie-jauge").style.width = `${Math.min(100, AFFICHE.batterie)}%`;
  }
}

function pousserHistorique() {
  pousser(ETAT.historique.cpu, AFFICHE.cpu);
  dessinerTendance(document.getElementById("cpu-tendance"), ETAT.historique.cpu, "#FF8C1A", 100);
  pousser(ETAT.historique.ram, AFFICHE.ram);
  dessinerTendance(document.getElementById("ram-tendance"), ETAT.historique.ram, "#FF8C1A", 100);
  pousser(ETAT.historique.gpu, AFFICHE.gpu);
  dessinerTendance(document.getElementById("gpu-tendance"), ETAT.historique.gpu, "#FF8C1A", 100);
  pousser(ETAT.historique.reception, AFFICHE.reception);
  pousser(ETAT.historique.envoi, AFFICHE.envoi);
  dessinerTendanceDouble(document.getElementById("reseau-tendance"), ETAT.historique.reception, ETAT.historique.envoi);
}

function etapeAnimation(temps) {
  requestAnimationFrame(etapeAnimation);
  if (!lissageAmorce) return; // rien à rattraper avant le tout premier sondage

  AFFICHE.cpu += (CIBLE.cpu - AFFICHE.cpu) * TAUX_LISSAGE;
  AFFICHE.ram += (CIBLE.ram - AFFICHE.ram) * TAUX_LISSAGE;
  AFFICHE.gpu += (CIBLE.gpu - AFFICHE.gpu) * TAUX_LISSAGE;
  AFFICHE.reception += (CIBLE.reception - AFFICHE.reception) * TAUX_LISSAGE;
  AFFICHE.envoi += (CIBLE.envoi - AFFICHE.envoi) * TAUX_LISSAGE;
  if (CIBLE.batterie !== null) {
    AFFICHE.batterie += (CIBLE.batterie - AFFICHE.batterie) * TAUX_LISSAGE;
  }
  if (AFFICHE.coeurs.length !== CIBLE.coeurs.length) {
    AFFICHE.coeurs = CIBLE.coeurs.slice(); // nombre de cœurs qui change (rare) : pas de tableau à interpoler
  } else {
    for (let i = 0; i < CIBLE.coeurs.length; i++) {
      AFFICHE.coeurs[i] += (CIBLE.coeurs[i] - AFFICHE.coeurs[i]) * TAUX_LISSAGE;
    }
  }

  rendreValeursAnimees();

  if (temps - dernierPushHistorique >= INTERVALLE_HISTORIQUE_MS) {
    dernierPushHistorique = temps;
    pousserHistorique();
  }
}

/* ---------------------------------------------------------------------- */
/* Sondage en direct                                                      */
/* ---------------------------------------------------------------------- */

function definirEnLigne(enLigne) {
  if (ETAT.enLigne === enLigne) return;
  ETAT.enLigne = enLigne;
  const temoin = document.getElementById("temoin");
  temoin.classList.toggle("hors-ligne", !enLigne);
  temoin.innerHTML = enLigne ? '<i class="point"></i> EN DIRECT' : '<i class="point"></i> HORS LIGNE';
}

async function sonderEtat() {
  try {
    const reponse = await fetch("/api/etat", { cache: "no-store" });
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    appliquerEtat(await reponse.json());
    definirEnLigne(true);
  } catch (erreur) {
    definirEnLigne(false);
  } finally {
    setTimeout(sonderEtat, ETAT.enLigne ? 1500 : 4000);
  }
}

/* ---------------------------------------------------------------------- */
/* Onglet Médecin                                                         */
/* ---------------------------------------------------------------------- */

function badgeEtat(id, ok) {
  const el = document.getElementById(id);
  if (ok === null || ok === undefined) { el.className = "badge inconnu"; el.textContent = "inconnu"; return; }
  if (ok) { el.className = "badge ok"; el.textContent = "OK"; return; }
  el.className = "badge echec"; el.textContent = "problème";
}

function appliquerBilan(b) {
  const outils = b.outils;
  document.getElementById("med-outils-total").textContent = outils.dispatcheur_trouve
    ? `${outils.total} outils, ${outils.joignables} joignables, ${outils.problemes.length} problème(s)`
    : `${outils.total} outils (/usr/bin/lexos introuvable ici)`;
  const badgeOutils = document.getElementById("med-outils-badge");
  if (outils.problemes.length === 0) { badgeOutils.className = "badge ok"; badgeOutils.textContent = "OK"; }
  else { badgeOutils.className = "badge echec"; badgeOutils.textContent = `${outils.problemes.length} problème(s)`; }
  document.getElementById("med-outils-problemes").innerHTML = outils.problemes.map((p) => {
    const raisons = [];
    if (!p.executable) raisons.push("pas exécutable");
    /*  « absent du dispatcheur » était vrai pour dix outils qui vont très
        bien : ils partent par udev, par une minuterie systemd ou à
        l'ouverture de session. La seule chose qui mérite qu'on dérange
        quelqu'un, c'est que PERSONNE ne puisse le lancer. */
    if (p.joignable === false) raisons.push("joignable par aucun chemin");
    return `<li>${escapeHtml(p.nom)} — ${raisons.join(", ")}</li>`;
  }).join("");

  badgeEtat("med-son", b.son.fonctionne);
  badgeEtat("med-wifi", b.wifi.disponible === null ? null : !!b.wifi.disponible);
  badgeEtat("med-journal", b.journal.disponible ? b.journal.nombre === 0 : null);

  const disquesPleins = document.getElementById("med-disques-pleins");
  disquesPleins.innerHTML = b.disques_pleins.length
    ? b.disques_pleins.map((d) =>
        `<div class="ligne-stat"><span>${escapeHtml(d.point_montage)}</span><span class="badge echec">${d.pourcentage.toFixed(0)} %</span></div>`
      ).join("")
    : '<p class="vide">Toutes les partitions sont sous le seuil d’alerte.</p>';
}

async function chargerMedecin() {
  try {
    const [bilan, rapport] = await Promise.all([
      fetch("/api/sante").then((r) => r.json()),
      fetch("/api/sante/rapport").then((r) => r.text()),
    ]);
    appliquerBilan(bilan);
    document.getElementById("med-rapport-texte").textContent = rapport;
  } catch (erreur) {
    document.getElementById("med-rapport-texte").textContent = "Impossible de joindre le serveur local.";
  }
  chargerFirmware(false);
}

function appliquerFirmware(d) {
  const msg = document.getElementById("firmware-message");
  const liste = document.getElementById("firmware-liste");
  if (!d.disponible) { msg.textContent = d.message; liste.innerHTML = ""; return; }
  msg.textContent = d.mises_a_jour.length
    ? `${d.mises_a_jour.length} mise(s) à jour disponible(s).`
    : `${d.peripheriques.length} périphérique(s) détecté(s), rien à mettre à jour pour l'instant.`;
  liste.innerHTML = d.peripheriques.map((p) =>
    `<div class="ligne-stat"><span>${escapeHtml(p.Name || "?")}</span><b>${escapeHtml(p.Version || "—")}</b></div>`
  ).join("");
}

async function chargerFirmware(forcer) {
  const bouton = document.getElementById("firmware-verifier");
  bouton.disabled = true;
  if (forcer) bouton.textContent = "Vérification…";
  try {
    const reponse = forcer
      ? await fetch("/api/firmware/verifier", { method: "POST" })
      : await fetch("/api/firmware");
    appliquerFirmware(await reponse.json());
  } catch (erreur) {
    document.getElementById("firmware-message").textContent = "Impossible de joindre le serveur local.";
  } finally {
    bouton.disabled = false;
    bouton.textContent = "Vérifier les mises à jour";
  }
}

/* ---------------------------------------------------------------------- */
/* Onglet Disques                                                         */
/* ---------------------------------------------------------------------- */

function carteSanteDisque(entree) {
  let badge = '<span class="badge inconnu">inconnu</span>';
  if (entree.sain === true) badge = '<span class="badge ok">sain</span>';
  else if (entree.sain === false) badge = '<span class="badge echec">à surveiller</span>';

  const details = [];
  if (entree.modele) details.push(escapeHtml(entree.modele));
  if (entree.temperature_c !== undefined && entree.temperature_c !== null) details.push(`${entree.temperature_c} °C`);
  if (entree.nvme && entree.nvme.usure_pourcentage !== undefined && entree.nvme.usure_pourcentage !== null) {
    details.push(`usure NVMe : ${entree.nvme.usure_pourcentage} %`);
  }
  if (entree.message) details.push(entree.message);

  return `
    <div class="disque-carte" style="margin-bottom:10px">
      <div class="disque-entete"><span class="nom">${escapeHtml(entree.peripherique)}</span>${badge}</div>
      <div class="note">${details.join(" · ") || "—"}</div>
    </div>`;
}

function appliquerDisques(d) {
  document.getElementById("disques-sante-liste").innerHTML = d.sante.length
    ? d.sante.map(carteSanteDisque).join("") : '<p class="vide">Aucun disque détecté.</p>';
  document.getElementById("disques-espace-liste").innerHTML = d.espace.length
    ? d.espace.map(disqueMiniHtml).join("") : '<p class="vide">Aucune partition détectée.</p>';

  const manquants = Object.entries(d.outils).filter(([, dispo]) => !dispo).map(([nom]) => nom);
  document.getElementById("disques-outils-note").textContent = manquants.length
    ? `Non installés ici : ${manquants.join(", ")}` : "";
}

async function chargerDisques() {
  try {
    appliquerDisques(await fetch("/api/disques").then((r) => r.json()));
  } catch (erreur) {
    document.getElementById("disques-sante-liste").innerHTML = '<p class="vide">Impossible de joindre le serveur local.</p>';
  }
}

async function chercherDoublons() {
  const bouton = document.getElementById("doublons-lancer");
  const dossier = document.getElementById("doublons-dossier").value.trim();
  const resultats = document.getElementById("doublons-resultats");
  bouton.disabled = true;
  bouton.textContent = "Recherche…";
  resultats.innerHTML = '<p class="vide">Recherche en cours…</p>';
  try {
    const reponse = await fetch("/api/disques/doublons", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dossier: dossier || null }),
    });
    const d = await reponse.json();
    if (!d.disponible) {
      resultats.innerHTML = `<p class="vide">${escapeHtml(d.message)}</p>`;
    } else if (!d.doublons.length) {
      resultats.innerHTML = `<p class="vide">${escapeHtml(d.message || "Aucun doublon trouvé.")}</p>`;
    } else {
      resultats.innerHTML = `<p class="note">${d.doublons.length} doublon(s) dans ${escapeHtml(d.dossier)} :</p>` +
        d.doublons.map((x) =>
          `<div class="ligne-stat"><span>${escapeHtml(x.chemin)}</span><b>${formaterOctets(x.taille_o)}</b></div>`
        ).join("");
    }
  } catch (erreur) {
    resultats.innerHTML = '<p class="vide">Impossible de joindre le serveur local.</p>';
  } finally {
    bouton.disabled = false;
    bouton.textContent = "Chercher les doublons";
  }
}

/* ---------------------------------------------------------------------- */
/* Onglets                                                                 */
/* ---------------------------------------------------------------------- */

function activerOnglet(nom) {
  document.querySelectorAll(".onglet").forEach((b) => b.classList.toggle("actif", b.dataset.onglet === nom));
  document.querySelectorAll(".page").forEach((p) => p.classList.toggle("active", p.id === `page-${nom}`));
  ETAT.ongletActif = nom;
  history.replaceState(null, "", `#${nom}`);
  if (nom === "medecin") chargerMedecin();
  if (nom === "disques") chargerDisques();
}

/* ---------------------------------------------------------------------- */
/* Démarrage                                                              */
/* ---------------------------------------------------------------------- */

document.querySelectorAll(".onglet").forEach((b) => {
  b.addEventListener("click", () => activerOnglet(b.dataset.onglet));
});

document.getElementById("med-actualiser").addEventListener("click", chargerMedecin);
document.getElementById("firmware-verifier").addEventListener("click", () => chargerFirmware(true));
document.getElementById("disques-actualiser").addEventListener("click", chargerDisques);
document.getElementById("doublons-lancer").addEventListener("click", chercherDoublons);

document.getElementById("med-copier").addEventListener("click", async () => {
  const statut = document.getElementById("med-copier-statut");
  const texte = document.getElementById("med-rapport-texte").textContent;
  try {
    await navigator.clipboard.writeText(texte);
    statut.textContent = "Copié.";
  } catch (erreur) {
    statut.textContent = "Copie automatique impossible — sélectionnez le texte ci-dessus.";
  }
  setTimeout(() => { statut.textContent = ""; }, 4000);
});

window.addEventListener("resize", () => {
  dessinerTendance(document.getElementById("cpu-tendance"), ETAT.historique.cpu, "#FF8C1A", 100);
  dessinerTendance(document.getElementById("ram-tendance"), ETAT.historique.ram, "#FF8C1A", 100);
  dessinerTendance(document.getElementById("gpu-tendance"), ETAT.historique.gpu, "#FF8C1A", 100);
  dessinerTendanceDouble(document.getElementById("reseau-tendance"), ETAT.historique.reception, ETAT.historique.envoi);
});

const ongletsValides = ["materiel", "medecin", "disques"];

function ongletDepuisHash() {
  const nom = (location.hash || "#materiel").slice(1);
  return ongletsValides.includes(nom) ? nom : "materiel";
}

// Si un onglet est déjà ouvert dans un navigateur et qu'un des alias
// (lexos-medecin, lexos-disques…) le rappelle avec un nouveau lien, certains
// navigateurs réutilisent l'onglet existant : ce n'est alors qu'un
// changement de fragment d'URL, pas un rechargement complet. Sans cette
// écoute, le clic resterait sans effet sur un onglet déjà ouvert.
window.addEventListener("hashchange", () => activerOnglet(ongletDepuisHash()));

activerOnglet(ongletDepuisHash());
sonderEtat();
requestAnimationFrame(etapeAnimation);
