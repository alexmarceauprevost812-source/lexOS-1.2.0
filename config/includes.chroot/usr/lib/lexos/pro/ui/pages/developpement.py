"""Développement — projets, Git en lecture seule, tests sur demande.

L'AVERTISSEMENT EST À L'ÉCRAN, pas seulement dans le code : lancer les
tests d'un projet exécute son code. Ouvrir un dossier ne les déclenche
jamais, et le bouton le dit.
"""
from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import (QFileDialog, QHBoxLayout, QInputDialog,
                               QListWidget, QListWidgetItem, QMessageBox,
                               QPlainTextEdit, QWidget)

from ...services import prefs, projets, terminal
from ...services import execution
from .. import theme, widgets

_ROLE = 256


class PageDeveloppement(widgets.Page):
    def __init__(self, parent=None):
        super().__init__(
            "Développement",
            "Vos dossiers de projet. Git est consulté en LECTURE SEULE : "
            "aucun commit, aucun envoi, aucun changement de branche.", parent)
        self._prefs = prefs.charger()

        haut = QWidget(); d = QHBoxLayout(haut)
        d.setContentsMargins(0, 0, 0, 0)
        for libelle, fonction, ic in (
                ("Ajouter un dossier existant", self._ajouter, "fichiers"),
                ("Créer un nouveau dossier de projet", self._creer,
                 "applications"),
                ("Retirer de la liste", self._retirer, "retour")):
            b = widgets.bouton(libelle, ic)
            b.clicked.connect(fonction)
            d.addWidget(b)
        d.addStretch(1)
        self.disposition.addWidget(haut)

        self.liste = QListWidget()
        self.liste.setMinimumHeight(140)
        self.liste.currentItemChanged.connect(lambda *_: self._decrire())
        self.disposition.addWidget(self.liste)

        self.carte = widgets.Carte("Projet sélectionné", "developpement")
        self.carte.jauge.hide(); self.carte.courbe.hide()
        self.disposition.addWidget(self.carte)

        actions = QWidget(); da = QHBoxLayout(actions)
        da.setContentsMargins(0, 0, 0, 0)
        self.b_editeur = widgets.bouton("Ouvrir dans l'éditeur", "developpement")
        self.b_editeur.clicked.connect(self._editeur)
        self.b_terminal = widgets.bouton("Ouvrir un terminal ici", "terminal")
        self.b_terminal.clicked.connect(self._terminal)
        self.b_venv = widgets.bouton("Créer un environnement Python (.venv)",
                                     "processeur")
        self.b_venv.clicked.connect(self._venv)
        self.b_tests = widgets.bouton("Lancer les tests du projet",
                                      "performances", principal=True)
        self.b_tests.clicked.connect(self._tests)
        for b in (self.b_editeur, self.b_terminal, self.b_venv, self.b_tests):
            da.addWidget(b)
        da.addStretch(1)
        self.disposition.addWidget(actions)

        self.sortie = QPlainTextEdit()
        self.sortie.setReadOnly(True)
        self.sortie.setMinimumHeight(190)
        self.sortie.setPlaceholderText(
            "La sortie des tests s'affichera ici. Les tests ne sont jamais "
            "lancés automatiquement.")
        self.disposition.addWidget(widgets.titre_section("Résultat des tests"))
        self.disposition.addWidget(self.sortie)

    # ------------------------------------------------------------------
    def rafraichir(self):
        courant = self._chemin()
        self.liste.clear()
        for chemin in self._prefs.get("projets", []):
            item = QListWidgetItem(chemin)
            item.setData(_ROLE, chemin)
            if not Path(chemin).is_dir():
                item.setText(chemin + "   (dossier introuvable)")
                item.setToolTip("Ce dossier n'existe plus sur le disque.")
            self.liste.addItem(item)
            if chemin == courant:
                self.liste.setCurrentItem(item)
        o = projets.outils()
        self.statut.neutre(
            " · ".join(f"{n} : {v['version'] or v['raison']}"
                       for n, v in o.items()))
        self._decrire()

    def _chemin(self):
        item = self.liste.currentItem()
        return item.data(_ROLE) if item else None

    def _decrire(self):
        chemin = self._chemin()
        boutons = (self.b_editeur, self.b_terminal, self.b_venv, self.b_tests)
        if not chemin or not Path(chemin).is_dir():
            self.carte.montrer("Aucun projet",
                               "Ajoutez un dossier existant ou créez-en un.")
            for b in boutons:
                widgets.eteindre(b, "Aucun projet sélectionné.")
            return
        for b in boutons:
            b.setEnabled(True)
            b.setToolTip("")
        g = projets.etat_git(chemin)
        py = projets.python_du_projet(chemin)
        t = projets.commande_tests(chemin)
        lignes = [Path(chemin).name]
        detail = [chemin]
        detail.append("Git : " + (
            f"branche {g['branche']}, {g['modifies']} fichier(s) modifié(s)"
            if g["trouve"] else g["raison"]))
        detail.append("Environnement Python : " + (
            py["chemin"] if py["trouve"] else py["raison"]))
        detail.append("Tests : " + (
            t["libelle"] if t["trouve"] else t["raison"]))
        self.carte.montrer(lignes[0], "\n".join(detail))
        if py["trouve"]:
            widgets.eteindre(self.b_venv,
                             f"Un environnement existe déjà : {py['chemin']}")
        if not t["trouve"]:
            widgets.eteindre(self.b_tests, t["raison"])
        else:
            self.b_tests.setToolTip(
                f"Lancera « {t['libelle']} ». ATTENTION : cela exécute le "
                f"code de ce projet.")

    # ------------------------------------------------------------------
    def _enregistrer(self):
        if not prefs.enregistrer(self._prefs):
            self.statut.echec("La liste des projets n'a pas pu être écrite.")

    def _ajouter(self):
        d = QFileDialog.getExistingDirectory(self, "Ajouter un projet",
                                             str(Path.home()))
        if not d:
            return
        if d in self._prefs.get("projets", []):
            self.statut.attention("Ce dossier est déjà dans la liste.")
            return
        self._prefs.setdefault("projets", []).append(d)
        self._enregistrer()
        self.statut.succes(f"Projet ajouté : {d}")
        self.rafraichir()

    def _creer(self):
        parent = QFileDialog.getExistingDirectory(
            self, "Où créer le projet ?", str(Path.home()))
        if not parent:
            return
        nom, ok = QInputDialog.getText(self, "Nouveau projet",
                                       "Nom du dossier de projet :")
        if not ok or not nom.strip():
            return
        from ...services import fichiers as sf
        r = sf.creer_dossier(parent, nom.strip())
        if not self.afficher_resultat(r, f"Projet créé : {r.sortie}"):
            return
        self._prefs.setdefault("projets", []).append(r.sortie)
        self._enregistrer()
        self.rafraichir()

    def _retirer(self):
        chemin = self._chemin()
        if not chemin:
            self.statut.attention("Aucun projet sélectionné.")
            return
        self._prefs["projets"] = [p for p in self._prefs.get("projets", [])
                                  if p != chemin]
        self._enregistrer()
        self.statut.succes("Projet retiré de la liste. "
                           "Le dossier n'a PAS été supprimé du disque.")
        self.rafraichir()

    def _editeur(self):
        chemin = self._chemin()
        from ...services import capacites
        editeur = capacites.premier_present(capacites.EDITEURS)
        if not editeur:
            self.statut.echec(
                "Aucun éditeur connu n'est installé (code, kate, gedit, "
                "mousepad, vim…).")
            return
        self.afficher_resultat(execution.lancer_detache([editeur, chemin]),
                               f"{editeur} lancé sur {chemin}.")

    def _terminal(self):
        self.afficher_resultat(terminal.ouvrir(self._chemin()),
                               "Terminal ouvert dans le projet.")

    def _venv(self):
        chemin = self._chemin()
        if QMessageBox.question(
                self, "Créer un environnement Python",
                f"Créer « .venv » dans {chemin} ?\n\n"
                f"Cela peut prendre une minute.") != QMessageBox.Yes:
            return
        self.statut.occupe("Création de l'environnement en cours…")
        widgets.en_fond(self, projets.creer_venv,
                        lambda r: (self.afficher_resultat(
                            r, "Environnement « .venv » créé."),
                            self.rafraichir()),
                        lambda m: self.statut.echec(m), chemin)

    def _tests(self):
        chemin = self._chemin()
        cmd = projets.commande_tests(chemin)
        if not cmd["trouve"]:
            self.statut.echec(cmd["raison"])
            return
        if QMessageBox.warning(
                self, "Lancer les tests",
                f"LEXOS PRO va lancer « {cmd['libelle']} » dans :\n{chemin}\n\n"
                f"ATTENTION : lancer des tests EXÉCUTE LE CODE de ce projet. "
                f"Ne le faites que sur un projet dont vous connaissez "
                f"l'origine.\n\nContinuer ?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No) != QMessageBox.Yes:
            self.statut.neutre("Tests annulés.")
            return
        self.sortie.setPlainText(f"$ {' '.join(cmd['argv'])}\n")
        self.statut.occupe(f"« {cmd['libelle']} » en cours…")
        widgets.en_fond(self, projets.lancer_tests, self._tests_finis,
                        lambda m: self.statut.echec(m), chemin)

    def _tests_finis(self, r):
        self.sortie.setPlainText(
            self.sortie.toPlainText() + (r.sortie or r.erreur or
                                         "(aucune sortie)"))
        if r.ok:
            self.statut.succes("Tests terminés sans erreur.")
        else:
            self.statut.echec(f"Tests en échec : {r.erreur}")
