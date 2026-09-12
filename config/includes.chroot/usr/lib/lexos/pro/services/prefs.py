"""Préférences de l'application — dans XDG, et nulle part ailleurs.

AUCUN SECRET N'EST ÉCRIT ICI. Pas de mot de passe Wi-Fi, pas de jeton :
ces choses appartiennent au trousseau du bureau, et LEXOS PRO ne les
touche pas. Ce fichier ne contient que des goûts : thème, taille du texte,
animations, favoris, projets.

Écriture ATOMIQUE — fichier temporaire dans le MÊME dossier puis rename.
Une écriture directe interrompue (batterie, plantage) laisserait un JSON
tronqué, et l'application repartirait sans préférences sans dire pourquoi.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

from ..version import repertoire_config

DEFAUTS = {
    "animations": True,
    "taille_texte": 100,          # pourcentage
    "densite": "confortable",     # « compacte » ou « confortable »
    "favoris": [
        {"nom": "Debian", "url": "https://www.debian.org/"},
        {"nom": "Documentation Python", "url": "https://docs.python.org/fr/3/"},
    ],
    "projets": [],
    "dernier_dossier": "",
}


def _chemin() -> Path:
    return repertoire_config() / "preferences.json"


def charger() -> dict:
    valeurs = dict(DEFAUTS)
    chemin = _chemin()
    try:
        brut = json.loads(chemin.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return valeurs
    except (json.JSONDecodeError, OSError):
        #  Un fichier illisible ne doit pas empêcher l'application de
        #  démarrer : on repart des défauts, sans écraser le fichier —
        #  l'utilisateur peut encore le récupérer.
        return valeurs
    if isinstance(brut, dict):
        for cle, val in brut.items():
            if cle in DEFAUTS and isinstance(val, type(DEFAUTS[cle])):
                valeurs[cle] = val
    return valeurs


def enregistrer(valeurs: dict) -> bool:
    chemin = _chemin()
    try:
        chemin.parent.mkdir(parents=True, exist_ok=True)
        temporaire = chemin.with_suffix(".json.nouveau")
        temporaire.write_text(
            json.dumps(valeurs, ensure_ascii=False, indent=2),
            encoding="utf-8")
        os.replace(temporaire, chemin)
        return True
    except OSError:
        return False
