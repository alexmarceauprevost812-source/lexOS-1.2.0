"""Composants réutilisables — et le travailleur qui garde l'interface vive.

LA RÈGLE DU FIL GRAPHIQUE. Tout ce qui peut durer — nvidia-smi, systemctl,
apt-get --just-print, glxinfo — part dans un QThreadPool et revient par un
signal. Une seule commande lente exécutée dans le fil de Qt fige la
fenêtre entière : plus de défilement, plus de redessin, et l'utilisateur
croit que l'application a planté.

LA ZONE DE STATUT. Chaque page en a une. Elle porte le dernier résultat,
succès comme échec, AVEC son motif. C'est là que finissent les erreurs des
services : jamais dans une console que personne ne lit, jamais nulle part.
"""
from __future__ import annotations

from PySide6.QtCore import (QObject, QRunnable, Qt, QThreadPool, QTimer,
                            Signal, Slot)
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (QFrame, QGridLayout, QHBoxLayout, QLabel,
                               QPushButton, QScrollArea, QSizePolicy,
                               QVBoxLayout, QWidget)

from . import theme


# ══ Travail en arrière-plan ══════════════════════════════════════════════
class _Signaux(QObject):
    fini = Signal(object)
    rate = Signal(str)


class Tache(QRunnable):
    """Exécute une fonction hors du fil graphique et rend son résultat.

    Toute exception est rattrapée et devient un message : une exception qui
    remonte depuis un QRunnable termine le processus sans un mot.
    """

    def __init__(self, fonction, *args, **kwargs):
        super().__init__()
        #  setAutoDelete(False) N'EST PAS UNE PRÉCAUTION, C'EST LE CORRECTIF
        #  D'UN PLANTAGE MESURÉ. Par défaut, QThreadPool supprime le
        #  QRunnable côté C++ dès que run() rend la main — y compris le
        #  QObject porteur des signaux qu'il contient. Python, lui, tient
        #  encore la référence et émet : « RuntimeError: Signal source has
        #  been deleted », relevé au premier parcours complet des pages.
        #  Avec False, c'est Python qui décide de la durée de vie, via la
        #  liste tenue par en_fond().
        self.setAutoDelete(False)
        self._f, self._a, self._k = fonction, args, kwargs
        self.signaux = _Signaux()
        self.terminee = False

    @Slot()
    def run(self):
        try:
            resultat = self._f(*self._a, **self._k)
        except Exception as e:                      # noqa: BLE001
            self._emettre(self.signaux.rate, f"{type(e).__name__} : {e}")
            return
        finally:
            self.terminee = True
        self._emettre(self.signaux.fini, resultat)

    @staticmethod
    def _emettre(signal, charge):
        """La page peut avoir été détruite pendant que la tâche tournait —
        fermeture de la fenêtre, par exemple. Ce n'est pas une erreur."""
        try:
            signal.emit(charge)
        except RuntimeError:
            pass


def en_fond(parent, fonction, sur_resultat, sur_erreur=None, *args, **kwargs):
    """Lance `fonction` en arrière-plan. `parent` garde la tâche en vie."""
    tache = Tache(fonction, *args, **kwargs)
    tache.signaux.fini.connect(sur_resultat)
    if sur_erreur is not None:
        tache.signaux.rate.connect(sur_erreur)
    if not hasattr(parent, "_taches"):
        parent._taches = []
    #  On purge les tâches finies à chaque envoi : sans ça la liste
    #  grossirait indéfiniment sur une page qui se rafraîchit toutes les
    #  deux secondes.
    parent._taches = [t for t in parent._taches if not t.terminee]
    parent._taches.append(tache)
    QThreadPool.globalInstance().start(tache)
    return tache


# ══ Éléments d'affichage ═════════════════════════════════════════════════
class Courbe(QWidget):
    """Une courbe d'historique. Ne dessine RIEN tant qu'il n'y a pas deux
    points : une ligne plate inventée ressemblerait à une mesure à zéro."""

    def __init__(self, maximum: float = 100.0, points: int = 60, parent=None):
        super().__init__(parent)
        self._valeurs = []
        self._max = maximum
        self._capacite = points
        self.setMinimumHeight(38)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

    def ajouter(self, valeur):
        if valeur is None:
            return
        self._valeurs.append(float(valeur))
        if len(self._valeurs) > self._capacite:
            self._valeurs.pop(0)
        self.update()

    def vider(self):
        self._valeurs.clear()
        self.update()

    def paintEvent(self, evenement):       # noqa: N802 (API Qt)
        if len(self._valeurs) < 2:
            return
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing, True)
        l, h = self.width(), self.height()
        pas = l / max(1, len(self._valeurs) - 1)
        chemin = QPainterPath()
        for i, v in enumerate(self._valeurs):
            y = h - (min(v, self._max) / self._max) * (h - 4) - 2
            point = (i * pas, y)
            chemin.moveTo(*point) if i == 0 else chemin.lineTo(*point)
        stylo = QPen(QColor(theme.ORANGE))
        stylo.setWidthF(1.6)
        p.setPen(stylo)
        p.drawPath(chemin)
        p.end()


class Jauge(QWidget):
    """Barre de remplissage. `None` = mesure absente : barre creuse."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._pourcent = None
        self.setFixedHeight(6)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

    def regler(self, pourcent):
        self._pourcent = None if pourcent is None else max(0.0, min(100.0, float(pourcent)))
        self.update()

    def paintEvent(self, evenement):       # noqa: N802
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(theme.BORDURE))
        p.drawRoundedRect(0, 0, self.width(), self.height(), 3, 3)
        if self._pourcent:
            p.setBrush(QColor(theme.ORANGE))
            p.drawRoundedRect(0, 0, int(self.width() * self._pourcent / 100.0),
                              self.height(), 3, 3)
        p.end()


class Carte(QFrame):
    """Le panneau anthracite de la maquette : titre, grande valeur, détail."""

    def __init__(self, titre: str, icone: str = "", parent=None):
        super().__init__(parent)
        self.setObjectName("Carte")
        self.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Preferred)
        exterieur = QVBoxLayout(self)
        exterieur.setContentsMargins(16, 14, 16, 14)
        exterieur.setSpacing(6)

        haut = QHBoxLayout()
        haut.setSpacing(9)
        if icone:
            pastille = QLabel()
            pastille.setPixmap(theme.icone(icone, theme.ORANGE, 20).pixmap(20, 20))
            haut.addWidget(pastille)
        self.titre = QLabel(titre)
        self.titre.setObjectName("CarteTitre")
        haut.addWidget(self.titre)
        haut.addStretch(1)
        exterieur.addLayout(haut)

        self.valeur = QLabel("—")
        self.valeur.setObjectName("CarteValeur")
        exterieur.addWidget(self.valeur)

        self.detail = QLabel("")
        self.detail.setObjectName("CarteDetail")
        self.detail.setWordWrap(True)
        exterieur.addWidget(self.detail)

        self.jauge = Jauge()
        exterieur.addWidget(self.jauge)
        self.courbe = Courbe()
        exterieur.addWidget(self.courbe)
        self.corps = exterieur

    def montrer(self, valeur: str, detail: str = "", pourcent=None,
                historique=None):
        self.valeur.setText(valeur)
        self.valeur.setStyleSheet("")
        self.detail.setText(detail)
        self.jauge.regler(pourcent)
        if historique is not None:
            self.courbe.ajouter(historique)

    def indisponible(self, raison: str):
        """L'UNIQUE façon d'afficher une absence. Jamais un zéro."""
        self.valeur.setText("Indisponible")
        self.valeur.setStyleSheet(f"color: {theme.JAUNE};")
        self.detail.setText(raison)
        self.setToolTip(raison)
        self.jauge.regler(None)

    def sans_courbe(self):
        self.courbe.hide()
        return self

    def sans_jauge(self):
        self.jauge.hide()
        return self


class ZoneStatut(QFrame):
    """Le bas de chaque page : le dernier résultat, avec sa raison."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("Carte")
        d = QHBoxLayout(self)
        d.setContentsMargins(12, 9, 12, 9)
        self._point = QLabel("●")
        self._texte = QLabel("Prêt.")
        self._texte.setWordWrap(True)
        self._texte.setTextInteractionFlags(Qt.TextSelectableByMouse)
        d.addWidget(self._point)
        d.addWidget(self._texte, 1)
        self.neutre("Prêt.")

    def _dire(self, couleur: str, texte: str):
        self._point.setStyleSheet(f"color: {couleur};")
        self._texte.setStyleSheet(f"color: {theme.TEXTE};")
        self._texte.setText(texte)
        self.setToolTip(texte)

    def neutre(self, texte):  self._dire(theme.TEXTE_FAIBLE, texte)
    def succes(self, texte):  self._dire(theme.VERT, texte)
    def echec(self, texte):   self._dire(theme.ROUGE, texte)
    def attention(self, texte): self._dire(theme.JAUNE, texte)
    def occupe(self, texte):  self._dire(theme.ORANGE, texte)


class Page(QWidget):
    """Structure commune à TOUTES les pages : titre, description, corps,
    zone de statut. C'est ce qui fait qu'on se repère d'une page à l'autre.
    """

    def __init__(self, titre: str, description: str, parent=None):
        super().__init__(parent)
        racine = QVBoxLayout(self)
        racine.setContentsMargins(22, 20, 22, 18)
        racine.setSpacing(14)

        self.titre = QLabel(titre)
        self.titre.setObjectName("TitrePage")
        racine.addWidget(self.titre)

        self.description = QLabel(description)
        self.description.setObjectName("SousTitre")
        self.description.setWordWrap(True)
        racine.addWidget(self.description)

        defilement = QScrollArea()
        defilement.setWidgetResizable(True)
        defilement.setFrameShape(QFrame.NoFrame)
        self.corps = QWidget()
        self.disposition = QVBoxLayout(self.corps)
        self.disposition.setContentsMargins(0, 0, 6, 0)
        self.disposition.setSpacing(14)
        defilement.setWidget(self.corps)
        racine.addWidget(defilement, 1)

        self.statut = ZoneStatut()
        racine.addWidget(self.statut)

        self._minuteur = None

    # -- cycle de vie, piloté par la fenêtre principale ------------------
    def entrer(self):
        """Appelée quand la page devient visible. Les minuteurs ne
        tournent QUE là : rafraîchir dix pages cachées en continu, c'est
        du travail et de la batterie pour rien."""
        self.rafraichir()
        if self._minuteur:
            self._minuteur.start()

    def sortir(self):
        if self._minuteur:
            self._minuteur.stop()

    def rafraichir(self):
        """À redéfinir."""

    def periodique(self, millisecondes: int):
        self._minuteur = QTimer(self)
        self._minuteur.setInterval(millisecondes)
        self._minuteur.timeout.connect(self.rafraichir)

    # -- aides -----------------------------------------------------------
    def ajouter_grille(self, colonnes: int = 3) -> QGridLayout:
        boite = QWidget()
        grille = QGridLayout(boite)
        grille.setContentsMargins(0, 0, 0, 0)
        grille.setSpacing(14)
        for c in range(colonnes):
            grille.setColumnStretch(c, 1)
        self.disposition.addWidget(boite)
        return grille

    def afficher_resultat(self, resultat, message_succes: str = ""):
        """Transforme un services.execution.Resultat en zone de statut."""
        if getattr(resultat, "ok", False):
            self.statut.succes(message_succes or
                               (resultat.sortie or "Opération réussie."))
        else:
            self.statut.echec(getattr(resultat, "erreur", str(resultat)))
        return getattr(resultat, "ok", False)


def bouton(texte: str, icone: str = "", principal: bool = False,
           infobulle: str = "") -> QPushButton:
    b = QPushButton(texte)
    if icone:
        b.setIcon(theme.icone(icone, theme.TEXTE if not principal else "#16110B", 18))
    if principal:
        b.setObjectName("Principal")
    if infobulle:
        b.setToolTip(infobulle)
    b.setCursor(Qt.PointingHandCursor)
    return b


def eteindre(b: QPushButton, raison: str):
    """Un bouton désactivé DIT pourquoi — consigne explicite. Un bouton
    gris muet est indiscernable d'un bouton cassé."""
    b.setEnabled(False)
    b.setToolTip(raison)


def titre_section(texte: str) -> QLabel:
    l = QLabel(texte)
    l.setObjectName("CarteTitre")
    l.setStyleSheet(f"color: {theme.TEXTE}; font-weight: 600;")
    return l
