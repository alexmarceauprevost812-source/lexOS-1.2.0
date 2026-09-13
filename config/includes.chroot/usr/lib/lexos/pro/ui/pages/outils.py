"""Outils — la planche d'Alex, branchée sur les vrais programmes.

CHAQUE TUILE FAIT QUELQUE CHOSE, ou dit pourquoi elle ne peut pas. C'est la
consigne d'origine, mot pour mot : « ne transforme pas l'image entière en
arrière-plan de faux boutons ». Une tuile grise n'est pas décorative — elle
porte en infobulle la liste des programmes cherchés, et la page compte à
voix haute combien sont branchés.

Les trois tuiles de session (éteindre, redémarrer, déconnexion) demandent
confirmation. Ce sont les seules de cette page qui font perdre du travail.
"""
from __future__ import annotations

from PySide6.QtCore import QSize, Qt
from PySide6.QtWidgets import (QGridLayout, QHBoxLayout, QLabel, QLineEdit,
                               QMessageBox, QToolButton, QVBoxLayout,
                               QWidget)

from ...services import outils as svc
from .. import theme, widgets

TAILLE = 56
LARGEUR_TUILE = 140      # assez large pour « Dossier personnel » sans coupure
HAUTEUR_TUILE = 120


class Tuile(QToolButton):
    """Un carré cliquable : icône, libellé, et la vérité sur son état.

    QToolButton plutôt que le bouton ordinaire : c'est le seul des deux qui
    sait mettre l'icône AU-DESSUS du texte (ToolButtonTextUnderIcon), la
    disposition de la planche d'Alex. Avec l'autre, l'icône reste collée à
    gauche du libellé quoi qu'on écrive dans la feuille de style — mesuré.
    """

    def __init__(self, outil, etat, parent=None):
        super().__init__(parent)
        self.outil = outil
        self.etat = etat
        self.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        self.setFocusPolicy(Qt.StrongFocus)
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(QSize(LARGEUR_TUILE, HAUTEUR_TUILE))
        self.setIcon(theme.icone_outil(outil.icone, TAILLE,
                                       etat["disponible"]))
        self.setIconSize(QSize(TAILLE, TAILLE))
        self.setText(outil.libelle)
        self.setStyleSheet(f"""
            QPushButton {{
                background: transparent; border: 1px solid transparent;
                border-radius: 12px; padding: 8px 4px 6px 4px;
                color: {theme.TEXTE if etat['disponible']
                        else theme.TEXTE_FAIBLE};
                font-size: 11px; text-align: center;
            }}
            QToolButton:hover  {{ background: {theme.PANNEAU_HAUT};
                                  border-color: {theme.ORANGE}; }}
            QToolButton:focus  {{ border-color: {theme.ORANGE}; }}
            QToolButton:disabled {{ color: {theme.TEXTE_FAIBLE}; }}
        """)
        if etat["disponible"]:
            self.setToolTip(f"{outil.description}\n→ {etat.get('detail', '')}")
        else:
            self.setEnabled(False)
            self.setToolTip(f"{outil.description}\n\nIndisponible : "
                            f"{etat['raison']}")


class PageOutils(widgets.Page):
    def __init__(self, aller_vers, ouvrir_dossier, parent=None):
        super().__init__(
            "Outils",
            "Chaque tuile lance un vrai programme de cette machine. "
            "Une tuile grise n'est pas installée — son infobulle dit ce qui "
            "a été cherché.", parent)
        self._aller = aller_vers
        self._ouvrir_dossier = ouvrir_dossier

        barre = QWidget()
        d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        self.filtre = QLineEdit()
        self.filtre.setPlaceholderText("Rechercher un outil…")
        self.filtre.textChanged.connect(self._remplir)
        d.addWidget(self.filtre, 1)
        b = widgets.bouton("Relire", "maj",
                           infobulle="Re-chercher les programmes installés")
        b.clicked.connect(self.rafraichir)
        d.addWidget(b)
        self.disposition.addWidget(barre)

        self._zone = QWidget()
        self._grille = QVBoxLayout(self._zone)
        self._grille.setContentsMargins(0, 0, 0, 0)
        self._grille.setSpacing(16)
        self.disposition.addWidget(self._zone)
        self.disposition.addStretch(1)
        self._etats = {}
        self._colonnes = 0

    # ------------------------------------------------------------------
    def rafraichir(self):
        self.statut.occupe("Recherche des programmes installés…")
        widgets.en_fond(self, self._sonder, self._pret,
                        lambda m: self.statut.echec(m))

    @staticmethod
    def _sonder():
        #  La résolution appelle shutil.which() 150 fois : c'est rapide,
        #  mais sur un disque lent ou un montage réseau ça se sent. Hors
        #  du fil graphique, donc.
        return {o.cle: svc.resoudre(o) for o in svc.CATALOGUE}

    def _pret(self, etats):
        self._etats = etats
        self._remplir()
        n = sum(1 for e in etats.values() if e["disponible"])
        manque = len(etats) - n
        if manque:
            self.statut.neutre(
                f"{n} outils sur {len(etats)} sont branchés sur un programme "
                f"de cette machine. Les {manque} autres sont grisés, avec "
                f"leur raison en infobulle.")
        else:
            self.statut.succes(f"Les {n} outils sont branchés.")

    def _remplir(self):
        while self._grille.count():
            w = self._grille.takeAt(0).widget()
            if w:
                w.deleteLater()
        if not self._etats:
            return
        motif = self.filtre.text().strip().lower()
        groupes = svc.par_categorie()
        for categorie in svc.CATEGORIES:
            gardes = [o for o in groupes.get(categorie, [])
                      if not motif or motif in o.libelle.lower()
                      or motif in o.description.lower()]
            if not gardes:
                continue
            bloc = QWidget()
            db = QVBoxLayout(bloc)
            db.setContentsMargins(0, 0, 0, 0)
            db.setSpacing(6)
            titre = QLabel(categorie)
            titre.setObjectName("CarteTitre")
            titre.setStyleSheet(
                f"color: {theme.TEXTE}; font-weight: 600;")
            db.addWidget(titre)

            interne = QWidget()
            g = QGridLayout(interne)
            g.setContentsMargins(0, 0, 0, 0)
            g.setSpacing(6)
            colonnes = self._colonnes or self._colonnes_possibles()
            for i, outil in enumerate(gardes):
                etat = self._etats.get(outil.cle, {"disponible": False,
                                                   "raison": "non résolu"})
                t = Tuile(outil, etat)
                t.clicked.connect(
                    lambda _=False, o=outil: self._activer(o))
                g.addWidget(t, i // colonnes, i % colonnes)
            #  Une colonne élastique à droite : sans elle, six tuiles
            #  s'étalent sur toute la largeur et la grille se déforme d'une
            #  catégorie à l'autre.
            g.setColumnStretch(colonnes, 1)
            db.addWidget(interne)
            self._grille.addWidget(bloc)

    # ------------------------------------------------------------------
    def _colonnes_possibles(self) -> int:
        """Combien de tuiles tiennent dans la largeur actuelle.

        LA GRILLE S'ADAPTE, ELLE NE DÉBORDE PAS. Avec un nombre de colonnes
        figé à neuf, la page demandait 1134 px de tuiles pour 1070 px
        disponibles à 1280 × 720 : une barre de défilement HORIZONTALE
        apparaissait en bas, ce que le cahier des charges interdit
        explicitement pour le corps d'une page. Mesuré sur capture.
        """
        #  ON MESURE LA PAGE, PAS LA ZONE INTÉRIEURE. La première version
        #  lisait self._zone.width(), qui n'est pas encore à jour quand
        #  resizeEvent se déclenche : elle rendait 4 colonnes à 1280 px et
        #  5 à 1120 px — l'inverse du bon sens, et la preuve qu'elle lisait
        #  une largeur périmée. self.width() est connue tout de suite ; les
        #  marges, elles, sont fixes et écrites dans widgets.Page.
        MARGES = 22 + 22        # marges gauche/droite de widgets.Page
        ASCENSEUR = 18          # l'ascenseur vertical, quand il apparaît
        utile = max(200, self.width() - MARGES - ASCENSEUR)
        return max(2, utile // (LARGEUR_TUILE + 6))

    def resizeEvent(self, evenement):      # noqa: N802 (API Qt)
        """On ne redessine QUE si le nombre de colonnes change.

        Reconstruire 45 tuiles à chaque pixel de redimensionnement ferait
        ramer la fenêtre pendant qu'on l'attrape par le coin.
        """
        super().resizeEvent(evenement)
        n = self._colonnes_possibles()
        if n != self._colonnes:
            self._colonnes = n
            if self._etats:
                self._remplir()

    def _activer(self, outil):
        etat = self._etats.get(outil.cle, {})
        if not etat.get("disponible"):
            self.statut.echec(etat.get("raison", "Outil indisponible."))
            return

        if etat["genre"] == svc.PAGE:
            self._aller(etat["page"])
            return

        if etat["genre"] == svc.DOSSIER:
            self._ouvrir_dossier(etat["chemin"])
            self.statut.succes(f"Fichiers ouvert sur {etat['chemin']}.")
            return

        if outil.confirmation:
            #  Les trois actions de session, et elles seules.
            reponse = QMessageBox.warning(
                self, outil.libelle, outil.confirmation,
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            if reponse != QMessageBox.Yes:
                self.statut.neutre(f"« {outil.libelle} » annulé.")
                return

        self.afficher_resultat(svc.lancer(outil),
                               f"« {outil.libelle} » lancé "
                               f"({etat.get('detail', '')}).")
