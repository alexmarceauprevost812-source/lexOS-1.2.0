"""Les mesures — et la règle « jamais une valeur inventée »."""
import unittest
from unittest import mock

from pro.services import disques, execution, processus, securite, systeme, unites


class TestCPU(unittest.TestCase):
    def test_premiere_mesure_refuse_de_repondre(self):
        """Un seul relevé de /proc/stat ne donne QUE la moyenne depuis le
        démarrage. Rendre ce chiffre serait rendre un faux."""
        m = systeme.MesureCPU()
        r = m.pourcent()
        self.assertFalse(r.disponible)
        self.assertIn("deux lectures", r.raison)

    def test_deuxieme_mesure_donne_un_pourcentage_borne(self):
        m = systeme.MesureCPU()
        m.pourcent()
        for _ in range(20000):
            pass
        r = m.pourcent()
        if r.disponible:
            self.assertGreaterEqual(r.valeur, 0.0)
            self.assertLessEqual(r.valeur, 100.0)

    def test_proc_stat_illisible_donne_un_motif(self):
        m = systeme.MesureCPU()
        with mock.patch.object(execution, "lire_fichier",
                               return_value=execution.Resultat(
                                   False, erreur="pas de /proc")):
            r = m.pourcent()
        self.assertFalse(r.disponible)
        self.assertEqual(r.raison, "pas de /proc")


class TestMemoire(unittest.TestCase):
    def test_mesure_reelle_coherente(self):
        m = systeme.memoire()
        if not m["disponible"]:
            self.skipTest(m["raison"])
        self.assertGreater(m["total"], 0)
        self.assertLessEqual(m["utilise"], m["total"])
        self.assertGreaterEqual(m["pourcent"], 0)
        self.assertLessEqual(m["pourcent"], 100)

    def test_memavailable_absent_est_dit(self):
        faux = "MemTotal:       16000000 kB\nMemFree:         8000000 kB\n"
        with mock.patch.object(execution, "lire_fichier",
                               return_value=execution.Resultat(True, sortie=faux)):
            m = systeme.memoire()
        self.assertFalse(m["disponible"])
        self.assertIn("MemAvailable", m["raison"])


class TestFormats(unittest.TestCase):
    def test_octets_lisibles(self):
        self.assertEqual(systeme.octets_lisibles(None), "Indisponible")
        self.assertEqual(systeme.octets_lisibles("abc"), "Indisponible")
        self.assertEqual(systeme.octets_lisibles(512), "512 o")
        self.assertIn("Go", systeme.octets_lisibles(2_500_000_000))

    def test_duree_lisible(self):
        self.assertEqual(systeme.duree_lisible(None), "Indisponible")
        self.assertIn("min", systeme.duree_lisible(300))
        self.assertIn("j", systeme.duree_lisible(200000))


class TestDisques(unittest.TestCase):
    def test_la_racine_est_mesuree(self):
        v = disques.volume_racine()
        if v is None:
            self.skipTest("aucun volume « / » dans /proc/mounts")
        self.assertTrue(v.mesure)
        self.assertGreater(v.total, 0)
        self.assertLessEqual(v.utilise, v.total)

    def test_les_systemes_virtuels_sont_ecartes_par_defaut(self):
        normaux = {v.point for v in disques.volumes()}
        tous = {v.point for v in disques.volumes(tout=True)}
        self.assertTrue(normaux.issubset(tous))

    def test_decodage_des_espaces_octales(self):
        self.assertEqual(disques._demonter_octal(r"/mnt/Mes\040documents"),
                         "/mnt/Mes documents")


class TestProcessus(unittest.TestCase):
    def test_liste_non_vide_et_nous_appartient_en_partie(self):
        m = processus.Moniteur()
        liste = m.liste()
        self.assertTrue(liste)
        self.assertTrue(any(p.a_nous for p in liste))

    def test_nom_avec_espaces_ne_decale_pas_les_champs(self):
        """/proc/<pid>/stat met le nom entre parenthèses, et ce nom peut
        contenir des espaces. Découper sur les espaces décalerait tout."""
        m = processus.Moniteur()
        faux = "42 (mon programme (v2)) S 1 42 42 0 -1 4194304 " \
               + " ".join(["0"] * 30)
        with mock.patch.object(execution, "lire_fichier") as lire, \
             mock.patch("os.listdir", return_value=["42"]), \
             mock.patch("os.stat") as stat_:
            stat_.return_value = mock.Mock(st_uid=processus.os.getuid())
            lire.side_effect = lambda chemin, **k: (
                execution.Resultat(True, sortie="cpu 1 2 3 4 5 6 7 8")
                if chemin == "/proc/stat" else
                execution.Resultat(True, sortie=faux) if chemin.endswith("/stat")
                else execution.Resultat(True, sortie=""))
            liste = m.liste()
        self.assertEqual(len(liste), 1)
        self.assertEqual(liste[0].nom, "mon programme (v2)")

    def test_arret_refuse_sur_un_processus_d_un_autre(self):
        with mock.patch("os.stat") as stat_:
            stat_.return_value = mock.Mock(st_uid=999999)
            r = processus.demander_arret(4242)
        self.assertFalse(r.ok)
        self.assertIn("autre utilisateur", r.erreur)

    def test_arret_refuse_sur_soi_meme_et_sur_init(self):
        import os as _os
        r = processus.demander_arret(_os.getpid())
        self.assertFalse(r.ok)
        self.assertIn("LEXOS PRO lui-même", r.erreur)

    def test_processus_inexistant(self):
        r = processus.demander_arret(999999)
        self.assertFalse(r.ok)
        self.assertIn("n'existe plus", r.erreur)

    def test_temperatures_absentes_le_disent(self):
        with mock.patch("os.listdir", side_effect=OSError(2, "absent")):
            t = processus.temperatures()
        self.assertFalse(t["trouve"])
        self.assertTrue(t["raison"])


class TestServicesSystemd(unittest.TestCase):
    def test_les_services_systeme_sont_en_lecture_seule(self):
        u = unites.Unite("nginx.service", portee="system")
        permis, raison = unites.action_permise(u)
        self.assertFalse(permis)
        self.assertIn("lecture seule", raison)
        r = unites.agir(u, "restart")
        self.assertFalse(r.ok)

    def test_les_services_utilisateur_sont_permis(self):
        u = unites.Unite("x.service", portee="user")
        permis, raison = unites.action_permise(u)
        self.assertTrue(permis)
        self.assertEqual(raison, "")

    def test_action_inconnue_refusee(self):
        u = unites.Unite("x.service", portee="user")
        self.assertFalse(unites.agir(u, "rm -rf").ok)


class TestSecurite(unittest.TestCase):
    def test_la_synthese_ne_prononce_jamais_de_verdict(self):
        r = securite.synthese()
        self.assertIn("mesures", r)
        self.assertIn("avertissement", r)
        texte = r["avertissement"].lower()
        self.assertNotIn("sécurisé", texte.replace("pas si la machine est sûre", ""))
        self.assertLessEqual(r["mesures"], r["total"])

    def test_chaque_point_indisponible_porte_une_raison(self):
        r = securite.synthese()
        for nom, v in r["points"].items():
            if not (v.get("mesure") or v.get("trouve") or v.get("sans_objet")):
                self.assertTrue(v.get("raison"),
                                f"« {nom} » indisponible sans raison")


if __name__ == "__main__":
    unittest.main()
