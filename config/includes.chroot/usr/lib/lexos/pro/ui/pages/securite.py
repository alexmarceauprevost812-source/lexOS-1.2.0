"""Sécurité — diagnostic défensif, jamais un verdict.

La page n'affiche JAMAIS « système sécurisé ». Elle compte les points
qu'elle a pu vérifier et le dit ainsi, avec un avertissement permanent :
quatre contrôles réussis ne disent rien des mots de passe, des permissions
ou de ce qui tourne dans le navigateur.
"""
from __future__ import annotations

from PySide6.QtGui import QColor
from PySide6.QtWidgets import QPlainTextEdit, QTreeWidget, QTreeWidgetItem

from ...services import securite as svc
from .. import theme, widgets


class PageSecurite(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "Sécurité",
            "Constat défensif sur cette machine. Aucun balayage, aucune "
            "tentative, aucune modification de pare-feu : uniquement la "
            "lecture de ce qui est accessible.", parent)

        self.resume = widgets.Carte("Points vérifiés", "securite")
        self.resume.jauge.hide(); self.resume.courbe.hide()
        self.disposition.addWidget(self.resume)

        self.details = QTreeWidget()
        self.details.setHeaderLabels(["Contrôle", "État", "Détail"])
        self.details.setColumnWidth(0, 190)
        self.details.setColumnWidth(1, 150)
        self.details.setMinimumHeight(190)
        self.disposition.addWidget(self.details)

        self.ports = QTreeWidget()
        self.ports.setHeaderLabels(["Protocole", "Adresse locale", "Processus"])
        self.ports.setColumnWidth(0, 100)
        self.ports.setColumnWidth(1, 230)
        self.ports.setMinimumHeight(170)
        self.disposition.addWidget(widgets.titre_section("Ports en écoute"))
        self.disposition.addWidget(self.ports)

        self.journal = QPlainTextEdit()
        self.journal.setReadOnly(True)
        self.journal.setMinimumHeight(160)
        self.disposition.addWidget(
            widgets.titre_section("Journaux accessibles (avertissements et plus)"))
        self.disposition.addWidget(self.journal)

        b = widgets.bouton("Relire maintenant", "maj")
        b.clicked.connect(self.rafraichir)
        self.disposition.addWidget(b)

    def rafraichir(self):
        self.statut.occupe("Lecture des points de contrôle…")
        widgets.en_fond(self, svc.synthese, self._pret,
                        lambda m: self.statut.echec(m))

    def _pret(self, r):
        self.resume.montrer(
            f"{r['mesures']} sur {r['total']}",
            r["avertissement"])
        self.resume.valeur.setStyleSheet(
            f"color: {theme.TEXTE}; font-size: 24px; font-weight: 600;")

        self.details.clear()
        for nom, v in r["points"].items():
            if nom == "pare-feu":
                if v.get("mesure"):
                    etat = "Actif" if v.get("actif") else "Inactif"
                    couleur = theme.VERT if v.get("actif") else theme.JAUNE
                    detail = f"{v.get('outil', '')} — {v.get('detail', '')}"
                else:
                    etat, couleur, detail = "Indéterminé", theme.JAUNE, v["raison"]
            elif nom == "Secure Boot":
                if v.get("sans_objet"):
                    etat, couleur, detail = "Sans objet", theme.TEXTE_FAIBLE, v["detail"]
                elif v.get("mesure"):
                    etat = "Actif" if v.get("actif") else "Désactivé"
                    couleur = theme.VERT if v.get("actif") else theme.JAUNE
                    detail = v.get("detail", "")
                else:
                    etat, couleur, detail = "Indéterminé", theme.JAUNE, v["raison"]
            else:
                if v.get("trouve"):
                    etat, couleur = "Lisible", theme.VERT
                    detail = v.get("note") or "Lecture réussie."
                else:
                    etat, couleur, detail = "Indisponible", theme.JAUNE, v["raison"]
            item = QTreeWidgetItem([nom.capitalize(), etat, detail])
            item.setForeground(1, QColor(couleur))
            item.setToolTip(2, detail)
            self.details.addTopLevelItem(item)

        self.ports.clear()
        p = r["points"]["ports en écoute"]
        if p.get("trouve"):
            for e in p["ports"]:
                self.ports.addTopLevelItem(QTreeWidgetItem(
                    [e["protocole"], e["locale"],
                     e["processus"] or "non nommé (droits insuffisants)"]))
            self.statut.neutre(p.get("note") or
                               f"{len(p['ports'])} ports en écoute listés.")
        else:
            self.ports.addTopLevelItem(QTreeWidgetItem(
                ["—", "Indisponible", p["raison"]]))
            self.statut.attention(p["raison"])

        j = r["points"]["journaux"]
        self.journal.setPlainText(
            j["texte"] if j.get("trouve") else "Indisponible — " + j["raison"])
