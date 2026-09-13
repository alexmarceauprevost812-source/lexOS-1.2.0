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


# ══ Icônes de TYPES DE FICHIERS ══════════════════════════════════════════
#  D'APRÈS LA PLANCHE D'ALEX : carré arrondi coloré, coin replié, symbole
#  blanc au centre, bandeau sombre portant l'extension.
#
#  TRACÉES, COMME LES AUTRES, et pour la même raison — mais elle pèse plus
#  lourd ici : un gestionnaire de fichiers affiche des centaines d'icônes
#  par dossier. Quarante-neuf fichiers PNG à livrer, c'est quarante-neuf
#  occasions qu'il en manque un, et une icône manquante dans une liste de
#  fichiers ne se remarque pas — elle se confond avec « fichier inconnu ».
#
#  LA COULEUR DIT LA FAMILLE, PAS L'EXTENSION. .jpg et .jpeg sont la même
#  chose ; les distinguer par la couleur serait du bruit. Ce qu'on veut
#  reconnaître d'un coup d'œil, c'est « une image », « une archive », « un
#  exécutable » — l'extension exacte, le bandeau la donne.
_FAMILLES = {
    "image":        ("#FF7A18", "image"),
    "image2":       ("#F0433A", "image"),
    "image3":       ("#EC1E79", "image"),
    "vectoriel":    ("#8B3DEC", "vectoriel"),
    "photo":        ("#3B3F46", "image"),
    "video":        ("#E8322B", "video"),
    "audio":        ("#1F7AE0", "audio"),
    "audio2":       ("#5BB522", "audio"),
    "audio3":       ("#8B3DEC", "audio"),
    "partition":    ("#6B4BB5", "partition"),
    "texte":        ("#5A6069", "texte"),
    "document":     ("#1F7AE0", "texte"),
    "tableur":      ("#3B9B2F", "tableur"),
    "diapo":        ("#E8721B", "diapo"),
    "pdf":          ("#D92B2B", "pdf"),
    "balisage":     ("#8B3DEC", "texte"),
    "donnees":      ("#2C5BD8", "accolades"),
    "web":          ("#F07C1B", "chevrons"),
    "style":        ("#E0452F", "accolades"),
    "script":       ("#E8901B", "accolades"),
    "archive":      ("#F0B41B", "archive"),
    "archive2":     ("#8B3DEC", "archive"),
    "archive3":     ("#2C6BD8", "archive"),
    "archive4":     ("#4A4F57", "archive"),
    "disque":       ("#6E757E", "disque"),
    "paquet":       ("#19A5CC", "paquet"),
    "paquet_deb":   ("#3B9B2F", "paquet"),
    "paquet_snap":  ("#7B3DD8", "paquet"),
    "paquet_flat":  ("#3BA82F", "paquet"),
    "binaire":      ("#F07C1B", "engrenage"),
    "shell":        ("#E8322B", "invite"),
    "python":       ("#C4651B", "python"),
    "service":      ("#4A4F57", "engrenage"),
    "dossier":      ("#F0891B", "dossier"),
    "inconnu":      ("#5A6069", "texte"),
    #  CES QUATRE-LÀ SONT NÉS D'UN DÉFAUT VU SUR LA PLANCHE DE CONTRÔLE.
    #  J'avais rangé .ogg dans « image », .wma dans « image3 » et .m4a dans
    #  « paquet » parce que la COULEUR de ces familles correspondait à celle
    #  de la planche d'Alex — en oubliant qu'une famille porte aussi son
    #  SYMBOLE. Résultat : trois fichiers audio avec une icône de photo ou
    #  de cube. Une famille, c'est un couple couleur+symbole ; en réutiliser
    #  une pour sa seule couleur, c'est hériter de l'autre moitié sans le
    #  vouloir.
    "audio_ogg":    ("#E8721B", "audio"),
    "audio_wma":    ("#D4267E", "audio"),
    "audio_m4a":    ("#19A5CC", "audio"),
    "texte_rtf":    ("#3B3F46", "texte"),
}

#  extension -> famille. Les extensions composées (.tar.gz) sont gérées par
#  la reconnaissance du suffixe dans famille_fichier().
_EXTENSIONS = {
    # images
    "png": "image", "webp": "image", "bmp": "image", "ico": "image",
    "jpg": "image2", "jpeg": "image2", "heic": "image2", "avif": "image2",
    "gif": "image3",
    "svg": "vectoriel", "eps": "vectoriel", "ai": "vectoriel",
    "tif": "photo", "tiff": "photo",
    "raw": "photo", "cr2": "photo", "nef": "photo", "arw": "photo",
    "dng": "photo",
    # vidéo
    "mp4": "video", "mkv": "video", "avi": "video", "mov": "video",
    "webm": "video", "wmv": "video", "m4v": "video", "mpg": "video",
    "mpeg": "video",
    # audio
    "mp3": "audio", "aac": "audio", "opus": "audio",
    "wav": "audio2", "aiff": "audio2",
    "flac": "audio3", "ape": "audio3",
    "ogg": "audio_ogg", "oga": "audio_ogg",
    "wma": "audio_wma",
    "mid": "partition", "midi": "partition",
    "m4a": "audio_m4a",
    # bureautique
    "doc": "document", "docx": "document", "odt": "document",
    "xls": "tableur", "xlsx": "tableur", "ods": "tableur", "csv": "tableur",
    "tsv": "tableur",
    "ppt": "diapo", "pptx": "diapo", "odp": "diapo",
    "pdf": "pdf",
    # texte et code
    "txt": "texte", "log": "texte", "conf": "texte", "cfg": "texte",
    "ini": "texte", "list": "texte",
    "rtf": "texte_rtf",
    "md": "balisage", "rst": "balisage", "adoc": "balisage",
    "json": "donnees", "yaml": "donnees", "yml": "donnees",
    "toml": "donnees", "xml": "donnees", "sql": "donnees",
    "html": "web", "htm": "web", "php": "web",
    "css": "style", "scss": "style", "less": "style",
    "js": "script", "ts": "script", "jsx": "script", "tsx": "script",
    "c": "script", "h": "script", "cpp": "script", "hpp": "script",
    "rs": "script", "go": "script", "java": "script", "rb": "script",
    "lua": "script", "pl": "script",
    # archives
    "zip": "archive",
    "rar": "archive2",
    "7z": "archive3",
    "tar": "archive4", "gz": "archive4", "xz": "archive4", "bz2": "archive4",
    "zst": "archive4", "tgz": "archive4",
    "iso": "disque", "img": "disque", "vhd": "disque", "qcow2": "disque",
    # paquets et exécutables
    "app": "paquet", "appimage": "archive3",
    "deb": "paquet_deb", "rpm": "paquet_deb",
    "snap": "paquet_snap",
    "flatpak": "paquet_flat", "flatpakref": "paquet_flat",
    "exe": "binaire", "msi": "binaire", "dll": "binaire",
    "sh": "shell", "bash": "shell", "zsh": "shell", "fish": "shell",
    "py": "python", "pyc": "python",
    "service": "service", "socket": "service", "timer": "service",
    "target": "service", "mount": "service",
    "desktop": "paquet",
}


def famille_fichier(nom: str) -> tuple:
    """(clé de famille, extension affichable) pour un nom de fichier.

    Les archives composées sont reconnues d'abord : « paquet.tar.gz » est une
    archive TAR.GZ, pas un fichier « GZ ». Sans ce passage, la moitié des
    archives d'un dossier de développement s'afficheraient sous la mauvaise
    étiquette.
    """
    bas = (nom or "").lower()
    for compose in ("tar.gz", "tar.xz", "tar.bz2", "tar.zst"):
        if bas.endswith("." + compose):
            return "archive4", compose.upper()
    if "." not in bas.strip("."):
        return "inconnu", ""
    ext = bas.rsplit(".", 1)[-1]
    return _EXTENSIONS.get(ext, "inconnu"), ext.upper()


def _teinte(couleur: str, facteur: float) -> QColor:
    c = QColor(couleur)
    h, s, v, a = c.getHsv()
    return QColor.fromHsv(h, s, max(0, min(255, int(v * facteur))), a)


def _glyphe(nom: str, p: QPainter, r: QRectF, couleur: str = "#FFFFFF") -> None:
    """Le symbole au centre, tracé dans le rectangle donné.

    La couleur est un PARAMÈTRE et non une constante : le même symbole sert
    en blanc sur une icône de fichier colorée, et en orange sur une tuile
    d'outil sombre. Le figer en blanc obligerait à le redessiner une
    seconde fois — deux copies du même trait qui divergent au premier
    changement.
    """
    stylo = QPen(QColor(couleur))
    stylo.setWidthF(max(1.1, r.width() * 0.075))
    stylo.setCapStyle(Qt.RoundCap)
    stylo.setJoinStyle(Qt.RoundJoin)
    p.setPen(stylo)
    p.setBrush(Qt.NoBrush)
    x, y, l, h = r.x(), r.y(), r.width(), r.height()

    def P(fx, fy):
        return QPointF(x + l * fx, y + h * fy)

    if nom == "image":
        p.drawRoundedRect(QRectF(x, y, l, h), l * 0.12, l * 0.12)
        p.drawEllipse(P(0.30, 0.30), l * 0.08, h * 0.08)
        p.drawPolyline([P(0.10, 0.80), P(0.40, 0.45), P(0.62, 0.66),
                        P(0.75, 0.54), P(0.92, 0.78)])
    elif nom == "vectoriel":
        p.drawPolyline([P(0.18, 0.82), P(0.62, 0.20)])
        p.drawPolygon([P(0.58, 0.12), P(0.82, 0.30), P(0.70, 0.44),
                       P(0.48, 0.26)])
        p.drawEllipse(P(0.20, 0.84), l * 0.07, h * 0.07)
    elif nom == "video":
        p.drawRoundedRect(QRectF(x, y + h * 0.10, l, h * 0.80),
                          l * 0.12, l * 0.12)
        p.drawPolygon([P(0.40, 0.32), P(0.72, 0.50), P(0.40, 0.68)])
    elif nom == "audio":
        p.drawEllipse(P(0.32, 0.74), l * 0.15, h * 0.12)
        p.drawLine(P(0.47, 0.74), P(0.47, 0.18))
        p.drawPolyline([P(0.47, 0.18), P(0.86, 0.06), P(0.86, 0.30)])
    elif nom == "partition":
        p.drawRect(QRectF(x + l * 0.10, y + h * 0.22, l * 0.80, h * 0.56))
        for f in (0.28, 0.42, 0.58, 0.72):
            p.drawLine(P(f, 0.22), P(f, 0.78))
    elif nom == "texte":
        for f in (0.24, 0.42, 0.60, 0.78):
            p.drawLine(P(0.12, f), P(0.88 if f != 0.78 else 0.62, f))
    elif nom == "tableur":
        p.drawRect(QRectF(x + l * 0.08, y + h * 0.14, l * 0.84, h * 0.72))
        for f in (0.38, 0.62):
            p.drawLine(P(0.08, f), P(0.92, f))
        for f in (0.36, 0.64):
            p.drawLine(P(f, 0.14), P(f, 0.86))
    elif nom == "diapo":
        p.drawEllipse(P(0.50, 0.50), l * 0.36, h * 0.36)
        p.drawLine(P(0.50, 0.50), P(0.50, 0.14))
        p.drawLine(P(0.50, 0.50), P(0.84, 0.58))
    elif nom == "pdf":
        #  Le « A » du document imprimé : deux jambages et leur barre. Lisible
        #  à 20 px, là où l'arc et le chevron de la première version se
        #  mélangeaient en un gribouillis — vu sur la planche de contrôle.
        p.drawPolyline([P(0.20, 0.84), P(0.50, 0.16), P(0.80, 0.84)])
        p.drawLine(P(0.33, 0.60), P(0.67, 0.60))
    elif nom == "accolades":
        p.drawPolyline([P(0.38, 0.14), P(0.26, 0.22), P(0.26, 0.42),
                        P(0.16, 0.50), P(0.26, 0.58), P(0.26, 0.78),
                        P(0.38, 0.86)])
        p.drawPolyline([P(0.62, 0.14), P(0.74, 0.22), P(0.74, 0.42),
                        P(0.84, 0.50), P(0.74, 0.58), P(0.74, 0.78),
                        P(0.62, 0.86)])
    elif nom == "chevrons":
        p.drawPolyline([P(0.34, 0.24), P(0.12, 0.50), P(0.34, 0.76)])
        p.drawPolyline([P(0.66, 0.24), P(0.88, 0.50), P(0.66, 0.76)])
        p.drawLine(P(0.58, 0.14), P(0.42, 0.86))
    elif nom == "archive":
        p.drawRoundedRect(QRectF(x + l * 0.14, y, l * 0.72, h), l * 0.10,
                          l * 0.10)
        p.drawLine(P(0.50, 0.02), P(0.50, 0.46))
        p.drawRect(QRectF(x + l * 0.40, y + h * 0.48, l * 0.20, h * 0.26))
    elif nom == "disque":
        p.drawEllipse(P(0.50, 0.50), l * 0.40, h * 0.40)
        p.drawEllipse(P(0.50, 0.50), l * 0.10, h * 0.10)
    elif nom == "paquet":
        p.drawPolygon([P(0.50, 0.06), P(0.92, 0.28), P(0.92, 0.72),
                       P(0.50, 0.94), P(0.08, 0.72), P(0.08, 0.28)])
        p.drawPolyline([P(0.08, 0.28), P(0.50, 0.50), P(0.92, 0.28)])
        p.drawLine(P(0.50, 0.50), P(0.50, 0.94))
    elif nom == "engrenage":
        import math
        p.drawEllipse(P(0.50, 0.50), l * 0.16, h * 0.16)
        p.drawEllipse(P(0.50, 0.50), l * 0.34, h * 0.34)
        for i in range(6):
            a = math.radians(i * 60)
            p.drawLine(QPointF(x + l * (0.5 + 0.34 * math.cos(a)),
                               y + h * (0.5 + 0.34 * math.sin(a))),
                       QPointF(x + l * (0.5 + 0.46 * math.cos(a)),
                               y + h * (0.5 + 0.46 * math.sin(a))))
    elif nom == "invite":
        p.drawPolyline([P(0.16, 0.28), P(0.44, 0.50), P(0.16, 0.72)])
        p.drawLine(P(0.52, 0.74), P(0.86, 0.74))
    elif nom == "python":
        p.drawArc(QRectF(x + l * 0.16, y + h * 0.08, l * 0.68, h * 0.50),
                  0, 180 * 16)
        p.drawArc(QRectF(x + l * 0.16, y + h * 0.42, l * 0.68, h * 0.50),
                  180 * 16, 180 * 16)
        p.drawLine(P(0.16, 0.33), P(0.50, 0.33))
        p.drawLine(P(0.50, 0.67), P(0.84, 0.67))
    elif nom == "dossier":
        p.drawPolygon([P(0.06, 0.22), P(0.42, 0.22), P(0.52, 0.36),
                       P(0.94, 0.36), P(0.94, 0.82), P(0.06, 0.82)])
    else:
        p.drawRoundedRect(QRectF(x + l * 0.14, y + h * 0.06,
                                 l * 0.72, h * 0.88), l * 0.08, l * 0.08)


def icone_fichier(nom_fichier: str, taille: int = 40,
                  dossier: bool = False) -> QIcon:
    """L'icône d'un fichier d'après son nom. Ne lit JAMAIS le fichier.

    Deux rendus selon la place disponible, et c'est une décision, pas une
    approximation : en dessous de 30 px, le bandeau d'extension serait
    illisible — trois lettres dans six pixels de haut donnent une bouillie
    grise qui salit la liste. On garde alors le symbole seul, qui reste
    reconnaissable. Au-dessus, le bandeau apparaît.
    """
    if dossier:
        cle, etiquette = "dossier", ""
    else:
        cle, etiquette = famille_fichier(nom_fichier)
    couleur, glyphe = _FAMILLES.get(cle, _FAMILLES["inconnu"])

    pix = QPixmap(taille, taille)
    pix.fill(Qt.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.Antialiasing, True)
    p.setRenderHint(QPainter.TextAntialiasing, True)
    p.scale(taille / 64.0, taille / 64.0)

    grand = taille >= 30
    corps = QRectF(4, 2, 56, 60)
    rayon = 9.0

    #  Le corps, avec un dégradé vertical léger — la planche d'Alex en a un,
    #  et sans lui les icônes paraissent plates à côté du reste du thème.
    from PySide6.QtGui import QLinearGradient
    degrade = QLinearGradient(corps.topLeft(), corps.bottomLeft())
    degrade.setColorAt(0.0, _teinte(couleur, 1.18))
    degrade.setColorAt(1.0, _teinte(couleur, 0.88))
    p.setPen(Qt.NoPen)
    p.setBrush(degrade)
    p.drawRoundedRect(corps, rayon, rayon)

    #  Le coin replié, en haut à droite.
    pli = QPainterPath()
    pli.moveTo(60 - 16, 2)
    pli.lineTo(60, 2 + 16)
    pli.lineTo(60, 2 + rayon)
    pli.quadTo(60, 2, 60 - rayon, 2)
    pli.closeSubpath()
    p.setBrush(_teinte(couleur, 0.66))
    p.drawPath(pli)

    #  Le symbole. Il monte un peu quand le bandeau prend le bas.
    zone = QRectF(17, 13, 30, 30) if grand else QRectF(15, 16, 34, 34)
    _glyphe(glyphe, p, zone)

    if grand and etiquette:
        bande = QRectF(4, 45, 56, 17)
        chemin = QPainterPath()
        chemin.addRoundedRect(bande, rayon * 0.7, rayon * 0.7)
        p.setPen(Qt.NoPen)
        p.setBrush(_teinte(couleur, 0.52))
        p.drawPath(chemin)
        #  L'étiquette rétrécit si elle est longue (« FLATPAKREF », « TAR.GZ »)
        #  plutôt que de déborder du bandeau.
        texte = etiquette[:9]
        f = QFont()
        f.setBold(True)
        f.setPointSizeF(11.0 if len(texte) <= 4 else
                        (9.0 if len(texte) <= 6 else 7.0))
        p.setFont(f)
        p.setPen(QColor("#FFFFFF"))
        p.drawText(bande, Qt.AlignCenter, texte)

    p.end()
    return QIcon(pix)


# ══ Tuiles d'OUTILS ══════════════════════════════════════════════════════
#  D'APRÈS LA SECONDE PLANCHE D'ALEX : carré sombre, symbole orange, un
#  halo discret. Même principe que partout — tracées, donc jamais absentes.
FOND_TUILE = "#14161A"


def _dessiner_outil(nom: str, p: QPainter, r: QRectF) -> None:
    """Les symboles propres aux tuiles d'outils, dans un carré 24×24
    ramené au rectangle r. Ceux qui existent déjà ailleurs (menu, types de
    fichiers) sont réutilisés par icone_outil() plutôt que redessinés."""
    x, y, l, h = r.x(), r.y(), r.width(), r.height()

    def P(fx, fy):
        return QPointF(x + l * fx, y + h * fy)

    if nom == "maison":
        p.drawPolyline([P(0.08, 0.46), P(0.50, 0.10), P(0.92, 0.46)])
        p.drawPolyline([P(0.20, 0.40), P(0.20, 0.88), P(0.80, 0.88),
                        P(0.80, 0.40)])
        p.drawRect(QRectF(x + l * 0.41, y + h * 0.58, l * 0.18, h * 0.30))
    elif nom == "enveloppe":
        p.drawRoundedRect(QRectF(x + l * 0.06, y + h * 0.20, l * 0.88,
                                 h * 0.58), l * 0.06, l * 0.06)
        p.drawPolyline([P(0.06, 0.24), P(0.50, 0.56), P(0.94, 0.24)])
    elif nom == "sacoche":
        p.drawRoundedRect(QRectF(x + l * 0.08, y + h * 0.32, l * 0.84,
                                 h * 0.56), l * 0.07, l * 0.07)
        p.drawPolyline([P(0.34, 0.32), P(0.34, 0.16), P(0.66, 0.16),
                        P(0.66, 0.32)])
        p.drawLine(P(0.42, 0.66), P(0.58, 0.66))
        p.drawPolyline([P(0.50, 0.48), P(0.42, 0.62), P(0.58, 0.62)])
    elif nom == "corbeille":
        p.drawPolyline([P(0.20, 0.26), P(0.26, 0.90), P(0.74, 0.90),
                        P(0.80, 0.26)])
        p.drawLine(P(0.10, 0.26), P(0.90, 0.26))
        p.drawPolyline([P(0.38, 0.26), P(0.38, 0.12), P(0.62, 0.12),
                        P(0.62, 0.26)])
        for f in (0.40, 0.55, 0.70):
            p.drawLine(QPointF(x + l * f, y + h * 0.38),
                       QPointF(x + l * (f + 0.02), y + h * 0.80))
    elif nom == "globe":
        p.drawEllipse(P(0.50, 0.50), l * 0.42, h * 0.42)
        p.drawEllipse(P(0.50, 0.50), l * 0.17, h * 0.42)
        p.drawLine(P(0.08, 0.50), P(0.92, 0.50))
        p.drawArc(QRectF(x + l * 0.08, y + h * 0.14, l * 0.84, h * 0.50),
                  200 * 16, 140 * 16)
    elif nom == "disque-dur":
        p.drawRoundedRect(QRectF(x + l * 0.06, y + h * 0.26, l * 0.88,
                                 h * 0.48), l * 0.08, l * 0.08)
        p.drawEllipse(P(0.78, 0.50), l * 0.06, h * 0.06)
        p.drawLine(P(0.16, 0.50), P(0.60, 0.50))
    elif nom == "usb":
        p.drawRoundedRect(QRectF(x + l * 0.34, y + h * 0.30, l * 0.32,
                                 h * 0.62), l * 0.06, l * 0.06)
        p.drawRect(QRectF(x + l * 0.42, y + h * 0.10, l * 0.16, h * 0.20))
        p.drawLine(P(0.42, 0.46), P(0.58, 0.46))
        p.drawLine(P(0.42, 0.58), P(0.58, 0.58))
    elif nom == "camera":
        p.drawRoundedRect(QRectF(x + l * 0.06, y + h * 0.28, l * 0.88,
                                 h * 0.56), l * 0.08, l * 0.08)
        p.drawPolyline([P(0.34, 0.28), P(0.40, 0.16), P(0.60, 0.16),
                        P(0.66, 0.28)])
        p.drawEllipse(P(0.50, 0.56), l * 0.16, h * 0.16)
    elif nom == "telechargement":
        p.drawLine(P(0.50, 0.10), P(0.50, 0.60))
        p.drawPolyline([P(0.30, 0.42), P(0.50, 0.62), P(0.70, 0.42)])
        p.drawPolyline([P(0.14, 0.72), P(0.14, 0.88), P(0.86, 0.88),
                        P(0.86, 0.72)])
    elif nom == "nuage":
        p.drawArc(QRectF(x + l * 0.10, y + h * 0.34, l * 0.44, h * 0.48),
                  60 * 16, 200 * 16)
        p.drawArc(QRectF(x + l * 0.34, y + h * 0.20, l * 0.44, h * 0.52),
                  0, 200 * 16)
        p.drawLine(P(0.22, 0.78), P(0.80, 0.78))
        p.drawArc(QRectF(x + l * 0.58, y + h * 0.42, l * 0.34, h * 0.38),
                  270 * 16, 160 * 16)
    elif nom == "pinceau":
        p.drawPolygon([P(0.68, 0.10), P(0.90, 0.30), P(0.44, 0.72),
                       P(0.26, 0.56)])
        p.drawPolyline([P(0.26, 0.58), P(0.16, 0.84), P(0.42, 0.74)])
    elif nom == "manette":
        p.drawRoundedRect(QRectF(x + l * 0.06, y + h * 0.32, l * 0.88,
                                 h * 0.42), h * 0.21, h * 0.21)
        p.drawLine(P(0.24, 0.44), P(0.24, 0.62))
        p.drawLine(P(0.15, 0.53), P(0.33, 0.53))
        p.drawEllipse(P(0.70, 0.46), l * 0.05, h * 0.05)
        p.drawEllipse(P(0.80, 0.58), l * 0.05, h * 0.05)
    elif nom == "calculatrice":
        p.drawRoundedRect(QRectF(x + l * 0.18, y + h * 0.08, l * 0.64,
                                 h * 0.84), l * 0.07, l * 0.07)
        p.drawRect(QRectF(x + l * 0.28, y + h * 0.18, l * 0.44, h * 0.16))
        for fy in (0.50, 0.66, 0.82):
            for fx in (0.32, 0.50, 0.68):
                p.drawPoint(P(fx, fy))
                p.drawEllipse(P(fx, fy), l * 0.028, h * 0.028)
    elif nom == "calendrier":
        p.drawRoundedRect(QRectF(x + l * 0.08, y + h * 0.18, l * 0.84,
                                 h * 0.72), l * 0.07, l * 0.07)
        p.drawLine(P(0.08, 0.40), P(0.92, 0.40))
        p.drawLine(P(0.30, 0.08), P(0.30, 0.26))
        p.drawLine(P(0.70, 0.08), P(0.70, 0.26))
        for fy in (0.56, 0.74):
            for fx in (0.28, 0.50, 0.72):
                p.drawEllipse(P(fx, fy), l * 0.035, h * 0.035)
    elif nom == "imprimante":
        p.drawPolyline([P(0.24, 0.34), P(0.24, 0.10), P(0.76, 0.10),
                        P(0.76, 0.34)])
        p.drawRoundedRect(QRectF(x + l * 0.06, y + h * 0.34, l * 0.88,
                                 h * 0.34), l * 0.06, l * 0.06)
        p.drawRect(QRectF(x + l * 0.24, y + h * 0.64, l * 0.52, h * 0.26))
        p.drawEllipse(P(0.82, 0.46), l * 0.035, h * 0.035)
    elif nom == "bouee":
        p.drawEllipse(P(0.50, 0.50), l * 0.42, h * 0.42)
        p.drawEllipse(P(0.50, 0.50), l * 0.18, h * 0.18)
        import math
        for i in range(4):
            a = math.radians(45 + i * 90)
            p.drawLine(QPointF(x + l * (0.5 + 0.18 * math.cos(a)),
                               y + h * (0.5 + 0.18 * math.sin(a))),
                       QPointF(x + l * (0.5 + 0.42 * math.cos(a)),
                               y + h * (0.5 + 0.42 * math.sin(a))))
    elif nom == "virtualisation":
        p.drawRoundedRect(QRectF(x + l * 0.06, y + h * 0.14, l * 0.60,
                                 h * 0.52), l * 0.06, l * 0.06)
        p.drawRoundedRect(QRectF(x + l * 0.34, y + h * 0.38, l * 0.60,
                                 h * 0.52), l * 0.06, l * 0.06)
    elif nom == "conteneurs":
        for fx, fy in ((0.10, 0.54), (0.38, 0.54), (0.66, 0.54),
                       (0.38, 0.28), (0.66, 0.28)):
            p.drawRect(QRectF(x + l * fx, y + h * fy, l * 0.22, h * 0.20))
        p.drawArc(QRectF(x + l * 0.04, y + h * 0.74, l * 0.92, h * 0.28),
                  200 * 16, 140 * 16)
    elif nom == "base":
        p.drawEllipse(QRectF(x + l * 0.12, y + h * 0.10, l * 0.76, h * 0.24))
        p.drawLine(P(0.12, 0.22), P(0.12, 0.78))
        p.drawLine(P(0.88, 0.22), P(0.88, 0.78))
        p.drawArc(QRectF(x + l * 0.12, y + h * 0.32, l * 0.76, h * 0.24),
                  180 * 16, 180 * 16)
        p.drawArc(QRectF(x + l * 0.12, y + h * 0.66, l * 0.76, h * 0.24),
                  180 * 16, 180 * 16)
    elif nom == "cles":
        p.drawLine(P(0.14, 0.86), P(0.60, 0.40))
        p.drawPolyline([P(0.54, 0.28), P(0.72, 0.10), P(0.90, 0.28),
                        P(0.72, 0.46), P(0.54, 0.28)])
        p.drawLine(P(0.86, 0.86), P(0.52, 0.52))
        p.drawPolyline([P(0.10, 0.22), P(0.22, 0.10), P(0.40, 0.28)])
    elif nom == "vpn":
        p.drawEllipse(P(0.42, 0.46), l * 0.34, h * 0.34)
        p.drawLine(P(0.08, 0.46), P(0.76, 0.46))
        p.drawEllipse(P(0.42, 0.46), l * 0.14, h * 0.34)
        p.drawRoundedRect(QRectF(x + l * 0.60, y + h * 0.60, l * 0.34,
                                 h * 0.30), l * 0.05, l * 0.05)
        p.drawArc(QRectF(x + l * 0.67, y + h * 0.46, l * 0.20, h * 0.28),
                  0, 180 * 16)
    elif nom == "journal":
        p.drawRoundedRect(QRectF(x + l * 0.12, y + h * 0.08, l * 0.76,
                                 h * 0.84), l * 0.06, l * 0.06)
        for fy in (0.28, 0.44, 0.60, 0.76):
            p.drawEllipse(P(0.26, fy), l * 0.03, h * 0.03)
            p.drawLine(P(0.36, fy), P(0.76 if fy != 0.76 else 0.58, fy))
    elif nom == "cle":
        p.drawEllipse(P(0.30, 0.30), l * 0.20, h * 0.20)
        p.drawLine(P(0.44, 0.44), P(0.88, 0.88))
        p.drawLine(P(0.72, 0.72), P(0.60, 0.84))
        p.drawLine(P(0.82, 0.82), P(0.70, 0.94))
    elif nom == "personnes":
        p.drawEllipse(P(0.36, 0.30), l * 0.17, h * 0.17)
        p.drawArc(QRectF(x + l * 0.10, y + h * 0.52, l * 0.52, h * 0.56),
                  0, 180 * 16)
        p.drawArc(QRectF(x + l * 0.54, y + h * 0.14, l * 0.30, h * 0.30),
                  270 * 16, 250 * 16)
        p.drawArc(QRectF(x + l * 0.50, y + h * 0.52, l * 0.46, h * 0.56),
                  0, 120 * 16)
    elif nom == "langues":
        p.drawPolyline([P(0.08, 0.46), P(0.26, 0.10), P(0.44, 0.46)])
        p.drawLine(P(0.14, 0.34), P(0.38, 0.34))
        p.drawRect(QRectF(x + l * 0.50, y + h * 0.52, l * 0.42, h * 0.40))
        p.drawLine(P(0.58, 0.62), P(0.84, 0.62))
        p.drawLine(P(0.71, 0.62), P(0.71, 0.84))
        p.drawArc(QRectF(x + l * 0.56, y + h * 0.64, l * 0.30, h * 0.24),
                  200 * 16, 140 * 16)
    elif nom == "alimentation":
        p.drawArc(QRectF(x + l * 0.14, y + h * 0.18, l * 0.72, h * 0.72),
                  300 * 16, 300 * 16)
        p.drawLine(P(0.50, 0.08), P(0.50, 0.46))
    elif nom == "redemarrer":
        p.drawArc(QRectF(x + l * 0.12, y + h * 0.12, l * 0.76, h * 0.76),
                  40 * 16, 280 * 16)
        p.drawPolyline([P(0.66, 0.06), P(0.92, 0.22), P(0.66, 0.34)])
    elif nom == "sortie":
        p.drawPolyline([P(0.54, 0.10), P(0.12, 0.10), P(0.12, 0.90),
                        P(0.54, 0.90)])
        p.drawLine(P(0.40, 0.50), P(0.90, 0.50))
        p.drawPolyline([P(0.72, 0.32), P(0.90, 0.50), P(0.72, 0.68)])
    else:
        _dessiner(nom, p, TEXTE)   # repli sur les symboles du menu


#  Les symboles déjà écrits ailleurs, réutilisés plutôt que redessinés.
_OUTIL_DEPUIS_MENU = {"fichiers", "terminal", "parametres", "navigateur",
                      "securite", "developpement", "systeme", "apparence",
                      "performances", "reseau", "stockage", "applications",
                      "services", "maj", "accueil", "apropos", "gpu",
                      "processeur", "memoire", "son", "affichage"}
_OUTIL_DEPUIS_TYPES = {"image", "video", "audio", "texte", "archive",
                       "disque"}
_TYPE_ALIAS = {"cube": "paquet"}


def icone_outil(nom: str, taille: int = 56, actif: bool = True) -> QIcon:
    """Une tuile d'outil : carré sombre, symbole orange, halo discret.

    `actif=False` grise la tuile — c'est ce que voit un outil non installé.
    On ne la CACHE pas : savoir qu'un outil existe mais n'est pas là vaut
    mieux que ne rien savoir, et l'infobulle dit ce qui manque.
    """
    pix = QPixmap(taille, taille)
    pix.fill(Qt.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.Antialiasing, True)
    p.scale(taille / 64.0, taille / 64.0)

    accent = QColor(ORANGE) if actif else QColor(TEXTE_FAIBLE)
    #  Le fond de la tuile, puis un liseré de l'accent.
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(FOND_TUILE))
    p.drawRoundedRect(QRectF(2, 2, 60, 60), 13, 13)
    liseré = QPen(QColor(accent))
    liseré.setWidthF(1.3)
    p.setPen(liseré)
    p.setBrush(Qt.NoBrush)
    p.setOpacity(0.55 if actif else 0.30)
    p.drawRoundedRect(QRectF(2.6, 2.6, 58.8, 58.8), 12.5, 12.5)
    p.setOpacity(1.0)

    stylo = QPen(accent)
    stylo.setWidthF(2.4)
    stylo.setCapStyle(Qt.RoundCap)
    stylo.setJoinStyle(Qt.RoundJoin)
    p.setPen(stylo)
    p.setBrush(Qt.NoBrush)
    zone = QRectF(17, 17, 30, 30)
    if nom in _OUTIL_DEPUIS_MENU:
        p.save()
        p.translate(zone.x(), zone.y())
        p.scale(zone.width() / 24.0, zone.height() / 24.0)
        _dessiner(nom, p, accent.name())
        p.restore()
    elif nom in _OUTIL_DEPUIS_TYPES or nom in _TYPE_ALIAS:
        p.save()
        _glyphe(_TYPE_ALIAS.get(nom, nom), p, zone, accent.name())
        p.restore()
    else:
        _dessiner_outil(nom, p, zone)
    p.end()
    return QIcon(pix)
