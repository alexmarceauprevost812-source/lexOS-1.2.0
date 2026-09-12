"""Espace projets — Git en lecture seule, tests sur demande EXPLICITE.

LA RÈGLE QUI PROTÈGE L'UTILISATEUR : lancer les tests d'un projet, c'est
EXÉCUTER SON CODE. Ouvrir un dossier ne doit donc jamais les déclencher.
La fonction s'appelle lancer_tests() et n'est appelée que depuis un bouton
dont le libellé le dit, après un avertissement affiché.

Git est en lecture seule : « status », « branche ». Aucun commit, aucun
push, aucun checkout — une application de bureau n'a pas à toucher
l'historique de quelqu'un.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from . import execution


def est_depot_git(dossier) -> bool:
    return (Path(dossier) / ".git").exists()


def etat_git(dossier) -> dict:
    if not execution.outil_present("git"):
        return {"trouve": False,
                "raison": "git n'est pas installé sur ce système."}
    if not est_depot_git(dossier):
        return {"trouve": False,
                "raison": "Ce dossier n'est pas un dépôt Git."}
    branche = execution.lancer(
        ["git", "-C", str(dossier), "rev-parse", "--abbrev-ref", "HEAD"])
    etat = execution.lancer(
        ["git", "-C", str(dossier), "status", "--porcelain"], delai=15.0)
    if not etat.ok:
        return {"trouve": False, "raison": etat.erreur}
    modifies = [l for l in etat.lignes()]
    return {"trouve": True,
            "branche": branche.sortie.strip() if branche.ok else "inconnue",
            "modifies": len(modifies),
            "details": modifies[:200]}


def python_du_projet(dossier) -> dict:
    """Un environnement virtuel du projet, s'il existe déjà."""
    for nom in (".venv", "venv", "env"):
        candidat = Path(dossier) / nom / "bin" / "python"
        if candidat.exists():
            return {"trouve": True, "chemin": str(candidat), "venv": nom}
    return {"trouve": False,
            "raison": "Aucun environnement virtuel (.venv, venv, env) dans "
                      "ce dossier."}


def creer_venv(dossier) -> execution.Resultat:
    """Crée .venv avec le Python du système. Jamais en écrasant un existant."""
    cible = Path(dossier) / ".venv"
    if cible.exists():
        return execution.Resultat(
            False, erreur=f"{cible} existe déjà. LEXOS PRO n'écrase pas un "
                          f"environnement existant.")
    return execution.lancer([sys.executable, "-m", "venv", str(cible)],
                            delai=180.0)


def commande_tests(dossier) -> dict:
    """QUOI lancer, décidé sur ce que le projet contient RÉELLEMENT.

    On ne devine pas : on cherche des marqueurs. Si aucun n'est là, on le
    dit et le bouton reste éteint — plutôt que de lancer « make test » dans
    un dossier qui n'a pas de Makefile.
    """
    d = Path(dossier)
    py = python_du_projet(dossier)
    interprete = py["chemin"] if py["trouve"] else sys.executable
    if (d / "pytest.ini").exists() or (d / "pyproject.toml").exists() \
            or (d / "tests").is_dir():
        return {"trouve": True, "argv": [interprete, "-m", "pytest", "-q"],
                "libelle": "pytest"}
    if (d / "package.json").exists():
        if execution.outil_present("npm"):
            return {"trouve": True, "argv": ["npm", "test"], "libelle": "npm test"}
        return {"trouve": False, "raison": "package.json présent mais npm "
                                           "n'est pas installé."}
    if (d / "Makefile").exists():
        return {"trouve": True, "argv": ["make", "test"], "libelle": "make test"}
    if (d / "Cargo.toml").exists():
        return {"trouve": True, "argv": ["cargo", "test"], "libelle": "cargo test"}
    return {"trouve": False,
            "raison": "Aucun test reconnu dans ce dossier (ni pytest, ni "
                      "package.json, ni Makefile, ni Cargo.toml)."}


def lancer_tests(dossier, *, delai: float = 300.0) -> execution.Resultat:
    """N'EST JAMAIS APPELÉE AUTOMATIQUEMENT. Exécute le code du projet."""
    cmd = commande_tests(dossier)
    if not cmd["trouve"]:
        return execution.Resultat(False, erreur=cmd["raison"])
    ancien = os.getcwd()
    try:
        os.chdir(dossier)
        return execution.lancer(cmd["argv"], delai=delai)
    except OSError as e:
        return execution.Resultat(False, erreur=f"{dossier} : {e.strerror or e}")
    finally:
        try:
            os.chdir(ancien)
        except OSError:
            pass


def outils() -> dict:
    """Python et Git, mesurés."""
    resultat = {}
    for nom, argv in (("python", [sys.executable, "--version"]),
                      ("git", ["git", "--version"])):
        r = execution.lancer(argv)
        resultat[nom] = {"present": r.ok,
                         "version": r.sortie.strip() if r.ok else "",
                         "raison": "" if r.ok else r.erreur}
    return resultat
