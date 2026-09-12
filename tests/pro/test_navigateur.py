"""La validation des adresses — les deux trous trouvés en écrivant ce banc.

Ces deux cas ne sont pas théoriques : la première version de normaliser()
les laissait passer tous les deux, et c'est ce banc qui les a montrés.
"""
import unittest

from pro.services import navigateur


class TestNormaliser(unittest.TestCase):
    def test_sans_schema_on_suppose_https_jamais_http(self):
        r = navigateur.normaliser("exemple.fr")
        self.assertTrue(r["ok"])
        self.assertTrue(r["url"].startswith("https://"))

    def test_http_explicite_reste_accepte(self):
        self.assertTrue(navigateur.normaliser("http://exemple.fr")["ok"])

    def test_schema_sans_double_barre_ne_passe_pas(self):
        """LE PREMIER TROU. « javascript:alert(1) » ne contient pas « :// » :
        l'ancienne version lui collait « https:// » devant et le laissait
        entrer."""
        for dangereux in ("javascript:alert(1)", "JavaScript:alert(1)",
                          "data:text/html,<script>", "vbscript:x",
                          "file:///etc/passwd", "ftp://serveur/f"):
            with self.subTest(adresse=dangereux):
                r = navigateur.normaliser(dangereux)
                self.assertFalse(r["ok"], f"{dangereux} a été accepté")
                self.assertIn("refusé", r["raison"])

    def test_utilisateur_avant_l_arobase_est_refuse(self):
        """LE SECOND TROU. Pour « https://banque.fr@pirate.fr », u.hostname
        rend déjà « pirate.fr » : vérifier l'hôte ne voyait pas le piège.
        C'est netloc qu'il faut regarder."""
        r = navigateur.normaliser("https://banque.fr@pirate.fr")
        self.assertFalse(r["ok"])
        self.assertIn("@", r["raison"])

    def test_port_non_numerique_refuse(self):
        r = navigateur.normaliser("https://exemple.fr:pasunport")
        self.assertFalse(r["ok"])

    def test_espaces_et_caracteres_de_controle(self):
        for mauvais in ("a b", "https://site.fr\tcache", "https://site.fr\nx"):
            with self.subTest(adresse=mauvais):
                self.assertFalse(navigateur.normaliser(mauvais)["ok"])

    def test_vide(self):
        self.assertFalse(navigateur.normaliser("")["ok"])
        self.assertFalse(navigateur.normaliser("   ")["ok"])

    def test_url_complete_est_preservee(self):
        r = navigateur.normaliser("https://x.fr:8443/a/b?c=1#d")
        self.assertTrue(r["ok"])
        self.assertEqual(r["url"], "https://x.fr:8443/a/b?c=1#d")


if __name__ == "__main__":
    unittest.main()
