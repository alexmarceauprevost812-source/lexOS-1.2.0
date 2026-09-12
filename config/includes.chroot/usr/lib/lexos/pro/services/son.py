"""Son — wpctl (PipeWire), pactl, ou délégation aux réglages natifs.

Quand aucune intégration fiable n'existe, on n'invente pas un curseur qui
ne bouge rien : on ouvre l'outil natif et on explique pourquoi.
"""
from __future__ import annotations

from . import capacites, execution


def peripheriques() -> dict:
    a = capacites.audio()
    if not a["present"]:
        return {"trouve": False, "raison": a["raison"]}
    if a["outil"] == "wpctl":
        r = execution.lancer(["wpctl", "status"])
        if not r.ok:
            return {"trouve": False, "raison": r.erreur}
        return {"trouve": True, "pile": a["pile"], "brut": r.sortie,
                "sorties": _wpctl_sorties(r.sortie)}
    if a["outil"] == "pactl":
        r = execution.lancer(["pactl", "list", "short", "sinks"])
        if not r.ok:
            return {"trouve": False, "raison": r.erreur}
        sorties = []
        for ligne in r.lignes():
            champs = ligne.split("\t")
            if len(champs) >= 2:
                sorties.append({"nom": champs[1], "detail": champs[-1]})
        if not sorties:
            return {"trouve": False,
                    "raison": "pactl ne signale aucune sortie audio."}
        return {"trouve": True, "pile": a["pile"], "sorties": sorties,
                "brut": r.sortie}
    return {"trouve": False,
            "raison": f"Seul « {a['outil']} » est disponible : LEXOS PRO "
                      f"n'en lit pas les périphériques."}


def _wpctl_sorties(texte: str) -> list:
    """Extrait la section « Sinks » de wpctl status."""
    sorties, dedans = [], False
    for ligne in texte.splitlines():
        if "Sinks:" in ligne:
            dedans = True
            continue
        if dedans:
            nu = ligne.strip(" │├└─")
            if not nu:
                break
            sorties.append({"nom": nu, "detail": ""})
    return sorties


def volume() -> dict:
    a = capacites.audio()
    if a["outil"] == "wpctl":
        r = execution.lancer(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
        if not r.ok:
            return {"trouve": False, "raison": r.erreur}
        #  « Volume: 0.65 [MUTED] »
        txt = r.sortie
        muet = "MUTED" in txt.upper()
        try:
            val = float(txt.split(":")[1].split()[0])
        except (IndexError, ValueError):
            return {"trouve": False,
                    "raison": f"Réponse de wpctl inattendue : {txt[:80]}"}
        return {"trouve": True, "pourcent": round(val * 100), "muet": muet,
                "outil": "wpctl"}
    if a["outil"] == "pactl":
        r = execution.lancer(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
        rm = execution.lancer(["pactl", "get-sink-mute", "@DEFAULT_SINK@"])
        if not r.ok:
            return {"trouve": False, "raison": r.erreur}
        pourcent = None
        for mot in r.sortie.replace("/", " ").split():
            if mot.endswith("%"):
                try:
                    pourcent = int(mot[:-1])
                    break
                except ValueError:
                    continue
        if pourcent is None:
            return {"trouve": False,
                    "raison": "pactl n'a pas rendu de pourcentage lisible."}
        return {"trouve": True, "pourcent": pourcent,
                "muet": rm.ok and "yes" in rm.sortie.lower(), "outil": "pactl"}
    return {"trouve": False,
            "raison": a.get("raison", "Aucun outil audio utilisable.")}


def regler_volume(pourcent: int) -> execution.Resultat:
    pourcent = max(0, min(150, int(pourcent)))
    a = capacites.audio()
    if a["outil"] == "wpctl":
        return execution.lancer(
            ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{pourcent}%"])
    if a["outil"] == "pactl":
        return execution.lancer(
            ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{pourcent}%"])
    return execution.Resultat(False, erreur=a.get(
        "raison", "Aucun outil audio utilisable."))


def basculer_muet(muet: bool) -> execution.Resultat:
    a = capacites.audio()
    if a["outil"] == "wpctl":
        return execution.lancer(
            ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if muet else "0"])
    if a["outil"] == "pactl":
        return execution.lancer(
            ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "1" if muet else "0"])
    return execution.Resultat(False, erreur=a.get(
        "raison", "Aucun outil audio utilisable."))


REGLAGES_NATIFS = ("pavucontrol", "pavucontrol-qt", "gnome-control-center",
                   "xfce4-pulseaudio-plugin", "systemsettings")


def ouvrir_reglages_natifs() -> execution.Resultat:
    for outil in REGLAGES_NATIFS:
        if execution.outil_present(outil):
            argv = [outil]
            if outil == "gnome-control-center":
                argv.append("sound")
            return execution.lancer_detache(argv)
    return execution.Resultat(
        False, erreur="Aucun panneau de réglages audio natif trouvé "
                      "(pavucontrol, gnome-control-center…).")
