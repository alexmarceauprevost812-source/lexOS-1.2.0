"""Les dix pages de Paramètres.

Chacune suit la même structure (widgets.Page) et la même règle : une
mesure absente s'affiche avec sa raison, une action impossible est un
bouton éteint AVEC son motif en infobulle, et rien de destructeur ne part
sans confirmation.
"""
from __future__ import annotations

import time
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox,
                               QHBoxLayout, QHeaderView, QLabel, QLineEdit,
                               QMessageBox, QPlainTextEdit, QSlider,
                               QTreeWidget, QTreeWidgetItem, QVBoxLayout,
                               QWidget)

from ....services import (applications, capacites, disques, execution, gpu,
                          maj, prefs, processus, reseau, son, systeme,
                          unites)
from ... import theme, widgets

_ROLE = 256


def _carte_simple(titre, icone):
    c = widgets.Carte(titre, icone)
    c.jauge.hide()
    c.courbe.hide()
    return c


# ══════════════════════════════════════════════════════════════════════
class PageSysteme(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Système",
            "Informations matérielles et logicielles relevées sur cette "
            "machine.", parent)
        self.arbre = QTreeWidget()
        self.arbre.setHeaderLabels(["Élément", "Valeur"])
        self.arbre.setColumnWidth(0, 240)
        self.arbre.setMinimumHeight(400)
        self.arbre.setAlternatingRowColors(True)
        self.disposition.addWidget(self.arbre)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        b = widgets.bouton("Copier ces informations", "apropos")
        b.clicked.connect(self._copier)
        d.addWidget(b)
        self.b_nom = widgets.bouton("Changer le nom de la machine…", "systeme")
        self.b_nom.clicked.connect(self._nom)
        d.addWidget(self.b_nom)
        d.addStretch(1)
        self.disposition.addWidget(barre)

    def rafraichir(self):
        i = systeme.infos()
        s = i["session"]
        lignes = [
            ("Nom de la machine", i["machine"]),
            ("Distribution", i["distribution"]),
            ("Identifiant de distribution", i["distribution_id"]),
            ("Version", i["distribution_version"]),
            ("Familles déclarées (ID_LIKE)", i["familles"]),
            ("LexOS détecté", "oui" if i["lexos"] else "non"),
            ("Noyau", i["noyau"]),
            ("Architecture", i["architecture"]),
            ("Processeur", i["processeur"]),
            ("Cœurs logiques", str(i["coeurs_logiques"])),
            ("Cœurs physiques", str(i["coeurs_physiques"])),
            ("Session graphique", s["type"]),
            ("Bureau déclaré", s["bureau"] or "non déclaré"),
            ("Gestionnaire de session", s["gestionnaire"] or "non déclaré"),
            ("Utilisateur", i["utilisateur"] or "inconnu"),
            ("Lancé en root", "oui" if i["racine"] else "non"),
            ("Python de l'application", i["python"]),
        ]
        self.arbre.clear()
        for cle, val in lignes:
            item = QTreeWidgetItem([cle, val])
            item.setToolTip(1, val)
            self.arbre.addTopLevelItem(item)
        #  hostnamectl est le mécanisme système, authentifié par polkit :
        #  on ne réimplémente pas un formulaire de mot de passe maison.
        if execution.outil_present("hostnamectl"):
            self.b_nom.setEnabled(True)
            self.b_nom.setToolTip(
                "Ouvre le mécanisme système (hostnamectl), qui demandera "
                "lui-même l'autorisation.")
        else:
            widgets.eteindre(
                self.b_nom,
                "hostnamectl est absent : LEXOS PRO ne modifie pas le nom de "
                "la machine par un autre moyen.")
        self.statut.neutre("Informations relues.")

    def _copier(self):
        texte = "\n".join(
            f"{self.arbre.topLevelItem(i).text(0)} : "
            f"{self.arbre.topLevelItem(i).text(1)}"
            for i in range(self.arbre.topLevelItemCount()))
        QApplication.clipboard().setText(texte)
        self.statut.succes("Informations copiées dans le presse-papiers.")

    def _nom(self):
        from PySide6.QtWidgets import QInputDialog
        actuel = systeme.infos()["machine"]
        nom, ok = QInputDialog.getText(
            self, "Nom de la machine",
            "Nouveau nom (lettres, chiffres et tirets) :",
            QLineEdit.Normal, actuel)
        if not ok or not nom.strip():
            return
        nom = nom.strip()
        if not all(c.isalnum() or c == "-" for c in nom):
            self.statut.echec(
                "Un nom de machine ne peut contenir que des lettres, des "
                "chiffres et des tirets.")
            return
        if QMessageBox.question(
                self, "Confirmer",
                f"Renommer cette machine « {nom} » ?\n\n"
                f"Le système demandera votre autorisation.") != QMessageBox.Yes:
            return
        #  pkexec plutôt qu'un mot de passe saisi dans notre fenêtre.
        r = execution.lancer(["pkexec", "hostnamectl", "set-hostname", nom],
                             delai=30.0)
        self.afficher_resultat(r, f"Machine renommée « {nom} ».")
        self.rafraichir()


# ══════════════════════════════════════════════════════════════════════
class PagePerformances(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Performances",
            "Courbes en direct et liste des processus. L'arrêt demandé est "
            "un SIGTERM — une demande polie — et seulement sur vos propres "
            "processus.", parent)
        self._cpu = systeme.MesureCPU()
        self._moniteur = processus.Moniteur()

        grille = self.ajouter_grille(3)
        self.c_cpu = widgets.Carte("Processeur", "processeur")
        self.c_mem = widgets.Carte("Mémoire", "memoire")
        self.c_temp = _carte_simple("Températures", "performances")
        for i, c in enumerate((self.c_cpu, self.c_mem, self.c_temp)):
            grille.addWidget(c, 0, i)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.filtre = QLineEdit()
        self.filtre.setPlaceholderText("Filtrer par nom ou PID…")
        self.filtre.textChanged.connect(self._remplir)
        d.addWidget(self.filtre, 1)
        self.seuls_miens = QCheckBox("Seulement mes processus")
        self.seuls_miens.setChecked(True)
        self.seuls_miens.stateChanged.connect(self._remplir)
        d.addWidget(self.seuls_miens)
        self.b_arret = widgets.bouton("Demander l'arrêt", "retour")
        self.b_arret.clicked.connect(self._arreter)
        d.addWidget(self.b_arret)
        self.disposition.addWidget(barre)

        self.table = QTreeWidget()
        self.table.setHeaderLabels(["PID", "Nom", "Processeur", "Mémoire",
                                    "Commande"])
        self.table.setSortingEnabled(True)
        self.table.setColumnWidth(0, 80)
        self.table.setColumnWidth(1, 200)
        self.table.setColumnWidth(2, 100)
        self.table.setColumnWidth(3, 110)
        self.table.header().setSectionResizeMode(4, QHeaderView.Stretch)
        self.table.setMinimumHeight(320)
        self.table.setAlternatingRowColors(True)
        self.disposition.addWidget(self.table, 1)

        self._liste = []
        self.periodique(2000)

    def rafraichir(self):
        m = self._cpu.pourcent()
        if m.disponible:
            ch = systeme.charge()
            self.c_cpu.montrer(f"{m.valeur:.0f} %",
                               f"Charge moyenne : {ch.detail or ch.raison}",
                               m.valeur, m.valeur)
        else:
            self.c_cpu.indisponible(m.raison)
        mem = systeme.memoire()
        if mem["disponible"]:
            echange = ""
            if mem["echange_total"]:
                utilise = mem["echange_total"] - mem["echange_libre"]
                echange = (f"\nÉchange : "
                           f"{systeme.octets_lisibles(utilise)} / "
                           f"{systeme.octets_lisibles(mem['echange_total'])}")
            self.c_mem.montrer(
                f"{mem['pourcent']:.0f} %",
                f"{systeme.octets_lisibles(mem['utilise'])} sur "
                f"{systeme.octets_lisibles(mem['total'])}{echange}",
                mem["pourcent"], mem["pourcent"])
        else:
            self.c_mem.indisponible(mem["raison"])
        t = processus.temperatures()
        if t["trouve"]:
            plus_chaud = max(t["capteurs"], key=lambda c: c["celsius"])
            self.c_temp.montrer(
                f"{plus_chaud['celsius']:.0f} °C",
                "\n".join(f"{c['nom']} : {c['celsius']:.0f} °C"
                          for c in t["capteurs"][:5]))
        else:
            self.c_temp.indisponible(t["raison"])

        self._liste = self._moniteur.liste()
        self._remplir()

    def _remplir(self):
        motif = self.filtre.text().strip().lower()
        seuls = self.seuls_miens.isChecked()
        selection = self._pid_choisi()
        self.table.setSortingEnabled(False)
        self.table.clear()
        n = 0
        for p in self._liste:
            if seuls and not p.a_nous:
                continue
            if motif and motif not in p.nom.lower() and motif != str(p.pid):
                continue
            cpu = "—" if p.cpu is None else f"{p.cpu:.1f} %"
            item = QTreeWidgetItem([str(p.pid), p.nom, cpu,
                                    systeme.octets_lisibles(p.memoire),
                                    p.commande[:160]])
            item.setData(0, _ROLE, p)
            item.setTextAlignment(2, Qt.AlignRight | Qt.AlignVCenter)
            item.setTextAlignment(3, Qt.AlignRight | Qt.AlignVCenter)
            if not p.a_nous:
                item.setForeground(1, QColor(theme.TEXTE_FAIBLE))
                item.setToolTip(1, "Processus d'un autre utilisateur : "
                                   "l'arrêt n'est pas proposé.")
            self.table.addTopLevelItem(item)
            if p.pid == selection:
                self.table.setCurrentItem(item)
            n += 1
        self.table.setSortingEnabled(True)
        if self._moniteur.premier_passage:
            self.statut.neutre(
                f"{n} processus. Le pourcentage processeur apparaît au "
                f"prochain relevé : il se calcule entre deux lectures.")
        else:
            self.statut.neutre(f"{n} processus affichés.")

    def _pid_choisi(self):
        item = self.table.currentItem()
        if not item:
            return None
        p = item.data(0, _ROLE)
        return p.pid if p else None

    def _arreter(self):
        item = self.table.currentItem()
        if not item:
            self.statut.attention("Sélectionnez d'abord un processus.")
            return
        p = item.data(0, _ROLE)
        if not p.a_nous:
            self.statut.echec(
                f"Le processus {p.pid} appartient à un autre utilisateur. "
                f"LEXOS PRO ne demande l'arrêt que de vos propres processus.")
            return
        if QMessageBox.question(
                self, "Demander l'arrêt",
                f"Demander l'arrêt de « {p.nom} » (PID {p.pid}) ?\n\n"
                f"Un signal SIGTERM sera envoyé : le programme peut "
                f"sauvegarder puis se fermer. Il peut aussi refuser.",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No) != QMessageBox.Yes:
            return
        self.afficher_resultat(processus.demander_arret(p.pid))
        self.rafraichir()


# ══════════════════════════════════════════════════════════════════════
class PageReseau(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Réseau",
            "Interfaces et état de la connexion, en lecture seule. Les "
            "mots de passe Wi-Fi restent dans les réglages natifs : LEXOS "
            "PRO n'en stocke aucun.", parent)
        self.c_etat = _carte_simple("Connectivité", "reseau")
        self.disposition.addWidget(self.c_etat)

        self.arbre = QTreeWidget()
        self.arbre.setHeaderLabels(["Interface", "Type", "État", "Adresses",
                                    "MAC"])
        self.arbre.setColumnWidth(0, 130)
        self.arbre.setColumnWidth(1, 110)
        self.arbre.setColumnWidth(2, 90)
        self.arbre.setColumnWidth(3, 260)
        self.arbre.setMinimumHeight(260)
        self.arbre.setAlternatingRowColors(True)
        self.disposition.addWidget(self.arbre, 1)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.b_natif = widgets.bouton("Ouvrir les réglages réseau du système",
                                      "reseau", principal=True)
        self.b_natif.clicked.connect(self._natif)
        d.addWidget(self.b_natif)
        b = widgets.bouton("Relire", "maj")
        b.clicked.connect(self.rafraichir)
        d.addWidget(b); d.addStretch(1)
        self.disposition.addWidget(barre)

    def rafraichir(self):
        self.statut.occupe("Lecture du réseau…")
        widgets.en_fond(self, self._lire, self._pret,
                        lambda m: self.statut.echec(m))

    @staticmethod
    def _lire():
        return {"interfaces": reseau.interfaces(),
                "passerelle": reseau.passerelle(),
                "connectivite": reseau.connectivite(),
                "active": reseau.connexion_active()}

    def _pret(self, r):
        con = r["connectivite"]
        pas = r["passerelle"]
        detail = [f"Mesure : {con.get('source', '?')} — {con.get('etat', '?')}"]
        detail.append("Passerelle : " + (
            f"{pas['adresse']} via {pas['interface']}" if pas.get("trouve")
            else pas.get("raison", "")))
        a = r["active"]
        detail.append("Connexion active : " + (
            ", ".join(f"{c['nom']} ({c['type']})" for c in a["connexions"])
            if a.get("trouve") else a.get("raison", "")))
        self.c_etat.montrer("Connecté" if con.get("connecte") else "Hors ligne",
                            "\n".join(detail))
        self.c_etat.valeur.setStyleSheet(
            f"color: {theme.VERT if con.get('connecte') else theme.JAUNE};"
            f"font-size: 22px; font-weight: 600;")

        self.arbre.clear()
        for i in r["interfaces"]:
            adresses = ", ".join(f"{a['adresse']}" for a in i.adresses) or "—"
            item = QTreeWidgetItem([i.nom, i.type_, i.etat, adresses,
                                    i.mac or "—"])
            if i.etat == "up":
                item.setForeground(2, QColor(theme.VERT))
            self.arbre.addTopLevelItem(item)
        g = capacites.reseau_gestionnaire()
        if g["present"]:
            self.b_natif.setEnabled(True)
            self.statut.neutre(f"Gestionnaire détecté : {g['nom']}.")
        else:
            self.statut.attention(g["raison"])
        if not any(i.adresses for i in r["interfaces"]):
            self.statut.attention(
                "Aucune adresse lisible : l'outil « ip » est peut-être absent "
                "(paquet iproute2).")

    def _natif(self):
        for argv in (["nm-connection-editor"],
                     ["gnome-control-center", "network"],
                     ["xfce4-settings-manager"],
                     ["systemsettings", "kcm_networkmanagement"]):
            if execution.outil_present(argv[0]):
                self.afficher_resultat(execution.lancer_detache(argv),
                                       f"{argv[0]} lancé.")
                return
        self.statut.echec(
            "Aucun panneau réseau natif trouvé (nm-connection-editor, "
            "gnome-control-center, systemsettings).")


# ══════════════════════════════════════════════════════════════════════
class PageApparence(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Apparence",
            "Ces réglages concernent LEXOS PRO. Ceux du bureau Linux sont "
            "séparés, et signalés comme tels.", parent)
        self._contexte = contexte
        self._prefs = prefs.charger()

        c = _carte_simple("Réglages de l'application", "apparence")
        boite = QWidget(); d = QVBoxLayout(boite)
        d.setContentsMargins(0, 8, 0, 0); d.setSpacing(10)

        l1 = QHBoxLayout()
        l1.addWidget(QLabel("Taille du texte :"))
        self.taille = QSlider(Qt.Horizontal)
        self.taille.setRange(80, 160)
        self.taille.setSingleStep(5)
        self.taille.setPageStep(10)
        self.taille.setValue(int(self._prefs.get("taille_texte", 100)))
        self.etiquette_taille = QLabel(f"{self.taille.value()} %")
        self.taille.valueChanged.connect(
            lambda v: self.etiquette_taille.setText(f"{v} %"))
        self.taille.sliderReleased.connect(self._appliquer)
        l1.addWidget(self.taille, 1); l1.addWidget(self.etiquette_taille)
        d.addLayout(l1)

        l2 = QHBoxLayout()
        l2.addWidget(QLabel("Densité :"))
        self.densite = QComboBox()
        self.densite.addItems(["confortable", "compacte"])
        self.densite.setCurrentText(self._prefs.get("densite", "confortable"))
        self.densite.currentTextChanged.connect(lambda _: self._appliquer())
        l2.addWidget(self.densite); l2.addStretch(1)
        d.addLayout(l2)

        self.animations = QCheckBox(
            "Animations discrètes (désactivables)")
        self.animations.setChecked(bool(self._prefs.get("animations", True)))
        self.animations.stateChanged.connect(lambda _: self._appliquer())
        d.addWidget(self.animations)

        note = QLabel(
            "Le thème noir et orange est celui de LEXOS PRO : il ne change "
            "pas selon le thème du bureau, pour que l'application reste "
            "reconnaissable.")
        note.setWordWrap(True)
        note.setObjectName("CarteDetail")
        d.addWidget(note)
        c.corps.addWidget(boite)
        self.disposition.addWidget(c)

        cb = _carte_simple("Réglages du bureau Linux", "affichage")
        cb.detail.setText(
            "Le fond d'écran, le thème des fenêtres et les polices "
            "appartiennent à votre environnement de bureau, pas à cette "
            "application. LEXOS PRO ouvre l'outil natif plutôt que de "
            "modifier des réglages qu'il ne maîtrise pas.")
        bb = QWidget(); db = QHBoxLayout(bb)
        db.setContentsMargins(0, 8, 0, 0)
        self.b_fond = widgets.bouton("Changer le fond d'écran…", "apparence")
        self.b_fond.clicked.connect(self._fond)
        db.addWidget(self.b_fond)
        self.b_bureau = widgets.bouton("Apparence du bureau…", "affichage")
        self.b_bureau.clicked.connect(self._bureau)
        db.addWidget(self.b_bureau); db.addStretch(1)
        cb.corps.addWidget(bb)
        self.disposition.addWidget(cb)
        self.disposition.addStretch(1)

    def rafraichir(self):
        outil = self._outil_fond()
        if outil:
            self.b_fond.setEnabled(True)
            self.b_fond.setToolTip(f"Ouvrira « {outil[0]} ».")
        else:
            widgets.eteindre(
                self.b_fond,
                "Aucun outil de fond d'écran reconnu pour ce bureau "
                f"({capacites.session()['bureau'] or 'non déclaré'}).")
        self.statut.neutre("Réglages d'apparence.")

    @staticmethod
    def _outil_fond():
        candidats = (["xfdesktop-settings"], ["nitrogen"],
                     ["gnome-control-center", "background"],
                     ["plasma-apply-wallpaperimage"])
        for argv in candidats:
            if execution.outil_present(argv[0]):
                return argv
        return None

    def _appliquer(self):
        self._prefs["taille_texte"] = self.taille.value()
        self._prefs["densite"] = self.densite.currentText()
        self._prefs["animations"] = self.animations.isChecked()
        if prefs.enregistrer(self._prefs):
            self._contexte.appliquer_apparence(self._prefs)
            self.statut.succes("Apparence appliquée et enregistrée.")
        else:
            self.statut.echec("Les préférences n'ont pas pu être écrites.")

    def _fond(self):
        argv = self._outil_fond()
        if not argv:
            self.statut.echec("Aucun outil de fond d'écran disponible.")
            return
        self.afficher_resultat(execution.lancer_detache(argv),
                               f"{argv[0]} lancé.")

    def _bureau(self):
        for argv in (["xfce4-appearance-settings"],
                     ["gnome-control-center", "appearance"],
                     ["systemsettings", "kcm_style"],
                     ["xfce4-settings-manager"]):
            if execution.outil_present(argv[0]):
                self.afficher_resultat(execution.lancer_detache(argv),
                                       f"{argv[0]} lancé.")
                return
        self.statut.echec(
            "Aucun panneau d'apparence natif trouvé pour ce bureau.")


# ══════════════════════════════════════════════════════════════════════
class PageAffichage(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Affichage et GPU",
            "Carte, pilote et écrans réellement détectés. LEXOS PRO "
            "n'installe aucun pilote et ne touche ni au Secure Boot, ni à "
            "GRUB, ni aux modules du noyau.", parent)
        grille = self.ajouter_grille(2)
        self.c_carte = _carte_simple("Carte graphique", "gpu")
        self.c_session = _carte_simple("Session et rendu", "affichage")
        grille.addWidget(self.c_carte, 0, 0)
        grille.addWidget(self.c_session, 0, 1)

        self.arbre = QTreeWidget()
        self.arbre.setHeaderLabels(["Élément", "Valeur"])
        self.arbre.setColumnWidth(0, 260)
        self.arbre.setMinimumHeight(240)
        self.arbre.setAlternatingRowColors(True)
        self.disposition.addWidget(widgets.titre_section("Détails"))
        self.disposition.addWidget(self.arbre, 1)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.b_ecrans = widgets.bouton("Réglages d'écran du système",
                                       "affichage", principal=True)
        self.b_ecrans.clicked.connect(self._natif)
        d.addWidget(self.b_ecrans)
        b = widgets.bouton("Relire", "maj")
        b.clicked.connect(self.rafraichir)
        d.addWidget(b); d.addStretch(1)
        self.disposition.addWidget(barre)

    def rafraichir(self):
        self.statut.occupe("Interrogation du matériel graphique…")
        widgets.en_fond(self, self._lire, self._pret,
                        lambda m: self.statut.echec(m))

    @staticmethod
    def _lire():
        return {"cartes": gpu.cartes(), "nvidia": gpu.nvidia(),
                "ecrans": gpu.ecrans(), "rendu": gpu.rendu_opengl(),
                "session": capacites.session()}

    def _pret(self, r):
        nv, cartes = r["nvidia"], r["cartes"]
        if nv["trouve"]:
            c = nv["cartes"][0]
            self.c_carte.montrer(
                c.get("name", "NVIDIA"),
                f"Pilote {c.get('driver_version', '?')}\n"
                f"Mémoire {c.get('memory.used', '?')} / "
                f"{c.get('memory.total', '?')} Mio\n"
                f"Occupation {c.get('utilization.gpu', '?')} % · "
                f"{c.get('temperature.gpu', '?')} °C")
        elif cartes["trouve"]:
            c = cartes["cartes"][0]
            self.c_carte.montrer(
                c.fournisseur or "Carte graphique",
                f"{c.description}\nPilote lié : {c.pilote}\n{nv['raison']}")
        else:
            self.c_carte.indisponible(cartes["raison"])

        s, rendu = r["session"], r["rendu"]
        if rendu["trouve"]:
            texte = ("accélération matérielle" if rendu["materiel"]
                     else "rendu LOGICIEL (pas d'accélération)")
            detail = f"{rendu['moteur']}\n{texte}"
            couleur = theme.VERT if rendu["materiel"] else theme.JAUNE
        else:
            detail = rendu["raison"]
            couleur = theme.TEXTE_SECOND
        self.c_session.montrer(s["type"].upper(), detail)
        self.c_session.valeur.setStyleSheet(
            f"color: {couleur}; font-size: 22px; font-weight: 600;")

        self.arbre.clear()
        def ajouter(cle, val):
            it = QTreeWidgetItem([cle, str(val)])
            it.setToolTip(1, str(val))
            self.arbre.addTopLevelItem(it)

        ajouter("Type de session", s["type"])
        ajouter("Bureau", s["bureau"] or "non déclaré")
        if cartes["trouve"]:
            for c in cartes["cartes"]:
                ajouter(f"Carte {c.identifiant}",
                        f"{c.description} — pilote : {c.pilote}")
        else:
            ajouter("Cartes PCI", cartes["raison"])
        if nv["trouve"]:
            for i, c in enumerate(nv["cartes"]):
                for cle, val in c.items():
                    ajouter(f"nvidia-smi [{i}] {cle}", val)
        else:
            ajouter("nvidia-smi", nv["raison"])
        e = r["ecrans"]
        if e["trouve"]:
            for ecran in e["ecrans"]:
                ajouter("Écran", ecran)
            ajouter("Source", e["source"])
            if e.get("note"):
                ajouter("Remarque", e["note"])
            self.statut.neutre(f"{len(e['ecrans'])} écran(s) détecté(s) "
                               f"par {e['source']}.")
        else:
            ajouter("Écrans", e["raison"])
            self.statut.attention(e["raison"])

    def _natif(self):
        for argv in (["xfce4-display-settings"],
                     ["gnome-control-center", "display"],
                     ["systemsettings", "kcm_kscreen"], ["arandr"]):
            if execution.outil_present(argv[0]):
                self.afficher_resultat(execution.lancer_detache(argv),
                                       f"{argv[0]} lancé.")
                return
        self.statut.echec(
            "Aucun panneau d'affichage natif trouvé (xfce4-display-settings, "
            "gnome-control-center, arandr).")


# ══════════════════════════════════════════════════════════════════════
class PageSon(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Son",
            "Volume et périphériques, quand l'intégration est fiable. "
            "Sinon, LEXOS PRO ouvre les réglages audio natifs et le dit.",
            parent)
        self.c = _carte_simple("Sortie par défaut", "son")
        boite = QWidget(); d = QVBoxLayout(boite)
        d.setContentsMargins(0, 8, 0, 0)
        l = QHBoxLayout()
        l.addWidget(QLabel("Volume :"))
        self.curseur = QSlider(Qt.Horizontal)
        self.curseur.setRange(0, 100)
        self.curseur.sliderReleased.connect(self._regler)
        l.addWidget(self.curseur, 1)
        self.pourcent = QLabel("—")
        l.addWidget(self.pourcent)
        d.addLayout(l)
        self.muet = QCheckBox("Muet")
        self.muet.clicked.connect(self._muet)
        d.addWidget(self.muet)
        self.c.corps.addWidget(boite)
        self.disposition.addWidget(self.c)

        self.liste = QTreeWidget()
        self.liste.setHeaderLabels(["Périphérique de sortie", "Détail"])
        self.liste.setColumnWidth(0, 420)
        self.liste.setMinimumHeight(200)
        self.disposition.addWidget(self.liste, 1)

        b = widgets.bouton("Ouvrir les réglages audio du système", "son",
                           principal=True)
        b.clicked.connect(lambda: self.afficher_resultat(
            son.ouvrir_reglages_natifs(), "Réglages audio ouverts."))
        self.disposition.addWidget(b)

    def rafraichir(self):
        v = son.volume()
        if v["trouve"]:
            self.curseur.setEnabled(True)
            self.muet.setEnabled(True)
            self.curseur.blockSignals(True)
            self.curseur.setValue(min(100, v["pourcent"]))
            self.curseur.blockSignals(False)
            self.pourcent.setText(f"{v['pourcent']} %")
            self.muet.setChecked(v["muet"])
            self.c.montrer(f"{v['pourcent']} %",
                           f"Contrôlé par « {v['outil']} »"
                           + (" — actuellement muet" if v["muet"] else ""))
            self.statut.neutre(f"Son géré par « {v['outil']} ».")
        else:
            self.c.indisponible(v["raison"])
            self.pourcent.setText("—")
            widgets.eteindre(self.curseur, v["raison"])
            widgets.eteindre(self.muet, v["raison"])
            self.statut.attention(v["raison"])

        p = son.peripheriques()
        self.liste.clear()
        if p["trouve"]:
            for s in p["sorties"]:
                self.liste.addTopLevelItem(
                    QTreeWidgetItem([s["nom"], s.get("detail", "")]))
        else:
            self.liste.addTopLevelItem(
                QTreeWidgetItem(["Indisponible", p["raison"]]))

    def _regler(self):
        self.afficher_resultat(son.regler_volume(self.curseur.value()),
                               f"Volume réglé à {self.curseur.value()} %.")
        self.rafraichir()

    def _muet(self):
        self.afficher_resultat(son.basculer_muet(self.muet.isChecked()),
                               "Muet activé." if self.muet.isChecked()
                               else "Son rétabli.")
        self.rafraichir()


# ══════════════════════════════════════════════════════════════════════
class PageStockage(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Stockage",
            "Volumes montés et espace occupé. Aucun formatage, aucun "
            "partitionnement, aucun montage privilégié : cette page ne "
            "fait que lire.", parent)
        self.arbre = QTreeWidget()
        self.arbre.setHeaderLabels(["Point de montage", "Système", "Utilisé",
                                    "Libre", "Total", "Occupation",
                                    "Périphérique"])
        for i, largeur in enumerate((210, 90, 100, 100, 100, 100)):
            self.arbre.setColumnWidth(i, largeur)
        self.arbre.setMinimumHeight(340)
        self.arbre.setAlternatingRowColors(True)
        self.arbre.itemDoubleClicked.connect(lambda *_: self._ouvrir())
        self.disposition.addWidget(self.arbre, 1)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.b_ouvrir = widgets.bouton(
            "Ouvrir dans le gestionnaire de fichiers", "fichiers",
            principal=True)
        self.b_ouvrir.clicked.connect(self._ouvrir)
        d.addWidget(self.b_ouvrir)
        self.tout = QCheckBox("Afficher aussi les systèmes virtuels")
        self.tout.stateChanged.connect(lambda _: self.rafraichir())
        d.addWidget(self.tout)
        b = widgets.bouton("Relire", "maj")
        b.clicked.connect(self.rafraichir)
        d.addWidget(b); d.addStretch(1)
        self.disposition.addWidget(barre)

    def rafraichir(self):
        self.arbre.clear()
        liste = disques.volumes(tout=self.tout.isChecked())
        for v in liste:
            if v.mesure:
                item = QTreeWidgetItem([
                    v.point, v.systeme,
                    systeme.octets_lisibles(v.utilise),
                    systeme.octets_lisibles(v.libre),
                    systeme.octets_lisibles(v.total),
                    f"{v.pourcent:.0f} %", v.peripherique])
                if v.pourcent >= 90:
                    item.setForeground(5, QColor(theme.ROUGE))
                elif v.pourcent >= 75:
                    item.setForeground(5, QColor(theme.JAUNE))
            else:
                item = QTreeWidgetItem([v.point, v.systeme, "Indisponible",
                                        "—", "—", "—", v.peripherique])
                item.setToolTip(2, v.raison)
            if v.lecture_seule:
                item.setToolTip(0, f"{v.point} — monté en lecture seule")
            item.setData(0, _ROLE, v)
            for c in (2, 3, 4, 5):
                item.setTextAlignment(c, Qt.AlignRight | Qt.AlignVCenter)
            self.arbre.addTopLevelItem(item)
        self.statut.neutre(f"{len(liste)} volume(s) monté(s).")

    def _ouvrir(self):
        item = self.arbre.currentItem()
        if not item:
            self.statut.attention("Sélectionnez d'abord un volume.")
            return
        v = item.data(0, _ROLE)
        from ....services import fichiers as sf
        self.afficher_resultat(sf.ouvrir(v.point),
                               f"{v.point} ouvert dans le gestionnaire.")


# ══════════════════════════════════════════════════════════════════════
class PageApplications(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Applications",
            "Les lanceurs installés sur ce système. Pour installer ou "
            "retirer un logiciel, LEXOS PRO ouvre la logithèque native : "
            "il ne gère pas les paquets lui-même.", parent)
        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.filtre = QLineEdit()
        self.filtre.setPlaceholderText("Rechercher une application…")
        self.filtre.textChanged.connect(self._remplir)
        d.addWidget(self.filtre, 1)
        b = widgets.bouton("Lancer", "applications", principal=True)
        b.clicked.connect(self._lancer)
        d.addWidget(b)
        self.b_logi = widgets.bouton("Ouvrir la logithèque", "maj")
        self.b_logi.clicked.connect(
            lambda: self.afficher_resultat(applications.ouvrir_logitheque(),
                                           "Logithèque ouverte."))
        d.addWidget(self.b_logi)
        self.disposition.addWidget(barre)

        self.arbre = QTreeWidget()
        self.arbre.setHeaderLabels(["Application", "Description", "Catégories"])
        self.arbre.setColumnWidth(0, 250)
        self.arbre.setColumnWidth(1, 380)
        self.arbre.setMinimumHeight(380)
        self.arbre.setAlternatingRowColors(True)
        self.arbre.itemDoubleClicked.connect(lambda *_: self._lancer())
        self.disposition.addWidget(self.arbre, 1)
        self._tous = []

    def rafraichir(self):
        self._tous = applications.lanceurs()
        self._remplir()
        logi = capacites.premier_present(capacites.LOGITHEQUES)
        if logi:
            self.b_logi.setEnabled(True)
            self.b_logi.setToolTip(f"Ouvrira « {logi} ».")
        else:
            widgets.eteindre(
                self.b_logi,
                "Aucune logithèque graphique installée (gnome-software, "
                "plasma-discover, mintinstall…).")

    def _remplir(self):
        motif = self.filtre.text().strip().lower()
        self.arbre.clear()
        n = 0
        for l in self._tous:
            if motif and motif not in l.nom.lower() \
                    and motif not in l.commentaire.lower():
                continue
            item = QTreeWidgetItem([l.nom, l.commentaire, l.categories])
            item.setData(0, _ROLE, l)
            item.setToolTip(0, l.fichier)
            self.arbre.addTopLevelItem(item)
            n += 1
        self.statut.neutre(f"{n} application(s) sur {len(self._tous)}.")

    def _lancer(self):
        item = self.arbre.currentItem()
        if not item:
            self.statut.attention("Sélectionnez d'abord une application.")
            return
        l = item.data(0, _ROLE)
        self.afficher_resultat(applications.lancer(l), f"« {l.nom} » lancé.")


# ══════════════════════════════════════════════════════════════════════
class PageServices(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Services",
            "Services systemd. Ceux de votre SESSION peuvent être démarrés, "
            "arrêtés ou redémarrés ; ceux du SYSTÈME restent en lecture "
            "seule tant qu'aucune règle PolicyKit ciblée n'est en place.",
            parent)
        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.portee = QComboBox()
        self.portee.addItems(["Services système (lecture seule)",
                              "Services utilisateur"])
        self.portee.currentIndexChanged.connect(lambda _: self.rafraichir())
        d.addWidget(self.portee)
        self.filtre = QLineEdit()
        self.filtre.setPlaceholderText("Filtrer…")
        self.filtre.textChanged.connect(self._remplir)
        d.addWidget(self.filtre, 1)
        self.boutons = {}
        for action, libelle in (("start", "Démarrer"), ("stop", "Arrêter"),
                                ("restart", "Redémarrer")):
            b = widgets.bouton(libelle, "services")
            b.clicked.connect(lambda _=False, a=action: self._agir(a))
            d.addWidget(b)
            self.boutons[action] = b
        b_j = widgets.bouton("Voir le journal", "apropos")
        b_j.clicked.connect(self._journal)
        d.addWidget(b_j)
        self.disposition.addWidget(barre)

        self.arbre = QTreeWidget()
        self.arbre.setHeaderLabels(["Service", "Chargement", "Actif", "État",
                                    "Description"])
        self.arbre.setColumnWidth(0, 260)
        self.arbre.setColumnWidth(1, 100)
        self.arbre.setColumnWidth(2, 90)
        self.arbre.setColumnWidth(3, 100)
        self.arbre.setMinimumHeight(300)
        self.arbre.setAlternatingRowColors(True)
        self.disposition.addWidget(self.arbre, 1)

        self.journal = QPlainTextEdit()
        self.journal.setReadOnly(True)
        self.journal.setMinimumHeight(170)
        self.journal.setPlaceholderText(
            "Sélectionnez un service puis « Voir le journal ».")
        self.disposition.addWidget(self.journal)
        self._unites = []

    def _portee(self):
        return "user" if self.portee.currentIndex() == 1 else "system"

    def rafraichir(self):
        self.statut.occupe("Lecture des services…")
        portee = self._portee()
        widgets.en_fond(self, unites.utilisateur if portee == "user"
                        else unites.systeme, self._pret,
                        lambda m: self.statut.echec(m))

    def _pret(self, r):
        if not r["trouve"]:
            self._unites = []
            self.arbre.clear()
            self.arbre.addTopLevelItem(
                QTreeWidgetItem(["Indisponible", "—", "—", "—", r["raison"]]))
            for b in self.boutons.values():
                widgets.eteindre(b, r["raison"])
            self.statut.attention(r["raison"])
            return
        self._unites = r["unites"]
        self._remplir()
        if self._portee() == "user":
            for b in self.boutons.values():
                b.setEnabled(True)
                b.setToolTip("Action sur un service de votre session.")
            self.statut.neutre(f"{len(self._unites)} service(s) utilisateur.")
        else:
            from ....services.unites import Unite, action_permise
            _, raison = action_permise(Unite("x", portee="system"))
            for b in self.boutons.values():
                widgets.eteindre(b, raison)
            self.statut.neutre(
                f"{len(self._unites)} service(s) système — lecture seule.")

    def _remplir(self):
        motif = self.filtre.text().strip().lower()
        self.arbre.clear()
        n = 0
        for u in self._unites:
            if motif and motif not in u.nom.lower() \
                    and motif not in u.description.lower():
                continue
            item = QTreeWidgetItem([u.nom, u.charge, u.actif, u.sous_etat,
                                    u.description])
            item.setData(0, _ROLE, u)
            if u.actif == "active":
                item.setForeground(2, QColor(theme.VERT))
            elif u.actif == "failed":
                item.setForeground(2, QColor(theme.ROUGE))
            self.arbre.addTopLevelItem(item)
            n += 1
        if motif:
            self.statut.neutre(f"{n} service(s) filtré(s).")

    def _choisi(self):
        item = self.arbre.currentItem()
        return item.data(0, _ROLE) if item else None

    def _agir(self, action):
        u = self._choisi()
        if not u:
            self.statut.attention("Sélectionnez d'abord un service.")
            return
        libelle = {"start": "démarrer", "stop": "arrêter",
                   "restart": "redémarrer"}[action]
        if QMessageBox.question(
                self, "Confirmer",
                f"Voulez-vous {libelle} « {u.nom} » ?\n\n"
                f"Ce service appartient à votre session.",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No) != QMessageBox.Yes:
            return
        self.afficher_resultat(unites.agir(u, action))
        self.rafraichir()

    def _journal(self):
        u = self._choisi()
        if not u:
            self.statut.attention("Sélectionnez d'abord un service.")
            return
        self.statut.occupe(f"Lecture du journal de {u.nom}…")
        widgets.en_fond(
            self, unites.journal,
            lambda r: self.journal.setPlainText(
                r["texte"] if r.get("trouve")
                else "Indisponible — " + r["raison"]),
            lambda m: self.statut.echec(m), u.nom, u.portee)


# ══════════════════════════════════════════════════════════════════════
class PageMaj(widgets.Page):
    def __init__(self, contexte, parent=None):
        super().__init__(
            "Mises à jour",
            "Ce que le cache LOCAL sait, et depuis quand. LEXOS PRO ne "
            "lance ni mise à niveau, ni suppression de paquets, ni "
            "redémarrage : il ouvre l'outil natif.", parent)
        self.c = _carte_simple("Mécanisme détecté", "maj")
        self.disposition.addWidget(self.c)

        self.liste = QTreeWidget()
        self.liste.setHeaderLabels(["Paquets pouvant être mis à jour"])
        self.liste.setMinimumHeight(280)
        self.liste.setAlternatingRowColors(True)
        self.disposition.addWidget(self.liste, 1)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.b_natif = widgets.bouton("Ouvrir le gestionnaire de mises à jour",
                                      "maj", principal=True)
        self.b_natif.clicked.connect(
            lambda: self.afficher_resultat(maj.ouvrir_outil_natif(),
                                           "Outil de mise à jour ouvert."))
        d.addWidget(self.b_natif)
        b = widgets.bouton("Relire le cache local", "recherche")
        b.clicked.connect(self.rafraichir)
        d.addWidget(b); d.addStretch(1)
        self.disposition.addWidget(barre)

    def rafraichir(self):
        m = maj.mecanisme()
        if not m["trouve"]:
            self.c.indisponible(m["raison"])
        self.statut.occupe("Lecture du cache local des paquets…")
        widgets.en_fond(self, maj.etat_local, self._pret,
                        lambda x: self.statut.echec(x))

    def _pret(self, r):
        m = maj.mecanisme()
        self.liste.clear()
        if not r["trouve"]:
            self.c.indisponible(r["raison"])
            self.liste.addTopLevelItem(
                QTreeWidgetItem(["Indisponible — " + r["raison"]]))
            self.statut.attention(r["raison"])
        else:
            age = r.get("age", {})
            quand = (maj.age_lisible(age.get("secondes"))
                     if age.get("trouve") else "date inconnue")
            self.c.montrer(
                f"{r['nombre']} mise(s) à jour en attente",
                f"{m.get('note', '')}\n"
                f"Source : cache LOCAL, dernière actualisation {quand}.\n"
                f"Ce n'est PAS une vérification en direct : le cache peut "
                f"dater. Ouvrez l'outil natif pour interroger les dépôts.")
            for p in r["paquets"]:
                self.liste.addTopLevelItem(QTreeWidgetItem([p]))
            self.statut.neutre(
                f"{r['nombre']} paquet(s) d'après le cache local "
                f"({quand}).")
        outil = next((o for o in maj.OUTILS_NATIFS
                      if execution.outil_present(o)), "")
        if outil:
            self.b_natif.setEnabled(True)
            self.b_natif.setToolTip(f"Ouvrira « {outil} ».")
        else:
            widgets.eteindre(
                self.b_natif,
                "Aucun outil graphique de mise à jour n'est installé "
                "(update-manager, gnome-software, plasma-discover…).")
