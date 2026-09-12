"""Paramètres — un sous-menu vertical, comme sur la maquette.

La forme est volontairement celle du menu principal : liste verticale,
icône + libellé, accent orange sur l'élément choisi. C'est ce qu'Alex a
demandé, et ça a un mérite au-delà du goût : on apprend UNE façon de
naviguer, et elle vaut aux deux niveaux.
"""
from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (QButtonGroup, QFrame, QHBoxLayout,
                               QPushButton, QStackedWidget, QVBoxLayout,
                               QWidget)

from ... import theme
from . import pages as sous

#  (clé, libellé, icône, classe)
SECTIONS = (
    ("systeme", "Système", "systeme", sous.PageSysteme),
    ("performances", "Performances", "performances", sous.PagePerformances),
    ("reseau", "Réseau", "reseau", sous.PageReseau),
    ("apparence", "Apparence", "apparence", sous.PageApparence),
    ("affichage", "Affichage et GPU", "affichage", sous.PageAffichage),
    ("son", "Son", "son", sous.PageSon),
    ("stockage", "Stockage", "stockage", sous.PageStockage),
    ("applications", "Applications", "applications", sous.PageApplications),
    ("services", "Services", "services", sous.PageServices),
    ("maj", "Mises à jour", "maj", sous.PageMaj),
)


class PageParametres(QWidget):
    """Conteneur : sous-menu à gauche, page choisie à droite."""

    def __init__(self, contexte, parent=None):
        super().__init__(parent)
        racine = QHBoxLayout(self)
        racine.setContentsMargins(22, 20, 22, 18)
        racine.setSpacing(16)

        menu = QFrame()
        menu.setObjectName("SousMenu")
        menu.setFixedWidth(212)
        dm = QVBoxLayout(menu)
        dm.setContentsMargins(8, 12, 8, 12)
        dm.setSpacing(3)

        self.groupe = QButtonGroup(self)
        self.groupe.setExclusive(True)
        self.pile = QStackedWidget()
        self._pages = {}
        self._cles = []

        for index, (cle, libelle, ic, classe) in enumerate(SECTIONS):
            b = QPushButton(libelle)
            b.setCheckable(True)
            b.setCursor(Qt.PointingHandCursor)
            b.setIcon(theme.icone(ic, theme.TEXTE_SECOND, 18))
            b.setToolTip(libelle)
            b.clicked.connect(lambda _=False, i=index: self.aller(i))
            self.groupe.addButton(b, index)
            dm.addWidget(b)
            page = classe(contexte)
            self._pages[cle] = page
            self._cles.append(cle)
            self.pile.addWidget(page)
        dm.addStretch(1)

        racine.addWidget(menu)
        racine.addWidget(self.pile, 1)
        self.groupe.button(0).setChecked(True)

    # ------------------------------------------------------------------
    def aller(self, index):
        courante = self.pile.currentWidget()
        if courante is not None and hasattr(courante, "sortir"):
            courante.sortir()
        self.pile.setCurrentIndex(index)
        bouton = self.groupe.button(index)
        if bouton:
            bouton.setChecked(True)
        nouvelle = self.pile.currentWidget()
        if nouvelle is not None and hasattr(nouvelle, "entrer"):
            nouvelle.entrer()

    def aller_par_cle(self, cle: str):
        if cle in self._cles:
            self.aller(self._cles.index(cle))

    # -- appelées par la fenêtre principale ------------------------------
    def entrer(self):
        page = self.pile.currentWidget()
        if page is not None and hasattr(page, "entrer"):
            page.entrer()

    def sortir(self):
        page = self.pile.currentWidget()
        if page is not None and hasattr(page, "sortir"):
            page.sortir()
