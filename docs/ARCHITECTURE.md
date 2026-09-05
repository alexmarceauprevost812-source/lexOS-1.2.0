# Comment LexOS est fabriqué

Ce document explique la mécanique interne — utile si tu veux modifier le
processus de construction plutôt que le contenu.

---

## Vue d'ensemble

LexOS n'est pas compilé à partir de rien. Il est **assemblé** : on part d'un
système Debian minimal, on y installe des paquets, on le personnalise, puis on
le compresse en image amorçable.

```
lexos.conf
    │
    ├─→ build.sh ─────→ vérifie l'environnement
    │                   génère /etc/lexos/build.conf
    │                   copie branding/ dans l'image
    │                   choisit les listes de paquets selon la saveur
    │
    ├─→ auto/config ──→ traduit lexos.conf en options live-build
    │
    └─→ lb build
          │
          ├─ 1. bootstrap    debootstrap installe un Debian minimal
          ├─ 2. chroot       installe les paquets des listes
          │                  copie config/includes.chroot/
          │                  exécute config/hooks/normal/ dans l'ordre
          ├─ 3. binary       construit le squashfs
          │                  ajoute isolinux + GRUB EFI
          │                  intègre l'installateur Debian
          └─ 4. iso          produit lexos-1.0-<saveur>-amd64.iso
```

---

## Les quatre étages de live-build

### 1. `bootstrap`

`debootstrap` télécharge les paquets essentiels de Debian et construit un
système minimal dans `chroot/`. Environ 250 Mo, sans noyau ni bureau.

Ce qui est piloté depuis `lexos.conf` : `LEXOS_DEBIAN_SUITE`, `LEXOS_ARCH`,
`LEXOS_MIRROR`.

### 2. `chroot`

L'étage qui fait tout le travail. Dans l'ordre :

1. Configuration d'APT (dépôts, sécurité, mises à jour).
2. Copie de `config/includes.chroot/` à la racine du chroot.
3. Installation de tous les paquets listés dans `config/package-lists/`.
4. Exécution des hooks `config/hooks/normal/*.hook.chroot`, par ordre
   alphabétique — d'où la numérotation.

> Les hooks tournent **à l'intérieur** du futur système, en root. Une commande
> qui échoue interrompt la construction : d'où les `|| true` sur tout ce qui
> n'est pas vital.

### 3. `binary`

Le chroot est compressé en `filesystem.squashfs` (xz). On y ajoute le
chargeur de démarrage (isolinux pour le BIOS, GRUB pour l'UEFI), l'écran du
menu, et l'installateur Debian.

### 4. `iso`

`xorriso` assemble le tout en une image hybride : le même fichier fonctionne
gravé sur DVD **et** copié brut sur clé USB.

---

## Circulation de la configuration

Le problème classique d'une distribution maison : la version est écrite à
douze endroits et trois d'entre eux sont oubliés. Ici il n'y en a qu'un.

```
lexos.conf                          ← tu édites ici, et seulement ici
    │
    ├─→ auto/config                 options live-build (nom de l'ISO, boot…)
    │
    └─→ build.sh
          └─→ config/includes.chroot/etc/lexos/build.conf   (fichier généré)
                    │
                    └─→ lu par les hooks, à l'intérieur du chroot :
                          0100 → /usr/lib/os-release, /etc/issue, /etc/motd
                          0110 → locales, clavier, fuseau horaire
                          0400 → LightDM, sudo
                          0500 → branding Calamares
                          0600 → thème LexOS Noir
                    │
                    └─→ lu à l'exécution par lexos, lexos-wm, lexos-firstrun
```

`build.conf` est **généré** : il est dans `.gitignore` et recréé à chaque
construction. Les hooks embarquent des valeurs de repli, si bien qu'un
`lb build` lancé directement (sans passer par `build.sh`) produit quand même
une image cohérente.

---

## Les hooks, un par un

| Hook | Rôle | Peut échouer sans casser ? |
|---|---|---|
| `0100-lexos-identity` | `os-release`, `lsb-release`, `issue`, `motd`, GRUB | Non — c'est l'identité |
| `0110-lexos-locale` | Locales, clavier, fuseau, police console | Partiellement |
| `0200-lexos-performance` | initramfs zstd, oomd, irqbalance, service de profil | Oui |
| `0250-lexos-optional` | Paquets de confort, un par un, tolérant | Oui — c'est son rôle |
| `0300-lexos-assets` | WebP→PNG, SVG→PNG, icônes, avatar, Plymouth | Oui — dégradation propre |
| `0400-lexos-desktop` | LightDM, compte invité, menus, clic droit, raccourcis | Sauté si pas de bureau |
| `0450-lexos-settings` | Panneau Paramètres (routeur vers les outils LexOS) | Sauté si pas de bureau |
| `0500-lexos-installer` | Calamares + chiffrement du disque (LUKS2) | Sauté si pas de Calamares |
| `0600-lexos-theme` | LexOS Noir dans `/etc/skel`, dock, base dconf | Oui |
| `9900-lexos-cleanup` | Caches, journaux, machine-id, clés SSH | Non |

### Pourquoi cet ordre

* L'identité (`0100`) doit précéder tout ce qui lit `/etc/os-release`.
* Les visuels (`0300`) doivent précéder le bureau (`0400`), qui pointe
  LightDM vers le fond d'écran produit.
* Le thème (`0600`) vient après le bureau, parce qu'il détecte si un bureau
  est installé.
* Le nettoyage (`9900`) doit être dernier — il vide les caches APT dont tout
  le reste se sert.

### Ce que fait `9900` et pourquoi c'est important

```sh
: > /etc/machine-id                    # sinon toutes les machines partagent le même
rm -f /etc/ssh/ssh_host_*_key          # sinon toutes partagent les mêmes clés SSH
```

Ces deux fichiers sont régénérés au premier démarrage réel. Les oublier
produirait des installations impossibles à distinguer sur un réseau — et un
risque de sécurité pour SSH.

---

## Le mécanisme des saveurs

`config/package-lists/` est lu intégralement par live-build : impossible d'y
mettre des listes conditionnelles.

La solution : les listes optionnelles vivent dans `flavours/<nom>/`, et
`build.sh` copie celles qui s'appliquent vers
`config/package-lists/zz-flavour-<saveur>-<fichier>` juste avant de lancer la
construction. Ces copies sont ignorées par Git et effacées par `make clean`.

```
minimal   →  (rien)
standard  →  flavours/standard/
dev       →  flavours/standard/ + flavours/dev/
full      →  flavours/standard/ + flavours/dev/ + flavours/full/
gaming    →  flavours/standard/ + flavours/dev/ + flavours/gaming/
```

Le préfixe `zz-` garantit qu'elles sont traitées après les listes de base.

---

## Le repli des effets CRT

Compiz donne l'effet « téléviseur », mais exige une accélération 3D réelle.
Sur une machine sans pilote graphique — courant en machine virtuelle — le
lancer produirait un écran noir sans bureau.

`lexos-wm` est déclaré comme gestionnaire de fenêtres dans
`xfce4-session.xml`, à la place de `xfwm4`. Sa logique :

```
LEXOS_CRT_EFFECTS == "off"        →  xfwm4
compiz absent                     →  xfwm4
glxinfo absent ou en échec        →  xfwm4
pas de « direct rendering: Yes »  →  xfwm4
renderer = llvmpipe/softpipe/swrast (rendu logiciel)
                                  →  xfwm4
sinon                             →  compiz, avec filet de sécurité 5 s
```

Le filet : si Compiz meurt dans les cinq premières secondes, `lexos-wm` prend
le relais avec xfwm4. Tout est journalisé dans `~/.config/lexos/wm.log`, que
`lexos crt status` affiche.

**Le principe** : jamais d'écran noir. Un bureau moins joli vaut mille fois
mieux qu'un bureau absent.

---

## Le thème : pourquoi générer plutôt que livrer

Un thème GTK complet, c'est des milliers de lignes de CSS et des images de
décoration. En écrire un de zéro pour six couleurs d'accent serait
ingérable.

`lexos-theme-gen` prend le chemin inverse : il s'appuie sur **Arc-Dark**
(thème existant, complet, testé) et écrit par-dessus une feuille CSS
utilisateur — appliquée en dernier par GTK, donc gagnante. Environ 200 lignes
suffisent pour le noir pur, l'écriture blanche et l'accent.

Le script écrit dans `$HOME`, ce qui donne deux usages :

```bash
# à la construction, pour tout futur compte
HOME=/etc/skel lexos-theme-gen orange --target /etc/skel

# à l'exécution, pour l'utilisateur courant
lexos accent violet
```

Fichiers produits :

| Fichier | Pour |
|---|---|
| `.config/gtk-3.0/gtk.css` | Applications GTK 3 (la majorité) |
| `.config/gtk-4.0/gtk.css` | Applications GTK 4 |
| `.gtkrc-2.0` | Applications GTK 2 (anciennes) |
| `.config/xfce4/terminal/terminalrc` | Terminal |
| `.config/lexos/theme.conf` | Variables pour les autres scripts |

---

## Les volets du terminal

`lexos-multi` ouvre un terminal divisible en volets et en onglets. C'est une
enveloppe autour de **tmux**, pas une réécriture : le multiplexeur fait le
travail, LexOS fournit les réglages et le nom.

```
lexos-multi              # exec tmux -f /usr/share/lexos/tmux/lexos.conf
                         #             new-session -A -s lexos
```

| Fichier | Rôle |
|---|---|
| `/usr/bin/lexos-multi` | Le lanceur : garde-fous, aide, sous-commandes |
| `/usr/share/lexos/tmux/lexos.conf` | Les réglages (souris, raccourcis, couleurs) |
| `/usr/share/applications/lexos-multi.desktop` | Le lanceur du menu et du dock |

Deux décisions structurent le reste.

**tmux n'est jamais lancé automatiquement.** `interactive.sh` pose l'alias
`multi` et rien d'autre. Démarrer tmux à l'ouverture de chaque shell aurait
placé dans un multiplexeur tous les shells ouverts *par des programmes*
(Claude Code, un éditeur, le gestionnaire de fichiers), fait tourner un tmux
dans un tmux à chaque session SSH, et enfermé dans les volets ceux qui n'en
veulent pas. Le banc `tests/test_lexos_multi.sh` vérifie qu'aucun appel à tmux
ne réapparaît dans `interactive.sh`.

**Les réglages sont vérifiés sur un vrai tmux, pas relus.** Un `.conf` tmux ne
se compile pas : une option mal orthographiée provoque une erreur au démarrage,
puis l'abandon silencieux du reste du fichier. Le terminal s'ouvre quand même
et la souris ne marche plus. La CI démarre donc un serveur tmux sur une prise à
part, lui donne le fichier, et lui **redemande** ce qu'il en a retenu
(`tmux show -gv mouse`, `list-keys -T root`) — la seule question qui répond
vraiment.

---

## Le garde-fou d'installation

`lexos-install` s'interpose entre l'utilisateur et Calamares. Il ne formate
rien lui-même : il vérifie, avertit, et passe la main.

```
lexos-install
    │
    ├─ pas en session live ?        → refus (« démarre depuis la clé USB »)
    ├─ liste les disques (lsblk)
    ├─ avertit que l'effacement est irréversible
    ├─ demande confirmation
    │     graphique : bouton « J'ai compris, installer »
    │     console   : taper EFFACER en toutes lettres
    ├─ refus ou autre saisie        → sortie 0, rien n'est modifié
    └─ confirmation                 → exec calamares
```

Le raccourci du bureau et l'entrée du dock pointent sur `lexos-install`, pas
sur `calamares` : le garde-fou ne peut pas être contourné par accident.

### Le sudo de la démo ne survit pas à l'installation

En session démo, `lex` a un sudo sans mot de passe (`/etc/sudoers.d/lexos-live`).
C'est volontaire : il n'y a rien à protéger sur une clé USB, et l'installateur
en a besoin.

Le piège : Calamares recopie le système de fichiers **tel quel** sur le disque,
ce fichier compris. Sur la machine installée il reste là — et quelqu'un qui
nomme son compte `lex`, le nom qu'il a sous les yeux depuis le début de la
démo, hériterait en silence d'un sudo sans mot de passe qu'il n'a jamais
demandé.

Et ce n'est pas le seul réglage de démo qui voyage. L'**ouverture de session
automatique** part avec, elle aussi — c'est même la plus gênante des trois :
sur la machine installée, LightDM ouvrait directement la session `lex`, celle
de la démo. On n'atteignait donc jamais l'écran où choisir son propre compte,
et on en concluait que l'installateur ne l'avait pas créé. Il l'avait bien
créé ; on n'arrivait simplement jamais jusqu'à lui.

`lexos-demo-guard.service` ferme les trois au démarrage, avant l'écran de
connexion :

```
/proc/cmdline contient « boot=live » ?
    ├─ oui  → session démo, on garde tout
    └─ non  → système installé, on efface
              ├─ /etc/sudoers.d/lexos-live
              ├─ /etc/lightdm/lightdm.conf.d/60-lexos-autologin.conf
              └─ /etc/systemd/system/getty@tty1.service.d/lexos-autologin.conf
```

L'unité n'a **aucun** `ConditionPathExists`. La précédente en avait une sur le
fichier sudoers : une fois celui-ci effacé au premier démarrage, l'unité ne se
relançait plus jamais — et les ouvertures automatiques seraient restées en
place pour toujours.

Le compte `lex` lui-même n'est pas supprimé, volontairement : si la création du
compte a échoué pendant l'installation, il reste la seule façon d'entrer
(identifiant `lex`, mot de passe `lex`) pour réparer.

Le choix de ne dépendre d'aucun réglage de Calamares est délibéré : une
installation faite autrement — clonage de disque, copie manuelle, image
restaurée — est rattrapée de la même façon.

---

## Deux niveaux de paquets

live-build interrompt la construction dès qu'un nom de paquet n'existe pas.
C'est le bon réflexe pour le noyau — beaucoup moins pour un thème d'icônes
renommé entre deux versions de Debian.

D'où la séparation :

| | Où | Comportement si absent |
|---|---|---|
| **Essentiels** | `config/package-lists/`, `flavours/*/` | La construction s'arrête |
| **Confort** | `config/includes.chroot/usr/share/lexos/optional-packages/` | Noté et ignoré |

Le hook `0250` tente d'abord d'installer tous les paquets de confort d'un
bloc — c'est bien plus rapide. Si ça échoue, il reprend un par un pour
identifier précisément le fautif, et écrit le bilan dans
`/etc/lexos/optional-report` :

```
# Paquets optionnels — saveur pro
# Installés : 84    Indisponibles : 2

# Non installés (nom absent de l'archive, ou conflit) :
plank
compiz-plugins-extra
```

Le code qui dépend de ces paquets s'y attend : `lexos-wm` retombe sur xfwm4
sans Compiz, le dock ne démarre simplement pas sans Plank, `lexos share`
affiche l'URL sans QR code sans `qrencode`. Aucun de ces cas ne casse la
session.

---

## Le moteur de performance

`lexos-perf` agit sur deux plans, parce que la moitié des réglages exige root
et l'autre moitié une session ouverte :

| Plan | Exécuté par | Ce qu'il touche |
|---|---|---|
| Système | `lexos-perf.service` au démarrage, ou `sudo` | Gouverneur CPU, EPP, turbo, sysctl, ordonnanceur E/S, zram, services |
| Session | `lexos-firstrun`, ou la commande directe | Compositing, effets CRT, zoom du dock, miniatures |

Un seul `case` définit les quatre profils, avec les mêmes variables partout :
pour comprendre ce que fait `max`, il n'y a qu'un bloc de quinze lignes à
lire.

Les réglages CPU dégradent proprement. `schedutil` n'existe pas sur tous les
noyaux : le script lit `scaling_available_governors` et retombe sur
`ondemand`, puis `conservative`. Dans une machine virtuelle sans `cpufreq`,
il l'annonce au lieu de prétendre avoir agi.

---

## Le partage par QR code

Le besoin : envoyer une photo au téléphone sans installer d'application des
deux côtés. La réponse tient en trois pièces :

1. `lexos-share qr` crée un dossier temporaire et y fait des liens durs vers
   les fichiers — pas de copie, même pour une vidéo de 2 Go.
2. `share-server.py` sert ce dossier en HTTP sur le réseau local, avec une
   page dans les couleurs de LexOS et un formulaire d'envoi.
3. `qrencode` affiche l'adresse en QR code dans le terminal.

Le serveur s'arrête tout seul après quinze minutes. Rien ne sort du réseau
local, rien n'est téléversé nulle part.

**Un jeton dans l'adresse.** Le serveur écoute sur toutes les interfaces —
il le faut, le téléphone doit pouvoir le joindre. Mais « réseau local » ne
veut pas dire « gens de confiance » : dans un café, c'est tout le monde.
Chaque partage tire donc un jeton aléatoire (`secrets.token_urlsafe`) qui
devient le début du chemin :

```
http://192.168.1.42:8080/kJ3nR7pQxW2vLa/
                         └── jeton du partage, à usage unique
```

Toute requête sans ce jeton reçoit un `404` — pas un `403`, qui confirmerait
qu'un partage tourne ici. Le QR code contient l'adresse complète : scanner ne
change pas, deviner devient impossible. La comparaison passe par
`secrets.compare_digest`, à temps constant. Un jeton vide ferme tout : un
oubli de configuration doit verrouiller la porte, pas l'ouvrir.

`tests/test_share_server.py` couvre les deux côtés : sans jeton, la page, les
fichiers et l'envoi renvoient `404` et rien n'est écrit ; avec le bon jeton,
tout fonctionne.

Le parseur multipart est écrit à la main plutôt que d'utiliser le module
`cgi` de Python : celui-ci disparaît en Python 3.13, donc dans Debian trixie.
Il lit en flux, borné par `Content-Length`, et ne garde jamais plus de
64 Kio en mémoire — un envoi de 4 Go passe sans problème. Le nom de fichier
reçu est réduit à son nom de base : impossible d'écrire ailleurs que dans le
dossier de réception. `tests/test_share_server.py` vérifie les seize cas,
remontées de chemin comprises.

---

## Les autres outils, et ce qu'ils délèguent

La règle est la même partout : LexOS **n'écrit pas un moteur de plus** quand
Debian en fournit déjà un bon. Chaque outil `lexos-*` est une façade en
français au-dessus d'un logiciel éprouvé, avec les garde-fous de la maison.

| Outil | Délègue à | Ce que LexOS ajoute |
|---|---|---|
| `lexos-format` | `wipefs`, `parted`, `mkfs.*` | Refuse tout disque non amovible, et tout disque hébergeant `/`, `/home`, `/boot`, `/usr` ou `/var`. Confirmation exigée. |
| `lexos-vpn` | `nmcli connection import` | Détecte seul si le fichier est OpenVPN (`.ovpn`) ou WireGuard (`[Interface]`) et choisit le bon type. |
| `lexos-secure` | `ufw`, ClamAV, `fail2ban`, `rkhunter` | Un seul tableau de bord, et `secure enable` qui applique des réglages sûrs d'un coup. |
| `lexos-game` | `gamemoderun`, MangoHud | Bascule le profil de performance avant le jeu et **le remet comme avant** après. |
| `lexos-sticker` | `rembg` (IA) ou ImageMagick | Choisit seul le meilleur moteur disponible ; jamais bloqué si l'IA est absente. |
| `lexos-ia` | Ollama | Boucle d'agent, liste noire de commandes destructrices, `sudo` refusé par défaut. |
| `lexos-update-check` | `apt-get -s upgrade` | Prévient chaque jour les utilisateurs connectés, sans jamais installer de force. |

### Le garde-fou du formatage

`lexos-format` suit exactement la logique de `lexos-install` — vérifier,
avertir, puis seulement agir :

```
lexos-format /dev/sdX
    │
    ├─ le disque héberge / /home /boot /usr /var ?  → refus, sans appel
    ├─ le disque n'est pas amovible (lsblk RM=0) ?  → refus
    ├─ affiche taille, modèle, contenu actuel
    ├─ demande confirmation
    │     graphique : bouton clairement étiqueté
    │     console   : taper FORMATER en toutes lettres
    ├─ refus ou autre saisie                        → sortie, rien n'est touché
    └─ confirmation                                 → wipefs + parted + mkfs
```

### Pourquoi l'IA tourne en local

`lexos-ia` s'appuie sur **Ollama**, qui exécute le modèle sur la machine.
Une fois le modèle téléchargé (une seule fois, ~2 Gio), plus rien ne sort sur
internet — y compris en mode agent, où le modèle voit la sortie de commandes
qui peuvent contenir des noms de fichiers ou des adresses réseau. Un service
distant aurait été plus simple à brancher, mais aurait fait sortir ces
données de la machine à chaque question.

Le mode agent applique quatre limites, dans cet ordre :

1. **Liste noire** — refus sec de quelques formes notoires (`rm -rf /`,
   `mkfs`, `dd of=/dev/…`, `parted`…). C'est un filet, jamais la protection
   principale : voir l'encadré ci-dessous.
2. **Liste blanche** — seules les commandes de **lecture** reconnues (`ls`,
   `df`, `cat`, `grep`, `systemctl --failed`, `journalctl`…) tournent sans
   rien demander. Tout le reste exige un accord humain.
3. `sudo` refusé sauf `--sudo` explicite.
4. Sans terminal (script, cron), une commande qui exigerait une confirmation
   n'est **pas** exécutée — elle est refusée.

Le tout plafonne à vingt étapes : un modèle qui tourne en rond s'arrête au
lieu de consommer la machine.

> **Pourquoi une liste blanche et pas une liste noire.**
> Une liste noire ne protège rien, et c'est mesurable : la première version de
> cet agent bloquait `rm -rf /` mais laissait passer `rm -rf /home`,
> `rm -rf /*`, `find / -delete`, `mv /home/lex /tmp`, `chmod -R 000 /home`,
> `echo <base64> | base64 -d | sh`, et même `r''m -rf /` — quatorze
> commandes destructrices testées, quatorze qui passaient. On ne peut pas
> énumérer à l'avance toutes les façons d'abîmer une machine.
> La liste blanche renverse la charge : ce qui n'est pas reconnu comme une
> lecture est suspect par défaut. `--auto` accélère les diagnostics
> (« pourquoi mon disque est plein ? ») sans jamais donner le droit d'écrire
> en silence.

### Le repli à deux moteurs des autocollants

`lexos-sticker` illustre le principe du repli propre appliqué ailleurs (CRT,
gouverneurs CPU, thème Plymouth) :

| Moteur | Quand | Qualité |
|---|---|---|
| `rembg` (réseau U2-Net) | S'il est installé | Découpe même sur fond complexe |
| ImageMagick, remplissage depuis les coins | Toujours disponible | Bon sur fond uni |

Aucun des deux n'est obligatoire à la construction : `python3-rembg` vit dans
`optional-packages/90-decoupe-image.list`, donc en « best effort », et
`imagemagick` est déjà dans `00-core.list`. Si l'IA manque, l'outil bascule
sans rien dire et rend quand même un PNG à fond transparent.

---

## Pourquoi ces choix

**Debian plutôt qu'Ubuntu comme socle.** `live-build` est l'outil officiel
Debian pour ce travail, stable et documenté. Ubuntu a divergé vers ses propres
outils. L'apparence s'inspire d'Ubuntu ; la plomberie est Debian.

**XFCE plutôt que GNOME ou KDE.** XFCE se configure par fichiers XML lisibles
et versionnables, il tourne sur du matériel modeste, et il accepte Compiz comme
gestionnaire de fenêtres — ce que GNOME refuse.

**Plank plutôt qu'un second panneau XFCE.** Plank est un vrai dock, avec zoom
et masquage intelligent, configurable par simples fichiers `.dockitem`. Un
panneau XFCE vertical demanderait bien plus de XML pour un résultat moins
proche d'Ubuntu.

**Calamares plutôt que l'installateur Debian seul.** Calamares s'habille aux
couleurs de la distribution et se pilote à la souris. L'installateur Debian
reste disponible depuis le menu de démarrage, comme filet de sécurité.

**Debian trixie plutôt que bookworm.** Noyau 6.12 LTS, systemd 257, Mesa 25 :
la même génération de composants qu'Ubuntu 26.04. Le matériel récent est
reconnu, et les performances graphiques suivent. `LEXOS_KERNEL_CHANNEL=backports`
va chercher un noyau encore plus neuf quand la machine l'exige.

**Connexion automatique aux réseaux ouverts : désactivée.** La fonctionnalité
est là parce qu'elle a été demandée, mais l'activer par défaut reviendrait à
faire circuler le trafic de l'utilisateur en clair sans qu'il l'ait choisi.
Elle demande donc `OUI` en toutes lettres après un avertissement, ne se
déclenche que hors ligne, et notifie à chaque connexion. La CI vérifie que le
défaut reste `off`.

**MIT plutôt que GPL.** Le travail original ici, ce sont des scripts de
construction. MIT laisse le maximum de liberté à qui veut partir de ce dépôt.
Les paquets embarqués gardent évidemment leurs licences respectives.

---

## Cycle de développement

```bash
# 1. modifier
$EDITOR lexos.conf
$EDITOR flavours/standard/desktop.list.chroot

# 2. vérifier sans construire (quelques secondes)
make lint
make preview

# 3. construire la saveur la plus légère (plus rapide)
sudo ./build.sh --flavour minimal

# 4. essayer dans QEMU
make test

# 5. construire pour de vrai
make build FLAVOUR=standard
```

Astuce : `lb build` reprend là où il s'est arrêté. Après un échec dans l'étage
`chroot`, corrige puis relance sans `make clean` — le bootstrap n'est pas
refait.

Pour repartir de zéro (changement de suite Debian, corruption) :

```bash
make distclean
```

## Comptes en ligne — `lexos-comptes`

Deux mécanismes coexistent sous Linux et ne font pas la même chose :

| | GVFS (via GNOME Online Accounts) | rclone |
|---|---|---|
| Ce que ça donne | Le compte **dans Fichiers** | Un **disque monté**, ou une **copie locale** |
| Hors ligne | Non — chaque ouverture télécharge | Oui, avec `rclone sync` |
| Services | Google, WebDAV, SMB, SFTP | ~50, dont OneDrive, Dropbox, Proton, S3 |

`lexos-comptes` pilote **rclone**, le plus complet, et laisse GVFS faire ce
qu'il fait bien : afficher les mêmes comptes dans la barre latérale de Thunar.

**Aucun mot de passe de compte n'est conservé.** L'autorisation passe par le
navigateur ; le fournisseur remet un jeton révocable, que rclone garde dans un
fichier passé en `chmod 600` par le script. Révoquer l'accès côté fournisseur
suffit à tout couper.

Le catalogue des services (clé + type rclone) est dupliqué dans la démo web ;
une étape de CI, *« Services de comptes en ligne identiques »*, refuse toute
divergence — une faute de type d'un seul côté ferait taper à l'utilisateur un
`unknown remote type`.

## Bien-être numérique — `lexos-bienetre`

Trois choses réunies parce qu'elles servent la même intention.

**Le temps d'écran** est mesuré par un minuteur systemd *utilisateur*
(`lexos-bienetre.timer`) qui appelle `lexos-bienetre --tic` chaque minute. Le
battement n'incrémente le compteur que si `xprintidle` rapporte **moins de 90
secondes d'inactivité** : sans ce garde-fou, un écran laissé allumé la nuit
compterait huit heures d'usage et rendrait le chiffre inutilisable. Une valeur
par jour, en texte, dans `~/.local/share/lexos/bienetre/AAAA-MM-JJ`.

Le service tourne avec `PrivateNetwork=yes` — non par précaution
rédactionnelle, mais parce que rien n'a à sortir d'ici, et qu'une interdiction
vérifiable vaut mieux qu'une promesse.

**Le compteur est arrêté par défaut.** Mesurer le temps que quelqu'un passe
devant sa machine ne se décide pas à sa place, même quand la mesure ne quitte
jamais la machine. `lexos bienetre demarrer` l'allume, `oublier` efface tout.

**Les pauses** (`workrave`) et **la lumière du soir** (`redshift`) sont des
logiciels tiers ; LexOS ne fait que les allumer et les éteindre proprement.

## Ce qu'un bureau complet doit avoir

`config/includes.chroot/usr/share/lexos/optional-packages/15-essentiel.list`
vient d'une comparaison poste à poste avec ce qu'Ubuntu 24.04 livre par
défaut. Vingt-cinq manques ont été trouvés ; ils sont comblés. Les plus
importants, parce qu'ils ne se rattrapent pas facilement à la main :

* **`fwupd`** — met à jour le BIOS, les SSD et les périphériques depuis le
  bureau. Sans lui, il faut une clé USB de constructeur, souvent Windows.
* **`orca`** et **`onboard`** — lecteur d'écran et clavier visuel. Un système
  sans lecteur d'écran n'est pas utilisable par une personne aveugle : ce
  n'est pas du confort.
* **`libavcodec-extra`** — sans ces codecs, une vidéo H.264 téléchargée ne
  s'ouvre pas, et le message d'erreur ne dit pas qu'il manque un paquet.
* **`deja-dup`** — sauvegarde des *fichiers*, chiffrée. Timeshift, déjà
  présent, restaure le *système*. Les deux ne se remplacent pas.
* **`needrestart`** — prévient quand un service tourne encore sur une
  bibliothèque mise à jour ; sans lui, un correctif de sécurité peut rester
  sans effet jusqu'au prochain redémarrage, sans que personne le sache.

Deux noms diffèrent volontairement de ceux d'Ubuntu :

| Ubuntu | LexOS | Pourquoi |
|---|---|---|
| `cups-pdf` | `printer-driver-cups-pdf` | C'est le nom Debian |
| `mlocate` | `plocate` seul | plocate le remplace ; les deux ensemble se disputent le même index |

Et `apt-transport-https` est écarté : intégré à apt depuis des années, le
paquet n'est plus qu'une coquille de transition.

**Ce que LexOS ne reprend pas d'Ubuntu, et l'assume** : `snapd` (Flatpak
occupe ce rôle, et n'impose pas un magasin unique), `apport` (envoi de
rapports de plantage), `ubuntu-advantage-tools` et `ubuntu-report`.
