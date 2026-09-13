"""Le catalogue des outils — aucune tuile ne peut être un faux bouton.

La consigne d'origine l'interdit explicitement : « ne transforme pas
l'image entière en arrière-plan de faux boutons ». Ces contrôles sont la
traduction de cette phrase en code.
"""
import unittest
from unittest import mock

from pro.services import outils


class TestCatalogue(unittest.TestCase):
    def test_toutes_les_entrees_sont_completes(self):
        for o in outils.CATALOGUE:
            with self.subTest(outil=o.cle):
                self.assertTrue(o.libelle, "libellé vide")
                self.assertTrue(o.icone, "icône vide")
                self.assertTrue(o.description, "description vide")
                self.assertIn(o.categorie, outils.CATEGORIES)
                self.assertIn(o.genre, (outils.PAGE, outils.DOSSIER,
                                        outils.COMMANDE, outils.TERMINAL,
                                        outils.SESSION))

    def test_les_cles_sont_uniques(self):
        cles = [o.cle for o in outils.CATALOGUE]
        self.assertEqual(len(cles), len(set(cles)), "clés en double")

    def test_aucune_entree_n_est_orpheline(self):
        """Un genre COMMANDE ou TERMINAL sans candidat ne pourrait JAMAIS
        être disponible : ce serait une tuile morte par construction."""
        for o in outils.CATALOGUE:
            if o.genre in (outils.COMMANDE, outils.TERMINAL):
                with self.subTest(outil=o.cle):
                    self.assertTrue(o.candidats,
                                    "aucun programme candidat")
            if o.genre in (outils.PAGE, outils.DOSSIER, outils.SESSION):
                with self.subTest(outil=o.cle):
                    self.assertTrue(o.cible, "aucune cible")

    def test_chaque_resolution_tranche_et_motive(self):
        """Deux états, jamais trois : soit c'est disponible AVEC une cible
        concrète, soit c'est indisponible AVEC une raison lisible."""
        for o in outils.CATALOGUE:
            r = outils.resoudre(o)
            with self.subTest(outil=o.cle):
                self.assertIn("disponible", r)
                if r["disponible"]:
                    concret = (r.get("page") or r.get("chemin")
                               or r.get("argv"))
                    self.assertTrue(concret,
                                    "disponible mais sans cible concrète")
                    if r.get("argv"):
                        self.assertTrue(all(str(a).strip() for a in r["argv"]),
                                        f"argv troué : {r['argv']}")
                else:
                    self.assertTrue(r.get("raison", "").strip(),
                                    "indisponible sans raison")
                    self.assertGreater(len(r["raison"]), 20,
                                       "raison trop courte pour être utile")

    def test_les_pages_sont_toujours_disponibles(self):
        """Une page de LEXOS PRO ne peut pas manquer : c'est nous."""
        for o in outils.CATALOGUE:
            if o.genre == outils.PAGE:
                self.assertTrue(outils.resoudre(o)["disponible"], o.cle)

    def test_les_actions_de_session_demandent_confirmation(self):
        """Éteindre, redémarrer et fermer la session font perdre du
        travail. Aucune ne doit partir sur un simple clic."""
        session = [o for o in outils.CATALOGUE if o.genre == outils.SESSION]
        self.assertEqual(len(session), 3)
        for o in session:
            with self.subTest(outil=o.cle):
                self.assertTrue(o.confirmation,
                                "action de session sans confirmation")

    def test_seules_les_actions_de_session_confirment(self):
        """L'inverse compte aussi : demander confirmation pour ouvrir une
        calculatrice apprendrait à cliquer « oui » sans lire."""
        for o in outils.CATALOGUE:
            if o.genre != outils.SESSION:
                self.assertFalse(o.confirmation, o.cle)

    def test_aucune_commande_lancee_par_un_shell(self):
        """resoudre() rend une LISTE d'arguments, jamais une chaîne."""
        for o in outils.CATALOGUE:
            r = outils.resoudre(o)
            if r.get("argv") is not None:
                with self.subTest(outil=o.cle):
                    self.assertIsInstance(r["argv"], list)

    def test_un_programme_absent_nomme_ce_qui_a_ete_cherche(self):
        faux = outils.Outil("essai", "Essai", "cube", "Travail",
                            outils.COMMANDE, None, "Un essai.",
                            candidats=["programme-absent-aaa",
                                       "programme-absent-bbb"])
        r = outils.resoudre(faux)
        self.assertFalse(r["disponible"])
        self.assertIn("programme-absent-aaa", r["raison"])
        self.assertIn("programme-absent-bbb", r["raison"])

    def test_le_premier_candidat_installe_gagne(self):
        """L'ordre des candidats est un ordre de PRÉFÉRENCE."""
        faux = outils.Outil("essai", "Essai", "cube", "Travail",
                            outils.COMMANDE, None, "Un essai.",
                            candidats=["absent-xyz", "sh", "bash"])
        outils.capacites.premier_present.cache_clear()
        r = outils.resoudre(faux)
        self.assertTrue(r["disponible"])
        self.assertEqual(r["argv"][0], "sh")

    def test_un_dossier_absent_est_indisponible(self):
        faux = outils.Outil("essai", "Essai", "cube", "Travail",
                            outils.DOSSIER, "XDG_NEXISTE_PAS_DIR",
                            "Un essai.")
        r = outils.resoudre(faux)
        self.assertFalse(r["disponible"])

    def test_le_dossier_personnel_est_toujours_la(self):
        maison = next(o for o in outils.CATALOGUE if o.cle == "maison")
        r = outils.resoudre(maison)
        self.assertTrue(r["disponible"])

    def test_session_sans_systemctl_ni_loginctl(self):
        eteindre = next(o for o in outils.CATALOGUE if o.cle == "eteindre")
        with mock.patch.object(outils.execution, "outil_present",
                               return_value=False):
            r = outils.resoudre(eteindre)
        self.assertFalse(r["disponible"])
        self.assertIn("loginctl", r["raison"])

    def test_lancer_refuse_une_page(self):
        """Les pages changent de page dans l'interface ; les lancer comme
        un programme n'aurait aucun sens et doit être refusé ici."""
        page = next(o for o in outils.CATALOGUE if o.genre == outils.PAGE)
        r = outils.lancer(page)
        self.assertFalse(r.ok)

    def test_les_cinq_categories_sont_peuplees(self):
        g = outils.par_categorie()
        for c in outils.CATEGORIES:
            with self.subTest(categorie=c):
                self.assertTrue(g.get(c), f"catégorie vide : {c}")

    def test_etat_general_compte_juste(self):
        e = outils.etat_general()
        self.assertEqual(e["total"], len(outils.CATALOGUE))
        self.assertEqual(e["disponibles"] + e["manquants"], e["total"])


if __name__ == "__main__":
    unittest.main()
