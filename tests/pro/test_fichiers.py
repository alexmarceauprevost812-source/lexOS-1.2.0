"""Les opérations de fichiers — conflits, refus, et l'absence de
suppression définitive."""
import os
import tempfile
import unittest
from pathlib import Path

from pro.services import fichiers


class TestOperations(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.d = Path(self._d.name)

    def tearDown(self):
        self._d.cleanup()

    def test_creer_dossier_et_conflit(self):
        self.assertTrue(fichiers.creer_dossier(self.d, "a").ok)
        r = fichiers.creer_dossier(self.d, "a")
        self.assertFalse(r.ok)
        self.assertIn("existe déjà", r.erreur)

    def test_nom_avec_barre_oblique_refuse(self):
        r = fichiers.creer_dossier(self.d, "a/b")
        self.assertFalse(r.ok)
        self.assertIn("/", r.erreur)

    def test_nom_vide_refuse(self):
        self.assertFalse(fichiers.creer_dossier(self.d, "   ").ok)
        self.assertFalse(fichiers.creer_dossier(self.d, "..").ok)

    def test_copie_refuse_d_ecraser_sans_qu_on_le_demande(self):
        (self.d / "src").mkdir()
        (self.d / "dst").mkdir()
        (self.d / "src" / "f.txt").write_text("un")
        (self.d / "dst" / "f.txt").write_text("deux")
        r = fichiers.copier(self.d / "src" / "f.txt", self.d / "dst")
        self.assertFalse(r.ok)
        self.assertIn("existe déjà", r.erreur)
        #  Le fichier de destination est INTACT.
        self.assertEqual((self.d / "dst" / "f.txt").read_text(), "deux")

    def test_copie_remplace_seulement_si_on_l_autorise(self):
        (self.d / "src").mkdir(); (self.d / "dst").mkdir()
        (self.d / "src" / "f.txt").write_text("un")
        (self.d / "dst" / "f.txt").write_text("deux")
        r = fichiers.copier(self.d / "src" / "f.txt", self.d / "dst",
                            remplacer=True)
        self.assertTrue(r.ok)
        self.assertEqual((self.d / "dst" / "f.txt").read_text(), "un")

    def test_deplacer_meme_regle(self):
        (self.d / "a.txt").write_text("x")
        (self.d / "cible").mkdir()
        (self.d / "cible" / "a.txt").write_text("y")
        self.assertFalse(fichiers.deplacer(self.d / "a.txt",
                                           self.d / "cible").ok)
        self.assertTrue((self.d / "a.txt").exists())

    def test_renommer(self):
        (self.d / "a.txt").write_text("x")
        self.assertTrue(fichiers.renommer(self.d / "a.txt", "b.txt").ok)
        self.assertTrue((self.d / "b.txt").exists())
        (self.d / "c.txt").write_text("y")
        self.assertFalse(fichiers.renommer(self.d / "c.txt", "b.txt").ok)

    def test_lister_dossier_absent(self):
        r = fichiers.lister(self.d / "nexiste-pas")
        self.assertFalse(r["ok"])
        self.assertTrue(r["raison"])

    def test_lister_sur_un_fichier(self):
        (self.d / "f").write_text("x")
        r = fichiers.lister(self.d / "f")
        self.assertFalse(r["ok"])
        self.assertIn("n'est pas un dossier", r["raison"])

    def test_dossiers_d_abord_puis_alphabetique(self):
        (self.d / "zz").mkdir()
        (self.d / "aa.txt").write_text("")
        r = fichiers.lister(self.d)
        self.assertTrue(r["ok"])
        self.assertEqual([e.nom for e in r["entrees"]], ["zz", "aa.txt"])

    def test_proprietes(self):
        (self.d / "f").write_text("abc")
        p = fichiers.proprietes(self.d / "f")
        self.assertTrue(p["ok"])
        self.assertEqual(p["taille"], 3)
        self.assertEqual(p["type"], "Fichier")

    def test_aucune_suppression_definitive_dans_le_module(self):
        """Garde structurelle : le module ne doit APPELER aucun verbe de
        suppression. Un module qui n'a pas le verbe ne peut pas commettre
        l'action au prochain remaniement.

        ON ANALYSE L'ARBRE SYNTAXIQUE, PAS LE TEXTE. La première version de
        ce contrôle cherchait la chaîne « os.remove » dans le fichier — et
        échouait sur la DOCSTRING du module, qui cite ces noms justement
        pour expliquer leur absence. Un contrôle qui se déclenche sur sa
        propre justification ne contrôle rien : il apprend à ignorer les
        rouges. Ici on ne regarde que les APPELS réellement écrits.
        """
        import ast
        arbre = ast.parse(Path(fichiers.__file__).read_text(encoding="utf-8"))
        appels = set()
        for noeud in ast.walk(arbre):
            if isinstance(noeud, ast.Call):
                try:
                    appels.add(ast.unparse(noeud.func))
                except Exception:            # noqa: BLE001
                    pass
        interdits = {"os.remove", "os.unlink", "os.rmdir", "shutil.rmtree",
                     "os.removedirs"}
        trouves = appels & interdits
        self.assertFalse(
            trouves, f"appels de suppression définitive interdits : {trouves}")
        #  .unlink() et .rmdir() sur un Path ne s'écrivent pas « os.… » :
        #  on regarde donc aussi le NOM de méthode appelé sur un objet.
        methodes = {a.rsplit(".", 1)[-1] for a in appels if "." in a}
        for interdite in ("unlink", "rmtree", "rmdir", "removedirs"):
            self.assertNotIn(
                interdite, methodes,
                f"« .{interdite}() » ne doit pas être appelé dans ce module")


class TestDossiersUsuels(unittest.TestCase):
    def test_le_dossier_personnel_est_toujours_la(self):
        u = fichiers.dossiers_usuels()
        self.assertTrue(u)
        self.assertEqual(u[0]["nom"], "Dossier personnel")
        self.assertEqual(u[0]["chemin"], str(Path.home()))

    def test_aucun_dossier_inexistant_n_est_propose(self):
        for entree in fichiers.dossiers_usuels():
            self.assertTrue(os.path.isdir(entree["chemin"]),
                            f"{entree['chemin']} n'existe pas")


if __name__ == "__main__":
    unittest.main()
