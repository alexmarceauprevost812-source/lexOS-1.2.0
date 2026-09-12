"""Préférences XDG et version réelle."""
import json
import os
import tempfile
import unittest
from pathlib import Path

from pro import version
from pro.services import prefs


class TestPrefs(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self._ancien = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = self._d.name

    def tearDown(self):
        if self._ancien is None:
            os.environ.pop("XDG_CONFIG_HOME", None)
        else:
            os.environ["XDG_CONFIG_HOME"] = self._ancien
        self._d.cleanup()

    def test_les_prefs_vont_dans_xdg(self):
        self.assertTrue(prefs.enregistrer(dict(prefs.DEFAUTS)))
        attendu = Path(self._d.name) / "lexos-pro" / "preferences.json"
        self.assertTrue(attendu.exists())

    def test_aller_retour(self):
        v = dict(prefs.DEFAUTS)
        v["taille_texte"] = 140
        v["projets"] = ["/un/projet"]
        prefs.enregistrer(v)
        relu = prefs.charger()
        self.assertEqual(relu["taille_texte"], 140)
        self.assertEqual(relu["projets"], ["/un/projet"])

    def test_fichier_illisible_ne_bloque_pas_le_demarrage(self):
        chemin = Path(self._d.name) / "lexos-pro" / "preferences.json"
        chemin.parent.mkdir(parents=True, exist_ok=True)
        chemin.write_text("{ceci n'est pas du JSON")
        relu = prefs.charger()
        self.assertEqual(relu["taille_texte"], prefs.DEFAUTS["taille_texte"])
        #  Le fichier abîmé n'est PAS écrasé : l'utilisateur peut le relire.
        self.assertIn("ceci n'est pas", chemin.read_text())

    def test_type_inattendu_est_ignore(self):
        chemin = Path(self._d.name) / "lexos-pro" / "preferences.json"
        chemin.parent.mkdir(parents=True, exist_ok=True)
        chemin.write_text(json.dumps({"taille_texte": "gros",
                                      "densite": "compacte"}))
        relu = prefs.charger()
        self.assertEqual(relu["taille_texte"], 100)      # défaut conservé
        self.assertEqual(relu["densite"], "compacte")    # celui-là est bon

    def test_aucun_secret_dans_les_defauts(self):
        texte = json.dumps(prefs.DEFAUTS).lower()
        for mot in ("password", "passwd", "secret", "token", "mot_de_passe"):
            self.assertNotIn(mot, texte)


class TestVersion(unittest.TestCase):
    def test_version_vient_du_depot_ou_dit_inconnue(self):
        v = version.version()
        self.assertTrue(v)
        self.assertIsInstance(v, str)

    def test_lecture_de_conf_sans_execution(self):
        with tempfile.NamedTemporaryFile("w", suffix=".conf",
                                         delete=False) as f:
            f.write('LEXOS_VERSION="9.9.9"\nX=$(touch /tmp/jamais-lexos)\n')
            nom = f.name
        try:
            v = version._lire_conf(Path(nom))
            self.assertEqual(v["LEXOS_VERSION"], "9.9.9")
            self.assertFalse(os.path.exists("/tmp/jamais-lexos"))
        finally:
            os.unlink(nom)

    def test_repertoires_xdg(self):
        self.assertIn("lexos-pro", str(version.repertoire_config()))
        self.assertIn("lexos-pro", str(version.repertoire_donnees()))


if __name__ == "__main__":
    unittest.main()
