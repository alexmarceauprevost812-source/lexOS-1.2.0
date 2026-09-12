# Installer LexOS — du fichier ISO à la machine

Ce guide suit l'ordre prudent : **on essaie d'abord, on efface après.**

---

## Étape 0 — Ce que tu vas faire

```
ISO  →  clé USB  →  session DÉMO (sans risque)  →  installation (optionnelle)
```

Les trois premières étapes ne touchent **jamais** ton disque dur. Seule la
quatrième peut effacer des données, et elle te le demandera clairement.

### Quel chemin prendre ?

La clé USB n'est pas le seul moyen d'arriver au bureau LexOS. Choisis selon
ce que tu veux faire :

| Tu veux… | Prends | Touche à ton disque ? |
|---|---|---|
| Juste voir à quoi ça ressemble, tout de suite | **[Machine virtuelle](#autre-moyen-1--machine-virtuelle-lexos-comme-un-simple-logiciel)** | Non, jamais |
| Essayer sur ta vraie machine (vrai matériel, vraie vitesse) | Étapes 2 et 3 (clé USB) | Non |
| Garder plusieurs ISO sur une seule clé | **[Ventoy](#autre-moyen-2--ventoy-la-clé-sans-rien-graver)** | Non |
| Démarrer l'ISO sans aucune clé USB | **[Boucle GRUB](#autre-moyen-3--démarrer-liso-depuis-le-disque-sans-clé-usb)** | Non (lecture seule) |
| LexOS **à côté** de Windows, pour de bon | Étape 4 → « Installer à côté » | Oui — repartitionne |
| LexOS **seul** sur la machine | Étape 4 → « Effacer le disque » | Oui — efface tout |

> **Aucune ISO encore ?** Tous ces chemins partent du même fichier `.iso`.
> Commence par l'**Étape 1**.

### ⚠ Avant d'installer À CÔTÉ de Windows 11 — à faire DANS Windows

Trois réglages de Windows empêchent le partage du disque s'ils ne sont pas
faits **avant**. Ils ne se règlent pas depuis LexOS : c'est dans Windows, une
seule fois, puis on n'y revient plus.

| À faire dans Windows | Pourquoi | Si tu oublies |
|---|---|---|
| **Suspendre BitLocker** (ou noter la clé sur `aka.ms/myrecoverykey`) | Windows 11 chiffre souvent le disque tout seul | L'option « à côté » n'apparaît pas, ou Windows réclame une clé au redémarrage |
| **Désactiver le démarrage rapide** (Options d'alimentation → « Choisir l'action des boutons ») | Windows « hiberne » au lieu de s'arrêter, le disque reste verrouillé | Le redimensionnement échoue avec un message obscur |
| **Laisser de l'espace libre** (20 à 40 % du disque) | LexOS a besoin de place | Rien à partager |

Puis, dans le **BIOS** (touche `F2` ou `F12` au démarrage) :

- **Secure Boot : Désactivé.** L'édition pro embarque le pilote NVIDIA, qui
  ne se charge pas quand Secure Boot est actif → écran noir au premier
  démarrage. (Si Windows est chiffré, suspends BitLocker **avant** de toucher
  au Secure Boot.)

Une fois dans l'installateur : choisis **« Installer à côté »**, jamais
« effacer », et **ne coche pas** le chiffrement pour un premier double
démarrage.

> Ces trois pièges sont les seuls que LexOS ne peut pas régler à ta place.
> Le reste — voir Windows au démarrage, garder tes deux systèmes — est
> automatique.

---

## Étape 1 — Obtenir l'ISO

### Option A — la construire toi-même

```bash
git clone https://github.com/alexmarceauprevost812-source/lexOS-2.0.git
cd lexOS-2.0
make check
make build
```

### Option B — la faire construire par GitHub

Onglet **Actions** du dépôt → workflow **« Construire l'ISO »** →
**Run workflow** → choisis la saveur. Au bout d'une heure environ, l'ISO est
téléchargeable en artefact au bas de la page du job.

### Vérifier l'intégrité

```bash
sha256sum -c lexos-2.0.0-pro-amd64.iso.sha256
```

Si la réponse n'est pas `OK`, l'ISO est corrompue : recommence le
téléchargement plutôt que de graver un fichier abîmé.

---

## Étape 2 — Écrire l'ISO sur une clé USB

Il te faut une clé d'au moins **4 Go** (8 Go pour la saveur `full`). **Tout ce
qu'elle contient sera effacé.**

### Depuis Linux

```bash
lsblk               # identifie la clé — regarde bien la taille !
```

```
NAME   SIZE TYPE MOUNTPOINTS
sda    477G disk               ← disque dur interne : NE PAS TOUCHER
├─sda1   1G part /boot/efi
└─sda2  476G part /
sdb     15G disk               ← la clé USB, c'est celle-là
└─sdb1   15G part /media/lex/USB
```

```bash
make usb DEVICE=/dev/sdb
```

La commande affiche le périphérique visé et attend que tu tapes `OUI`.

Sans le Makefile :

```bash
sudo umount /dev/sdb* 2>/dev/null
sudo dd if=lexos-2.0.0-pro-amd64.iso of=/dev/sdb bs=4M status=progress oflag=sync
sync
```

> `of=` prend le **disque entier** (`/dev/sdb`), jamais une partition
> (`/dev/sdb1`). Relis la ligne avant d'appuyer sur Entrée : `dd` ne demande
> aucune confirmation.

### Depuis Windows ou macOS

Utilise [balenaEtcher](https://etcher.balena.io/) : sélectionne l'ISO,
sélectionne la clé, clique sur *Flash*. Il refuse par sécurité d'écrire sur un
disque système.

---

## Autre moyen 1 — Machine virtuelle (LexOS comme un simple logiciel)

C'est le moyen **le plus sûr** et le plus rapide : LexOS s'ouvre dans une
fenêtre, comme n'importe quel programme. Ton disque dur n'est jamais touché,
aucune partition n'est modifiée, et tu peux tout casser sans conséquence.

### Depuis Windows ou macOS — VirtualBox

1. Installe [VirtualBox](https://www.virtualbox.org/) (gratuit, libre).
2. **Nouvelle** → nom `LexOS`, type *Linux*, version *Debian (64-bit)*.
3. Mémoire : **4096 Mio** (2048 minimum pour la saveur `minimal`).
4. Disque virtuel : **25 Go** dynamiquement alloué — c'est un fichier sur ton
   disque, pas une partition.
5. Une fois créée : **Configuration** → *Système* → *Carte mère* → coche
   **Activer l'EFI**. LexOS démarre en UEFI comme les machines modernes.
6. **Configuration** → *Stockage* → clique le lecteur optique vide → choisis
   ton fichier `.iso`.
7. **Démarrer**. Le menu LexOS apparaît : prends **Live**.

Pour installer LexOS *dans* la machine virtuelle (et le garder d'une fois à
l'autre), lance `lexos install-disk` **à l'intérieur** de la fenêtre : il
n'écrit alors que dans le disque virtuel de 25 Go, jamais sur ton vrai disque.

> **Écran trop petit ?** *Écran* → *Affichage* → mets la mémoire vidéo à
> 128 Mio et le contrôleur graphique à `VMSVGA`.

### Depuis Linux — QEMU, sans rien installer de plus

Si tu es déjà dans le dépôt :

```bash
make test           # démarrage BIOS
make test-uefi      # démarrage UEFI (exige le paquet ovmf)
```

---

## Autre moyen 2 — Ventoy (la clé sans rien graver)

Avec [Ventoy](https://www.ventoy.net/), tu prépares la clé **une seule fois**,
puis tu **copies-colles** les fichiers `.iso` dessus comme des fichiers
ordinaires. Tu peux en garder plusieurs et choisir au démarrage.

1. Installe Ventoy sur la clé (⚠ cette étape-là efface la clé, une fois).
2. Glisse-dépose `lexos-2.0.0-pro-amd64.iso` sur la clé, comme un fichier.
3. Redémarre, choisis la clé dans le menu de démarrage, puis LexOS dans la
   liste que Ventoy affiche.

Avantage : pour tester une nouvelle version, tu remplaces juste le fichier.
Pas besoin de regraver.

---

## Autre moyen 3 — Démarrer l'ISO depuis le disque, sans clé USB

Si tu as **déjà un Linux avec GRUB** sur la machine, tu peux démarrer l'ISO
posée sur ton disque dur, sans aucune clé. GRUB la lit **en lecture seule** —
rien n'est écrit, rien n'est effacé.

1. Pose l'ISO quelque part de stable, par exemple `/boot/iso/lexos.iso`.
2. Ajoute ceci à `/etc/grub.d/40_custom` :

```sh
menuentry "LexOS 1.0 (démo depuis le disque)" {
    set isofile="/boot/iso/lexos.iso"
    loopback loop $isofile
    linux (loop)/live/vmlinuz boot=live findiso=$isofile components quiet splash
    initrd (loop)/live/initrd.img
}
```

3. `sudo update-grub`, puis redémarre et choisis l'entrée.

⚠ Ça ne marche **pas** depuis Windows seul (Windows n'a pas GRUB), et le
chemin `/boot/iso/` doit être sur une partition que GRUB sait lire (ext4 ou
FAT32 conviennent ; un `/boot` chiffré, non).

---

## Étape 3 — Démarrer en session démo

1. Laisse la clé branchée et redémarre l'ordinateur.
2. Au tout début du démarrage, appuie répétitivement sur la touche du menu de
   démarrage : souvent `F12`, parfois `F11`, `F9`, `Échap` ou `Suppr`. Le
   fabricant l'affiche brièvement au premier écran.
3. Choisis la ligne qui correspond à ta clé (`USB`, `UEFI: SanDisk…`).
4. Dans le menu LexOS, prends **Live**.

Après quelques secondes, tu es sur le bureau LexOS, connecté en tant que
`lex`. L'écran de bienvenue s'ouvre.

### Ce que tu peux faire sans aucun risque

* Ouvrir un terminal et taper `lexfetch`, `lexos doctor`, `lexos help`.
* Changer la couleur des boutons : `lexos accent violet`.
* Vérifier que le Wi-Fi, le son, l'écran et le pavé tactile fonctionnent.
* Installer des logiciels, ouvrir tes fichiers, naviguer sur le web.

Tout disparaît au redémarrage. **Ton disque dur n'a pas été ouvert.**

Pour t'en assurer :

```bash
lexos demo
```

### Si le démarrage échoue

| Symptôme | Piste |
|---|---|
| La clé n'apparaît pas dans le menu | Désactive *Secure Boot* dans le BIOS/UEFI, ou active le mode *Legacy/CSM* |
| Écran noir après le menu | Rechoisis l'entrée Live et ajoute `nomodeset` aux options de démarrage (touche `e` sur l'entrée) |
| Bureau très lent | Normal en démo : tout tourne depuis l'USB. Ce sera bien plus rapide une fois installé |
| Pas de Wi-Fi | Certaines cartes ont besoin d'un firmware absent. Branche un câble réseau puis `lexos update` |

---

## TI-LEX-OS Pro — l'édition pour jouer

Une **ISO à part**, pas une option à cocher. Même socle que LexOS, mais
assemblée pour une machine de jeu :

| | LexOS standard | TI-LEX-OS Pro |
|---|---|---|
| Pilotes Vulkan et Mesa | à installer | **déjà là** |
| Wine (jeux Windows) | à installer | **déjà là** |
| Steam + Proton | à installer | **déjà là** |
| Lutris, GameMode, MangoHud | à installer | **déjà là** |
| Manettes (Steam, Xbox, PS) | règles à ajouter | **reconnues au branchement** |
| Émulateurs | à installer | RetroArch, Dolphin, PPSSPP, mGBA, ScummVM |
| Jeux libres pour démarrer | aucun | SuperTuxKart, 0 A.D., Minetest, OpenTTD, Xonotic |

Le système s'annonce sous son propre nom — écran de démarrage, « À propos »,
`lexfetch` — parce que ce n'est pas le même produit.

### Faire construire l'ISO Pro

Dans `.iso-build-request`, mets `flavour: pro` et incrémente `build:` :

```yaml
flavour: pro
build: 8
```

Pousse : GitHub Actions produit `lexos-2.0.0-pro-amd64.iso`, à côté de
l'édition standard. En local : `sudo ./build.sh --flavour pro`.

### Les jeux Windows

Deux chemins, et ils ne se valent pas :

* **Steam → Proton.** Le plus simple. Steam installe Proton tout seul ; dans
  les propriétés d'un jeu, coche *Forcer l'utilisation d'un outil de
  compatibilité*. La plupart des jeux démarrent sans autre réglage.
* **Lutris.** Pour ce qui n'est pas sur Steam — GOG, Epic, un installeur
  `.exe` trouvé ailleurs. Lutris applique des scripts écrits par d'autres
  joueurs pour chaque jeu.

Ce qui ne marchera pas, et il vaut mieux le savoir avant d'essayer : les
jeux en ligne dont l'anti-triche refuse Linux — c'est un refus délibéré de
leur éditeur, pas une limite technique de LexOS. `lexos game info` affiche
ce que la machine sait faire (Vulkan, GameMode, MangoHud) avant de lancer.

> **Secure Boot et le pilote NVIDIA.** L'édition pro installe le pilote
> NVIDIA depuis le dépôt officiel : son module noyau n'est pas signé par la
> clé de Debian. Il faut donc **laisser le Secure Boot désactivé** dans le
> BIOS — sinon le module ne se charge pas et l'écran reste noir au démarrage.
> Ce n'est pas un dépannage optionnel : pour le pro, c'est un prérequis.

### Si l'écran reste noir malgré tout

Prends d'abord l'entrée **« mode secours »** du menu de démarrage : elle
s'arrête en console, sur du texte, sans jamais lancer de bureau. C'est le
seul état dont on ait la preuve qu'il tient même sur un téléviseur récalcitrant.
Une fois la console affichée, `lexos tv` lit ce que l'écran réclame, sans
serveur graphique ni pilote, et `lexos gpu` dit quel pilote tient la carte.

Deux réglages de BIOS reviennent souvent sur les Dell et Alienware. **Ils
ne sont pas mesurés ici** — Secure Boot et AHCI, eux, l'ont été, sur
l'Alienware, écran noir à l'appui. Ceux-ci sont à essayer seulement si le
reste n'a rien donné :

| Réglage | Valeur à essayer | L'idée |
|---|---|---|
| **Fastboot** | `Thorough` plutôt que `Minimal` | Le démarrage écourté saute une partie de l'initialisation de la carte graphique. |
| **Graphics / Optimus** (portables seulement) | `Discrete` | Évite le mode hybride tant qu'aucun pilote n'est chargé. Coûte cher en autonomie : c'est un réglage de diagnostic, pas un réglage de tous les jours. |

Sur une tour, le second ne s'applique pas — il n'y a pas de carte intégrée à
arbitrer.

---

## Sur un Mac

« Est-ce que ça tourne sur du Apple ? » n'a pas une seule réponse. Il y a
trois familles de Mac, et elles n'ont presque rien en commun.

| Machine | LexOS démarre ? | Ce qu'il faut savoir |
|---|---|---|
| **Mac Intel 2008-2017** | Oui | Comme sur un PC UEFI. Wi-Fi Broadcom à régler |
| **Mac Intel 2018-2020** (puce T2) | Oui, avec réserves | Clavier et souris **USB** obligatoires |
| **Mac Intel 2006-2008** (EFI 32 bits) | Oui, en mode BIOS | Choisir l'entrée « Windows » dans le menu ⌥ |
| **Mac 2006** (Core Duo) | Non | Processeur 32 bits |
| **Mac M1 · M2 · M3 · M4** | **Non** | Ce n'est pas un processeur x86 |

Pour savoir dans quelle case tombe une machine précise, sans rien installer :
le panneau **Paramètres → Matériel → Mac (Apple)** de la
[démo en ligne](https://logiciel-ti-lex.vercel.app/demo)
donne le verdict modèle par modèle. Une fois LexOS démarré, `lexos mac` fait le
même travail sur la machine réelle.

### Mac Intel (2008-2017) — le cas simple

1. Écris l'ISO sur une clé USB avec `dd` — pas un copier-coller :

   ```bash
   diskutil list                     # trouver le numéro N de la clé
   diskutil unmountDisk /dev/diskN
   sudo dd if=lexos-2.0.0-pro-amd64.iso of=/dev/rdiskN bs=4m status=progress
   ```

2. Redémarre en tenant **Option (⌥)**.
3. Choisis **EFI Boot**.

Une fois sur le bureau :

```bash
lexos mac              # bilan de la machine
lexos mac wifi         # quel pilote Broadcom il faut, d'après l'identifiant PCI
lexos mac clavier fonction   # F1..F12 redeviennent de vraies touches F
lexos mac ventilateur        # qu'ils accélèrent quand ça chauffe
```

Les deux derniers comptent plus qu'ils n'en ont l'air. Sous Linux, **rien ne
pilote les ventilateurs d'un Mac** tant que `mbpfan` n'est pas lancé : la
machine chauffe en silence. Et la rangée F d'Apple pilote la luminosité, pas
les touches F — ce que la plupart des raccourcis Linux attendent.

Pour installer à côté de macOS, réduis d'abord la partition depuis
l'Utilitaire de disque **de macOS**. Redimensionner de l'APFS depuis Linux
n'est pas fiable.

### Mac à puce T2 (2018-2020) — ça marche, mais lis d'abord

Avant même de brancher la clé :

1. Redémarre en tenant **Commande + R** → Utilitaires →
   **Utilitaire de sécurité au démarrage**.
2. Sécurité au démarrage : **Aucune sécurité**.
3. Démarrage externe : **Autoriser**.

Sans ces deux réglages, le Mac refuse la clé sans rien expliquer.

Ensuite, **avec le noyau Debian d'origine que livre LexOS**, ceci ne
fonctionnera pas :

* le clavier et le pavé tactile internes → il faut un clavier et une souris USB ;
* le son interne ;
* le Wi-Fi interne (son micrologiciel est propre à la machine et vit dans macOS) ;
* le SSD interne peut rester invisible — donc pas d'installation dessus.

Ces quatre points demandent le noyau modifié du projet
[t2linux](https://t2linux.org). LexOS ne le livre pas : c'est un noyau à part,
qui suit son propre calendrier de correctifs. Nous préférons un noyau Debian
qui reçoit les mises à jour de sécurité, et le dire franchement, plutôt qu'une
promesse tenue par un noyau figé.

### Mac Apple Silicon (M1, M2, M3, M4) — non

Ce n'est pas un manque de réglage, c'est un autre processeur. Les puces M sont
en ARM ; l'ISO de LexOS est compilée pour amd64. Le firmware ne saura même pas
la lire.

La seule façon de faire tourner Linux sur ces machines aujourd'hui est
[Asahi Linux](https://asahilinux.org), qui a dû écrire son propre amorceur
(m1n1) et une bonne part des pilotes par rétro-ingénierie. LexOS ne se pose pas
dessus : ce serait une distribution entièrement différente, à recompiler pour
arm64 et à rebâtir sur leur noyau.

Ce qui reste possible :

* **LexOS dans une machine virtuelle x86** (UTM en mode émulation) — ça marche,
  c'est lent, tout est traduit instruction par instruction ;
* **Debian arm64 dans UTM ou Parallels** — rapide et complet, mais ce n'est
  pas LexOS.

---

## Windows pour jouer, LexOS pour travailler — les deux sur la même machine

C'est le cas d'usage le plus demandé : garder Windows tel quel, et prendre
**une part fixe du disque** pour LexOS — 40 Go, de quoi être à l'aise sans
grignoter les jeux.

### Une commande qui vérifie tout avant que tu touches à quoi que ce soit

Depuis la session démo, ouvre un terminal et tape :

```bash
sudo lexos dualboot
```

Cet outil **ne modifie rien** — il lit le disque et il ne fait qu'écrire à
l'écran. Il te dit, en une page :

- si Windows est bien là et quelle place il occupe **réellement** (une
  partition de 900 Go dont 200 sont utilisés peut céder beaucoup ; une de
  250 Go pleine à 240 ne peut rien céder) ;
- **si Windows a été vraiment éteint** — c'est le piège n° 1, voir ci-dessous ;
- **le chiffre exact** à régler sur le curseur de l'installateur ;
- si le menu de démarrage saura proposer Windows ensuite.

Tu peux le relancer autant de fois que tu veux, il n'écrit jamais sur le
disque.

### Le piège n° 1 : « Démarrage rapide » n'éteint pas Windows

Windows 10 et 11 sont livrés avec le **Démarrage rapide** activé. Quand tu
cliques « Arrêter », il ne s'arrête pas vraiment : il s'**hiberne**. Son
disque reste marqué comme en cours d'utilisation, et **aucun outil au monde**
ne peut le redimensionner sans risquer de l'abîmer.

À faire dans Windows, **une seule fois** :

1. Panneau de configuration → **Options d'alimentation**
2. « Choisir l'action des boutons d'alimentation »
3. « Modifier des paramètres actuellement non disponibles »
4. Décocher **« Activer le démarrage rapide »**
5. Enregistrer, puis **Arrêter** — pas Redémarrer, pas Veille

Ce n'est pas un défaut de LexOS : c'est Windows qui reste à moitié allumé.

### Ensuite, dans l'ordre

1. **Sauvegarde ce qui compte.** Par principe, avant tout partage de disque.
   L'installateur ne touche pas à tes fichiers Windows, mais une coupure de
   courant au mauvais moment, ça existe.
2. **BIOS (F2 au démarrage) : Secure Boot → Disabled.** Le pilote NVIDIA de
   LexOS n'est pas signé par Debian ; Secure Boot actif = pilote refusé =
   écran noir. Profites-en pour vérifier **SATA Operation → AHCI** (et non
   « RAID On ») : en mode RAID, aucun installateur Linux ne voit le disque.
3. Démarre sur la clé LexOS, lance **Installer LexOS**.
4. Choisis **« Installer à côté de »** — l'écran avec le curseur qui partage
   le disque. Règle-le sur le chiffre que `lexos dualboot` t'a donné (40 Go).
5. **Lis l'écran de résumé** avant de valider. Rien n'est écrit sur le disque
   avant que tu cliques.
6. Au redémarrage, un menu te propose **LexOS** ou **Windows Boot Manager**.
   Si tu ne touches à rien, **Windows démarre tout seul après 8 secondes**
   — Windows sert à jouer, et celui qui allume pour jouer n'a rien à faire.
   Pour LexOS : une flèche du clavier pendant ces 8 secondes, puis Entrée.

> **Pour changer ce délai ou le système par défaut**, une fois LexOS installé :
> `sudoedit /etc/default/grub.d/lexos.cfg` (la ligne `GRUB_TIMEOUT`), puis
> `sudo update-grub`. Et pour remettre LexOS par défaut :
> `sudo systemctl disable lexos-grub-defaut && sudo grub-editenv - unset saved_entry`.

### Ce qui rend ça possible, et qui reste du logiciel libre

| Outil | Rôle | Licence |
|---|---|---|
| Calamares | L'écran « Installer à côté de » et son curseur | GPL-3 |
| ntfs-3g / ntfsresize | Lire et redimensionner la partition Windows | GPL-2 |
| parted | La table de partitions | GPL-3 |
| os-prober | Trouver Windows pour le menu de démarrage | GPL-2/3 |
| GRUB | Le menu qui propose les deux systèmes | GPL-3 |

**Aucun outil propriétaire n'est nécessaire** — pas d'EaseUS, pas de
MiniTool, pas de Paragon. Tout le partage de disque se fait depuis LexOS,
avec du logiciel libre.

> **Pourquoi LexOS ne redimensionne pas Windows tout seul, automatiquement ?**
> Parce que le code de redimensionnement de Calamares tourne sur des millions
> de machines depuis des années, et qu'un script maison n'aurait jamais été
> essayé sur le disque de personne avant le tien. Sur un disque qui contient
> tes jeux et tes fichiers, ce n'est pas un pari raisonnable. `lexos dualboot`
> te donne le chiffre ; Calamares fait le travail, avec sa confirmation.

### Si quelque chose se passe mal

- **Windows n'apparaît plus dans le menu** — démarre sur LexOS et tape
  `sudo lexos dualboot` : il te dira si `os-prober` a bien vu Windows. Puis
  `sudo update-grub` régénère le menu.
- **Rien ne démarre du tout** — dans le BIOS, l'ordre de démarrage
  (Boot Order) a peut-être changé. Remets LexOS ou Windows en premier.
- **Windows démarre mais se plaint du disque** — laisse-le faire son
  `chkdsk` au premier démarrage, c'est normal après un redimensionnement.

---

## Installer LexOS À CÔTÉ d'un autre Linux (ou de Windows)

> **Deux installateurs, deux chemins.** Le plus simple, celui de l'Étape 4,
> est l'installateur graphique **Calamares** : il propose directement
> « Installer à côté » et redimensionne tout seul. La section ci-dessous
> décrit l'**installateur Debian** (écrans « Partitionner les disques »),
> disponible via l'entrée **« Install »** du menu de démarrage de la clé —
> à réserver au partitionnement manuel avancé. Pour Windows, préfère
> Calamares, et suis d'abord l'encadré **« Avant d'installer à côté de
> Windows 11 »** en haut de ce guide (BitLocker, démarrage rapide,
> Secure Boot).

C'est possible, et c'est même le cas le plus courant. Mais il y a un ordre à
respecter, sinon l'installateur s'arrête sur :

> **Échec du partitionnement du disque choisi** — Le disque ou l'espace
> disponible sont probablement trop petits pour que le partitionnement
> automatique puisse fonctionner.

Ce message ne veut pas dire que ton disque est petit. Il veut dire qu'il n'y
a **aucun espace libre** : le système déjà installé occupe tout.

### 1. Libérer de la place — sans quitter l'installateur

**Tu n'as pas besoin de redémarrer, ni d'installer quoi que ce soit.**
L'installateur Debian sait rétrécir une partition ext4 lui-même. Il travaille
depuis la clé USB, donc la partition de l'autre système n'est pas montée —
c'est exactement la condition qui manque quand on essaie de redimensionner
Ubuntu depuis Ubuntu.

Depuis l'écran d'erreur, reviens au menu principal, puis :

1. **Partitionner les disques** → **Manuel**.
2. La table s'affiche. Repère la **grande partition ext4** de l'autre système
   — celle qui fait presque toute la taille du disque. Sur un portable avec
   Ubuntu, ça ressemble à ça :

   ```
   SCSI2 (0,0,0) (sda) - 256.1 GB ATA SAMSUNG MZ7LN256
        n° 1     1.1 GB   ext4     ← /boot d'Ubuntu
        n° 2     1.1 GB   fat32    ← partition EFI, commune aux deux systèmes
        n° 3     2.1 GB   ext4     ← récupération
        n° 4   251.7 GB   ext4     ← Ubuntu : c'est celle-ci qu'on rétrécit
   ```

   Le deuxième disque de la liste (`sdb`, quelques dizaines de Go) est **ta
   clé USB**. N'y touche jamais.
3. Sélectionne la grande partition, **Entrée**, puis **« Redimensionner la
   partition »**.
4. Donne une taille plus petite — laisse **au moins 40 Go** libres pour LexOS.
   Rien n'est effacé : l'autre système garde tous ses fichiers.
5. Une ligne **« Espace libre »** apparaît alors dans la table.

**Ne touche pas à la partition fat32 (EFI).** Elle est prévue pour être
partagée : LexOS y ajoute son propre chargeur à côté de celui d'Ubuntu.

> **Sauvegarde tes fichiers importants avant.** Redimensionner une partition
> est l'opération la plus risquée de toute l'installation : une coupure de
> courant au mauvais moment peut coûter les deux systèmes. Ça se passe bien
> presque toujours — mais « presque » n'est pas « toujours ».

#### Si « Redimensionner la partition » n'apparaît pas

Le menu ne propose alors que « Effacer les données de cette partition » et
« Supprimer la partition ». **Ne choisis ni l'une ni l'autre** — les deux
détruisent l'autre système. Sors par « Fin du paramétrage de cette partition »,
qui ne modifie rien, et va d'abord voir ce qu'il y a vraiment dans cette
partition.

##### Regarder avant d'agir

Depuis le menu principal de l'installateur, tout en bas :
**« Exécuter un shell (ligne de commande) »** → **Continuer**, puis :

```sh
blkid
```

Une ligne par partition. Celle qui compte est la grande — `/dev/sda4` dans
l'exemple ci-dessus :

```
/dev/sda1: TYPE="ext4"
/dev/sda2: TYPE="vfat"
/dev/sda3: TYPE="ext4"
/dev/sda4: TYPE="crypto_LUKS"          ← c'est cette ligne qui décide
/dev/sdb1: LABEL="LexOS 1.0" TYPE="iso9660"   ← la clé USB, ne pas y toucher
```

`exit` pour revenir au menu.

| `TYPE=` | Ce que c'est | Ce qu'il faut faire |
|---|---|---|
| `ext4` mais pas d'option « Redimensionner » | Système de fichiers « sale » | Voir juste en dessous |
| `LVM2_member` | LVM non chiffré | GParted depuis la session live |
| `crypto_LUKS` | **Chiffré** | Voir « Et si l'autre système est chiffré ? » |
| *(la partition n'apparaît pas)* | Réellement vide | Rien à rétrécir, utilise-la directement |

##### Système de fichiers « sale »

L'autre système n'a pas été éteint proprement (ou Windows a laissé son
*démarrage rapide* actif). L'installateur refuse de toucher une partition dont
le journal n'est pas propre. Redémarre dessus, éteins-le normalement, et
reviens.

**Windows en plus ?** Réduis-le depuis Windows (Gestion des disques), pas
depuis Linux : lui seul sait déplacer ses propres fichiers système. Et
désactive le *démarrage rapide*, qui laisse la partition dans un état que
Linux refuse de toucher.

#### Solution de repli : GParted depuis la session live

Si l'installateur ne peut pas faire le redimensionnement, redémarre sur la clé
LexOS en mode **Live**, puis :

```bash
sudo apt install gparted
sudo gparted
```

Clic droit sur la partition de l'autre système → **Redimensionner** → laisse
**au moins 40 Go** d'espace non alloué → applique, puis relance l'installation.

GParted voit le LVM et le chiffrement, et son affichage graphique rend l'état
du disque plus lisible. C'est le seul avantage qu'il a ici : dans le cas
ordinaire, l'installateur fait la même chose sans redémarrage.

#### Et si l'autre système est chiffré ? (`crypto_LUKS`)

C'est le cas le plus difficile, et il vaut mieux le savoir avant de commencer
plutôt qu'au milieu.

Une partition `crypto_LUKS` est un coffre fermé. Tant qu'il n'est pas ouvert,
aucun outil — ni partman, ni GParted — ne voit ce qu'il y a dedans, donc aucun
ne peut le rétrécir. Et le contenu est, en général, un LVM : il y a donc
**trois couches** empilées à réduire, dans cet ordre, de l'intérieur vers
l'extérieur.

**Trois options, par risque croissant :**

##### 1. Installer LexOS sur une autre clé USB ou un disque externe *(recommandé)*

Une installation complète et persistante, qui démarre à part. On ne touche
jamais au disque interne, donc **le risque pour l'autre système est nul**.

Il faut une clé de **32 Go minimum** (64 Go confortable) ou un petit SSD
externe — en plus de la clé d'installation. Au partitionnement, choisis
« Assisté — utiliser un disque entier » et **sélectionne bien le nouveau
disque**. Vérifie sa taille dans la liste avant de valider : c'est le seul
garde-fou.

##### 2. Rester en session Live

LexOS tourne depuis la clé sans rien installer. Les changements sont perdus à
chaque redémarrage, mais tout est essayable immédiatement et sans risque.

##### 3. Rétrécir le coffre chiffré

Possible, mais à ne tenter qu'en sachant ce qu'on fait :

- **Il faut le mot de passe de chiffrement** — celui demandé au tout début du
  démarrage, avant l'écran de connexion. Sans lui, rien n'est possible : c'est
  précisément à quoi sert le chiffrement.
- La dernière étape recrée la partition en saisissant des numéros de secteurs.
  **Une erreur de chiffre et le système chiffré est perdu** — et chiffré veut
  dire qu'aucun outil de récupération ne rattrapera quoi que ce soit.
- **Sauvegarde complète obligatoire.** Pas « les documents importants » : tout
  ce qui ne doit pas disparaître.

Depuis une session live LexOS, l'ordre est le suivant — l'intérieur d'abord,
l'extérieur en dernier :

```bash
sudo cryptsetup luksOpen /dev/sda4 coffre    # demande le mot de passe
sudo vgchange -ay                            # active le LVM qui est dedans
sudo lvs                                     # note le nom exact du volume

sudo e2fsck -f /dev/mapper/<vg>-<lv>         # obligatoire avant resize2fs
sudo resize2fs /dev/mapper/<vg>-<lv> 150G    # 1. le système de fichiers
sudo lvreduce -L 155G /dev/mapper/<vg>-<lv>  # 2. le volume logique
sudo pvresize --setphysicalvolumesize 160G /dev/mapper/coffre   # 3. le volume physique

sudo vgchange -an
sudo cryptsetup luksClose coffre
```

Puis seulement, avec `parted` ou `fdisk`, supprimer et recréer `sda4` **au même
secteur de départ** et avec une fin plus petite. Le début doit être identique
au *secteur* près : l'en-tête LUKS est là, et le déplacer d'un seul secteur rend
le coffre illisible.

Les marges croissantes (150 → 155 → 160 Go) ne sont pas de la décoration :
chaque couche doit rester strictement plus grande que celle qu'elle contient.
Une couche qu'on rétrécit en dessous de son contenu, c'est la perte des
données, sans avertissement.

### 2. Remplir l'espace libéré

Toujours dans le partitionnement, remonte sur **« Partitionnement assisté »**
et choisis **« Utiliser le plus grand espace continu disponible »**. C'est la
seule des options qui ne touche pas aux partitions existantes.

Les autres commencent par « utiliser **tout** un disque » — et *tout* veut
dire tout, l'autre système compris.

Puis **« Terminer le partitionnement et appliquer les changements »**.

### 3. Au démarrage suivant

GRUB propose la liste : LexOS, l'autre système, et les outils de secours.
Les deux cohabitent sans se gêner et gardent chacun leurs fichiers.

---

## Étape 4 — Installer sur le disque (seulement si tu es convaincu)

### Avant de cliquer

- [ ] Tu as **essayé** la session démo et tout fonctionne.
- [ ] Tu as **sauvegardé** tes fichiers importants sur un disque externe.
- [ ] L'ordinateur est **branché sur le secteur**.
- [ ] Tu sais si tu veux **effacer le disque** ou **installer à côté** de ton
      système actuel.

### Lancer

Double-clique sur **« Installer LexOS sur le disque »**, ou en terminal :

```bash
lexos install-disk
```

Un avertissement s'affiche avec la liste des disques détectés. En mode
graphique il faut cliquer sur **« J'ai compris, installer »** ; en console il
faut taper `EFFACER` en toutes lettres. N'importe quoi d'autre annule.

### Les choix de l'installateur

| Choix | Ce que ça fait |
|---|---|
| **Effacer le disque** | Supprime **tout** et installe LexOS seul. Irréversible. |
| **Installer à côté** | Réduit la partition existante et installe LexOS à côté. Un menu au démarrage te laisse choisir. |
| **Partitionnement manuel** | Tu décides de chaque partition. Réservé à ceux qui savent. |

En cas de doute : **installer à côté**. Tu gardes ton système actuel et tu peux
revenir en arrière.

### Après l'installation

1. Éteins, **retire la clé USB**, rallume.
2. Connecte-toi avec le compte créé pendant l'installation.
3. Mets le système à jour :

```bash
lexos update
lexos upgrade
```

4. Vérifie que tout va bien :

```bash
lexos doctor
```

---

## Désinstaller LexOS

Il n'y a pas de « désinstalleur ». Selon ton cas :

* **LexOS seul sur le disque** — démarre l'installateur d'un autre système et
  laisse-le reformater le disque.
* **LexOS à côté d'un autre système** — supprime ses partitions avec GParted
  depuis une clé live, puis restaure le chargeur de démarrage de l'autre
  système (`bootrec /fixmbr` depuis un support de réparation Windows, par
  exemple).

Sauvegarde avant, dans les deux cas.

---

## Aide

* `lexos doctor` — diagnostic automatique
* `lexos logs` — dernières erreurs du système
* [Ouvrir un ticket](https://github.com/alexmarceauprevost812-source/lexOS-2.0/issues)
  en joignant la sortie de `lexos doctor` et `lexos version`
