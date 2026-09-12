"""La détection des capacités — et la distinction Ubuntu / Debian.

LE POINT QUI COMPTE : la consigne interdit de supposer qu'Ubuntu et Debian
utilisent les mêmes paquets. On éprouve donc que `est()` répond sur
l'identifiant EXACT et `dans_famille()` sur la parenté — et qu'on ne peut
pas confondre les deux.
"""
import unittest
from unittest import mock

from pro.services import capacites


class TestDistribution(unittest.TestCase):
    def test_ubuntu_n_est_pas_debian_mais_en_est_la_famille(self):
        d = capacites.Distribution(id="ubuntu", nom="Ubuntu 24.04",
                                   familles=["debian"])
        self.assertTrue(d.est("ubuntu"))
        self.assertFalse(d.est("debian"))
        self.assertTrue(d.dans_famille("debian"))
        self.assertTrue(d.dans_famille("ubuntu"))

    def test_debian_pure_n_a_pas_de_famille(self):
        d = capacites.Distribution(id="debian", nom="Debian 13", familles=[])
        self.assertTrue(d.est("debian"))
        self.assertFalse(d.dans_famille("ubuntu"))

    def test_distribution_inconnue_le_dit(self):
        d = capacites.Distribution()
        self.assertFalse(d.connue)
        self.assertEqual(d.libelle(), "Distribution inconnue")

    def test_lecture_reelle_de_os_release(self):
        capacites.distribution.cache_clear()
        d = capacites.distribution()
        #  On n'exige pas une valeur précise — la machine de test varie —
        #  mais si os-release existe, l'identifiant ne doit pas être vide.
        import os
        if os.path.exists("/etc/os-release"):
            self.assertTrue(d.id, "/etc/os-release existe mais ID est vide")


class TestOsRelease(unittest.TestCase):
    def test_les_guillemets_sont_retires_et_rien_n_est_execute(self):
        faux = 'ID="essai"\nID_LIKE="debian ubuntu"\n' \
               'PRETTY_NAME="Essai 1.0"\nMALVEILLANT=$(touch /tmp/non)\n'
        with mock.patch.object(capacites.execution, "lire_fichier",
                               return_value=capacites.execution.Resultat(
                                   True, sortie=faux)):
            v = capacites._lire_os_release()
        self.assertEqual(v["ID"], "essai")
        self.assertEqual(v["ID_LIKE"], "debian ubuntu")
        self.assertEqual(v["PRETTY_NAME"], "Essai 1.0")
        #  La ligne « malveillante » est lue comme une CHAÎNE, pas exécutée.
        self.assertEqual(v["MALVEILLANT"], "$(touch /tmp/non)")
        import os
        self.assertFalse(os.path.exists("/tmp/non"))


class TestCapacitesSysteme(unittest.TestCase):
    def test_systemd_distingue_installe_et_actif(self):
        capacites.systemd.cache_clear()
        with mock.patch.object(capacites.shutil, "which", return_value=None):
            r = capacites.systemd()
        self.assertFalse(r["present"])
        self.assertIn("systemctl", r["raison"])
        capacites.systemd.cache_clear()

        with mock.patch.object(capacites.shutil, "which",
                               return_value="/bin/systemctl"), \
             mock.patch.object(capacites.os.path, "isdir", return_value=False):
            r = capacites.systemd()
        self.assertFalse(r["present"])
        self.assertIn("n'est pas le gestionnaire", r["raison"])
        capacites.systemd.cache_clear()

    def test_aucun_gestionnaire_de_paquets_donne_une_raison(self):
        capacites.gestionnaire_paquets.cache_clear()
        with mock.patch.object(capacites.shutil, "which", return_value=None):
            r = capacites.gestionnaire_paquets()
        self.assertFalse(r["trouve"])
        self.assertIn("Aucun gestionnaire", r["raison"])
        capacites.gestionnaire_paquets.cache_clear()

    def test_resume_ne_leve_jamais(self):
        r = capacites.resume()
        for cle in ("distribution", "session", "paquets", "systemd", "audio",
                    "reseau", "outils"):
            self.assertIn(cle, r)


if __name__ == "__main__":
    unittest.main()
