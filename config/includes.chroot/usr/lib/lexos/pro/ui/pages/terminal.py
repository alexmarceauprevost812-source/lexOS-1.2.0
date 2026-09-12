"""Terminal — on ouvre le VRAI, on n'en imite pas un.

L'interface le dit à l'écran, pas seulement dans le code : c'est la
consigne, et c'est honnête envers quelqu'un qui s'attendrait à taper ici.
"""
from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import (QComboBox, QFileDialog, QHBoxLayout, QLabel,
                               QLineEdit, QVBoxLayout, QWidget)

from ...services import terminal as svc
from .. import theme, widgets


class PageTerminal(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "Terminal",
            "LEXOS PRO ouvre l'émulateur de terminal installé sur le "
            "système, dans le dossier de votre choix. Il n'imite pas un "
            "terminal dans une zone de texte : un faux terminal ne gère ni "
            "les couleurs, ni Ctrl-C, ni un éditeur plein écran.", parent)

        carte = widgets.Carte("Ouvrir un terminal", "terminal")
        carte.valeur.hide()
        carte.jauge.hide()
        carte.courbe.hide()
        boite = QWidget()
        d = QVBoxLayout(boite)
        d.setContentsMargins(0, 6, 0, 0)
        d.setSpacing(9)

        ligne = QHBoxLayout()
        ligne.addWidget(QLabel("Dossier :"))
        self.champ = QLineEdit(str(Path.home()))
        self.champ.setToolTip("Le terminal s'ouvrira dans ce dossier.")
        ligne.addWidget(self.champ, 1)
        parcourir = widgets.bouton("Parcourir…", "fichiers")
        parcourir.clicked.connect(self._parcourir)
        ligne.addWidget(parcourir)
        d.addLayout(ligne)

        ligne2 = QHBoxLayout()
        ligne2.addWidget(QLabel("Émulateur :"))
        self.choix = QComboBox()
        ligne2.addWidget(self.choix, 1)
        d.addLayout(ligne2)

        actions = QHBoxLayout()
        self.b_ouvrir = widgets.bouton("Ouvrir le terminal", "terminal",
                                       principal=True)
        self.b_ouvrir.clicked.connect(self._ouvrir)
        actions.addWidget(self.b_ouvrir)
        self.b_tilex = widgets.bouton("Lancer TI-LEX", "developpement")
        self.b_tilex.clicked.connect(self._tilex)
        actions.addWidget(self.b_tilex)
        actions.addStretch(1)
        d.addLayout(actions)
        carte.corps.addWidget(boite)
        self.disposition.addWidget(carte)

        self.info = widgets.Carte("Ce que LEXOS PRO a trouvé", "recherche")
        self.info.valeur.hide()
        self.info.jauge.hide()
        self.info.courbe.hide()
        self.disposition.addWidget(self.info)
        self.disposition.addStretch(1)

    def rafraichir(self):
        dispo = svc.terminaux_disponibles()
        courant = self.choix.currentText()
        self.choix.clear()
        self.choix.addItems(dispo)
        if courant in dispo:
            self.choix.setCurrentText(courant)
        t = svc.ti_lex()
        if t["trouve"]:
            self.b_tilex.setEnabled(True)
            self.b_tilex.setToolTip(f"Lance « {t['commande']} ».")
        else:
            widgets.eteindre(self.b_tilex, t["raison"])
        if dispo:
            self.b_ouvrir.setEnabled(True)
            self.info.detail.setText(
                "Émulateurs détectés : " + ", ".join(dispo) + "\n"
                + ("TI-LEX : " + t["commande"] if t["trouve"]
                   else "TI-LEX : " + t["raison"]))
            self.statut.neutre("Prêt.")
        else:
            widgets.eteindre(
                self.b_ouvrir,
                "Aucun émulateur de terminal n'est installé sur ce système.")
            self.info.detail.setText(
                "Aucun émulateur de terminal trouvé parmi : "
                + ", ".join(svc.capacites.TERMINAUX))
            self.statut.attention(
                "Aucun terminal installé. Installez par exemple "
                "xfce4-terminal ou gnome-terminal.")

    def _parcourir(self):
        d = QFileDialog.getExistingDirectory(self, "Choisir un dossier",
                                             self.champ.text())
        if d:
            self.champ.setText(d)

    def _ouvrir(self):
        r = svc.ouvrir(self.champ.text(), self.choix.currentText())
        self.afficher_resultat(
            r, f"Terminal ouvert dans {self.champ.text()}.")

    def _tilex(self):
        self.afficher_resultat(svc.lancer_ti_lex(self.champ.text()),
                               "TI-LEX lancé.")
