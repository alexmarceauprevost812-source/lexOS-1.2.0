/* =============================================================================
   Partager — ce que fait la page
   =============================================================================
   ELLE NE DÉCIDE RIEN. Tout ce qu'elle affiche vient de /api/etat, servi par
   partage.py ; tout ce qu'elle déclenche passe par /api/action, dont la liste
   est FERMÉE côté serveur. La page ne construit aucun chemin de fichier et ne
   lance aucune commande — même règle que le Volet et les Paramètres.

   LE COMPTE À REBOURS EST CALCULÉ SUR UNE FIN, PAS DÉCRÉMENTÉ.
   Un compteur qui fait « moins un » chaque seconde dérive : setInterval n'est
   pas garanti à la milliseconde, et il s'arrête net quand l'onglet passe en
   arrière-plan ou que la machine se met en veille. Au réveil, il afficherait
   encore 12 minutes sur un partage déjà fermé — c'est-à-dire un mensonge à
   l'écran. On garde donc l'HEURE DE FIN et on recalcule l'écart à chaque
   affichage : la veille n'y change rien.
   ========================================================================== */
(function () {
  "use strict";

  var fin = null;          //  horodatage de fin, en millisecondes
  var minuteur = null;

  function $(id) { return document.getElementById(id); }

  /*  Le nom de fichier vient du disque de l'utilisateur : il peut contenir
      n'importe quoi, y compris des chevrons. On le pose donc par
      textContent — jamais par innerHTML. */
  function ligneFichier(f) {
    var d = document.createElement("div");
    d.className = "fichier";
    var n = document.createElement("span");
    n.className = "nom";
    n.textContent = f.nom;
    var t = document.createElement("span");
    t.className = "taille";
    t.textContent = f.taille;
    d.appendChild(n);
    d.appendChild(t);
    return d;
  }

  function moyen(m) {
    var b = document.createElement("div");
    b.className = "moyen";
    var g = document.createElement("span");
    var t = document.createElement("span");
    t.className = "t";
    t.textContent = m.nom;
    var d = document.createElement("span");
    d.className = "d";
    d.textContent = m.detail;
    g.appendChild(t);
    g.appendChild(d);
    var e = document.createElement("span");
    e.className = "etat" + (m.pret ? " on" : "");
    e.textContent = m.etat;
    b.appendChild(g);
    b.appendChild(e);
    return b;
  }

  /*  ═══ LA LIGNE D'ÉTAT — CE QUE LA MACHINE A VÉRIFIÉ ═══
      ALEX : « on n'est pas capable de partager réellement ». La fenêtre ne
      disait RIEN de ce qui coinçait ; elle le dit maintenant, en une ligne et
      trois états. Le détail, en dessous, nomme la piste — y compris celle
      qu'aucun programme ne peut écarter tout seul : beaucoup de routeurs, et
      presque tous les réseaux « invité », interdisent à deux appareils du même
      Wi-Fi de se parler. */
  function etatPartage(d) {
    if (!d) { return; }
    var l = $("etat");
    l.classList.remove("pret", "souci");
    l.classList.add(d.niveau === "pret" ? "pret" : "souci");
    $("etat-texte").textContent = d.texte;
    $("etat-detail").textContent = d.detail || "";
  }

  function affiche(e) {
    $("url").textContent = e.url;
    if (e.qr) { $("qr").src = e.qr; }
    etatPartage(e.diagnostic);

    var box = $("fichiers");
    box.textContent = "";
    if (!e.fichiers.length) {
      var v = document.createElement("p");
      v.className = "vide";
      /*  ═══ « RIEN POUR L'INSTANT » RESSEMBLAIT À UNE PANNE ═══
          Sur la photo d'Alex, aucun fichier n'était choisi : la fenêtre
          disait « Rien pour l'instant » et le téléphone, en ouvrant la page,
          « Aucun fichier partagé pour l'instant ». Deux façons de dire la
          même chose, et les deux se lisent comme un partage qui ne marche
          pas — alors que tout marchait. On dit donc CE QUE ÇA CHANGE plutôt
          que ce qui manque. */
      v.textContent = "Aucun fichier choisi — la page servira seulement " +
                      "à recevoir depuis le téléphone.";
      box.appendChild(v);
    } else {
      e.fichiers.forEach(function (f) { box.appendChild(ligneFichier(f)); });
    }

    fin = Date.now() + e.secondes * 1000;
    tic();
    if (!minuteur) { minuteur = setInterval(tic, 1000); }
  }

  function tic() {
    var reste = Math.max(0, Math.round((fin - Date.now()) / 1000));
    var m = Math.floor(reste / 60);
    var s = reste % 60;
    $("reste").textContent = m + ":" + (s < 10 ? "0" : "") + s;
    if (reste === 0) {
      clearInterval(minuteur);
      minuteur = null;
      $("temoin").classList.add("mort");
      $("reste").parentNode.childNodes[2].textContent = " Partage fermé";
      $("reste").textContent = "";
    }
  }

  function action(quoi) {
    return fetch("api/action", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: quoi })
    });
  }

  /*  L'ADRESSE EST LE BOUTON. Avant : un <code> et une pastille « Copier »
      de douze pixels à côté. La cible du clic est maintenant toute la ligne,
      et il n'y a plus qu'une chose à comprendre. */
  $("url").addEventListener("click", function () {
    var b = this;
    var texte = b.textContent;
    /*  navigator.clipboard exige un contexte sûr. 127.0.0.1 en est un aux
        yeux de Chromium — mais QtWebEngine peut être bâti sans l'API, et une
        promesse rejetée laisserait le bouton sans réponse. Le repli par
        execCommand marche partout. */
    var fait = function () {
      b.classList.add("fait");
      b.title = "Copié";
      setTimeout(function () {
        b.classList.remove("fait");
        b.title = "Cliquer pour copier";
      }, 1600);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(texte).then(fait, replis);
    } else {
      replis();
    }
    function replis() {
      var z = document.createElement("textarea");
      z.value = texte;
      z.setAttribute("readonly", "");
      z.style.position = "absolute";
      z.style.left = "-9999px";
      document.body.appendChild(z);
      z.select();
      try { document.execCommand("copy"); fait(); } catch (err) { /* tant pis */ }
      document.body.removeChild(z);
    }
  });

  /*  ═══ LES APPAREILS PROCHES, DERRIÈRE LEUR BOUTON ═══
      Les rangées « KDE Connect » et « Bluetooth » étaient affichées en
      permanence, et coûtaient deux appels de quatre secondes à CHAQUE
      ouverture de la fenêtre — pour une information qu'on regarde rarement.
      Elles arrivent maintenant quand on les demande. Le bouton dit ce qui se
      passe pendant l'attente : sans ça, quatre secondes sans réaction se
      lisent comme un bouton mort — le défaut même qu'on répare ailleurs. */
  $("appareils").addEventListener("click", function () {
    var b = this;
    var libelle = b.textContent;
    b.disabled = true;
    b.textContent = "Recherche…";
    fetch("api/appareils")
      .then(function (r) { return r.json(); })
      .then(function (d) {
        var a = $("autres");
        a.textContent = "";
        (d.moyens || []).forEach(function (m) { a.appendChild(moyen(m)); });
      })
      .catch(function () {
        var a = $("autres");
        a.textContent = "";
        var v = document.createElement("p");
        v.className = "vide";
        v.textContent = "La recherche n'a pas abouti.";
        a.appendChild(v);
      })
      .then(function () {
        b.disabled = false;
        b.textContent = libelle;
      });
  });

  $("ouvrir").addEventListener("click", function () { action("ouvrir-recus"); });
  $("fermer").addEventListener("click", function () { action("fermer"); });

  fetch("api/etat")
    .then(function (r) { return r.json(); })
    .then(affiche)
    .catch(function () {
      /*  Si l'état ne vient pas, la page ne doit pas rester muette avec des
          points de suspension : on le dit, et on laisse le bouton Fermer. */
      $("url").textContent = "le serveur de partage n'a pas répondu";
    });
})();
