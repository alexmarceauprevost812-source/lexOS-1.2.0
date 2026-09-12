"""Navigateur — lancement d'adresses validées et favoris locaux.

L'adresse est VALIDÉE avant de partir (services/navigateur.py), et elle
part comme un élément d'argv. Elle n'est jamais interprétée par un shell.
"""
from __future__ import annotations

from PySide6.QtWidgets import (QAbstractItemView, QHBoxLayout, QInputDialog,
                               QLineEdit, QListWidget, QListWidgetItem,
                               QMessageBox, QVBoxLayout, QWidget)

from ...services import navigateur as svc
from ...services import prefs
from .. import widgets


class PageNavigateur(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "Navigateur",
            "Ouvre une adresse dans le navigateur par défaut du système. "
            "Seuls http et https sont acceptés ; les favoris sont "
            "enregistrés dans votre dossier de configuration.", parent)
        self._prefs = prefs.charger()

        carte = widgets.Carte("Adresse", "navigateur")
        carte.valeur.hide(); carte.jauge.hide(); carte.courbe.hide()
        boite = QWidget(); d = QVBoxLayout(boite)
        d.setContentsMargins(0, 6, 0, 0)
        ligne = QHBoxLayout()
        self.champ = QLineEdit()
        self.champ.setPlaceholderText("exemple.fr  ou  https://exemple.fr/page")
        self.champ.returnPressed.connect(self._ouvrir)
        ligne.addWidget(self.champ, 1)
        b = widgets.bouton("Ouvrir", "navigateur", principal=True)
        b.clicked.connect(self._ouvrir)
        ligne.addWidget(b)
        ba = widgets.bouton("Ajouter aux favoris", "apropos")
        ba.clicked.connect(self._ajouter)
        ligne.addWidget(ba)
        d.addLayout(ligne)
        carte.corps.addWidget(boite)
        self.disposition.addWidget(carte)

        f = widgets.Carte("Favoris", "apropos")
        f.valeur.hide(); f.jauge.hide(); f.courbe.hide()
        f.detail.setText("Double-cliquez pour ouvrir.")
        self.liste = QListWidget()
        self.liste.setSelectionMode(QAbstractItemView.SingleSelection)
        self.liste.itemDoubleClicked.connect(self._ouvrir_favori)
        self.liste.setMinimumHeight(180)
        f.corps.addWidget(self.liste)
        actions = QWidget(); da = QHBoxLayout(actions)
        da.setContentsMargins(0, 6, 0, 0)
        for libelle, fonction in (("Ouvrir", self._ouvrir_favori),
                                  ("Renommer", self._renommer),
                                  ("Retirer", self._retirer)):
            bb = widgets.bouton(libelle)
            bb.clicked.connect(fonction)
            da.addWidget(bb)
        da.addStretch(1)
        f.corps.addWidget(actions)
        self.disposition.addWidget(f)
        self.disposition.addStretch(1)

    def rafraichir(self):
        d = svc.navigateur_par_defaut()
        self.description.setText(
            self.description.text().split("\n")[0]
            if False else
            ("Navigateur par défaut : " + d["nom"] if d["trouve"]
             else "Navigateur par défaut : indisponible — " + d["raison"])
            + "  ·  Seuls http et https sont acceptés.")
        self.liste.clear()
        for fav in self._prefs.get("favoris", []):
            item = QListWidgetItem(f"{fav['nom']}  —  {fav['url']}")
            item.setData(256, fav)
            self.liste.addItem(item)

    def _enregistrer(self):
        if not prefs.enregistrer(self._prefs):
            self.statut.echec(
                "Les favoris n'ont pas pu être écrits dans votre dossier de "
                "configuration (droits ou disque plein).")
            return False
        return True

    def _ouvrir(self):
        v = svc.normaliser(self.champ.text())
        if not v["ok"]:
            self.statut.echec(v["raison"])
            return
        self.afficher_resultat(svc.ouvrir(self.champ.text()),
                               f"Ouverture de {v['url']}.")

    def _favori_choisi(self):
        item = self.liste.currentItem()
        return item.data(256) if item else None

    def _ouvrir_favori(self, *_):
        fav = self._favori_choisi()
        if not fav:
            self.statut.attention("Aucun favori sélectionné.")
            return
        self.afficher_resultat(svc.ouvrir(fav["url"]),
                               f"Ouverture de {fav['url']}.")

    def _ajouter(self):
        v = svc.normaliser(self.champ.text())
        if not v["ok"]:
            self.statut.echec(v["raison"])
            return
        nom, ok = QInputDialog.getText(self, "Nom du favori",
                                       "Sous quel nom l'enregistrer ?",
                                       QLineEdit.Normal, v["url"])
        if not ok or not nom.strip():
            return
        self._prefs.setdefault("favoris", []).append(
            {"nom": nom.strip(), "url": v["url"]})
        if self._enregistrer():
            self.statut.succes(f"Favori « {nom.strip()} » ajouté.")
        self.rafraichir()

    def _renommer(self):
        fav = self._favori_choisi()
        if not fav:
            self.statut.attention("Aucun favori sélectionné.")
            return
        nom, ok = QInputDialog.getText(self, "Renommer", "Nouveau nom :",
                                       QLineEdit.Normal, fav["nom"])
        if not ok or not nom.strip():
            return
        for f in self._prefs["favoris"]:
            if f == fav:
                f["nom"] = nom.strip()
                break
        if self._enregistrer():
            self.statut.succes("Favori renommé.")
        self.rafraichir()

    def _retirer(self):
        fav = self._favori_choisi()
        if not fav:
            self.statut.attention("Aucun favori sélectionné.")
            return
        if QMessageBox.question(
                self, "Retirer le favori",
                f"Retirer « {fav['nom']} » de vos favoris ?") \
                != QMessageBox.Yes:
            return
        self._prefs["favoris"] = [f for f in self._prefs["favoris"] if f != fav]
        if self._enregistrer():
            self.statut.succes("Favori retiré.")
        self.rafraichir()
