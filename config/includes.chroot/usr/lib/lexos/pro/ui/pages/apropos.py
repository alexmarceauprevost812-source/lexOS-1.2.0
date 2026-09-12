"""À propos — version réelle, dépendances, diagnostic exportable.

AUCUNE LICENCE INVENTÉE. On cherche un fichier de licence dans le dépôt ;
s'il n'y en a pas, on écrit « à définir » — pas « MIT », pas « GPL ».
"""
from __future__ import annotations

import platform
import sys
from pathlib import Path

from PySide6.QtWidgets import (QFileDialog, QHBoxLayout, QPlainTextEdit,
                               QWidget)

from ... import version as v
from ...services import capacites, systeme
from .. import widgets

_FICHIERS_LICENCE = ("LICENSE", "LICENSE.md", "LICENCE", "LICENCE.md",
                     "COPYING", "COPYING.md")


def _licence() -> str:
    racine = Path(__file__).resolve().parents[6]
    for nom in _FICHIERS_LICENCE:
        chemin = racine / nom
        if chemin.is_file():
            premiere = ""
            try:
                for ligne in chemin.read_text(encoding="utf-8",
                                              errors="replace").splitlines():
                    if ligne.strip():
                        premiere = ligne.strip()
                        break
            except OSError:
                pass
            return f"{nom} — {premiere}" if premiere else nom
    return ("à définir : aucun fichier de licence n'a été trouvé à la "
            "racine du dépôt.")


class PageApropos(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "À propos",
            "Version réellement installée, dépendances mesurées, et export "
            "du diagnostic.", parent)

        self.carte = widgets.Carte("LEXOS PRO", "apropos")
        self.carte.jauge.hide(); self.carte.courbe.hide()
        self.disposition.addWidget(self.carte)

        self.texte = QPlainTextEdit()
        self.texte.setReadOnly(True)
        self.texte.setMinimumHeight(280)
        self.disposition.addWidget(widgets.titre_section("Diagnostic"))
        self.disposition.addWidget(self.texte)

        barre = QWidget(); d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        b1 = widgets.bouton("Copier le diagnostic", "apropos")
        b1.clicked.connect(self._copier)
        b2 = widgets.bouton("Enregistrer dans un fichier…", "stockage")
        b2.clicked.connect(self._enregistrer)
        d.addWidget(b1); d.addWidget(b2); d.addStretch(1)
        self.disposition.addWidget(barre)
        self.disposition.addStretch(1)

    def rafraichir(self):
        self.carte.montrer(
            f"{v.NOM} {v.version()}",
            f"Licence : {_licence()}\n"
            f"Python {platform.python_version()} · "
            f"PySide6 {self._pyside()}\n"
            + ("Lancé depuis les sources du dépôt."
               if v.depuis_les_sources() else
               "Lancé depuis le système installé."))
        self.texte.setPlainText(self._diagnostic())

    @staticmethod
    def _pyside() -> str:
        try:
            import PySide6
            return PySide6.__version__
        except Exception:                              # noqa: BLE001
            return "indisponible"

    def _diagnostic(self) -> str:
        i = systeme.infos()
        r = capacites.resume()
        lignes = [
            f"{v.NOM} {v.version()}",
            f"Licence : {_licence()}",
            "",
            "— Machine —",
            f"Nom            : {i['machine']}",
            f"Distribution   : {i['distribution']} (id « {i['distribution_id']} », "
            f"familles : {i['familles']})",
            f"Noyau          : {i['noyau']}",
            f"Architecture   : {i['architecture']}",
            f"Processeur     : {i['processeur']}",
            f"Cœurs          : {i['coeurs_logiques']} logiques, "
            f"{i['coeurs_physiques']} physiques",
            f"Session        : {i['session']['type']} "
            f"(bureau : {i['session']['bureau'] or 'non déclaré'})",
            f"LexOS détecté  : {'oui' if i['lexos'] else 'non'}",
            "",
            "— Environnement Python —",
            f"Interpréteur   : {sys.executable}",
            f"Version        : {platform.python_version()}",
            f"PySide6        : {self._pyside()}",
            "",
            "— Capacités détectées —",
            f"Gestionnaire de paquets : "
            f"{r['paquets']['nom'] or r['paquets'].get('raison', '')}",
            f"systemd        : {'oui' if r['systemd']['present'] else r['systemd']['raison']}",
            f"Audio          : {r['audio'].get('pile') or r['audio'].get('raison')}",
            f"Réseau         : {r['reseau'].get('nom') or r['reseau'].get('raison')}",
            f"Terminaux      : {', '.join(r['terminaux']) or 'aucun'}",
            f"Éditeurs       : {', '.join(r['editeurs']) or 'aucun'}",
            f"Gestionnaire de fichiers : {r['fichiers'] or 'aucun'}",
            f"Logithèque     : {r['logitheque'] or 'aucune'}",
            "",
            "— Outils externes —",
        ]
        for nom, present in sorted(r["outils"].items()):
            lignes.append(f"{nom:<15}: {'présent' if present else 'absent'}")
        lignes += ["", "— Volumes —"]
        from ...services import disques
        for vol in disques.volumes():
            if vol.mesure:
                lignes.append(
                    f"{vol.point:<22} {vol.systeme:<10} "
                    f"{systeme.octets_lisibles(vol.utilise)} / "
                    f"{systeme.octets_lisibles(vol.total)}")
            else:
                lignes.append(f"{vol.point:<22} {vol.systeme:<10} {vol.raison}")
        return "\n".join(lignes)

    def _copier(self):
        from PySide6.QtWidgets import QApplication
        QApplication.clipboard().setText(self.texte.toPlainText())
        self.statut.succes("Diagnostic copié dans le presse-papiers.")

    def _enregistrer(self):
        chemin, _ = QFileDialog.getSaveFileName(
            self, "Enregistrer le diagnostic",
            str(Path.home() / "lexos-pro-diagnostic.txt"),
            "Fichier texte (*.txt)")
        if not chemin:
            return
        try:
            Path(chemin).write_text(self.texte.toPlainText(), encoding="utf-8")
        except OSError as e:
            self.statut.echec(f"Écriture impossible : {e.strerror or e}")
            return
        self.statut.succes(f"Diagnostic enregistré dans {chemin}.")
