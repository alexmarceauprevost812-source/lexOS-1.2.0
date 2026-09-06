#!/usr/bin/env bash
# =============================================================================
#  LexOS — script de construction de l'ISO
# =============================================================================
#  Usage :
#     sudo ./build.sh                      # saveur par défaut (lexos.conf)
#     sudo ./build.sh --flavour full       # minimal | standard | dev | full
#     sudo ./build.sh --suite trixie       # change la base Debian
#     sudo ./build.sh --check              # vérifie l'environnement et sort
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# --- Couleurs ----------------------------------------------------------------
if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'; C_ORANGE=$'\033[38;5;208m'; C_DIM=$'\033[2m'
	C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
	C_RESET=''; C_ORANGE=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
fi

info()  { printf '%s[LexOS]%s %s\n' "$C_ORANGE" "$C_RESET" "$*"; }
ok()    { printf '%s  ok  %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s warn %s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()   { printf '%s fail %s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# --- Bannière ----------------------------------------------------------------
banner() {
	printf '%s' "$C_ORANGE"
	cat <<'EOF'
   __         _____ _____
  / /  _____ / __  |  ___|
 / /  / _ \ \/ / | | |___
/ /__|  __/>  <  | |___  |
\____/\___/_/\_\ |_____/    build system
EOF
	printf '%s\n' "$C_RESET"
}

# --- Arguments ---------------------------------------------------------------
CHECK_ONLY=0
CLI_FLAVOUR=""
CLI_SUITE=""
CLI_ARCH=""
LB_EXTRA=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		-f|--flavour) CLI_FLAVOUR="${2:-}"; shift 2 ;;
		-s|--suite)   CLI_SUITE="${2:-}";   shift 2 ;;
		-a|--arch)    CLI_ARCH="${2:-}";    shift 2 ;;
		-c|--check)   CHECK_ONLY=1;         shift ;;
		-h|--help)
			cat <<-'USAGE'
			LexOS — construction de l'ISO

			  sudo ./build.sh                     saveur par défaut (lexos.conf)
			  sudo ./build.sh --flavour full      minimal | standard | dev | full | gaming | pro
			  sudo ./build.sh --suite trixie      change la base Debian
			  sudo ./build.sh --arch amd64        architecture cible
			  sudo ./build.sh --check             vérifie l'environnement et sort
			  ./build.sh --help                   cette aide

			Tout ce qui suit « -- » est transmis tel quel à `lb build`.
			USAGE
			exit 0 ;;
		--) shift; LB_EXTRA+=("$@"); break ;;
		*)  die "Option inconnue : $1  (essaie --help)" ;;
	esac
done

banner

# --- Chargement de la config -------------------------------------------------
[[ -f lexos.conf ]] || die "lexos.conf introuvable — tu n'es pas à la racine du projet ?"
# shellcheck source=lexos.conf
source ./lexos.conf

[[ -n "$CLI_FLAVOUR" ]] && LEXOS_FLAVOUR="$CLI_FLAVOUR"
[[ -n "$CLI_SUITE"   ]] && LEXOS_DEBIAN_SUITE="$CLI_SUITE"
[[ -n "$CLI_ARCH"    ]] && LEXOS_ARCH="$CLI_ARCH"
export LEXOS_FLAVOUR LEXOS_DEBIAN_SUITE LEXOS_ARCH

case "$LEXOS_FLAVOUR" in
	minimal|standard|dev|full|gaming|pro) ;;
	*) die "Saveur inconnue : '$LEXOS_FLAVOUR' (minimal | standard | dev | full | gaming | pro)" ;;
esac

info "Distribution : ${LEXOS_NAME} ${LEXOS_VERSION} « ${LEXOS_CODENAME} »"
info "Socle        : Debian ${LEXOS_DEBIAN_SUITE} / ${LEXOS_ARCH} (noyau ${LEXOS_KERNEL_CHANNEL})"
info "Saveur       : ${LEXOS_FLAVOUR}"

# --- Vérification de l'environnement ----------------------------------------
check_env() {
	local missing=() c
	info "Vérification de l'environnement de build…"

	[[ "$(uname -s)" == "Linux" ]] || die "La construction d'une ISO Debian exige un hôte Linux."

	for c in lb debootstrap xorriso mksquashfs rsync wget gpg; do
		if command -v "$c" >/dev/null 2>&1; then
			ok "$c"
		else
			missing+=("$c")
		fi
	done

	if ((${#missing[@]})); then
		printf '%s\n' "" >&2
		warn "Outils manquants : ${missing[*]}"
		cat >&2 <<-EOF

		    Sur Debian / Ubuntu, installe-les avec :

		      sudo apt update
		      sudo apt install -y live-build debootstrap xorriso squashfs-tools \\
		                          rsync wget gnupg ca-certificates \\
		                          syslinux-common isolinux grub-efi-amd64-bin \\
		                          grub-pc-bin mtools dosfstools librsvg2-bin

		EOF
		return 1
	fi

	# live-build >= 1:20230502 pour --uefi-secure-boot
	local lbver
	lbver="$(dpkg-query -W -f='${Version}' live-build 2>/dev/null || echo '?')"
	ok "live-build ${lbver}"

	# Espace disque : ~12 Go conseillés
	local avail_kb avail_gb
	avail_kb="$(df -Pk . | awk 'NR==2{print $4}')"
	avail_gb=$(( avail_kb / 1024 / 1024 ))
	if (( avail_gb < 12 )); then
		warn "Seulement ${avail_gb} Go libres ici — 12 Go minimum recommandés."
	else
		ok "espace disque : ${avail_gb} Go libres"
	fi

	if [[ "${EUID}" -ne 0 ]]; then
		warn "live-build doit tourner en root : relance avec sudo."
		return 1
	fi
	ok "privilèges root"
	return 0
}

if ! check_env; then
	(( CHECK_ONLY )) && exit 1
	die "Environnement incomplet — corrige les points ci-dessus puis relance."
fi

if (( CHECK_ONLY )); then
	info "Environnement prêt. ✔"
	exit 0
fi

# --- Génération des fichiers dérivés ----------------------------------------
info "Génération des fichiers de branding…"

BUILD_DATE="$(date -u '+%Y-%m-%d')"
BUILD_ID="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 'nogit')"

mkdir -p config/includes.chroot/etc/lexos
cat > config/includes.chroot/etc/lexos/build.conf <<EOF
# Généré par build.sh — ne pas éditer à la main.
LEXOS_NAME="${LEXOS_NAME}"
LEXOS_ID="${LEXOS_ID}"
LEXOS_VERSION="${LEXOS_VERSION}"
LEXOS_CODENAME="${LEXOS_CODENAME}"
LEXOS_TAGLINE="${LEXOS_TAGLINE}"
LEXOS_HOME_URL="${LEXOS_HOME_URL}"
LEXOS_BUG_URL="${LEXOS_BUG_URL}"
LEXOS_DEBIAN_SUITE="${LEXOS_DEBIAN_SUITE}"
LEXOS_FLAVOUR="${LEXOS_FLAVOUR}"
LEXOS_ARCH="${LEXOS_ARCH}"
LEXOS_TIMEZONE="${LEXOS_TIMEZONE}"
LEXOS_LOCALE="${LEXOS_LOCALE}"
LEXOS_KEYBOARD_LAYOUT="${LEXOS_KEYBOARD_LAYOUT}"
LEXOS_KEYBOARD_VARIANT="${LEXOS_KEYBOARD_VARIANT}"
LEXOS_BRAND="${LEXOS_BRAND}"
LEXOS_LICENSE="${LEXOS_LICENSE}"
LEXOS_ACCENT_NAME="${LEXOS_ACCENT_NAME}"
LEXOS_BG="${LEXOS_BG}"
LEXOS_FG="${LEXOS_FG}"
LEXOS_TERM_FG="${LEXOS_TERM_FG}"
LEXOS_GTK_BASE_THEME="${LEXOS_GTK_BASE_THEME}"
LEXOS_ICON_THEME="${LEXOS_ICON_THEME}"
LEXOS_CRT_EFFECTS="${LEXOS_CRT_EFFECTS}"
LEXOS_DOCK_POSITION="${LEXOS_DOCK_POSITION}"
LEXOS_PERF_PROFILE="${LEXOS_PERF_PROFILE}"
LEXOS_WIFI_AUTO_OPEN="${LEXOS_WIFI_AUTO_OPEN}"
LEXOS_DISK_ENCRYPTION="${LEXOS_DISK_ENCRYPTION}"
LEXOS_KERNEL_CHANNEL="${LEXOS_KERNEL_CHANNEL}"
LEXOS_NVIDIA_BRANCH="${LEXOS_NVIDIA_BRANCH:-}"
LEXOS_BUILD_DATE="${BUILD_DATE}"
LEXOS_BUILD_ID="${BUILD_ID}"
EOF
ok "etc/lexos/build.conf"

# branding/ est la source de vérité : on le recopie dans l'arbre de l'image.
BRAND_DST="config/includes.chroot/usr/share/lexos/branding"
mkdir -p "$BRAND_DST"
rm -f "$BRAND_DST"/*
cp branding/*.svg branding/*.png "$BRAND_DST"/ 2>/dev/null || true
#  Les .webp (mascottes rock et salut) et le .gif animé : le hook 0300 les
#  attend pour les convertir en PNG — sans cette ligne, sa boucle « *.webp »
#  tournait sur un dossier qui n'en avait aucun, en silence.
cp branding/*.webp branding/*.gif "$BRAND_DST"/ 2>/dev/null || true
#  Les images de l'animation Plymouth (démarrage) : un dossier, que le
#  « cp » sans -r du dessus ignorait — le thème animé retombait sur l'image
#  fixe sans le dire.
[ -d branding/mascot-anim-frames ] && cp -r branding/mascot-anim-frames "$BRAND_DST"/ 2>/dev/null
#  ═══ LA VIDÉO D'OUVERTURE EST UNE SOURCE DE CONSTRUCTION ═══
#  Le hook 0300 tourne DANS le chroot : il ne peut découper que ce qui s'y
#  trouve. Sans cette ligne, ouvrir-ordinateur.mp4 serait resté dans le
#  dépôt, le hook ne l'aurait jamais vue, et l'entrée en matière serait
#  tombée dans son repli à CHAQUE construction — en le disant, mais sans
#  que personne comprenne pourquoi. Le hook la RETIRE après le découpage :
#  7 Mo de vidéo n'ont rien à faire dans l'ISO, seules les images comptent.
cp branding/*.mp4 "$BRAND_DST"/ 2>/dev/null || true
ok "branding/ -> usr/share/lexos/branding ($(ls -1 "$BRAND_DST" | wc -l) fichiers)"

# --- Sélection de la saveur --------------------------------------------------
info "Assemblage des listes de paquets (saveur : ${LEXOS_FLAVOUR})…"
rm -f config/package-lists/zz-flavour-*.list.chroot

apply_flavour() {
	local f="$1" src count=0
	[[ -d "flavours/$f" ]] || return 0
	for src in "flavours/$f"/*.list.chroot; do
		[[ -e "$src" ]] || continue
		cp "$src" "config/package-lists/zz-flavour-$f-$(basename "$src")"
		count=$((count + 1))
	done
	ok "saveur '$f' : $count liste(s)"
}

# Toutes les saveurs de bureau reçoivent EXACTEMENT les mêmes listes.
#
# L'empilement d'avant creusait des trous que personne ne voyait : « pro »
# sautait la liste « full » (LibreOffice, VLC, GIMP, ffmpeg) et « dev » —
# la saveur du portable, celle sur laquelle on teste tout — sautait « full »,
# « gaming » ET « pro ». Le bureau essayé sur le portable n'était donc pas
# celui livré sur l'Alienware.
#
# Seule différence qui reste entre les ISO : le matériel. Le pilote NVIDIA
# propriétaire n'est embarqué que par la saveur « pro » (hook 0260) — le
# portable n'a pas de carte NVIDIA et le lui poser risquerait l'écran noir.
case "$LEXOS_FLAVOUR" in
	minimal)
		;;
	*)
		apply_flavour standard
		apply_flavour dev
		apply_flavour full
		apply_flavour gaming
		apply_flavour pro
		;;
esac

TOTAL_PKGS="$(cat config/package-lists/*.list.chroot 2>/dev/null \
	| grep -Ev '^\s*(#|$)' | sort -u | wc -l)"
OPT_DIR="config/includes.chroot/usr/share/lexos/optional-packages"
OPT_PKGS="$(cat "$OPT_DIR"/*.list 2>/dev/null | grep -Evc '^\s*(#|$)' || echo 0)"
ok "${TOTAL_PKGS} paquets stricts + ${OPT_PKGS} optionnels (best effort)"

# --- Droits d'exécution ------------------------------------------------------
chmod +x auto/config auto/build auto/clean 2>/dev/null || true
chmod +x config/hooks/normal/*.hook.chroot 2>/dev/null || true
chmod +x config/includes.chroot/usr/bin/* 2>/dev/null || true

# --- Construction ------------------------------------------------------------
info "lb config…"
lb config

info "lb build — ça va prendre 20 à 60 minutes et télécharger plusieurs Go."
START="$(date +%s)"
lb build "${LB_EXTRA[@]+"${LB_EXTRA[@]}"}"
END="$(date +%s)"

# --- Résultat ----------------------------------------------------------------
ISO="$(ls -1 ./*.iso 2>/dev/null | head -n1 || true)"
if [[ -n "$ISO" ]]; then
	sha256sum "$ISO" > "${ISO}.sha256"
	printf '\n'
	info "Terminé en $(( (END - START) / 60 )) min $(( (END - START) % 60 )) s"
	ok "ISO      : ${ISO}"
	ok "Taille   : $(du -h "$ISO" | cut -f1)"
	ok "SHA-256  : ${ISO}.sha256"
	printf '\n%sTester dans QEMU :%s\n  make test\n\n' "$C_DIM" "$C_RESET"
	printf '%sGraver sur clé USB :%s\n  sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n\n' \
		"$C_DIM" "$C_RESET" "$ISO"
else
	die "Aucune ISO produite — consulte build.log"
fi
