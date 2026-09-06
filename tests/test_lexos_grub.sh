#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — le thème GRUB : plus de rectangle bleu au démarrage
# =============================================================================
#  ALEX, PHOTO DU ThinkPad T460 (GRUB 2.12, UEFI) : le cadre LexOS est là —
#  « UEFI · x86_64 », « GRUB 2.12 », la barre d'aide — mais au milieu, « un
#  grand rectangle bleu-turquoise à vagues », avec « Loading Linux… » dessus.
#  « On dirait que mon logiciel est complètement planté. »
#
#  CE RECTANGLE EST LA ZONE TERMINAL DU THÈME (terminal-left/top/width/height
#  dans theme.txt : 8 → 92 % et 10 → 90 %, exactement le rectangle de la
#  photo). C'est la fenêtre où GRUB écrit ses messages quand il quitte le
#  menu. Sans « terminal-box », il n'y peint rien à nous et laisse voir l'image
#  de fond posée par /etc/grub.d/05_debian_theme — celle de desktop-base, les
#  vagues turquoise de trixie. Le thème gagnait pour le MENU ; il ne disait
#  rien de la zone terminal.
#
#  DEUX VERROUS, ET CE BANC LES TIENT TOUS LES DEUX :
#    1. « terminal-box » noir dans theme.txt (neuf tranches noires), dans les
#       DEUX exemplaires — système installé et ISO ;
#    2. GRUB_BACKGROUND="" dans /etc/default/grub.d/lexos.cfg, pour que
#       05_debian_theme n'écrive plus « background_image ». Le script de
#       Debian est JOUÉ, pas relu : avec et sans desktop-base.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_SYS="$RACINE/config/includes.chroot/usr/share/grub/themes/lexos"
THEME_ISO="$RACINE/config/includes.binary/boot/grub/themes/lexos"
HOOK="$RACINE/config/hooks/normal/0100-lexos-identity.hook.chroot"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0
ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

# -----------------------------------------------------------------------------
titre "1. Le thème est livré aux deux endroits, et c'est le même"
for D in "$THEME_SYS" "$THEME_ISO"; do
	[[ -r "$D/theme.txt" ]] || { non "theme.txt introuvable : $D"; printf '\n'; exit 1; }
done
ok "theme.txt présent côté système installé et côté ISO"
if diff -q "$THEME_SYS/theme.txt" "$THEME_ISO/theme.txt" >/dev/null; then
	ok "les deux theme.txt sont identiques — une seule vérité, deux copies"
else
	non "les deux theme.txt divergent : l'ISO et le système installé ne montreraient pas la même chose"
fi

# -----------------------------------------------------------------------------
titre "2. La zone terminal est peinte : « terminal-box » dans LES DEUX theme.txt"
#  ═══ ON LIT LA CLÉ, PAS LE MOT ═══
#  Le commentaire de theme.txt raconte le bogue et cite « terminal-box » : un
#  grep nu serait vert sur l'explication seule. On exige la clé en tête de
#  ligne, suivie de deux-points — la forme que GRUB analyse.
for D in "$THEME_SYS" "$THEME_ISO"; do
	NOM="${D##*/config/}"
	MOTIF="$(sed -n 's/^terminal-box:[[:space:]]*"\([^"]*\)".*/\1/p' "$D/theme.txt")"
	if [[ -z "$MOTIF" ]]; then
		non "$NOM : aucune clé « terminal-box: » — la zone terminal laisserait voir le fond"
		continue
	fi
	ok "$NOM : terminal-box: \"$MOTIF\""
	#  Le motif doit désigner des fichiers qui EXISTENT, les neuf tranches.
	PREFIXE="${MOTIF%\*.png}"
	MANQUE=""
	for T in c n s e w ne nw se sw; do
		[[ -r "$D/${PREFIXE}${T}.png" ]] || MANQUE="$MANQUE ${PREFIXE}${T}.png"
	done
	if [[ -z "$MANQUE" ]]; then
		ok "$NOM : les neuf tranches existent (centre, quatre bords, quatre coins)"
	else
		non "$NOM : tranches manquantes :$MANQUE"
	fi
done

#  ═══ ET ELLES SONT NOIRES, OPAQUES — MESURÉ PIXEL PAR PIXEL ═══
#  Une tranche transparente laisserait passer le fond ; une tranche d'une
#  autre couleur remplacerait le bleu par autre chose. Le noir plein, opaque,
#  est le seul résultat qui répond à « du noir, et rien que LEXOS ».
if python3 -c 'import PIL' 2>/dev/null; then
	VERDICT="$(python3 - "$THEME_SYS" "$THEME_ISO" <<'PY'
import sys, glob
from PIL import Image
bad = 0; n = 0
for d in sys.argv[1:]:
    for f in sorted(glob.glob(d + "/terminal_box_*.png")):
        im = Image.open(f).convert("RGBA")
        n += 1
        #  getcolors() plutôt que getdata() : le second est déprécié par
        #  Pillow 11 et fait crier un avertissement au milieu du banc.
        for _, p in (im.getcolors(maxcolors=1 << 20) or []):
            if p != (0, 0, 0, 255):
                print("NON " + f.split("/config/")[-1] + " contient " + str(p))
                bad += 1
                break
print("FIN", n, bad)
PY
)"
	N="$(printf '%s\n' "$VERDICT" | awk '/^FIN/{print $2}')"; B="$(printf '%s\n' "$VERDICT" | awk '/^FIN/{print $3}')"
	if [[ "${N:-0}" -ge 18 && "${B:-1}" -eq 0 ]]; then
		ok "les $N tranches sont du noir plein et opaque (0,0,0,255) — rien ne transparaît"
	else
		non "des tranches ne sont pas du noir opaque :"
		printf '%s\n' "$VERDICT" | grep '^NON' | sed 's/^NON /      /' >&2
	fi
else
	printf '  \033[2mPIL absent : la couleur des tranches n'"'"'a pas été mesurée\033[0m\n'
fi

# -----------------------------------------------------------------------------
titre "3. lexos.cfg coupe l'image de desktop-base"
#  ═══ LA VALEUR EXACTE COMPTE ═══
#  05_debian_theme regarde si GRUB_BACKGROUND est DÉFINI (« ${GRUB_BACKGROUND+x} »),
#  pas s'il est plein : défini et vide, il n'essaie rien d'autre. Ne pas
#  définir la variable — ou la retirer « parce qu'elle est vide » — rend la
#  main à desktop-base, et le bleu revient.
if grep -qE '^GRUB_BACKGROUND=""$' "$HOOK"; then
	ok "le hook 0100 écrit GRUB_BACKGROUND=\"\" dans lexos.cfg — défini, et vide"
else
	non "GRUB_BACKGROUND=\"\" manque dans le heredoc de lexos.cfg (hook 0100)"
fi
if grep -q 'GRUB_GFXPAYLOAD_LINUX=keep' "$HOOK"; then
	ok "GRUB_GFXPAYLOAD_LINUX=keep est toujours là — pas de passage par le mode texte"
else
	non "GRUB_GFXPAYLOAD_LINUX=keep a disparu : l'écran clignoterait entre deux résolutions"
fi

# -----------------------------------------------------------------------------
titre "4. Le VRAI 05_debian_theme est joué — avec et sans desktop-base"
#  ═══ ON JOUE LE SCRIPT DE DEBIAN, ON NE LE RELIT PAS ═══
#  Copie de travail où seuls les chemins absolus sont détournés vers un bac à
#  sable (/boot/grub, le fichier de desktop-base, l'image de repli, et
#  grub-mkconfig_lib, remplacé par trois aides qui ne demandent pas de
#  disque). Le script sous essai n'est pas celui de Debian — c'est l'EFFET de
#  notre réglage sur lui. Le témoin (desktop-base présent, GRUB_BACKGROUND
#  non défini) DOIT produire « background_image » : c'est la preuve que le
#  harnais voit le bleu quand il est là. Sans ce témoin, un banc qui ne
#  trouve jamais d'image ne prouverait que sa propre cécité — c'est
#  arrivé trois fois en l'écrivant (grub-probe sans disque, png.mod absent,
#  GRUB_TERMINAL_OUTPUT vide).
SCRIPT_DEB=/etc/grub.d/05_debian_theme
if [[ ! -r "$SCRIPT_DEB" ]]; then
	printf '  \033[2m%s absent de cette machine : le script de Debian n'"'"'a pas été joué\033[0m\n' "$SCRIPT_DEB"
else
	mkdir -p "$BANC/boot/x86_64-efi" "$BANC/db"
	: > "$BANC/boot/x86_64-efi/png.mod"
	cat > "$BANC/lib" <<'EOF'
grub_probe=/bin/true
is_path_readable_by_grub() { [ -f "$1" ]; }
prepare_grub_to_access_device() { :; }
make_system_path_relative_to_its_root() { printf '%s' "$1"; }
EOF
	#  Une « vague » : un PNG quelconque suffit, le script ne le regarde pas.
	printf '\x89PNG\r\n\x1a\n' > "$BANC/db/vagues.png"
	printf 'WALLPAPER="%s"\nCOLOR_NORMAL="white/black"\nCOLOR_HIGHLIGHT="black/white"\n' \
		"$BANC/db/vagues.png" > "$BANC/db/grub_background.sh"
	sed -e "s|/boot/grub|$BANC/boot|g" \
	    -e "s|/usr/share/desktop-base/grub_background.sh|$BANC/db/grub_background.sh|" \
	    -e "s|/usr/share/images/desktop-base/desktop-grub.png|$BANC/db/desktop-grub.png|" \
	    -e "s|^\. /usr/share/grub/grub-mkconfig_lib|. $BANC/lib|" \
	    "$SCRIPT_DEB" > "$BANC/05"
	sed "s|$BANC/db/grub_background.sh|$BANC/db/absent.sh|" "$BANC/05" > "$BANC/05-sans"

	joue() { # joue <script> [GRUB_BACKGROUND=…]
		local s="$1"; shift
		env -i PATH="$PATH" GRUB_DISTRIBUTOR=LexOS GRUB_TERMINAL_OUTPUT=gfxterm "$@" sh "$s" 2>/dev/null
	}
	#  Le témoin.
	if grep -q 'background_image' < <(joue "$BANC/05"); then
		ok "témoin : desktop-base présent, sans notre réglage → background_image (le harnais VOIT le bleu)"
	else
		non "témoin : le harnais ne voit pas le bleu même quand il est là — les trois contrôles suivants ne prouveraient rien"
	fi
	#  Notre réglage, tel que lexos.cfg le pose : défini et vide.
	if grep -q 'background_image' < <(joue "$BANC/05" GRUB_BACKGROUND=); then
		non "desktop-base présent, GRUB_BACKGROUND=\"\" → background_image quand même : le bleu reste"
	else
		ok "desktop-base présent, GRUB_BACKGROUND=\"\" → aucune image de fond"
	fi
	#  Sans desktop-base du tout — le repli ne doit jamais rouvrir sur du bleu.
	if grep -q 'background_image' < <(joue "$BANC/05-sans" GRUB_BACKGROUND=); then
		non "sans desktop-base, GRUB_BACKGROUND=\"\" → une image de fond sort d'on ne sait où"
	else
		ok "sans desktop-base, GRUB_BACKGROUND=\"\" → aucune image de fond"
	fi
	if grep -q 'background_image' < <(joue "$BANC/05-sans"); then
		non "sans desktop-base et sans réglage → une image de fond (le repli desktop-grub.png ?)"
	else
		ok "sans desktop-base et sans réglage → aucune image non plus (le repli reste noir)"
	fi
fi

printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
