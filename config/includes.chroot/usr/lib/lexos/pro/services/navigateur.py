"""Ouverture d'adresses Web — et la validation qui empêche le pire.

UNE URL N'EST JAMAIS UNE COMMANDE. Elle part comme UN élément d'argv vers
xdg-open, jamais dans un shell. Et seuls http:// et https:// sont acceptés :
« file:// » exposerait le disque, « javascript: » et « data: » sont des
vecteurs classiques, et un schéma inventé pourrait viser un gestionnaire
d'URL du bureau qui, lui, exécute des choses.
"""
from __future__ import annotations

import re
from urllib.parse import urlparse

from . import capacites, execution

SCHEMAS_AUTORISES = ("http", "https")
NAVIGATEURS = ("x-www-browser", "firefox", "chromium", "google-chrome",
               "brave-browser", "epiphany", "falkon", "midori")


#  UN SCHÉMA, C'EST « nom: » — PAS « nom:// ».
#  Le premier jet de cette fonction testait « "://" not in texte » avant
#  d'ajouter « https:// ». Or « javascript:alert(1) » ne contient pas
#  « :// » : il devenait donc « https://javascript:alert(1) », qui passait
#  la vérification de schéma les doigts dans le nez. C'est exactement le
#  vecteur que cette fonction existe pour bloquer, et il est passé.
#  La leçon : on RECONNAÎT le schéma déclaré, on ne devine pas son absence.
_SCHEMA = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")


def normaliser(saisie: str) -> dict:
    """Transforme une saisie en URL sûre, ou explique le refus."""
    texte = (saisie or "").strip()
    if not texte:
        return {"ok": False, "raison": "Adresse vide."}
    if any(c.isspace() for c in texte):
        return {"ok": False,
                "raison": "Une adresse Web ne contient pas d'espace. Pour "
                          "chercher, utilisez votre moteur de recherche."}
    #  Les caractères de contrôle ne sont jamais légitimes dans une saisie
    #  d'adresse et servent à masquer la vraie cible.
    if any(ord(c) < 32 or ord(c) == 127 for c in texte):
        return {"ok": False,
                "raison": "Cette adresse contient des caractères de "
                          "contrôle : elle est refusée."}
    declare = _SCHEMA.match(texte)
    if declare:
        schema = declare.group(0)[:-1].lower()
        if schema not in SCHEMAS_AUTORISES:
            return {"ok": False,
                    "raison": f"Seuls http et https sont acceptés ici. "
                              f"« {schema}: » est refusé."}
    else:
        #  Aucun schéma déclaré : on suppose https — le plus sûr des deux,
        #  jamais http.
        texte = "https://" + texte
    try:
        u = urlparse(texte)
    except ValueError as e:
        return {"ok": False, "raison": f"Adresse illisible : {e}"}
    if u.scheme not in SCHEMAS_AUTORISES:
        return {"ok": False,
                "raison": f"Seuls http et https sont acceptés ici. "
                          f"« {u.scheme}: » est refusé."}
    if not u.netloc:
        return {"ok": False, "raison": "Cette adresse n'a pas de nom de domaine."}
    #  urlparse accepte « https://javascript:alert(1) » et range
    #  « javascript » en hôte avec « alert(1) » en port. On EXIGE donc que
    #  le port, s'il y en a un, soit un nombre : c'est ce que .port fait,
    #  en levant ValueError sinon.
    try:
        u.port
    except ValueError:
        return {"ok": False,
                "raison": "Le port indiqué dans cette adresse n'est pas un "
                          "nombre : l'adresse est refusée."}
    #  « https://banque.fr@site-pirate.fr » : le vrai hôte est le SECOND.
    #  u.hostname rend déjà « site-pirate.fr » et masque donc le piège — il
    #  faut regarder netloc, avant découpage. Deuxième trou trouvé par le
    #  banc dans cette même fonction, et par le même mécanisme : une
    #  vérification faite sur une valeur déjà nettoyée ne vérifie rien.
    if "@" in u.netloc:
        return {"ok": False,
                "raison": "Cette adresse contient « @ » avant le nom de "
                          "domaine : la partie visible n'est alors pas le "
                          "site réellement visité. Refusée par précaution."}
    hote = u.hostname or ""
    if not hote or "\\" in hote:
        return {"ok": False,
                "raison": "Le nom de domaine de cette adresse est invalide."}
    return {"ok": True, "url": u.geturl()}


def ouvrir(saisie: str) -> execution.Resultat:
    v = normaliser(saisie)
    if not v["ok"]:
        return execution.Resultat(False, erreur=v["raison"])
    if execution.outil_present("xdg-open"):
        return execution.lancer_detache(["xdg-open", v["url"]])
    nav = capacites.premier_present(NAVIGATEURS)
    if nav:
        return execution.lancer_detache([nav, v["url"]])
    return execution.Resultat(
        False, erreur="Aucun navigateur Web n'a été trouvé sur ce système.")


def navigateur_par_defaut() -> dict:
    if execution.outil_present("xdg-settings"):
        r = execution.lancer(["xdg-settings", "get", "default-web-browser"])
        if r.ok and r.sortie.strip():
            return {"trouve": True, "nom": r.sortie.strip()}
    nav = capacites.premier_present(NAVIGATEURS)
    if nav:
        return {"trouve": True, "nom": nav,
                "note": "Déduit du PATH : xdg-settings n'a pas répondu."}
    return {"trouve": False,
            "raison": "Aucun navigateur par défaut n'a pu être déterminé."}
