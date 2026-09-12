"""La couche d'appels externes — et surtout ses REFUS.

Les quatre cas d'erreur exigés par la consigne sont éprouvés ici :
commande absente, permission refusée, délai dépassé, résultat invalide.
Chacun doit produire un motif LISIBLE, pas une exception ni un silence.
"""
import os
import stat
import tempfile
import unittest
from pathlib import Path

from pro.services import execution


class TestLancer(unittest.TestCase):
    def test_reussite_rend_la_sortie(self):
        r = execution.lancer(["echo", "bonjour"])
        self.assertTrue(r.ok)
        self.assertEqual(r.sortie, "bonjour")
        self.assertEqual(r.code, 0)

    def test_commande_absente_nomme_l_outil(self):
        r = execution.lancer(["cet-outil-n-existe-pas-du-tout"])
        self.assertFalse(r.ok)
        self.assertIn("cet-outil-n-existe-pas-du-tout", r.erreur)
        self.assertIn("n'est pas installé", r.erreur)

    def test_delai_depasse_donne_un_motif_et_pas_une_exception(self):
        r = execution.lancer(["sleep", "5"], delai=0.3)
        self.assertFalse(r.ok)
        self.assertIn("n'a pas répondu", r.erreur)
        #  Le défaut corrigé : « {delai:.0f} » affichait « 0 s » pour 0,3 s.
        self.assertNotIn("en 0 s", r.erreur)

    def test_code_non_nul_rend_la_derniere_ligne_utile(self):
        r = execution.lancer(["sh", "-c", "echo 'motif precis' >&2; exit 3"])
        self.assertFalse(r.ok)
        self.assertEqual(r.code, 3)
        self.assertEqual(r.erreur, "motif precis")

    def test_echec_sans_sortie_reste_explicable(self):
        r = execution.lancer(["false"])
        self.assertFalse(r.ok)
        self.assertIn("false", r.erreur)
        self.assertIn("code 1", r.erreur)

    def test_commande_vide(self):
        self.assertFalse(execution.lancer([]).ok)

    def test_argv_est_une_liste_jamais_un_shell(self):
        """Un argument qui ressemble à une commande reste un ARGUMENT."""
        r = execution.lancer(["echo", "a; touch /tmp/ne-doit-pas-exister-lexos"])
        self.assertTrue(r.ok)
        self.assertIn(";", r.sortie)
        self.assertFalse(Path("/tmp/ne-doit-pas-exister-lexos").exists())

    def test_permission_refusee(self):
        with tempfile.TemporaryDirectory() as d:
            faux = Path(d) / "pas-executable"
            faux.write_text("#!/bin/sh\necho x\n")
            faux.chmod(stat.S_IRUSR)         # lisible, PAS exécutable
            ancien = os.environ.get("PATH", "")
            os.environ["PATH"] = d + os.pathsep + ancien
            try:
                r = execution.lancer(["pas-executable"])
            finally:
                os.environ["PATH"] = ancien
            self.assertFalse(r.ok)
            self.assertTrue(r.erreur, "un refus doit porter un motif")


class TestLireFichier(unittest.TestCase):
    def test_fichier_absent(self):
        r = execution.lire_fichier("/ce/chemin/n/existe/pas")
        self.assertFalse(r.ok)
        self.assertIn("n'existe pas", r.erreur)

    def test_fichier_lisible(self):
        r = execution.lire_fichier("/proc/uptime")
        self.assertTrue(r.ok)
        self.assertTrue(r.sortie.strip())

    def test_permission_refusee_est_une_reponse(self):
        with tempfile.TemporaryDirectory() as d:
            secret = Path(d) / "secret"
            secret.write_text("x")
            secret.chmod(0)
            r = execution.lire_fichier(str(secret))
            if os.geteuid() == 0:
                self.skipTest("root lit tout : ce cas ne peut pas être joué ici")
            self.assertFalse(r.ok)
            self.assertIn("refusée", r.erreur)


class TestOutilPresent(unittest.TestCase):
    def test_present_et_absent(self):
        self.assertTrue(execution.outil_present("sh"))
        self.assertFalse(execution.outil_present("outil-absent-xyz-123"))


if __name__ == "__main__":
    unittest.main()
