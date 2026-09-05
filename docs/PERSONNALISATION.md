# Personnaliser LexOS

Deux niveaux : **à chaud** sur un système qui tourne, ou **à la source** dans
l'ISO que tu construis. Les deux sont documentés ici.

---

## 1. À chaud — changer sans reconstruire

### La couleur d'accent

Elle habille les boutons, les sélections, le curseur du terminal, les barres de
progression et le liseré du dock.

```bash
lexos accent            # affiche l'accent courant et la liste
lexos accent violet     # applique immédiatement
```

| Nom | Code | Variante claire | Variante foncée |
|---|---|---|---|
| `orange` *(défaut)* | `#E8590C` | `#FF7A33` | `#A84007` |
| `bleu` | `#3D8BFD` | `#6EA8FE` | `#0A58CA` |
| `rouge` | `#E5484D` | `#FF6B6F` | `#A32B2F` |
| `vert` | `#1F8F4E` | `#2DBF6B` | `#125C32` |
| `gris` | `#8A8A8A` | `#B4B4B4` | `#5A5A5A` |
| `violet` | `#8B5CF6` | `#A78BFA` | `#6234D1` |
| `neon` (vert néon) | `#39FF14` | `#7BFF5C` | `#1FA30A` |

Le choix est écrit dans `~/.config/lexos/accent` et rejoué à chaque session.
Les applications déjà ouvertes gardent l'ancienne couleur : ferme-les et
rouvre-les.

### Le fond d'écran

```bash
lexos wallpaper                                              # celui par défaut
lexos wallpaper /usr/share/backgrounds/lexos/wallpaper-crt.png
lexos wallpaper ~/Images/mon-fond.png
```

Fonds livrés dans `/usr/share/backgrounds/lexos/` :

| Fichier | Description |
|---|---|
| `wallpaper.png` | Noir pur, braise orange, marque LexOS |
| `wallpaper-crt.png` | Variante avec lignes de balayage et masque de phosphore |
| `wallpaper-4k.png` | Même visuel en 3840×2160 |
| `mascot*.png` | Les illustrations du masque |

### La position du dock

```bash
lexos dock              # position courante
lexos dock droite       # défaut
lexos dock gauche
lexos dock bas
lexos dock haut
```

Le dock se replace immédiatement. Pour changer le défaut de l'ISO, modifie
`LEXOS_DOCK_POSITION` dans `lexos.conf` (`right`, `left`, `bottom`, `top`).

Clic droit sur le dock → **Préférences** pour la taille des icônes, le zoom et
le masquage.

### Les écrans

```bash
lexos ecran                    # ce qui est branché
lexos ecran etendre droite     # ou gauche, haut, bas
lexos ecran miroir
lexos ecran principal HDMI-1   # l'écran qui porte la barre et le dock
lexos ecran gui                # réglage à la souris (Super+D)
lexos ecran profil save bureau # mémoriser cette disposition
```

### Le profil de performance

```bash
lexos perf              # liste
lexos perf auto         # d'après la RAM et les cœurs
lexos perf performant
lexos perf status       # ce qui tourne réellement
```

Pour figer un profil dans l'ISO : `LEXOS_PERF_PROFILE` dans `lexos.conf`
(`auto`, `petit`, `medium`, `performant`, `max`).

Le détail des quatre profils est dans
[`lexos-perf`](../config/includes.chroot/usr/bin/lexos-perf), fonction
`load_profile` — un seul bloc à lire pour tout comprendre.

### Les effets de fenêtres

```bash
lexos crt status    # dit ce qui tourne réellement et pourquoi
lexos crt off       # xfwm4 seul : fondus simples, très léger
lexos crt on        # Compiz : effet téléviseur (redémarrer la session)
```

Réglage fin des effets : `ccsm` (CompizConfig Settings Manager) →
**Effects** → **Animations**. Les effets utilisés par défaut :

| Événement | Effet | Durée |
|---|---|---|
| Ouverture | Glide 2 | 220 ms |
| Fermeture | Glide 2 | 260 ms |
| Réduction | Magic Lamp | 300 ms |
| Menus | Glide 2 | 220 ms |
| Infobulles | Fade | 150 ms |

### Le terminal

Le fichier `~/.config/xfce4/terminal/terminalrc` est régénéré par
`lexos-theme-gen` à chaque changement d'accent. Pour figer tes propres
couleurs, édite-le puis évite `lexos accent` — ou modifie plutôt
`lexos-theme-gen` (voir plus bas).

Valeurs par défaut :

```ini
ColorBackground=#000000     ; noir pur
ColorForeground=#39FF14     ; vert néon
ColorCursor=<accent>        ; orange par défaut
FontName=Fira Code 11
```

### Plusieurs volets dans un seul terminal

Le terminal de LexOS a **déjà des onglets** : `Ctrl+Shift+T` en ouvre un,
`Ctrl+Page haut` / `Ctrl+Page bas` circule entre eux. Ce qu'il n'a jamais eu,
c'est de **couper la fenêtre en volets** — voir une compilation à gauche et
éditer à droite.

La commande `multi` (ou `lexos-multi`) ouvre un terminal en volets :

```bash
multi              # ouvre la session « lexos », ou la reprend si elle existe
multi neuf         # une seconde session, à côté
multi liste        # ce qui tourne
multi fin          # ferme la session « lexos »
```

Une fois dedans :

| Touches | Effet |
|---|---|
| `Ctrl+B` puis `|` | couper en deux colonnes |
| `Ctrl+B` puis `-` | couper en deux rangées |
| `Ctrl+B` puis `c` | nouvel onglet |
| `Alt` + flèches | passer d'un volet à l'autre (sans préfixe) |
| `Ctrl+B` puis `d` | sortir en laissant tout tourner |

La souris marche : cliquer un volet pour y aller, tirer une bordure pour la
déplacer, cliquer un onglet. Une contrepartie à connaître : la roulette entre
dans le mode copie au lieu de défiler dans le terminal — on en sort avec
`Échap`.

**Ce qui tourne dans la session survit à la fermeture de la fenêtre.** C'est le
vrai intérêt : une compilation, un `claude` ou un `ssh` lancé là continue après
`Ctrl+B puis d`, et même après avoir fermé le terminal. On le retrouve en
retapant `multi`.

**`multi` ne se lance jamais tout seul, et c'est voulu.** Un terminal ouvert
par un programme — Claude Code, un éditeur, le gestionnaire de fichiers — reste
un terminal ordinaire. Faire autrement enfermerait dans les volets ceux qui
n'en veulent pas, sans leur dire comment en sortir.

Les réglages sont dans `/usr/share/lexos/tmux/lexos.conf` (souris, couleurs,
raccourcis). Chaque ligne y est commentée. Après modification, `Ctrl+B puis r`
les recharge sans fermer la session.

### Le dock

Clic droit sur le dock → **Préférences** : position, taille des icônes, zoom,
masquage. Pour ajouter une application, glisse son icône depuis le menu.

Les valeurs par défaut de l'image sont dans
`/etc/dconf/db/local.d/00-lexos-dock`.

---

## 2. À la source — reconstruire ton ISO

### `lexos.conf` : la seule source de vérité

Tout part de là. Modifie, relance `make build`, et l'ISO entière suit :
`/etc/os-release`, la bannière de console, le menu de démarrage,
l'installateur, le thème.

```bash
LEXOS_NAME="LexOS"              # le nom partout dans le système
LEXOS_VERSION="2.0.0"
LEXOS_CODENAME="Nomad"
LEXOS_BRAND="TI-LEX-AL"
LEXOS_TAGLINE="Explore. Build. Own your machine."

LEXOS_DEBIAN_SUITE="trixie"     # trixie (Debian 13) ou bookworm (Debian 12)
LEXOS_KERNEL_CHANNEL="stock"    # ou backports : noyau plus récent
LEXOS_ARCH="amd64"

LEXOS_LIVE_USER="lex"           # nom du compte en session démo
LEXOS_HOSTNAME="lexos"
LEXOS_TIMEZONE="America/Toronto"
LEXOS_LOCALE="fr_CA.UTF-8"
LEXOS_KEYBOARD_LAYOUT="ca"
LEXOS_KEYBOARD_VARIANT="fr"

LEXOS_ACCENT_NAME="orange"      # accent par défaut du système construit
LEXOS_DOCK_POSITION="right"     # right | left | bottom | top
LEXOS_CRT_EFFECTS="on"          # effets TV activés par défaut
LEXOS_PERF_PROFILE="auto"       # auto | petit | medium | performant | max
LEXOS_WIFI_AUTO_OPEN="off"      # connexion auto aux réseaux ouverts
LEXOS_DISK_ENCRYPTION="proposed" # chiffrement proposé à l'installation
LEXOS_FLAVOUR="standard"
```

`LEXOS_LOCALE` ne fixe que la langue par défaut au premier démarrage : LexOS
installe `locales-all` (toutes les langues de glibc, déjà compilées), donc
n'importe qui peut changer de langue à tout moment sans rien réinstaller —
`lexos lang quebecois`, `lexos lang fr_FR.UTF-8`, `lexos lang anglais`, ou
Paramètres → Région et langue. `lexos lang toutes` liste vraiment tout ce
qui est installé.

### Ajouter ou retirer des logiciels

Une ligne = un nom de paquet Debian. Les lignes vides et celles commençant par
`#` sont ignorées.

| Fichier | Portée |
|---|---|
| `config/package-lists/lexos-core.list.chroot` | Toutes les saveurs |
| `flavours/standard/desktop.list.chroot` | standard, dev, full, gaming |
| `flavours/dev/devtools.list.chroot` | dev, full, gaming |
| `flavours/full/office-media.list.chroot` | full |
| `flavours/gaming/gaming.list.chroot` | gaming |

Pour vérifier qu'un paquet existe avant de l'ajouter :

```bash
apt-cache search --names-only '^neovim$'
```

Créer une saveur à toi (ici, une saveur « retro » avec des émulateurs) :

```bash
mkdir -p flavours/retro
cat > flavours/retro/emulateurs.list.chroot <<'EOF'
retroarch
dosbox
scummvm
EOF
```

Puis déclare-la dans `build.sh` (fonction de sélection de saveur) et dans le
`case` de validation.

### Remplacer les visuels

Le dossier `branding/` contient les sources. Garde les mêmes noms de fichiers
et tout suit automatiquement.

| Fichier | Où ça apparaît | Format conseillé |
|---|---|---|
| `logo-ti-lex-al.png` | Icônes système, Plymouth, Calamares | PNG carré ≥ 512 px |
| `logo.svg` | Icône vectorielle (menus, panneau) | SVG 512×512 |
| `wallpaper.svg` | Fond d'écran par défaut, LightDM, GRUB | SVG 16:9 |
| `wallpaper-crt.svg` | Fond alternatif | SVG 16:9 |
| `mascot.png` | Avatar de session, écran d'accueil | PNG portrait, fond transparent |
| `config/bootloaders/isolinux/splash.svg` | Menu de démarrage | SVG 640×480 |

Regarder le résultat sans construire l'ISO complète :

```bash
make preview        # rend les SVG en PNG dans ./preview/
```

Les `.webp` sont convertis en `.png` pendant la construction (hook 0300),
parce que peu de composants GTK savent lire le WebP nativement.

### Modifier le thème lui-même

Le générateur est
[`config/includes.chroot/usr/bin/lexos-theme-gen`](../config/includes.chroot/usr/bin/lexos-theme-gen).
C'est un script Bash lisible qui produit :

* `~/.config/gtk-3.0/gtk.css` et `gtk-4.0/gtk.css`
* `~/.gtkrc-2.0` (vieilles applications)
* `~/.config/xfce4/terminal/terminalrc`
* `~/.config/lexos/theme.conf` (variables réutilisables)

Ajouter une couleur d'accent, par exemple un cyan :

```bash
# dans lexos-theme-gen, section « Palette des accents »
cyan|turquoise)  ACCENT="#22B8CF"; ACCENT_HI="#4DD4E8"; ACCENT_LO="#0B7285" ;;
```

Puis autorise-la dans la validation de `.github/workflows/ci.yml` et dans
`lexos.conf`.

Changer le noir pur pour un gris très sombre :

```bash
BG="#0B0B0D"        # au lieu de #000000
```

### Modifier la disposition du bureau

| Quoi | Fichier |
|---|---|
| Barre du haut | `config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml` |
| Gestionnaire de fenêtres | `.../xfwm4.xml` |
| Polices, thème, curseur | `.../xsettings.xml` |
| Programmes lancés à l'ouverture | `.../xfce4-session.xml` |
| Dock (icônes) | `config/includes.chroot/etc/skel/.config/plank/dock1/launchers/` |
| Dock (comportement) | `config/includes.chroot/etc/dconf/db/local.d/00-lexos-dock` |
| Effets Compiz | `config/includes.chroot/etc/dconf/db/local.d/01-lexos-compiz` |

Le plus simple : configure le bureau à la main dans une session live, puis
recopie les fichiers obtenus (`~/.config/xfce4/xfconf/…`) dans `etc/skel/`.

### Ajouter un hook

Les hooks s'exécutent **dans le système en construction**, dans l'ordre de
leur numéro.

```bash
cat > config/hooks/normal/0700-mon-hook.hook.chroot <<'EOF'
#!/bin/sh
set -e
echo "[lexos] hook 0700 : ma personnalisation"

# Ici tu es root, à l'intérieur du futur système.
systemctl disable bluetooth.service || true
echo "monserveur.local" >> /etc/hosts

echo "[lexos] hook 0700 : ok"
EOF
chmod +x config/hooks/normal/0700-mon-hook.hook.chroot
```

Numérotation utilisée :

| Plage | Usage |
|---|---|
| 0100–0199 | Identité et localisation |
| 0300–0399 | Visuels |
| 0400–0499 | Bureau |
| 0500–0599 | Installateur |
| 0600–0699 | Thème |
| 0700–8999 | **Libre pour toi** |
| 9900+ | Nettoyage final |

> Un hook qui retourne autre chose que 0 **interrompt la construction**.
> Termine les commandes non essentielles par `|| true`.

### Ajouter des fichiers tels quels

Tout ce qui est sous `config/includes.chroot/` est copié à l'identique à la
racine du système :

```
config/includes.chroot/etc/motd            →  /etc/motd
config/includes.chroot/usr/bin/mon-script  →  /usr/bin/mon-script
config/includes.chroot/etc/skel/.vimrc     →  hérité par chaque nouveau compte
```

N'oublie pas `chmod +x` sur les scripts : les permissions sont préservées.

---

## Vérifier avant de construire

```bash
make lint       # shellcheck sur tous les scripts
make check      # environnement de build complet ?
```

Le workflow CI rejoue ces contrôles à chaque poussée, plus la validation des
SVG, des XML XFCE, des noms de paquets et la génération des six accents.
