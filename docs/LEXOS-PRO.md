# LEXOS PRO

Application de bureau **native** (PySide6) : vue d'ensemble du système,
fichiers, terminal, paramètres, navigateur, sécurité et développement.

Elle est écrite pour Ubuntu/Linux **et** LexOS, et détecte la distribution
au lancement. « Ubuntu » et « Debian » n'y sont jamais confondus : le code
distingue l'identifiant exact (`ID`) de la parenté déclarée (`ID_LIKE`).

---

## Lancer l'application

```
lexos-pro
```

Depuis les sources du dépôt, sans rien installer :

```
LEXOS_PRO_RACINE=config/includes.chroot/usr/lib/lexos \
  config/includes.chroot/usr/bin/lexos-pro
```

| Variable | Effet |
|---|---|
| `LEXOS_PRO_RACINE` | Où trouver le paquet `pro/` (défaut : `/usr/lib/lexos`) |
| `LEXOS_PRO_PYTHON` | Interpréteur à utiliser (défaut : `python3`) |
| `LEXOS_PRO_AUTORISER_ROOT` | **Essais uniquement.** Lève le refus de démarrer en root |

### Elle refuse de démarrer en root

C'est volontaire, et vérifié à deux endroits (le lanceur et `app.py`). Un
gestionnaire de fichiers lancé en root écrit partout sans garde-fou. Les
rares actions qui demandent des droits — renommer la machine — passent par
`pkexec`, qui affiche **sa propre** fenêtre d'autorisation. LEXOS PRO ne
vous demandera jamais votre mot de passe dans un formulaire à lui.

---

## Dépendances

| Dépendance | Version | Rôle |
|---|---|---|
| Python | ≥ 3.9 | `ast.unparse`, annotations différées |
| PySide6 | ≥ 6.4 | interface graphique (QtCore, QtGui, QtWidgets) |

**PySide6 sans WebEngine suffit** : LEXOS PRO est une application native,
elle n'embarque aucun navigateur.

Sur LexOS et les saveurs de bureau, les trois modules sont déjà en liste
stricte (`flavours/standard/desktop.list.chroot`) : rien à installer.

Ailleurs :

| Distribution | Commande |
|---|---|
| Debian, Ubuntu, Mint, LexOS | `sudo apt install python3-pyside6.qtwidgets python3-pyside6.qtgui` |
| Fedora, RHEL | `sudo dnf install python3-pyside6` |
| Arch, Manjaro | `sudo pacman -S pyside6` |
| openSUSE | `sudo zypper install python3-pyside6` |

Le lanceur **n'installe rien lui-même** : il détecte la distribution et
affiche la commande exacte à taper.

### Outils facultatifs

Chacun est détecté au lancement. Son absence n'empêche jamais l'application
de démarrer : la fonction concernée affiche « Indisponible » **avec sa
raison**, et le bouton correspondant est éteint avec un motif en infobulle.

| Outil | Paquet Debian/Ubuntu | Ce qu'il apporte |
|---|---|---|
| `lspci` | `pciutils` | énumération des cartes graphiques |
| `nvidia-smi` | pilote NVIDIA | modèle, pilote, mémoire et température GPU |
| `glxinfo` | `mesa-utils` | distingue accélération matérielle et rendu logiciel |
| `ip`, `ss` | `iproute2` | adresses des interfaces, ports en écoute |
| `gio` | `glib2.0-bin` | mise à la corbeille, lancement des `.desktop` |
| `xdg-open` | `xdg-utils` | ouverture des fichiers et des adresses |
| `systemctl`, `journalctl` | `systemd` | services et journaux |
| `wpctl` / `pactl` | `wireplumber` / `pulseaudio-utils` | volume et périphériques audio |
| `nmcli` | `network-manager` | connexion active, état de connectivité |
| `mokutil` | `mokutil` | état du Secure Boot |
| `ufw` / `firewall-cmd` | `ufw` / `firewalld` | état du pare-feu |
| `pkexec` | `policykit-1` | autorisation pour renommer la machine |

---

## Ce que l'application NE fait pas

Ces limites sont des choix, pas des oublis.

**Fichiers** — aucune suppression définitive. Tout passe par la corbeille,
via `gio trash`. Le module `pro/services/fichiers.py` ne contient
littéralement aucun appel de suppression, et un test le vérifie sur l'arbre
syntaxique. Les conflits de noms ne sont jamais écrasés en silence : on
demande.

**Terminal** — aucune imitation de terminal dans une zone de texte. LEXOS
PRO ouvre l'émulateur réellement installé, dans le dossier choisi, et le
dit à l'écran.

**Performances** — l'arrêt d'un processus est un `SIGTERM` (une demande, que
le programme peut refuser), uniquement sur **vos** processus, après
confirmation. Jamais de `SIGKILL`, jamais sur un service système.

**Réseau** — lecture seule. Aucun balayage, aucune capture. Les mots de
passe Wi-Fi appartiennent aux réglages natifs : LEXOS PRO n'en stocke aucun
et ne les lit pas.

**Affichage et GPU** — constat uniquement. Aucune installation de pilote,
aucune modification du Secure Boot, de GRUB ou des modules du noyau.

**Stockage** — aucun formatage, aucun partitionnement, aucun montage
privilégié automatique.

**Applications** — pas de gestionnaire d'installation. Pour installer ou
retirer un logiciel, l'application ouvre la logithèque native.

**Services** — les services de votre **session** peuvent être démarrés,
arrêtés, redémarrés après confirmation. Les services **système** sont en
lecture seule : les modifier demanderait une règle PolicyKit ciblée et
éprouvée, qui n'existe pas encore. Le bouton est éteint **avec ce motif**.

**Mises à jour** — la page distingue le **cache local** (qui peut dater de
plusieurs semaines, et l'affiche) d'une vérification à jour. Elle ne lance
ni mise à niveau, ni suppression de paquets, ni redémarrage : elle ouvre
l'outil natif.

**Sécurité** — diagnostic défensif. L'application n'affiche **jamais**
« système sécurisé » : elle compte les points qu'elle a pu vérifier
(« 3 sur 4 ») et rappelle que ces contrôles ne disent rien des mots de
passe, des permissions ou du navigateur. Aucun outil offensif.

**Développement** — Git en lecture seule (branche, fichiers modifiés).
Lancer les tests d'un projet **exécute son code** : c'est écrit dans la
fenêtre de confirmation, et ce n'est jamais déclenché par l'ouverture d'un
dossier.

**Aucune donnée simulée en fonctionnement normal.** Les chiffres de la
maquette d'origine (18 %, RTX 5060, 3 h 24 min) ne sont nulle part dans le
code. Une mesure qu'on n'a pas obtenue s'affiche « Indisponible » avec sa
raison.

---

## Où sont vos données

| Chemin | Contenu |
|---|---|
| `$XDG_CONFIG_HOME/lexos-pro/preferences.json` | thème, taille du texte, densité, animations, favoris, liste des projets |

Par défaut : `~/.config/lexos-pro/preferences.json`.

**Aucun secret n'y est écrit** : ni mot de passe, ni jeton. Le fichier est
écrit de façon atomique (fichier temporaire puis renommage), donc une
coupure de courant ne le laisse jamais à moitié écrit.

---

## Raccourcis clavier

| Touches | Action |
|---|---|
| `Ctrl+1` … `Ctrl+8` | aller directement à une page du menu |
| `F5` | relire les mesures de la page courante |
| `Ctrl+Q` | quitter |
| `Tab` / `Maj+Tab` | parcourir les éléments (l'élément actif est cerclé d'orange) |

L'application est utilisable à partir de **1280 × 720**, redimensionnable,
et suit la mise à l'échelle HiDPI.

---

## Désinstaller

Sur une machine où l'application vient de l'ISO, elle fait partie du
système : la retirer n'est pas prévu séparément. Pour une installation
manuelle :

```
rm -f  ~/.local/share/applications/lexos-pro.desktop
rm -rf ~/.config/lexos-pro          # vos préférences et favoris
```

Ces deux commandes **effacent** — relisez-les avant de les lancer. Rien
d'autre n'est écrit en dehors de ces deux emplacements.

---

## Architecture

```
pro/
  version.py          version réelle, lue dans lexos.conf (jamais codée en dur)
  services/           AUCUN widget : lit le système, rend des objets simples
    execution.py      le SEUL endroit d'où l'on sort du processus
    capacites.py      ce que cette machine sait faire, mesuré une fois
    systeme.py disques.py reseau.py gpu.py son.py processus.py
    unites.py applications.py maj.py securite.py fichiers.py
    projets.py navigateur.py terminal.py prefs.py
  ui/                 N'interroge JAMAIS le système directement
    theme.py          palette, feuille de style, icônes tracées par QPainter
    widgets.py        cartes, jauges, courbes, zone de statut, travailleur de fond
    pages/            une page par entrée de menu
  app.py              assemble les deux, et refuse de tourner en root
```

Trois règles tenues en un seul endroit (`execution.py`) plutôt qu'espérées
partout : **jamais `shell=True`** (argv est une liste, donc un nom de
fichier contenant `; rm -rf` reste un nom de fichier), **toujours un délai
maximal** (une commande bloquée devient une erreur lisible, pas un gel), et
**`stdin` fermée** (rien ne peut réclamer un mot de passe sur un terminal
que personne ne regarde).

Tout ce qui peut durer part dans un `QThreadPool` et revient par un signal :
l'interface ne se fige pas.

---

## Éprouver

```
bash tests/test_lexos_pro.sh
```

Le banc a **trois** états : réussi, échoué, et **non mesuré**. Si PySide6
n'est pas installé, le démarrage graphique n'est pas vérifié — et le banc le
dit au lieu de passer au vert. Un banc vert qui n'a rien pu vérifier est
pire qu'un banc rouge.

Pour éprouver l'interface avec un PySide6 qui n'est pas celui du système :

```
PYTHON=/chemin/vers/python bash tests/test_lexos_pro.sh
```

Les tests unitaires seuls (aucun serveur graphique nécessaire) :

```
PYTHONPATH=config/includes.chroot/usr/lib/lexos \
  python3 -m unittest discover -s tests/pro -p 'test_*.py'
```

---

## Licence

Celle du dépôt. Si aucun fichier de licence n'est présent à sa racine, la
page **À propos** l'écrit ainsi : « à définir ». Aucune licence n'est
inventée.
