"""Services systemd — lecture pour le système, action pour l'utilisateur.

LA FRONTIÈRE, ET ELLE EST NETTE :
  · services UTILISATEUR (systemctl --user) : démarrer, arrêter, relancer
    sont permis, après confirmation. Ils appartiennent à la session ;
    aucune élévation de privilège n'est en jeu.
  · services SYSTÈME : LECTURE SEULE. Les modifier demanderait pkexec et
    une règle PolicyKit ciblée, que ce dépôt n'a pas encore écrite et
    éprouvée. Tant qu'elle n'existe pas, le bouton est désactivé AVEC sa
    raison — pas absent, pas silencieux.
"""
from __future__ import annotations

from dataclasses import dataclass

from . import capacites, execution

ACTIONS = ("start", "stop", "restart")
_LIBELLES = {"start": "démarrer", "stop": "arrêter", "restart": "redémarrer"}


@dataclass
class Unite:
    nom: str
    charge: str = ""
    actif: str = ""
    sous_etat: str = ""
    description: str = ""
    portee: str = "system"     # « system » ou « user »


def _lister(portee: str) -> dict:
    s = capacites.systemd()
    if not s["present"]:
        return {"trouve": False, "raison": s["raison"]}
    argv = ["systemctl"]
    if portee == "user":
        argv.append("--user")
    argv += ["list-units", "--type=service", "--all", "--no-pager",
             "--no-legend", "--plain"]
    r = execution.lancer(argv, delai=12.0)
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    unites = []
    for ligne in r.lignes():
        champs = ligne.split(None, 4)
        if len(champs) < 4:
            continue
        nom = champs[0].lstrip("●* ")
        unites.append(Unite(nom=nom, charge=champs[1], actif=champs[2],
                            sous_etat=champs[3],
                            description=champs[4] if len(champs) > 4 else "",
                            portee=portee))
    if not unites:
        return {"trouve": False,
                "raison": f"systemctl n'a listé aucun service "
                          f"({'utilisateur' if portee == 'user' else 'système'})."}
    return {"trouve": True, "unites": unites}


def systeme() -> dict:
    return _lister("system")


def utilisateur() -> dict:
    return _lister("user")


def journal(nom: str, portee: str = "system", lignes: int = 200) -> dict:
    """Les journaux ACCESSIBLES. Un refus de droits est une réponse
    normale et s'affiche telle quelle."""
    if not execution.outil_present("journalctl"):
        return {"trouve": False,
                "raison": "journalctl n'est pas installé : les journaux ne "
                          "sont pas consultables depuis cette application."}
    argv = ["journalctl", "--no-pager", "-n", str(int(lignes)), "-u", nom]
    if portee == "user":
        argv.insert(1, "--user")
    r = execution.lancer(argv, delai=15.0)
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    if not r.sortie.strip():
        return {"trouve": False,
                "raison": f"Aucune entrée de journal lisible pour {nom} "
                          f"(le journal peut être vide ou réservé au "
                          f"groupe systemd-journal)."}
    return {"trouve": True, "texte": r.sortie}


def action_permise(unite: Unite) -> tuple:
    """(permis, raison). La raison sert d'infobulle sur le bouton éteint."""
    if unite.portee == "user":
        return True, ""
    return False, ("Service système : LEXOS PRO reste en lecture seule. "
                   "Le modifier demande une règle PolicyKit ciblée, qui "
                   "n'est pas encore en place. Utilisez systemctl dans un "
                   "terminal si vous savez ce que vous faites.")


def agir(unite: Unite, action: str) -> execution.Resultat:
    if action not in ACTIONS:
        return execution.Resultat(False, erreur=f"Action inconnue : {action}")
    permis, raison = action_permise(unite)
    if not permis:
        return execution.Resultat(False, erreur=raison)
    r = execution.lancer(["systemctl", "--user", action, unite.nom],
                         delai=20.0)
    if r.ok:
        return execution.Resultat(
            True, sortie=f"Demande « {_LIBELLES[action]} » envoyée à "
                         f"{unite.nom}.")
    return r
