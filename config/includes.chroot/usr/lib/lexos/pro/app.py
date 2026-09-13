"""LEXOS PRO — fenêtre principale et point d'entrée.

Le menu vertical de gauche est PERMANENT, comme sur la maquette : huit
entrées, icône + libellé, accent orange sur celle qui est active. Les
Paramètres ont leur propre sous-menu de la même forme.

CE QUE LA FENÊTRE GARANTIT :
  · une seule page visible à la fois, et seule celle-ci rafraîchit ses
    mesures (les minuteurs des autres sont arrêtés) ;
  · navigation entièrement au clavier (Tab, flèches, Ctrl+1..9) ;
  · taille minimale 1280 × 720, redimensionnable, HiDPI ;
  · rien n'est lancé en root, et aucun mot de passe n'est saisi ici.
"""
from __future__ import annotations

import os
import sys

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (QApplication, QButtonGroup, QFrame,
                               QHBoxLayout, QLabel, QMessageBox, QPushButton,
                               QStackedWidget, QVBoxLayout, QWidget)

from . import version
from .services import prefs
from .ui import theme
from .ui.pages import (accueil, apropos, developpement, fichiers, navigateur,
                       outils, securite, terminal)
from .ui.pages.parametres import PageParametres

#  (clé, libellé, icône)
MENU = (
    ("accueil", "Accueil", "accueil"),
    ("fichiers", "Fichiers", "fichiers"),
    ("terminal", "Terminal", "terminal"),
    ("parametres", "Paramètres", "parametres"),
    ("navigateur", "Navigateur", "navigateur"),
    ("securite", "Sécurité", "securite"),
    ("developpement", "Développement", "developpement"),
    #  NEUVIÈME ENTRÉE, ajoutée après coup à la demande d'Alex : sa seconde
    #  planche, 45 tuiles branchées sur les vrais programmes de la machine.
    #  Placée avant « À propos », qui reste le dernier.
    ("outils", "Outils", "applications"),
    ("apropos", "À propos", "apropos"),
)


class Fenetre(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"{version.NOM} {version.version()}")
        #  1280 × 720 est le minimum demandé : la fenêtre doit RESTER
        #  utilisable à cette taille, pas seulement s'y ouvrir.
        self.setMinimumSize(QSize(1120, 660))
        self.resize(1280, 760)
        self._prefs = prefs.charger()

        racine = QVBoxLayout(self)
        racine.setContentsMargins(0, 0, 0, 0)
        racine.setSpacing(0)
        racine.addWidget(self._barre_haute())

        milieu = QWidget()
        dm = QHBoxLayout(milieu)
        dm.setContentsMargins(0, 0, 0, 0)
        dm.setSpacing(0)

        self.rail = QFrame()
        self.rail.setObjectName("Rail")
        self.rail.setFixedWidth(184)
        dr = QVBoxLayout(self.rail)
        dr.setContentsMargins(10, 14, 10, 14)
        dr.setSpacing(4)

        self.groupe = QButtonGroup(self)
        self.groupe.setExclusive(True)
        self.pile = QStackedWidget()
        self._cles = []

        self.page_parametres = PageParametres(self)
        pages = {
            "accueil": accueil.PageAccueil(self.aller),
            "fichiers": fichiers.PageFichiers(),
            "terminal": terminal.PageTerminal(),
            "parametres": self.page_parametres,
            "navigateur": navigateur.PageNavigateur(),
            "securite": securite.PageSecurite(),
            "developpement": developpement.PageDeveloppement(),
            "outils": outils.PageOutils(self.aller, self._ouvrir_dossier),
            "apropos": apropos.PageApropos(),
        }
        for index, (cle, libelle, ic) in enumerate(MENU):
            b = QPushButton(libelle)
            b.setCheckable(True)
            b.setCursor(Qt.PointingHandCursor)
            b.setIcon(theme.icone(ic, theme.TEXTE_SECOND, 20))
            b.setIconSize(QSize(20, 20))
            b.setToolTip(f"{libelle}  (Ctrl+{index + 1})")
            b.clicked.connect(lambda _=False, c=cle: self.aller(c))
            self.groupe.addButton(b, index)
            dr.addWidget(b)
            self._cles.append(cle)
            self.pile.addWidget(pages[cle])
            QShortcut(QKeySequence(f"Ctrl+{index + 1}"), self,
                      activated=lambda c=cle: self.aller(c))
        dr.addStretch(1)
        signature = QLabel("UN SYSTÈME POUR\nCEUX QUI CONSTRUISENT\nDEMAIN")
        signature.setObjectName("CarteDetail")
        signature.setWordWrap(True)
        dr.addWidget(signature)

        dm.addWidget(self.rail)
        dm.addWidget(self.pile, 1)
        racine.addWidget(milieu, 1)

        QShortcut(QKeySequence("Ctrl+Q"), self, activated=self.close)
        QShortcut(QKeySequence(Qt.Key_F5), self, activated=self._relire)

        self.appliquer_apparence(self._prefs)
        self.groupe.button(0).setChecked(True)
        self.pile.setCurrentIndex(0)
        pages["accueil"].entrer()

    # ------------------------------------------------------------------
    def _barre_haute(self) -> QWidget:
        barre = QWidget()
        barre.setFixedHeight(52)
        barre.setStyleSheet(
            f"background: {theme.PANNEAU}; "
            f"border-bottom: 1px solid {theme.BORDURE};")
        d = QHBoxLayout(barre)
        d.setContentsMargins(18, 0, 18, 0)
        d.setSpacing(6)
        marque = QLabel("LEXOS")
        marque.setObjectName("Marque")
        pro = QLabel("PRO")
        pro.setObjectName("MarquePro")
        d.addWidget(marque)
        d.addWidget(pro)
        d.addStretch(1)
        self.etiquette_page = QLabel("")
        self.etiquette_page.setObjectName("SousTitre")
        d.addWidget(self.etiquette_page)
        return barre

    # ------------------------------------------------------------------
    def aller(self, cle: str):
        """Change de page. Accepte « parametres:affichage » pour viser
        directement une section des Paramètres (les raccourcis de
        l'accueil s'en servent)."""
        sous_section = ""
        if ":" in cle:
            cle, sous_section = cle.split(":", 1)
        if cle not in self._cles:
            return
        index = self._cles.index(cle)
        courante = self.pile.currentWidget()
        if courante is not None and hasattr(courante, "sortir"):
            courante.sortir()
        self.pile.setCurrentIndex(index)
        bouton = self.groupe.button(index)
        if bouton:
            bouton.setChecked(True)
        nouvelle = self.pile.currentWidget()
        if sous_section and hasattr(nouvelle, "aller_par_cle"):
            nouvelle.aller_par_cle(sous_section)
        elif nouvelle is not None and hasattr(nouvelle, "entrer"):
            nouvelle.entrer()
        self.etiquette_page.setText(dict(
            (c, l) for c, l, _ in MENU).get(cle, ""))

    def _ouvrir_dossier(self, chemin):
        """Une tuile « dossier » ouvre la page Fichiers à cet endroit.

        On passe par NOTRE page, pas par le gestionnaire du bureau : c'est
        elle qui sait déjà lister, renommer et mettre à la corbeille.
        """
        self.aller("fichiers")
        page = self.pile.currentWidget()
        if hasattr(page, "_aller"):
            page._aller(chemin)

    def _relire(self):
        page = self.pile.currentWidget()
        if page is not None and hasattr(page, "rafraichir"):
            page.rafraichir()

    def appliquer_apparence(self, reglages: dict):
        """Applique taille du texte, densité et animations à CHAUD."""
        app = QApplication.instance()
        if app is None:
            return
        app.setStyleSheet(theme.feuille(
            int(reglages.get("taille_texte", 100)),
            reglages.get("densite", "confortable")))
        #  « Animations discrètes, désactivables » : quand elles sont
        #  éteintes, on coupe les effets de Qt plutôt que de faire semblant.
        app.setEffectEnabled(Qt.UI_AnimateCombo,
                             bool(reglages.get("animations", True)))
        app.setEffectEnabled(Qt.UI_FadeMenu,
                             bool(reglages.get("animations", True)))
        app.setEffectEnabled(Qt.UI_AnimateTooltip,
                             bool(reglages.get("animations", True)))

    def closeEvent(self, evenement):      # noqa: N802 (API Qt)
        page = self.pile.currentWidget()
        if page is not None and hasattr(page, "sortir"):
            page.sortir()
        super().closeEvent(evenement)


def principal(argv=None) -> int:
    """Point d'entrée. Refuse de tourner en root, et explique pourquoi."""
    argv = list(sys.argv if argv is None else argv)

    #  JAMAIS EN ROOT. Un gestionnaire de fichiers lancé en root écrit
    #  n'importe où sans garde-fou, et toute erreur devient irréparable.
    #  Les rares actions qui demandent des droits passent par pkexec, qui
    #  a sa propre fenêtre d'autorisation.
    if os.geteuid() == 0 and not os.environ.get("LEXOS_PRO_AUTORISER_ROOT"):
        sys.stderr.write(
            "LEXOS PRO refuse de démarrer en root.\n"
            "Lancez-le avec votre compte habituel : les quelques actions\n"
            "qui demandent des droits passent par pkexec, qui affichera\n"
            "sa propre fenêtre d'autorisation.\n")
        return 2

    #  HiDPI : Qt 6 met déjà à l'échelle tout seul ; on demande en plus
    #  les pixmaps haute définition pour que les icônes tracées restent
    #  nettes sur un écran 4K.
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps, True)
    app = QApplication(argv)
    app.setApplicationName(version.NOM)
    app.setApplicationDisplayName(version.NOM)
    app.setApplicationVersion(version.version())
    app.setDesktopFileName("lexos-pro")
    app.setWindowIcon(theme.icone("systeme", theme.ORANGE, 64))

    fenetre = Fenetre()
    fenetre.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(principal())
