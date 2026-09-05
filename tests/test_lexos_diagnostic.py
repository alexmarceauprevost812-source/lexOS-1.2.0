"""Tests de fumée pour LexOS Diagnostic.

Usage (depuis la racine du dépôt, une fois les fichiers copiés — voir
integration/README-integration.md) :

    python3 -m unittest tests/test_lexos_diagnostic.py -v

Zéro dépendance au-delà de la bibliothèque standard + psutil (déjà requis
par le moteur lui-même). Comme lexos-prive n'a « aucun test — c'est celui où
une régression silencieuse fait le plus de dégâts » (lexos-carte-des-trous.md,
section 5), ce fichier part avec ce nouvel outil plutôt que d'attendre.

Ne vérifie pas des valeurs précises (elles dépendent de la machine qui fait
tourner les tests) mais que :
  - chaque instantané se construit sans lever d'exception, même sans les
    outils externes (inxi, smartctl, nvidia-smi…) — condition réelle d'une
    machine de CI, et déjà la condition dans laquelle ce fichier a été
    écrit et vérifié ;
  - la forme du JSON renvoyé a les clés attendues, pour attraper une
    régression qui romprait le contrat entre le moteur et l'interface web
    (web/app.js lit ces clés par leur nom).
"""
import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

RACINE_MOTEUR = Path(__file__).resolve().parent.parent / "config/includes.chroot/usr/lib/lexos/diagnostic"
sys.path.insert(0, str(RACINE_MOTEUR))

import disques  # noqa: E402
import medecin  # noqa: E402
import moteur  # noqa: E402


RACINE_DEPOT = Path(__file__).resolve().parent.parent
IC = RACINE_DEPOT / "config/includes.chroot"


class TestOutilsJoignables(unittest.TestCase):
    """« lexos-medecin rapporte 73 problèmes qui n'existent pas » (Alex).

    DEUX DÉFAUTS EN UN. L'expression cherchait « ^\\s*capture\\) » — un nom
    SUIVI D'UNE PARENTHÈSE — alors que le dispatcheur écrit
    « capture|capture-ecran) ». Tout outil ayant un synonyme était déclaré
    absent : 7 vus sur 80. Et la question elle-même était mauvaise : dix
    outils ne sont dans aucun case et c'est VOULU (udev, minuterie, ouverture
    de session).
    """

    @classmethod
    def setUpClass(cls):
        cls.dispatcheur = (IC / "usr/bin/lexos").read_text(encoding="utf-8", errors="ignore")
        cls.etiquettes = medecin._etiquettes_du_case(cls.dispatcheur)

    def test_les_alternatives_du_case_sont_reconnues(self):
        #  Les quatre cas nommés dans le rapport d'Alex. Chacun a un synonyme,
        #  et chacun était compté « absent » par l'ancienne expression.
        for label in ("capture", "capture-ecran", "net", "reseau",
                      "musique", "music", "diagnostic", "panneau-diagnostic"):
            self.assertIn(label, self.etiquettes,
                          f"« {label} » n'est pas lu comme une étiquette du case")

    def test_les_alias_accentues_aussi(self):
        #  L'expression proposée pour corriger le défaut — avec une classe
        #  [a-z0-9_|-] — butait encore sur ceux-là, qui sont partout dans ce
        #  dispatcheur. D'où la lecture des étiquettes plutôt qu'un motif.
        for label in ("médecin", "matériel", "arrêt"):
            self.assertIn(label, self.etiquettes,
                          f"l'alias accentué « {label} » n'est pas lu")

    def test_tous_les_outils_du_depot_sont_joignables(self):
        """L'ASSERTION QUI COMPTE — elle aurait attrapé le défaut le jour même.

        Avec l'ancienne expression, elle donnerait 7 sur 80.
        """
        env = dict(os.environ)
        env["LEXOS_MEDECIN_RACINE"] = str(IC)
        env["LEXOS_MEDECIN_MAISON"] = str(IC / "etc/skel")
        releve = self._releve(env)
        injoignables = [r["nom"] for r in releve["outils"] if not r["joignable"]]

        #  ═══ LA SEULE EXCEPTION, ET ELLE EST PROUVÉE, PAS SUPPOSÉE ═══
        #  lexos-fenetre n'apparaît nulle part dans l'arbre du dépôt parce que
        #  les lanceurs qui l'emploient N'EXISTENT PAS ENCORE : c'est le hook
        #  0265 qui les écrit à la construction. Sur la machine installée, il
        #  est donc joignable comme les autres. On ne se contente pas de le
        #  croire — on relit le hook.
        hook = (RACINE_DEPOT / "config/hooks/normal/0265-lexos-launchers.hook.chroot"
                ).read_text(encoding="utf-8", errors="ignore")
        if injoignables == ["lexos-fenetre"]:
            self.assertIn('EXEC="lexos-fenetre ', hook,
                          "lexos-fenetre n'est joignable ni dans l'arbre ni par le hook 0265")
        else:
            self.assertEqual([], injoignables,
                             f"{len(injoignables)} outil(s) joignables par AUCUN chemin")
        self.assertGreaterEqual(releve["joignables"], releve["total"] - 1)
        self.assertGreaterEqual(releve["total"], 78)

    def test_le_chemin_annonce_est_bien_l_etiquette_du_case(self):
        """Les quatre outils d'Alex doivent etre vus PAR LEUR ETIQUETTE.

        Sans ce controle, remettre l'ancienne expression restait VERT : ces
        outils sont aussi cites dans le dock et dans d'autres outils, donc
        « joignable » restait vrai — par un autre chemin. C'est le mecanisme
        corrige qu'on epprouve ici, pas seulement son resultat.
        """
        env = dict(os.environ)
        env["LEXOS_MEDECIN_RACINE"] = str(IC)
        env["LEXOS_MEDECIN_MAISON"] = str(IC / "etc/skel")
        par_nom = {r["nom"]: r for r in self._releve(env)["outils"]}
        for nom, etiquette in (("lexos-capture", "capture"),
                               ("lexos-net", "net"),
                               ("lexos-musique", "musique"),
                               ("lexos-diagnostic", "diagnostic")):
            self.assertIn(nom, par_nom, f"{nom} absent du depot")
            self.assertIn(f"le dispatcheur (lexos {etiquette})",
                          par_nom[nom]["joignable_par"],
                          f"{nom} n'est pas vu par son etiquette du case, "
                          f"mais par {par_nom[nom]['joignable_par']}")

    def test_udev_minuterie_et_autostart_ne_sont_pas_des_problemes(self):
        """Ces trois-là ne sont dans aucun case, et c'est VOULU."""
        env = dict(os.environ)
        env["LEXOS_MEDECIN_RACINE"] = str(IC)
        env["LEXOS_MEDECIN_MAISON"] = str(IC / "etc/skel")
        releve = self._releve(env)
        par_nom = {r["nom"]: r for r in releve["outils"]}
        for nom, attendu in (("lexos-usb-notify", "une règle udev"),
                             ("lexos-update-check", "un service systemd"),
                             ("lexos-firstrun", "le démarrage de session")):
            self.assertIn(nom, par_nom, f"{nom} absent du dépôt")
            self.assertTrue(par_nom[nom]["joignable"], f"{nom} compté comme problème")
            self.assertIn(attendu, par_nom[nom]["joignable_par"],
                          f"{nom} : chemin attendu « {attendu} », vu {par_nom[nom]['joignable_par']}")

    def test_un_outil_vraiment_injoignable_est_signale(self):
        """Sans ce contre-essai, tout ce qui precede passerait aussi si la
        fonction repondait « joignable » a tout le monde."""
        with tempfile.TemporaryDirectory() as d:
            faux = Path(d)
            (faux / "usr/bin").mkdir(parents=True)
            dispatcheur = '#!/bin/sh\ncase "$1" in\n\tvrai) exec lexos-vrai "$@" ;;\nesac\n'
            (faux / "usr/bin/lexos").write_text(dispatcheur)
            for nom in ("lexos-vrai", "lexos-orphelin"):
                f = faux / "usr/bin" / nom
                f.write_text('#!/bin/sh\n')
                f.chmod(0o755)
            env = dict(os.environ)
            env["LEXOS_MEDECIN_RACINE"] = str(faux)
            env["LEXOS_MEDECIN_MAISON"] = str(faux)
            releve = self._releve(env)
            par_nom = {r["nom"]: r for r in releve["outils"]}
            self.assertTrue(par_nom["lexos-vrai"]["joignable"])
            self.assertFalse(par_nom["lexos-orphelin"]["joignable"],
                             "un outil que personne n'appelle doit ressortir")
            self.assertIn("lexos-orphelin", [p["nom"] for p in releve["problemes"]])

    @staticmethod
    def _releve(env):
        """On relance medecin dans un processus neuf : les racines sont lues
        à l'import, et un module déjà chargé garderait les anciennes."""
        code = (
            "import json, sys; sys.path.insert(0, %r); import medecin;"
            "print(json.dumps(medecin.verifier_outils()))" % str(RACINE_MOTEUR)
        )
        sortie = subprocess.run([sys.executable, "-c", code], env=env,
                                capture_output=True, text=True, timeout=120)
        if sortie.returncode != 0:
            raise AssertionError("medecin.verifier_outils a échoué :\n" + sortie.stderr)
        return json.loads(sortie.stdout)


class TestBruitDuJournal(unittest.TestCase):
    def test_les_refus_sudo_et_obexd_ne_comptent_pas(self):
        """Six lignes en trois secondes dans le bilan d'Alex, dont aucune
        n'est une panne. Un compteur qui compte du bruit ne sert plus."""
        for ligne in (
            "sudo[55888]: tilex : a password is required ; COMMAND=/usr/bin/true",
            "sudo[55898]: pam_unix(sudo:auth): conversation failed",
            "obexd[1234]: Failed to connect to evolution-source-registry",
            "-- No entries --",
        ):
            self.assertTrue(medecin._bruit_connu(ligne), f"non filtré : {ligne}")

    def test_une_vraie_erreur_compte_toujours(self):
        """Le contre-essai : sans lui, un filtre qui avale tout passerait."""
        for ligne in (
            "kernel: EXT4-fs error (device sda1): ext4_find_entry",
            "systemd[1]: Failed to start LexOS Boost.",
            "sudo[42]: pam_unix(sudo:session): session opened for user root",
        ):
            self.assertFalse(medecin._bruit_connu(ligne), f"filtré à tort : {ligne}")


class TestAucuneSondeSudo(unittest.TestCase):
    """Un test de droits ne doit pas passer par PAM : chaque tentative
    refusée écrit deux lignes dans le journal, et ce bruit remplissait le
    compteur d'erreurs du bilan."""

    def test_pas_de_sonde_dans_les_outils(self):
        import re as _re
        fautifs = []
        for dossier in ("usr/bin", "usr/lib"):
            for f in (IC / dossier).rglob("*"):
                if not f.is_file():
                    continue
                try:
                    texte = f.read_text(encoding="utf-8", errors="ignore")
                except OSError:
                    continue
                #  ON DÉCOMMENTE D'ABORD : les explications ci-dessus citent
                #  la sonde pour dire pourquoi elle n'est plus là.
                code = _re.sub(r"(?m)^\s*#.*$", "", texte)
                if _re.search(r"sudo\s+(-n\s+)?true\b|sudo\s+-v\b", code):
                    fautifs.append(str(f.relative_to(IC)))
        self.assertEqual([], fautifs,
                         "sonde de droits par sudo (donc par PAM) : " + ", ".join(fautifs))


class TestMoteur(unittest.TestCase):
    def test_instantane_ne_plante_pas(self):
        snap = moteur.instantane()
        for cle in ("systeme", "cpu", "ram", "gpu", "ventilateurs", "disques", "reseau", "batterie", "processus"):
            self.assertIn(cle, snap)

    def test_deux_instantanes_de_suite(self):
        # Le premier amorce les compteurs delta (réseau, processus) ; le
        # deuxième doit rester silencieux lui aussi.
        moteur.instantane()
        snap = moteur.instantane()
        self.assertIsInstance(snap["reseau"]["interfaces"], list)
        self.assertIsInstance(snap["processus"]["top_cpu"], list)

    def test_cpu_pourcentage_dans_les_bornes(self):
        pct = moteur.instantane()["cpu"]["utilisation_globale_pct"]
        self.assertIsNotNone(pct)
        self.assertGreaterEqual(pct, 0)
        self.assertLessEqual(pct, 100)

    def test_gpu_a_toujours_un_message_si_indisponible(self):
        gpu = moteur.instantane()["gpu"]
        if not gpu["disponible"]:
            self.assertIsNotNone(gpu["message"])


class TestMedecin(unittest.TestCase):
    def test_bilan_complet_ne_plante_pas(self):
        bilan = medecin.bilan_complet()
        for cle in ("outils", "son", "wifi", "disques_pleins", "journal"):
            self.assertIn(cle, bilan)

    def test_rapport_texte_est_une_chaine_non_vide(self):
        rapport = medecin.rapport_texte()
        self.assertIsInstance(rapport, str)
        self.assertIn("Bilan LexOS Médecin", rapport)

    def test_no_entries_journalctl_ne_compte_pas_comme_erreur(self):
        # Régression trouvée pendant l'écriture : journalctl répond
        # "-- No entries --" quand tout va bien, et ça ne doit jamais
        # gonfler le compte d'erreurs.
        resultat = medecin.verifier_erreurs_journal()
        for ligne in resultat["lignes"]:
            self.assertNotIn("No entries", ligne)


class TestDisques(unittest.TestCase):
    def test_rapport_disques_ne_plante_pas(self):
        rapport = disques.rapport_disques()
        for cle in ("sante", "espace", "outils"):
            self.assertIn(cle, rapport)

    def test_outils_disponibles_est_bien_forme(self):
        outils = disques.outils_disponibles()
        for cle in ("smartctl", "nvme", "rmlint", "f3"):
            self.assertIn(cle, outils)
            self.assertIsInstance(outils[cle], bool)


if __name__ == "__main__":
    unittest.main()


class TestServeurLocal(unittest.TestCase):
    """Le serveur n'obéit qu'à la machine elle-même.

    ═══ POURQUOI CE CONTRÔLE EXISTE ═══
    Ce module écoute sur un port FIXE (7861), contrairement au serveur des
    Paramètres qui tire un port libre au lancement (settings.py, bind sur le
    port 0). Un port local prévisible est joignable par n'importe quelle page
    web que l'utilisateur ouvre : le navigateur l'empêchera de LIRE la
    réponse, mais rien n'empêche l'envoi — un site pourrait déclencher en
    boucle un scan de doublons de trente secondes. Et le nom « localhost »
    peut être repointé vers une adresse extérieure (« DNS rebinding »), ce qui
    fait tomber l'en-tête Host hors de la boucle locale.

    Deux vérifications dans serveur.py suffisent (_appelant_local). Elles ne
    coûtent rien à l'usage normal — et sans banc, les retirer un jour ne se
    verrait nulle part.
    """

    @classmethod
    def setUpClass(cls):
        import serveur  # noqa: PLC0415 - importé ici : il démarre un serveur

        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            cls.port = s.getsockname()[1]
        from http.server import ThreadingHTTPServer  # noqa: PLC0415

        cls.httpd = ThreadingHTTPServer(("127.0.0.1", cls.port), serveur.Gestionnaire)
        cls.fil = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.fil.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def _demander(self, chemin, methode="GET", entetes=None, hote=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        try:
            en = dict(entetes or {})
            en.setdefault("Host", hote or f"127.0.0.1:{self.port}")
            conn.request(methode, chemin, headers=en)
            return conn.getresponse().status
        finally:
            conn.close()

    def test_notre_propre_page_est_servie(self):
        self.assertEqual(self._demander("/"), 200)
        self.assertEqual(self._demander("/api/etat"), 200)

    def test_notre_propre_origine_est_acceptee(self):
        origine = f"http://127.0.0.1:{self.port}"
        self.assertEqual(self._demander("/api/etat", entetes={"Origin": origine}), 200)

    def test_une_page_etrangere_est_refusee(self):
        for methode in ("GET", "POST"):
            with self.subTest(methode=methode):
                code = self._demander(
                    "/api/etat", methode=methode,
                    entetes={"Origin": "https://exemple-mechant.invalid"})
                self.assertEqual(code, 403)

    def test_un_host_etranger_est_refuse(self):
        #  Le cas du « DNS rebinding » : la connexion arrive bien sur la
        #  boucle locale, mais le navigateur croit parler à un autre domaine.
        code = self._demander("/api/etat", hote="exemple-mechant.invalid")
        self.assertEqual(code, 403)

    def test_pas_de_traversee_de_chemin(self):
        self.assertIn(self._demander("/../../etc/passwd"), (403, 404))


if __name__ == "__main__":
    unittest.main()
