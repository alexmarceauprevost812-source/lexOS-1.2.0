"""Diagnostic DÉFENSIF — constater, expliquer, ne rien modifier.

CE QUE CE MODULE NE FERA JAMAIS : ouvrir ou fermer un port, activer ou
désactiver un pare-feu, balayer une autre machine, tenter quoi que ce soit
contre un service. Il lit l'état de CETTE machine et le présente.

ET IL NE DIT JAMAIS « système sécurisé ». La consigne est explicite, et
elle a raison : un contrôle réussi ne prouve que ce contrôle. Un pare-feu
actif ne dit rien des mots de passe, des mises à jour ou des permissions.
La synthèse rend donc un COMPTE de points vérifiés, jamais un verdict.
"""
from __future__ import annotations

import os

from . import capacites, execution


def pare_feu() -> dict:
    """ufw, firewalld, ou nftables — et « indéterminable » est une réponse."""
    if execution.outil_present("ufw"):
        r = execution.lancer(["ufw", "status"])
        if r.ok:
            actif = "status: active" in r.sortie.lower()
            return {"mesure": True, "outil": "ufw",
                    "actif": actif, "detail": r.sortie.splitlines()[0]
                    if r.sortie else ""}
        return {"mesure": False, "outil": "ufw",
                "raison": f"ufw est installé mais son état n'est pas "
                          f"lisible sans droits d'administration : {r.erreur}"}
    if execution.outil_present("firewall-cmd"):
        r = execution.lancer(["firewall-cmd", "--state"])
        if r.ok:
            return {"mesure": True, "outil": "firewalld",
                    "actif": "running" in r.sortie.lower(),
                    "detail": r.sortie.strip()}
        return {"mesure": False, "outil": "firewalld", "raison": r.erreur}
    if execution.outil_present("nft"):
        r = execution.lancer(["nft", "list", "ruleset"])
        if r.ok:
            return {"mesure": True, "outil": "nftables",
                    "actif": bool(r.sortie.strip()),
                    "detail": f"{len(r.lignes())} lignes de règles"}
        return {"mesure": False, "outil": "nftables", "raison": r.erreur}
    return {"mesure": False, "outil": "",
            "raison": "Aucun outil de pare-feu connu n'est installé "
                      "(ufw, firewall-cmd, nft). Cela ne veut pas dire "
                      "qu'il n'y a pas de filtrage : le noyau peut en "
                      "porter sans ces outils."}


def secure_boot() -> dict:
    """L'état réel, lu dans les variables EFI.

    mokutil est le chemin propre ; à défaut, la variable EFI SecureBoot
    dont le dernier octet vaut 1 quand il est actif. Sur une machine
    démarrée en BIOS hérité, la question n'a pas de sens et on le dit.
    """
    if not os.path.isdir("/sys/firmware/efi"):
        return {"mesure": True, "actif": False, "sans_objet": True,
                "detail": "Machine démarrée en mode BIOS hérité : le Secure "
                          "Boot ne s'applique pas."}
    if execution.outil_present("mokutil"):
        r = execution.lancer(["mokutil", "--sb-state"])
        if r.ok:
            bas = r.sortie.lower()
            if "enabled" in bas:
                return {"mesure": True, "actif": True, "detail": r.sortie.strip()}
            if "disabled" in bas:
                return {"mesure": True, "actif": False, "detail": r.sortie.strip()}
            return {"mesure": False,
                    "raison": f"Réponse de mokutil non comprise : {r.sortie[:80]}"}
    import glob
    for chemin in glob.glob("/sys/firmware/efi/efivars/SecureBoot-*"):
        try:
            with open(chemin, "rb") as f:
                donnees = f.read()
            if len(donnees) >= 5:
                return {"mesure": True, "actif": donnees[4] == 1,
                        "detail": f"variable EFI {os.path.basename(chemin)}"}
        except OSError:
            continue
    return {"mesure": False,
            "raison": "L'état du Secure Boot n'est pas lisible : ni mokutil "
                      "installé, ni variable EFI accessible."}


def ports_en_ecoute() -> dict:
    """Les ports ouverts SUR CETTE MACHINE, lus avec ss.

    Sans droits d'administration, ss ne peut pas nommer le processus
    derrière chaque port. On le dit plutôt que de laisser une colonne vide
    qu'on croirait signifier « aucun processus ».
    """
    if not execution.outil_present("ss"):
        return {"trouve": False,
                "raison": "L'outil « ss » n'est pas installé (paquet "
                          "iproute2) : les ports en écoute ne peuvent pas "
                          "être listés."}
    r = execution.lancer(["ss", "-tulnp"], delai=10.0)
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    lignes = r.lignes()[1:]
    entrees = []
    sans_processus = 0
    for ligne in lignes:
        champs = ligne.split()
        if len(champs) < 5:
            continue
        proc = ""
        if "users:" in ligne:
            proc = ligne[ligne.index("users:"):].strip()
        else:
            sans_processus += 1
        entrees.append({"protocole": champs[0], "locale": champs[4],
                        "processus": proc})
    note = ""
    if sans_processus and os.geteuid() != 0:
        note = (f"{sans_processus} port(s) sans nom de processus : « ss » ne "
                f"nomme que les processus de l'utilisateur courant sans "
                f"droits d'administration.")
    if not entrees:
        return {"trouve": False,
                "raison": "ss n'a signalé aucun port en écoute."}
    return {"trouve": True, "ports": entrees, "note": note}


def journaux_accessibles() -> dict:
    if not execution.outil_present("journalctl"):
        return {"trouve": False,
                "raison": "journalctl n'est pas installé."}
    r = execution.lancer(["journalctl", "--no-pager", "-n", "80",
                          "-p", "warning"], delai=15.0)
    if not r.ok:
        return {"trouve": False, "raison": r.erreur}
    if not r.sortie.strip():
        return {"trouve": False,
                "raison": "Aucune entrée de niveau « avertissement » ou "
                          "plus n'est lisible par cet utilisateur."}
    return {"trouve": True, "texte": r.sortie}


def synthese() -> dict:
    """Un COMPTE de points vérifiés — jamais un verdict.

    « 3 points vérifiés sur 4 » est une information. « Système sécurisé »
    serait un mensonge : rien ici ne regarde les mots de passe, les
    permissions des fichiers, ni ce qui tourne dans le navigateur.
    """
    points = {
        "pare-feu": pare_feu(),
        "Secure Boot": secure_boot(),
        "ports en écoute": ports_en_ecoute(),
        "journaux": journaux_accessibles(),
    }
    mesures = sum(1 for v in points.values()
                  if v.get("mesure") or v.get("trouve"))
    return {"points": points, "mesures": mesures, "total": len(points),
            "avertissement":
                "Ce tableau constate quatre points précis. Il ne dit pas si "
                "la machine est sûre : aucun outil ne peut le dire."}
