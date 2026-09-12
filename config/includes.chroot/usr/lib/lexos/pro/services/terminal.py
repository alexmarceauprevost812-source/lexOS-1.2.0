"""Ouvrir le VRAI terminal du système — jamais une imitation.

La consigne est nette : pas de faux terminal interactif dans un champ
texte. Un champ texte qui fait semblant ne gère ni les couleurs, ni la
complétion, ni Ctrl-C, ni un éditeur plein écran — et donne l'illusion du
contraire. On lance donc l'émulateur installé, dans le bon dossier, et
l'interface le dit clairement à l'utilisateur.
"""
from __future__ import annotations

import os
import shutil
from pathlib import Path

from . import capacites, execution

#  L'option « démarrer ici » n'a pas le même nom partout.
_OPTION_DOSSIER = {
    "xfce4-terminal": "--working-directory={}",
    "gnome-terminal": "--working-directory={}",
    "mate-terminal": "--working-directory={}",
    "tilix": "--working-directory={}",
    "konsole": "--workdir={}",
    "kitty": "--directory={}",
    "alacritty": "--working-directory={}",
    "lxterminal": "--working-directory={}",
}

TI_LEX = ("ti-lex", "tilex", "TI-LEX", "lexos-ti-lex")


def terminaux_disponibles() -> list:
    return list(capacites.tous_presents(capacites.TERMINAUX))


def ouvrir(dossier=None, emulateur: str = "") -> execution.Resultat:
    dossier = str(dossier or Path.home())
    if not os.path.isdir(dossier):
        return execution.Resultat(
            False, erreur=f"{dossier} n'est pas un dossier.")
    choisi = emulateur or capacites.premier_present(capacites.TERMINAUX)
    if not choisi:
        return execution.Resultat(
            False, erreur="Aucun émulateur de terminal n'est installé "
                          "(xfce4-terminal, gnome-terminal, konsole, "
                          "xterm…).")
    argv = [choisi]
    gabarit = _OPTION_DOSSIER.get(choisi)
    if gabarit:
        argv.append(gabarit.format(dossier))
        return execution.lancer_detache(argv)
    #  xterm et les autres : pas d'option de dossier. On y va par « cd »,
    #  mais SANS shell=True — c'est bash qui reçoit la chaîne, pas un shell
    #  intermédiaire, et le chemin est passé par une variable
    #  d'environnement plutôt qu'interpolé dans la commande.
    return _ouvrir_par_cd(choisi, dossier)


def _ouvrir_par_cd(emulateur: str, dossier: str) -> execution.Resultat:
    """Le chemin passe par l'ENVIRONNEMENT, pas par la ligne de commande.

    Interpoler un chemin dans « cd <chemin> » serait une injection : un
    dossier nommé « ; rm -rf ~ » deviendrait une commande. Avec
    « cd -- "$LEXOS_PRO_DOSSIER" », la valeur reste une valeur quoi qu'elle
    contienne.
    """
    if not shutil.which("bash"):
        return execution.Resultat(
            False, erreur=f"« {emulateur} » n'accepte pas d'option de "
                          f"dossier et bash est absent : impossible d'ouvrir "
                          f"le terminal à cet emplacement.")
    script = 'cd -- "$LEXOS_PRO_DOSSIER" && exec bash'
    argv = [emulateur, "-e", "bash", "-lc", script]
    try:
        import subprocess
        env = dict(os.environ)
        env["LEXOS_PRO_DOSSIER"] = dossier
        subprocess.Popen(argv, start_new_session=True, env=env,
                         stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as e:
        return execution.Resultat(False, erreur=f"{emulateur} : {e}")
    return execution.Resultat(True)


def ti_lex() -> dict:
    """TI-LEX est-il installé ? On le dit franchement dans les deux cas."""
    nom = capacites.premier_present(TI_LEX)
    if nom:
        return {"trouve": True, "commande": nom}
    return {"trouve": False,
            "raison": "TI-LEX n'est pas installé sur ce système : aucun "
                      "exécutable « ti-lex » n'a été trouvé sur le PATH."}


def lancer_ti_lex(dossier=None) -> execution.Resultat:
    t = ti_lex()
    if not t["trouve"]:
        return execution.Resultat(False, erreur=t["raison"])
    return execution.lancer_detache([t["commande"]])
