"""Accueil — le tableau de bord, avec des mesures RÉELLES.

Aucun chiffre de la maquette n'est repris : ni « 18 % », ni « RTX 5060 »,
ni « 3 h 24 min ». Tout vient des services, et ce qui manque s'affiche
« Indisponible » avec sa raison.

Le rafraîchissement des mesures /proc est immédiat (quelques microsecondes)
et reste dans le fil graphique. Les mesures COÛTEUSES — GPU, cartes PCI —
partent en arrière-plan et ne sont refaites qu'une fois : une carte
graphique ne change pas pendant qu'on regarde la page.
"""
from __future__ import annotations

from PySide6.QtWidgets import QHBoxLayout, QWidget

from ...services import disques, gpu, reseau, systeme
from .. import theme, widgets


class PageAccueil(widgets.Page):
    def __init__(self, aller_vers, parent=None):
        super().__init__(
            "Vue d'ensemble du système",
            "Mesures relevées sur cette machine. Une valeur absente est "
            "signalée « Indisponible » avec sa raison — jamais remplacée "
            "par une estimation.", parent)
        self._aller = aller_vers
        self._cpu = systeme.MesureCPU()
        self._materiel_lu = False

        grille = self.ajouter_grille(3)
        self.c_cpu = widgets.Carte("Processeur", "processeur")
        self.c_gpu = widgets.Carte("Carte graphique", "gpu")
        self.c_mem = widgets.Carte("Mémoire", "memoire")
        self.c_sto = widgets.Carte("Stockage", "stockage")
        self.c_net = widgets.Carte("Réseau", "reseau")
        self.c_sys = widgets.Carte("Système", "systeme")
        for i, c in enumerate((self.c_cpu, self.c_gpu, self.c_mem,
                               self.c_sto, self.c_net, self.c_sys)):
            grille.addWidget(c, i // 3, i % 3)
        for c in (self.c_sto, self.c_sys, self.c_net):
            c.courbe.hide()
        self.c_sys.jauge.hide()
        self.c_net.jauge.hide()

        self.disposition.addWidget(widgets.titre_section("Raccourcis"))
        barre = QWidget()
        d = QHBoxLayout(barre)
        d.setContentsMargins(0, 0, 0, 0)
        for libelle, page, ic in (("Fichiers", "fichiers", "fichiers"),
                                  ("Terminal", "terminal", "terminal"),
                                  ("Performances", "parametres:performances",
                                   "performances"),
                                  ("Affichage et GPU", "parametres:affichage",
                                   "affichage"),
                                  ("Sécurité", "securite", "securite")):
            b = widgets.bouton(libelle, ic)
            b.clicked.connect(lambda _=False, p=page: self._aller(p))
            d.addWidget(b)
        d.addStretch(1)
        self.disposition.addWidget(barre)
        self.disposition.addStretch(1)

        self.periodique(2000)

    # ------------------------------------------------------------------
    def rafraichir(self):
        m = self._cpu.pourcent()
        if m.disponible:
            c = systeme.coeurs()
            detail = f"{c['logiques']} cœurs logiques"
            if c["physiques"]:
                detail += f" · {c['physiques']} physiques"
            self.c_cpu.montrer(f"{m.valeur:.0f} %", detail, m.valeur, m.valeur)
        else:
            self.c_cpu.indisponible(m.raison)

        mem = systeme.memoire()
        if mem["disponible"]:
            self.c_mem.montrer(
                f"{mem['pourcent']:.0f} %",
                f"{systeme.octets_lisibles(mem['utilise'])} utilisés sur "
                f"{systeme.octets_lisibles(mem['total'])}",
                mem["pourcent"], mem["pourcent"])
        else:
            self.c_mem.indisponible(mem["raison"])

        racine = disques.volume_racine()
        if racine and racine.mesure:
            self.c_sto.montrer(
                f"{racine.pourcent:.0f} %",
                f"{systeme.octets_lisibles(racine.utilise)} utilisés sur "
                f"{systeme.octets_lisibles(racine.total)} — {racine.systeme}",
                racine.pourcent)
        else:
            self.c_sto.indisponible(
                racine.raison if racine else
                "Aucun volume monté sur « / » n'a été trouvé dans /proc/mounts.")

        i = systeme.infos()
        demarrage = systeme.demarrage()
        self.c_sys.montrer(
            i["distribution"],
            f"Noyau {i['noyau']} · {i['architecture']}\n"
            f"Session {i['session']['type']}\n"
            f"Démarré depuis {systeme.duree_lisible(demarrage.valeur)}"
            if demarrage.disponible else
            f"Noyau {i['noyau']} · {i['architecture']}\n"
            f"Temps depuis le démarrage : indisponible — {demarrage.raison}")

        if not self._materiel_lu:
            self._materiel_lu = True
            self.c_gpu.detail.setText("Lecture en cours…")
            self.c_net.detail.setText("Lecture en cours…")
            widgets.en_fond(self, self._lire_materiel, self._materiel_pret,
                            self._materiel_rate)

    # -- hors du fil graphique ------------------------------------------
    @staticmethod
    def _lire_materiel():
        return {"cartes": gpu.cartes(), "nvidia": gpu.nvidia(),
                "interfaces": reseau.interfaces(),
                "passerelle": reseau.passerelle(),
                "connectivite": reseau.connectivite()}

    def _materiel_rate(self, motif):
        self.c_gpu.indisponible(motif)
        self.c_net.indisponible(motif)

    def _materiel_pret(self, r):
        nv = r["nvidia"]
        if nv["trouve"]:
            c = nv["cartes"][0]
            self.c_gpu.montrer(
                c.get("name", "Carte NVIDIA"),
                f"Pilote {c.get('driver_version', '?')} · "
                f"{c.get('memory.used', '?')} / {c.get('memory.total', '?')} Mio")
        else:
            cartes = r["cartes"]
            if cartes["trouve"]:
                carte = cartes["cartes"][0]
                self.c_gpu.montrer(
                    carte.fournisseur or "Carte graphique",
                    f"{carte.description}\nPilote : {carte.pilote}\n"
                    f"{nv['raison']}")
            else:
                self.c_gpu.indisponible(cartes["raison"])

        con = r["connectivite"]
        actives = [i for i in r["interfaces"]
                   if i.etat == "up" and not i.boucle and i.adresses]
        if actives:
            i = actives[0]
            adresses = ", ".join(a["adresse"] for a in i.adresses[:2])
            self.c_net.montrer(
                "Connecté" if con.get("connecte") else "Hors ligne",
                f"{i.nom} ({i.type_}) · {adresses}\n"
                f"État mesuré par {con.get('source', '?')} : {con.get('etat', '?')}")
            self.c_net.valeur.setStyleSheet(
                f"color: {theme.VERT if con.get('connecte') else theme.JAUNE};"
                f"font-size: 20px; font-weight: 600;")
        else:
            montees = [i for i in r["interfaces"] if not i.boucle]
            if montees:
                self.c_net.indisponible(
                    "Aucune interface active avec une adresse. "
                    + (r["passerelle"].get("raison", "")))
            else:
                self.c_net.indisponible(
                    "Aucune interface réseau en dehors de la boucle locale.")
