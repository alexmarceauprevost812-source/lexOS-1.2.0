"""Opérations de fichiers — sans suppression définitive.

CE QUE CETTE PREMIÈRE VERSION S'INTERDIT, sur consigne explicite : la
suppression définitive. Tout ce qui « supprime » va à la CORBEILLE, d'où
l'on peut revenir. Il n'y a donc aucun appel à os.remove / shutil.rmtree
dans ce fichier, et c'est volontaire : un module qui n'a pas le verbe ne
peut pas commettre l'action par mégarde au prochain remaniement.

LES CONFLITS DE NOMS NE SONT PAS ÉCRASÉS EN SILENCE. copier() et
deplacer() refusent une cible existante et rendent une erreur lisible ;
c'est à l'interface de proposer « remplacer » ou « renommer », après
confirmation.
"""
from __future__ import annotations

import os
import shutil
import stat
from dataclasses import dataclass
from pathlib import Path

from . import execution

#  Dossiers usuels : on lit ce que XDG déclare RÉELLEMENT, on ne devine pas
#  « ~/Documents » qui n'existe pas sur une session en anglais.
_XDG = (("XDG_DESKTOP_DIR", "Bureau"), ("XDG_DOCUMENTS_DIR", "Documents"),
        ("XDG_DOWNLOAD_DIR", "Téléchargements"), ("XDG_MUSIC_DIR", "Musique"),
        ("XDG_PICTURES_DIR", "Images"), ("XDG_VIDEOS_DIR", "Vidéos"))


@dataclass
class Entree:
    nom: str
    chemin: str
    dossier: bool
    taille: int = 0
    modifie: float = 0.0
    lisible: bool = True
    lien: bool = False


def dossiers_usuels() -> list:
    """Le dossier personnel et les dossiers XDG qui existent vraiment."""
    maison = Path.home()
    sortie = [{"nom": "Dossier personnel", "chemin": str(maison)}]
    config = Path(os.environ.get("XDG_CONFIG_HOME") or maison / ".config")
    declares = {}
    try:
        texte = (config / "user-dirs.dirs").read_text(encoding="utf-8",
                                                      errors="replace")
        for ligne in texte.splitlines():
            if "=" not in ligne or ligne.strip().startswith("#"):
                continue
            cle, _, val = ligne.partition("=")
            val = val.strip().strip('"')
            val = val.replace("$HOME", str(maison))
            declares[cle.strip()] = val
    except OSError:
        pass
    for cle, libelle in _XDG:
        chemin = os.environ.get(cle) or declares.get(cle)
        if not chemin:
            #  Repli : le nom anglais standard, mais SEULEMENT s'il existe.
            defaut = maison / cle.replace("XDG_", "").replace("_DIR", "").title()
            chemin = str(defaut)
        if os.path.isdir(chemin) and chemin != str(maison):
            sortie.append({"nom": libelle, "chemin": chemin})
    return sortie


def lister(dossier) -> dict:
    """Contenu d'un dossier. Un refus de droits est une réponse, pas un
    plantage."""
    chemin = Path(dossier)
    try:
        entrees = sorted(os.scandir(chemin), key=lambda e: e.name.lower())
    except PermissionError:
        return {"ok": False,
                "raison": f"Lecture de {chemin} refusée : vous n'avez pas "
                          f"les droits sur ce dossier."}
    except FileNotFoundError:
        return {"ok": False, "raison": f"{chemin} n'existe plus."}
    except NotADirectoryError:
        return {"ok": False, "raison": f"{chemin} n'est pas un dossier."}
    except OSError as e:
        return {"ok": False, "raison": f"{chemin} illisible : {e.strerror or e}"}
    liste = []
    for e in entrees:
        if e.name.startswith("."):
            continue
        try:
            est_dossier = e.is_dir(follow_symlinks=True)
            st = e.stat(follow_symlinks=False)
            taille = 0 if est_dossier else st.st_size
            modifie = st.st_mtime
            lisible = True
        except OSError:
            est_dossier, taille, modifie, lisible = False, 0, 0.0, False
        liste.append(Entree(nom=e.name, chemin=str(chemin / e.name),
                            dossier=est_dossier, taille=taille,
                            modifie=modifie, lisible=lisible,
                            lien=e.is_symlink()))
    liste.sort(key=lambda x: (not x.dossier, x.nom.lower()))
    return {"ok": True, "entrees": liste}


def ouvrir(chemin) -> execution.Resultat:
    """Ouvre avec l'application associée. xdg-open, jamais un shell."""
    if execution.outil_present("xdg-open"):
        return execution.lancer_detache(["xdg-open", str(chemin)])
    if execution.outil_present("gio"):
        return execution.lancer_detache(["gio", "open", str(chemin)])
    return execution.Resultat(
        False, erreur="Ni « xdg-open » ni « gio » n'est installé : LEXOS PRO "
                      "ne peut pas déterminer l'application associée.")


def creer_dossier(parent, nom: str) -> execution.Resultat:
    nom = nom.strip()
    if not nom or nom in (".", ".."):
        return execution.Resultat(False, erreur="Nom de dossier vide.")
    if "/" in nom:
        return execution.Resultat(
            False, erreur="Un nom de dossier ne peut pas contenir « / ».")
    cible = Path(parent) / nom
    try:
        cible.mkdir()
    except FileExistsError:
        return execution.Resultat(
            False, erreur=f"« {nom} » existe déjà dans ce dossier.")
    except PermissionError:
        return execution.Resultat(
            False, erreur=f"Création refusée : vous n'avez pas les droits "
                          f"d'écriture dans {parent}.")
    except OSError as e:
        return execution.Resultat(False, erreur=f"Création impossible : {e.strerror or e}")
    return execution.Resultat(True, sortie=str(cible))


def renommer(chemin, nouveau_nom: str) -> execution.Resultat:
    nouveau_nom = nouveau_nom.strip()
    if not nouveau_nom or "/" in nouveau_nom or nouveau_nom in (".", ".."):
        return execution.Resultat(False, erreur="Nom invalide.")
    source = Path(chemin)
    cible = source.parent / nouveau_nom
    if cible.exists():
        return execution.Resultat(
            False, erreur=f"« {nouveau_nom} » existe déjà dans ce dossier.")
    try:
        source.rename(cible)
    except PermissionError:
        return execution.Resultat(
            False, erreur="Renommage refusé : droits insuffisants.")
    except OSError as e:
        return execution.Resultat(False, erreur=f"Renommage impossible : {e.strerror or e}")
    return execution.Resultat(True, sortie=str(cible))


def copier(source, dossier_cible, *, remplacer: bool = False) -> execution.Resultat:
    src = Path(source)
    dst = Path(dossier_cible) / src.name
    if dst.exists() and not remplacer:
        return execution.Resultat(
            False, erreur=f"« {src.name} » existe déjà dans le dossier de "
                          f"destination.")
    if src.resolve() == dst.resolve():
        return execution.Resultat(
            False, erreur="La source et la destination sont identiques.")
    try:
        if src.is_dir():
            #  dirs_exist_ok seulement si l'utilisateur a confirmé.
            shutil.copytree(src, dst, dirs_exist_ok=remplacer,
                            symlinks=True)
        else:
            shutil.copy2(src, dst, follow_symlinks=False)
    except PermissionError:
        return execution.Resultat(False, erreur="Copie refusée : droits insuffisants.")
    except shutil.Error as e:
        return execution.Resultat(False, erreur=f"Copie partielle : {e}")
    except OSError as e:
        return execution.Resultat(False, erreur=f"Copie impossible : {e.strerror or e}")
    return execution.Resultat(True, sortie=str(dst))


def deplacer(source, dossier_cible, *, remplacer: bool = False) -> execution.Resultat:
    src = Path(source)
    dst = Path(dossier_cible) / src.name
    if dst.exists() and not remplacer:
        return execution.Resultat(
            False, erreur=f"« {src.name} » existe déjà dans le dossier de "
                          f"destination.")
    try:
        #  shutil.move traverse les systèmes de fichiers ; os.rename non.
        shutil.move(str(src), str(dst))
    except PermissionError:
        return execution.Resultat(False, erreur="Déplacement refusé : droits insuffisants.")
    except OSError as e:
        return execution.Resultat(False, erreur=f"Déplacement impossible : {e.strerror or e}")
    return execution.Resultat(True, sortie=str(dst))


def a_la_corbeille(chemin) -> execution.Resultat:
    """Corbeille, JAMAIS suppression définitive.

    On délègue à gio trash, qui respecte la spécification freedesktop
    (dossier .Trash-<uid> sur le bon volume, fichier .trashinfo pour
    pouvoir restaurer). Réimplémenter ça à la main, c'est se tromper de
    volume et perdre la possibilité de revenir en arrière.
    """
    if execution.outil_present("gio"):
        r = execution.lancer(["gio", "trash", str(chemin)], delai=15.0)
        if r.ok:
            return execution.Resultat(True, sortie=f"{chemin} mis à la corbeille.")
        return r
    if execution.outil_present("kioclient5"):
        return execution.lancer(["kioclient5", "move", str(chemin), "trash:/"],
                                delai=15.0)
    return execution.Resultat(
        False, erreur="Aucun outil de corbeille n'est disponible : « gio » "
                      "(paquet glib2.0-bin) est nécessaire. LEXOS PRO ne "
                      "supprime jamais définitivement un fichier.")


def proprietes(chemin) -> dict:
    p = Path(chemin)
    try:
        st = p.lstat()
    except OSError as e:
        return {"ok": False, "raison": f"{chemin} : {e.strerror or e}"}
    import grp
    import pwd
    try:
        proprietaire = pwd.getpwuid(st.st_uid).pw_name
    except (KeyError, ImportError):
        proprietaire = str(st.st_uid)
    try:
        groupe = grp.getgrgid(st.st_gid).gr_name
    except (KeyError, ImportError):
        groupe = str(st.st_gid)
    return {"ok": True, "nom": p.name, "chemin": str(p),
            "type": "Dossier" if p.is_dir() else
                    ("Lien symbolique" if p.is_symlink() else "Fichier"),
            "taille": st.st_size, "modifie": st.st_mtime,
            "droits": stat.filemode(st.st_mode),
            "proprietaire": proprietaire, "groupe": groupe,
            "accessible_ecriture": os.access(p, os.W_OK)}
