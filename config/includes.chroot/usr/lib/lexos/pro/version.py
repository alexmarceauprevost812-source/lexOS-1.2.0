"""La version de LEXOS PRO, et d'où elle vient vraiment.

On ne code pas un numéro en dur ici : le dépôt en a déjà un dans
lexos.conf (LEXOS_VERSION). On le lit, et si on ne le trouve pas on le
DIT — « inconnue » — au lieu d'afficher un chiffre plausible.
"""
from __future__ import annotations

import os
from pathlib import Path

NOM = "LEXOS PRO"

#  Chemins essayés dans l'ordre : celui du système installé, puis celui du
#  dépôt quand on lance depuis les sources (mise au point).
_CANDIDATS = (
    Path("/etc/lexos/build.conf"),
    Path("/etc/lexos/lexos.conf"),
    Path(__file__).resolve().parents[6] / "lexos.conf",
)


def _lire_conf(chemin: Path) -> dict:
    """Lit un fichier « CLE="valeur" » sans l'exécuter.

    Surtout PAS un « source » ni un exec() : ce fichier est modifiable par
    la construction, et l'exécuter donnerait à n'importe quelle ligne le
    droit de tourner dans l'application.
    """
    valeurs = {}
    try:
        texte = chemin.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return valeurs
    for ligne in texte.splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, _, brut = ligne.partition("=")
        cle = cle.strip()
        if not cle.replace("_", "").isalnum():
            continue
        brut = brut.strip()
        if len(brut) >= 2 and brut[0] == brut[-1] and brut[0] in "\"'":
            brut = brut[1:-1]
        valeurs[cle] = brut
    return valeurs


def version() -> str:
    for chemin in _CANDIDATS:
        v = _lire_conf(chemin).get("LEXOS_VERSION")
        if v:
            return v
    return "inconnue"


def depuis_les_sources() -> bool:
    """Vrai quand on tourne depuis le dépôt et non depuis /usr/lib."""
    return not str(Path(__file__).resolve()).startswith("/usr/lib/")


def repertoire_donnees() -> Path:
    """XDG, et rien d'autre. Jamais un dossier caché inventé dans $HOME."""
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "lexos-pro"


def repertoire_config() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "lexos-pro"
