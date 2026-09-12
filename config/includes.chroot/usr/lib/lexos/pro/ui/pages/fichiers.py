"""Fichiers — navigation et opérations, SANS suppression définitive.

Tout ce qui « supprime » va à la corbeille, après confirmation. Les
conflits de noms sont signalés et laissent le choix — jamais d'écrasement
silencieux. Les refus de droits s'affichent tels quels.
"""
from __future__ import annotations

import time
from pathlib import Path

from PySide6.QtCore import QSize, Qt
from PySide6.QtWidgets import (QAbstractItemView, QFileDialog, QHBoxLayout,
                               QInputDialog, QLineEdit, QListWidget,
                               QListWidgetItem, QMessageBox, QTreeWidget,
                               QTreeWidgetItem, QStackedWidget, QVBoxLayout,
                               QWidget)

from ...services import fichiers as svc
from ...services import prefs, systeme
from .. import theme, widgets

_ROLE = 256


class PageFichiers(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "Fichiers",
            "Navigation dans vos dossiers. La suppression définitive n'est "
            "pas proposée : tout passe par la corbeille, d'où l'on peut "
            "revenir.", parent)
        self._prefs = prefs.charger()
        self._dossier = Path(self._prefs.get("dernier_dossier") or Path.home())
        if not self._dossier.is_dir():
            self._dossier = Path.home()
        self._historique = []
        self._presse_papier = None

        # -- barre de navigation ----------------------------------------
        barre = QWidget()
        d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.b_retour = widgets.bouton("", "retour", infobulle="Dossier précédent")
        self.b_retour.clicked.connect(self._retour)
        d.addWidget(self.b_retour)
        b_haut = widgets.bouton("Dossier parent", "fichiers")
        b_haut.clicked.connect(self._parent)
        d.addWidget(b_haut)
        self.chemin = QLineEdit(str(self._dossier))
        self.chemin.setToolTip("Chemin courant — modifiable, Entrée pour y aller.")
        self.chemin.returnPressed.connect(self._aller_saisi)
        d.addWidget(self.chemin, 1)
        self.recherche = QLineEdit()
        self.recherche.setPlaceholderText("Rechercher dans ce dossier…")
        self.recherche.setMaximumWidth(260)
        self.recherche.textChanged.connect(self._filtrer)
        d.addWidget(self.recherche)
        self.b_vue = widgets.bouton("Vue icônes", "applications",
                                    infobulle="Basculer liste / icônes")
        self.b_vue.clicked.connect(self._basculer_vue)
        d.addWidget(self.b_vue)
        self.disposition.addWidget(barre)

        # -- raccourcis vers les dossiers usuels ------------------------
        self.usuels = QWidget()
        self._d_usuels = QHBoxLayout(self.usuels)
        self._d_usuels.setContentsMargins(0, 0, 0, 0)
        self.disposition.addWidget(self.usuels)

        # -- deux vues, une seule source de données ---------------------
        self.pile = QStackedWidget()
        self.vue_liste = QTreeWidget()
        self.vue_liste.setHeaderLabels(["Nom", "Taille", "Modifié"])
        self.vue_liste.setColumnWidth(0, 380)
        self.vue_liste.setAlternatingRowColors(True)
        self.vue_liste.setSelectionMode(QAbstractItemView.SingleSelection)
        self.vue_liste.itemDoubleClicked.connect(self._activer_liste)
        self.pile.addWidget(self.vue_liste)

        self.vue_icones = QListWidget()
        self.vue_icones.setViewMode(QListWidget.IconMode)
        self.vue_icones.setIconSize(QSize(48, 48))
        self.vue_icones.setResizeMode(QListWidget.Adjust)
        self.vue_icones.setSpacing(10)
        self.vue_icones.setMovement(QListWidget.Static)
        self.vue_icones.itemDoubleClicked.connect(self._activer_icone)
        self.pile.addWidget(self.vue_icones)
        self.pile.setMinimumHeight(300)
        self.disposition.addWidget(self.pile, 1)

        # -- actions -----------------------------------------------------
        actions = QWidget()
        da = QHBoxLayout(actions)
        da.setContentsMargins(0, 0, 0, 0)
        for libelle, fonction, ic in (
                ("Ouvrir", self._ouvrir, "fichiers"),
                ("Nouveau dossier", self._nouveau, "applications"),
                ("Renommer", self._renommer, "apropos"),
                ("Copier", self._copier, "stockage"),
                ("Couper", self._couper, "stockage"),
                ("Coller ici", self._coller, "stockage"),
                ("Propriétés", self._proprietes, "systeme"),
                ("Mettre à la corbeille", self._corbeille, "securite")):
            b = widgets.bouton(libelle, ic)
            b.clicked.connect(fonction)
            da.addWidget(b)
            if libelle == "Coller ici":
                self.b_coller = b
        da.addStretch(1)
        self.disposition.addWidget(actions)
        widgets.eteindre(self.b_coller, "Rien n'a encore été copié ou coupé.")

    # ══ navigation ════════════════════════════════════════════════════
    def rafraichir(self):
        self.chemin.setText(str(self._dossier))
        self.b_retour.setEnabled(bool(self._historique))
        self._peupler_usuels()
        r = svc.lister(self._dossier)
        self.vue_liste.clear()
        self.vue_icones.clear()
        if not r["ok"]:
            self.statut.echec(r["raison"])
            return
        self._entrees = r["entrees"]
        self._remplir(self._entrees)
        self.statut.neutre(f"{len(self._entrees)} élément(s) dans "
                           f"{self._dossier}.")

    def _remplir(self, entrees):
        self.vue_liste.clear()
        self.vue_icones.clear()
        for e in entrees:
            taille = "—" if e.dossier else systeme.octets_lisibles(e.taille)
            quand = (time.strftime("%d/%m/%Y %H:%M", time.localtime(e.modifie))
                     if e.modifie else "—")
            item = QTreeWidgetItem([e.nom, taille, quand])
            item.setIcon(0, theme.icone("fichiers" if e.dossier else "apropos",
                                        theme.ORANGE if e.dossier
                                        else theme.TEXTE_SECOND, 18))
            item.setData(0, _ROLE, e)
            if not e.lisible:
                item.setToolTip(0, "Élément illisible (droits insuffisants).")
            self.vue_liste.addTopLevelItem(item)

            ic = QListWidgetItem(theme.icone(
                "fichiers" if e.dossier else "apropos",
                theme.ORANGE if e.dossier else theme.TEXTE_SECOND, 42), e.nom)
            ic.setData(_ROLE, e)
            ic.setTextAlignment(Qt.AlignHCenter | Qt.AlignTop)
            self.vue_icones.addItem(ic)

    def _peupler_usuels(self):
        while self._d_usuels.count():
            w = self._d_usuels.takeAt(0).widget()
            if w:
                w.deleteLater()
        for u in svc.dossiers_usuels():
            b = widgets.bouton(u["nom"], "fichiers", infobulle=u["chemin"])
            b.clicked.connect(lambda _=False, c=u["chemin"]: self._aller(c))
            self._d_usuels.addWidget(b)
        self._d_usuels.addStretch(1)

    def _aller(self, chemin):
        chemin = Path(chemin)
        if not chemin.is_dir():
            self.statut.echec(f"{chemin} n'est pas un dossier accessible.")
            return
        self._historique.append(self._dossier)
        self._dossier = chemin
        self._prefs["dernier_dossier"] = str(chemin)
        prefs.enregistrer(self._prefs)
        self.recherche.clear()
        self.rafraichir()

    def _aller_saisi(self):
        self._aller(self.chemin.text().strip())

    def _retour(self):
        if self._historique:
            self._dossier = self._historique.pop()
            self.recherche.clear()
            self.rafraichir()

    def _parent(self):
        p = self._dossier.parent
        if p != self._dossier:
            self._aller(p)
        else:
            self.statut.neutre("Vous êtes à la racine du système de fichiers.")

    def _filtrer(self, texte):
        texte = texte.strip().lower()
        if not hasattr(self, "_entrees"):
            return
        if not texte:
            self._remplir(self._entrees)
            return
        gardes = [e for e in self._entrees if texte in e.nom.lower()]
        self._remplir(gardes)
        self.statut.neutre(f"{len(gardes)} résultat(s) pour « {texte} » "
                           f"dans ce dossier.")

    def _basculer_vue(self):
        nouvelle = 1 - self.pile.currentIndex()
        self.pile.setCurrentIndex(nouvelle)
        self.b_vue.setText("Vue liste" if nouvelle else "Vue icônes")

    # ══ sélection ═════════════════════════════════════════════════════
    def _selection(self):
        if self.pile.currentIndex() == 0:
            item = self.vue_liste.currentItem()
            return item.data(0, _ROLE) if item else None
        item = self.vue_icones.currentItem()
        return item.data(_ROLE) if item else None

    def _activer_liste(self, item, _col=0):
        self._activer(item.data(0, _ROLE))

    def _activer_icone(self, item):
        self._activer(item.data(_ROLE))

    def _activer(self, e):
        if e is None:
            return
        if e.dossier:
            self._aller(e.chemin)
        else:
            self.afficher_resultat(svc.ouvrir(e.chemin), f"{e.nom} ouvert.")

    # ══ actions ═══════════════════════════════════════════════════════
    def _exige_selection(self):
        e = self._selection()
        if e is None:
            self.statut.attention("Sélectionnez d'abord un élément.")
        return e

    def _ouvrir(self):
        e = self._exige_selection()
        if e:
            self._activer(e)

    def _nouveau(self):
        nom, ok = QInputDialog.getText(self, "Nouveau dossier",
                                       "Nom du dossier :")
        if not ok:
            return
        self.afficher_resultat(svc.creer_dossier(self._dossier, nom),
                               f"Dossier « {nom} » créé.")
        self.rafraichir()

    def _renommer(self):
        e = self._exige_selection()
        if not e:
            return
        nom, ok = QInputDialog.getText(self, "Renommer", "Nouveau nom :",
                                       QLineEdit.Normal, e.nom)
        if not ok:
            return
        self.afficher_resultat(svc.renommer(e.chemin, nom),
                               f"« {e.nom} » renommé en « {nom} ».")
        self.rafraichir()

    def _copier(self):
        e = self._exige_selection()
        if e:
            self._presse_papier = ("copier", e)
            self.b_coller.setEnabled(True)
            self.b_coller.setToolTip(f"Collera une copie de {e.nom} ici.")
            self.statut.neutre(f"« {e.nom} » prêt à être copié.")

    def _couper(self):
        e = self._exige_selection()
        if e:
            self._presse_papier = ("deplacer", e)
            self.b_coller.setEnabled(True)
            self.b_coller.setToolTip(f"Déplacera {e.nom} ici.")
            self.statut.neutre(f"« {e.nom} » prêt à être déplacé.")

    def _coller(self):
        if not self._presse_papier:
            self.statut.attention("Rien à coller.")
            return
        action, e = self._presse_papier
        fonction = svc.copier if action == "copier" else svc.deplacer
        r = fonction(e.chemin, self._dossier)
        if not r.ok and "existe déjà" in r.erreur:
            #  CONFLIT DE NOM : on demande, on n'écrase jamais tout seul.
            reponse = QMessageBox.question(
                self, "Le nom existe déjà",
                f"{r.erreur}\n\nRemplacer l'élément existant ?",
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            if reponse != QMessageBox.Yes:
                self.statut.neutre("Opération annulée : rien n'a été remplacé.")
                return
            r = fonction(e.chemin, self._dossier, remplacer=True)
        if self.afficher_resultat(
                r, f"« {e.nom} » "
                   f"{'copié' if action == 'copier' else 'déplacé'} ici."):
            if action == "deplacer":
                self._presse_papier = None
                widgets.eteindre(self.b_coller, "Rien n'a été copié ou coupé.")
        self.rafraichir()

    def _proprietes(self):
        e = self._exige_selection()
        if not e:
            return
        p = svc.proprietes(e.chemin)
        if not p["ok"]:
            self.statut.echec(p["raison"])
            return
        QMessageBox.information(
            self, "Propriétés",
            f"Nom : {p['nom']}\nType : {p['type']}\nChemin : {p['chemin']}\n"
            f"Taille : {systeme.octets_lisibles(p['taille'])}\n"
            f"Modifié : {time.strftime('%d/%m/%Y %H:%M', time.localtime(p['modifie']))}\n"
            f"Droits : {p['droits']}\n"
            f"Propriétaire : {p['proprietaire']} · groupe {p['groupe']}\n"
            f"Écriture autorisée : {'oui' if p['accessible_ecriture'] else 'non'}")

    def _corbeille(self):
        e = self._exige_selection()
        if not e:
            return
        if QMessageBox.question(
                self, "Mettre à la corbeille",
                f"Mettre « {e.nom} » à la corbeille ?\n\n"
                f"L'élément restera récupérable depuis la corbeille du "
                f"bureau. LEXOS PRO ne supprime jamais définitivement.",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No) != QMessageBox.Yes:
            return
        self.afficher_resultat(svc.a_la_corbeille(e.chemin),
                               f"« {e.nom} » mis à la corbeille.")
        self.rafraichir()
