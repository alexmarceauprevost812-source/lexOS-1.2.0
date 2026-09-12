"""Le seul endroit d'où LEXOS PRO sort de son processus.

TROIS RÈGLES, TENUES ICI ET NULLE PART AILLEURS :

  1. JAMAIS shell=True. argv est une LISTE. Un nom de fichier contenant
     « ; rm -rf » est alors un nom de fichier, pas une commande. C'est la
     différence entre un gestionnaire de fichiers et un piège.
  2. TOUJOURS un délai maximal. Une commande qui ne rend pas la main
     (nvidia-smi sur un pilote à moitié chargé, systemctl sur un bus mort)
     gèlerait l'interface. Le délai est une erreur lisible, pas un gel.
  3. stdin FERMÉE. Sans ça, un outil qui réclame un mot de passe le
     demanderait sur le terminal d'où l'application a été lancée — une
     fenêtre que personne ne regarde — et le bouton resterait figé jusqu'au
     délai. Leçon déjà payée dans settings.py de ce dépôt.

Et une quatrième, qui est la raison d'être du type Resultat : un échec
porte TOUJOURS un motif affichable. « Ça n'a pas marché » sans raison,
c'est ce qui a fait croire pendant des semaines que des boutons étaient
cassés alors qu'il manquait un paquet.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass, field

#  Délai par défaut. Volontairement court : tout ce qu'on appelle ici est
#  censé répondre en un clin d'œil. Les rares commandes lentes le disent
#  en passant leur propre délai.
DELAI_DEFAUT = 8.0


@dataclass
class Resultat:
    """Ce qu'une commande a VRAIMENT donné.

    `ok` ne veut pas dire « la commande existe » : il veut dire « elle a
    tourné et a rendu 0 ». Tout le reste porte `erreur`, et `erreur` est
    faite pour être montrée à l'écran telle quelle.
    """

    ok: bool
    sortie: str = ""
    erreur: str = ""
    code: int | None = None
    argv: list = field(default_factory=list)

    def lignes(self) -> list:
        return [l for l in self.sortie.splitlines() if l.strip()]

    def __bool__(self) -> bool:  # pragma: no cover - sucre
        return self.ok


def outil_present(nom: str) -> bool:
    """L'outil est-il exécutable sur le PATH ?"""
    return shutil.which(nom) is not None


def lancer(argv, *, delai: float = DELAI_DEFAUT, entree: str | None = None,
           env_sup: dict | None = None) -> Resultat:
    """Exécute argv et rend un Resultat. Ne lève jamais.

    Une exception qui traverse cette fonction finirait dans la boucle Qt et
    fermerait la fenêtre. On les attrape donc toutes ici, et chacune devient
    un motif lisible.
    """
    if not argv:
        return Resultat(False, erreur="Commande vide.", argv=[])
    argv = [str(a) for a in argv]
    if shutil.which(argv[0]) is None:
        return Resultat(False, argv=argv,
                        erreur=f"L'outil « {argv[0]} » n'est pas installé "
                               f"sur ce système.")
    env = None
    if env_sup:
        env = dict(os.environ)
        env.update(env_sup)
    try:
        r = subprocess.run(
            argv, capture_output=True, text=True, timeout=delai,
            stdin=subprocess.DEVNULL if entree is None else subprocess.PIPE,
            input=entree, env=env, errors="replace")
    except subprocess.TimeoutExpired:
        #  « %g » et pas « %.0f » : un délai de 0,3 s s'affichait « 0 s »,
        #  ce qui donnait le message absurde « n'a pas répondu en 0 s ».
        return Resultat(False, argv=argv,
                        erreur=f"« {argv[0]} » n'a pas répondu en "
                               f"{delai:g} s — abandon.")
    except PermissionError:
        return Resultat(False, argv=argv,
                        erreur=f"Permission refusée pour « {argv[0]} ».")
    except OSError as e:
        return Resultat(False, argv=argv,
                        erreur=f"« {argv[0]} » n'a pas pu être lancé : {e}")

    sortie = (r.stdout or "").strip()
    erreur_brute = (r.stderr or "").strip()
    if r.returncode == 0:
        #  stderr non vide avec un code 0 n'est PAS un échec : beaucoup
        #  d'outils y écrivent des avertissements. On garde la sortie.
        return Resultat(True, sortie=sortie or erreur_brute, code=0, argv=argv)

    #  L'échec porte la DERNIÈRE ligne utile, celle qui dit pourquoi.
    source = erreur_brute or sortie
    motif = ""
    for ligne in reversed(source.splitlines()):
        if ligne.strip():
            motif = ligne.strip()
            break
    if not motif:
        motif = f"« {argv[0]} » a échoué (code {r.returncode})."
    return Resultat(False, sortie=source, erreur=motif,
                    code=r.returncode, argv=argv)


def lancer_detache(argv) -> Resultat:
    """Lance une application graphique et rend la main immédiatement.

    start_new_session : l'enfant survit à la fermeture de LEXOS PRO, ce qui
    est le comportement attendu quand on ouvre un terminal ou un navigateur.
    """
    if not argv:
        return Resultat(False, erreur="Commande vide.")
    argv = [str(a) for a in argv]
    if shutil.which(argv[0]) is None:
        return Resultat(False, argv=argv,
                        erreur=f"L'outil « {argv[0]} » n'est pas installé "
                               f"sur ce système.")
    try:
        subprocess.Popen(argv, start_new_session=True,
                         stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    except OSError as e:
        return Resultat(False, argv=argv,
                        erreur=f"« {argv[0]} » n'a pas pu être lancé : {e}")
    return Resultat(True, argv=argv)


def lire_fichier(chemin, *, limite: int = 1 << 20) -> Resultat:
    """Lit un fichier système. L'absence et le refus sont des cas NORMAUX.

    /proc et /sys sont pleins de fichiers qui existent sur une machine et
    pas sur l'autre, ou que seul root peut lire. Chacun doit devenir une
    phrase à l'écran, pas une exception.
    """
    try:
        with open(chemin, "r", encoding="utf-8", errors="replace") as f:
            return Resultat(True, sortie=f.read(limite))
    except FileNotFoundError:
        return Resultat(False, erreur=f"{chemin} n'existe pas sur ce système.")
    except PermissionError:
        return Resultat(False,
                        erreur=f"Lecture de {chemin} refusée (droits "
                               f"insuffisants pour cet utilisateur).")
    except OSError as e:
        return Resultat(False, erreur=f"{chemin} illisible : {e}")
