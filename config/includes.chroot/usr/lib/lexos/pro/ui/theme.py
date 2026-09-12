"""Palette, feuille de style et icônes dessinées.

LES ICÔNES SONT DESSINÉES, PAS CHARGÉES. Un thème d'icônes système peut
être absent, incomplet, ou ne pas contenir le nom qu'on lui demande — et
une icône manquante, c'est un bouton vide que personne ne reconnaît. Ici
chaque icône est tracée par QPainter à la couleur demandée : elle existe
toujours, elle suit l'accent orange quand l'élément est choisi, et elle
reste nette sur un écran HiDPI parce qu'elle est tracée à la taille finale.
"""
from __future__ import annotations

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (QColor, QFont, QIcon, QPainter, QPainterPath,
                           QPen, QPixmap)

#  ── La palette de la maquette, et rien d'autre ─────────────────────────
FOND = "#090A0C"
PANNEAU = "#181B20"
PANNEAU_HAUT = "#1F232A"
BORDURE = "#2A2F37"
ORANGE = "#FF7A18"
ORANGE_SOMBRE = "#C25A10"
TEXTE = "#F2F0EC"          # blanc cassé
TEXTE_SECOND = "#A9B0BA"   # gris : contraste ≈ 7:1 sur #181B20
TEXTE_FAIBLE = "#7C848F"
VERT = "#4ADE80"
ROUGE = "#F87171"
JAUNE = "#FBBF24"

_ECHELLE = {"compacte": 0.82, "confortable": 1.0}


def police_base(taille_pourcent: int = 100) -> QFont:
    f = QFont()
    f.setPointSizeF(max(7.0, 10.0 * taille_pourcent / 100.0))
    return f


def feuille(taille_pourcent: int = 100, densite: str = "confortable") -> str:
    """QSS de l'application. Les tailles suivent les deux réglages
    d'apparence, pour que « texte plus grand » agisse vraiment partout."""
    e = _ECHELLE.get(densite, 1.0)
    k = taille_pourcent / 100.0
    pad = int(12 * e)
    rayon = 10
    return f"""
    QWidget {{
        background: {FOND};
        color: {TEXTE};
        font-size: {max(9, int(14 * k))}px;
    }}
    QLabel {{ background: transparent; }}
    #Carte {{
        background: {PANNEAU};
        border: 1px solid {BORDURE};
        border-radius: {rayon}px;
    }}
    #CarteTitre  {{ color: {TEXTE_SECOND}; font-size: {max(9, int(13 * k))}px; }}
    #CarteValeur {{ color: {TEXTE}; font-size: {max(14, int(26 * k))}px;
                    font-weight: 600; }}
    #CarteDetail {{ color: {TEXTE_FAIBLE}; font-size: {max(8, int(12 * k))}px; }}
    #TitrePage   {{ color: {TEXTE}; font-size: {max(15, int(24 * k))}px;
                    font-weight: 600; }}
    #SousTitre   {{ color: {TEXTE_SECOND}; font-size: {max(9, int(13 * k))}px; }}
    #Marque      {{ color: {TEXTE}; font-size: {max(12, int(18 * k))}px;
                    font-weight: 700; letter-spacing: 2px; }}
    #MarquePro   {{ color: {ORANGE}; font-size: {max(12, int(18 * k))}px;
                    font-weight: 300; letter-spacing: 2px; }}
    #Indisponible {{ color: {JAUNE}; font-size: {max(8, int(12 * k))}px; }}

    /* ── Menu principal, celui de gauche ─────────────────────────── */
    #Rail {{ background: {PANNEAU}; border-right: 1px solid {BORDURE}; }}
    #Rail QPushButton {{
        background: transparent; border: none; border-radius: {rayon}px;
        color: {TEXTE_SECOND}; text-align: left;
        padding: {pad}px {int(14 * e)}px;
        font-size: {max(9, int(13 * k))}px;
    }}
    #Rail QPushButton:hover  {{ background: {PANNEAU_HAUT}; color: {TEXTE}; }}
    #Rail QPushButton:checked {{
        background: {PANNEAU_HAUT}; color: {ORANGE}; font-weight: 600;
        border-left: 3px solid {ORANGE};
    }}
    #Rail QPushButton:focus {{ border: 1px solid {ORANGE}; }}

    /* ── Sous-menu des Paramètres : même forme que le menu principal,
          comme sur la maquette ───────────────────────────────────── */
    #SousMenu {{ background: {PANNEAU}; border: 1px solid {BORDURE};
                 border-radius: {rayon}px; }}
    #SousMenu QPushButton {{
        background: transparent; border: none; color: {TEXTE_SECOND};
        text-align: left; padding: {int(10 * e)}px {int(12 * e)}px;
        border-radius: 8px; font-size: {max(9, int(13 * k))}px;
    }}
    #SousMenu QPushButton:hover   {{ background: {PANNEAU_HAUT}; color: {TEXTE}; }}
    #SousMenu QPushButton:checked {{
        background: {PANNEAU_HAUT}; color: {ORANGE}; font-weight: 600;
        border-left: 3px solid {ORANGE};
    }}
    #SousMenu QPushButton:focus {{ border: 1px solid {ORANGE}; }}

    QPushButton {{
        background: {PANNEAU_HAUT}; color: {TEXTE};
        border: 1px solid {BORDURE}; border-radius: 8px;
        padding: {int(8 * e)}px {int(14 * e)}px;
    }}
    QPushButton:hover    {{ border-color: {ORANGE}; }}
    QPushButton:focus    {{ border: 1px solid {ORANGE}; }}
    QPushButton:disabled {{ color: {TEXTE_FAIBLE}; border-color: #23262C; }}
    QPushButton#Principal {{
        background: {ORANGE}; color: #16110B; border: none; font-weight: 600;
    }}
    QPushButton#Principal:hover    {{ background: #FF8C39; }}
    QPushButton#Principal:disabled {{ background: {ORANGE_SOMBRE};
                                      color: #6B5335; }}

    QLineEdit, QPlainTextEdit, QTextEdit, QComboBox, QSpinBox {{
        background: {FOND}; border: 1px solid {BORDURE}; border-radius: 8px;
        padding: {int(7 * e)}px; color: {TEXTE};
        selection-background-color: {ORANGE}; selection-color: #16110B;
    }}
    QLineEdit:focus, QPlainTextEdit:focus, QComboBox:focus,
    QSpinBox:focus {{ border-color: {ORANGE}; }}

    QTreeWidget, QListWidget, QTableWidget {{
        background: {FOND}; border: 1px solid {BORDURE}; border-radius: 8px;
        alternate-background-color: #0E1013; outline: none;
    }}
    QTreeWidget::item, QListWidget::item, QTableWidget::item {{
        padding: {int(5 * e)}px; border: none;
    }}
    QTreeWidget::item:selected, QListWidget::item:selected,
    QTableWidget::item:selected {{
        background: {PANNEAU_HAUT}; color: {ORANGE};
    }}
    QHeaderView::section {{
        background: {PANNEAU}; color: {TEXTE_SECOND}; border: none;
        border-bottom: 1px solid {BORDURE}; padding: {int(6 * e)}px;
    }}

    QScrollBar:vertical   {{ background: transparent; width: 10px; margin: 2px; }}
    QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 2px; }}
    QScrollBar::handle {{ background: #333942; border-radius: 5px; min-height: 28px; }}
    QScrollBar::handle:hover {{ background: {ORANGE_SOMBRE}; }}
    QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; width: 0; }}
    QScrollBar::add-page, QScrollBar::sub-page {{ background: transparent; }}

    QCheckBox, QRadioButton {{ spacing: 8px; }}
    QCheckBox::indicator, QRadioButton::indicator {{
        width: 16px; height: 16px; border: 1px solid {BORDURE};
        border-radius: 4px; background: {FOND};
    }}
    QCheckBox::indicator:checked, QRadioButton::indicator:checked {{
        background: {ORANGE}; border-color: {ORANGE};
    }}
    QSlider::groove:horizontal {{ height: 4px; background: {BORDURE};
                                  border-radius: 2px; }}
    QSlider::handle:horizontal {{ width: 14px; height: 14px; margin: -6px 0;
                                  background: {ORANGE}; border-radius: 7px; }}
    QSlider::sub-page:horizontal {{ background: {ORANGE}; border-radius: 2px; }}
    QToolTip {{ background: {PANNEAU_HAUT}; color: {TEXTE};
                border: 1px solid {ORANGE}; padding: 5px; border-radius: 6px; }}
    QSplitter::handle {{ background: {BORDURE}; }}
    QMenu {{ background: {PANNEAU}; border: 1px solid {BORDURE};
             border-radius: 8px; padding: 4px; }}
    QMenu::item {{ padding: 6px 22px 6px 12px; border-radius: 6px; }}
    QMenu::item:selected {{ background: {PANNEAU_HAUT}; color: {ORANGE}; }}
    """


# ══ Icônes tracées ═══════════════════════════════════════════════════════
def _p(peintre: QPainter, couleur: str, epaisseur: float = 1.8) -> QPen:
    stylo = QPen(QColor(couleur))
    stylo.setWidthF(epaisseur)
    stylo.setCapStyle(Qt.RoundCap)
    stylo.setJoinStyle(Qt.RoundJoin)
    peintre.setPen(stylo)
    peintre.setBrush(Qt.NoBrush)
    return stylo


def _dessiner(nom: str, peintre: QPainter, c: str) -> None:
    """Chaque icône est tracée dans un carré de 24×24, coordonnées fixes."""
    _p(peintre, c)
    if nom == "accueil":
        peintre.drawPolyline([QPointF(3, 11), QPointF(12, 3), QPointF(21, 11)])
        peintre.drawPolyline([QPointF(5.5, 10), QPointF(5.5, 20),
                              QPointF(18.5, 20), QPointF(18.5, 10)])
        peintre.drawRect(QRectF(10, 14, 4, 6))
    elif nom == "fichiers":
        peintre.drawPolygon([QPointF(3, 6), QPointF(10, 6), QPointF(12, 8.5),
                             QPointF(21, 8.5), QPointF(21, 19), QPointF(3, 19)])
    elif nom == "terminal":
        peintre.drawRoundedRect(QRectF(3, 5, 18, 14), 3, 3)
        peintre.drawPolyline([QPointF(7, 10), QPointF(10.5, 12.5),
                              QPointF(7, 15)])
        peintre.drawLine(QPointF(13, 15.4), QPointF(17, 15.4))
    elif nom == "parametres":
        peintre.drawEllipse(QPointF(12, 12), 3.4, 3.4)
        peintre.drawEllipse(QPointF(12, 12), 8.0, 8.0)
        for i in range(6):
            import math
            a = math.radians(i * 60)
            peintre.drawLine(
                QPointF(12 + 8 * math.cos(a), 12 + 8 * math.sin(a)),
                QPointF(12 + 10.5 * math.cos(a), 12 + 10.5 * math.sin(a)))
    elif nom == "navigateur":
        peintre.drawEllipse(QPointF(12, 12), 9, 9)
        peintre.drawEllipse(QPointF(12, 12), 3.6, 9)
        peintre.drawLine(QPointF(3, 12), QPointF(21, 12))
    elif nom == "securite":
        chemin = QPainterPath(QPointF(12, 3))
        chemin.lineTo(20, 6.5)
        chemin.lineTo(20, 12)
        chemin.quadTo(20, 18.5, 12, 21)
        chemin.quadTo(4, 18.5, 4, 12)
        chemin.lineTo(4, 6.5)
        chemin.closeSubpath()
        peintre.drawPath(chemin)
        peintre.drawPolyline([QPointF(8.5, 12), QPointF(11, 14.5),
                              QPointF(15.5, 9.5)])
    elif nom == "developpement":
        peintre.drawPolyline([QPointF(8.5, 8), QPointF(4, 12), QPointF(8.5, 16)])
        peintre.drawPolyline([QPointF(15.5, 8), QPointF(20, 12),
                              QPointF(15.5, 16)])
        peintre.drawLine(QPointF(13.5, 5.5), QPointF(10.5, 18.5))
    elif nom == "apropos":
        peintre.drawEllipse(QPointF(12, 12), 9, 9)
        peintre.drawLine(QPointF(12, 11), QPointF(12, 16.5))
        peintre.drawPoint(QPointF(12, 7.8))
    elif nom == "processeur":
        peintre.drawRoundedRect(QRectF(7, 7, 10, 10), 2, 2)
        peintre.drawRect(QRectF(10, 10, 4, 4))
        for x in (9.5, 12, 14.5):
            peintre.drawLine(QPointF(x, 4), QPointF(x, 7))
            peintre.drawLine(QPointF(x, 17), QPointF(x, 20))
            peintre.drawLine(QPointF(4, x), QPointF(7, x))
            peintre.drawLine(QPointF(17, x), QPointF(20, x))
    elif nom == "gpu":
        peintre.drawRoundedRect(QRectF(3, 7, 18, 10), 2, 2)
        peintre.drawEllipse(QPointF(9, 12), 2.6, 2.6)
        peintre.drawEllipse(QPointF(15.5, 12), 2.0, 2.0)
        peintre.drawLine(QPointF(6, 17), QPointF(6, 19.5))
    elif nom == "memoire":
        peintre.drawRoundedRect(QRectF(3, 8, 18, 8), 2, 2)
        for x in (7, 10, 13, 16):
            peintre.drawLine(QPointF(x, 16), QPointF(x, 19))
        peintre.drawLine(QPointF(6, 11), QPointF(18, 11))
    elif nom == "stockage":
        peintre.drawRoundedRect(QRectF(3, 6, 18, 12), 3, 3)
        peintre.drawEllipse(QPointF(16.5, 12), 1.5, 1.5)
        peintre.drawLine(QPointF(6, 9.5), QPointF(12, 9.5))
    elif nom == "reseau":
        for r in (3.5, 6.8, 10.0):
            peintre.drawArc(QRectF(12 - r, 14 - r, r * 2, r * 2),
                            30 * 16, 120 * 16)
        peintre.drawPoint(QPointF(12, 17.5))
        peintre.drawEllipse(QPointF(12, 17.5), 1.1, 1.1)
    elif nom == "son":
        peintre.drawPolygon([QPointF(4, 10), QPointF(8, 10), QPointF(12.5, 6),
                             QPointF(12.5, 18), QPointF(8, 14), QPointF(4, 14)])
        peintre.drawArc(QRectF(13, 8, 6, 8), -60 * 16, 120 * 16)
    elif nom == "performances":
        peintre.drawPolyline([QPointF(3, 17), QPointF(8, 11), QPointF(12, 14),
                              QPointF(16, 7), QPointF(21, 10)])
        peintre.drawLine(QPointF(3, 20), QPointF(21, 20))
    elif nom == "systeme":
        peintre.drawPolygon([QPointF(12, 3), QPointF(20, 7.5), QPointF(20, 16.5),
                             QPointF(12, 21), QPointF(4, 16.5), QPointF(4, 7.5)])
    elif nom == "apparence":
        peintre.drawEllipse(QPointF(12, 12), 8.5, 8.5)
        peintre.drawEllipse(QPointF(9, 9.5), 1.3, 1.3)
        peintre.drawEllipse(QPointF(14.5, 9), 1.3, 1.3)
        peintre.drawEllipse(QPointF(16, 14), 1.3, 1.3)
    elif nom == "affichage":
        peintre.drawRoundedRect(QRectF(3, 5, 18, 12), 2, 2)
        peintre.drawLine(QPointF(9, 20), QPointF(15, 20))
        peintre.drawLine(QPointF(12, 17), QPointF(12, 20))
    elif nom == "applications":
        for x in (5, 13.5):
            for y in (5, 13.5):
                peintre.drawRoundedRect(QRectF(x, y, 5.5, 5.5), 1.5, 1.5)
    elif nom == "services":
        peintre.drawEllipse(QPointF(12, 12), 8.5, 8.5)
        peintre.drawLine(QPointF(12, 6.5), QPointF(12, 12))
        peintre.drawLine(QPointF(12, 12), QPointF(16, 14.5))
    elif nom == "maj":
        peintre.drawArc(QRectF(4, 4, 16, 16), 40 * 16, 280 * 16)
        peintre.drawPolyline([QPointF(16, 3), QPointF(20, 6), QPointF(16, 8.5)])
        peintre.drawLine(QPointF(12, 8), QPointF(12, 15))
        peintre.drawPolyline([QPointF(9, 12), QPointF(12, 15), QPointF(15, 12)])
    elif nom == "recherche":
        peintre.drawEllipse(QPointF(10.5, 10.5), 6, 6)
        peintre.drawLine(QPointF(15, 15), QPointF(20, 20))
    elif nom == "retour":
        peintre.drawPolyline([QPointF(13, 6), QPointF(7, 12), QPointF(13, 18)])
        peintre.drawLine(QPointF(7, 12), QPointF(19, 12))
    else:
        peintre.drawEllipse(QPointF(12, 12), 7, 7)


def icone(nom: str, couleur: str = TEXTE_SECOND, taille: int = 24) -> QIcon:
    """Une icône tracée, à la couleur demandée.

    devicePixelRatio n'est pas fixé ici : QIcon gère lui-même les écrans
    HiDPI à partir d'un pixmap tracé à la taille logique demandée.
    """
    pix = QPixmap(taille, taille)
    pix.fill(Qt.transparent)
    peintre = QPainter(pix)
    peintre.setRenderHint(QPainter.Antialiasing, True)
    peintre.scale(taille / 24.0, taille / 24.0)
    _dessiner(nom, peintre, couleur)
    peintre.end()
    return QIcon(pix)
