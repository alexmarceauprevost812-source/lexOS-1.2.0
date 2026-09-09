#!/usr/bin/env bash
# =============================================================================
#  La page « Formater un support » — la page demande, lexos-format décide
# =============================================================================
#  ALEX voulait une vraie page plutôt que la suite de boîtes zenity. Le gain
#  est double : une page se remet en forme toute seule (aucune hauteur en
#  pixels ne peut plus cacher la troisième option, quelle que soit l'écriture
#  choisie), et la liste des supports vient enfin d'un seul endroit.
#
#  ═══ CE QUE CE BANC PROTÈGE, ET POURQUOI CHAQUE POINT COMPTE ═══
#
#  1. UN SEUL JUGE. La page n'a le droit de rien décider. Elle affiche ce que
#     lexos-format ACCEPTERAIT (« --json »), et le moteur refuse tout ce qui
#     n'est pas dans cette liste. Deux juges finissent par ne plus dire la
#     même chose, et ce jour-là c'est un disque qui y passe.
#
#  2. LE DISQUE SYSTÈME N'APPARAÎT JAMAIS — ni celui qui porte /home, /boot,
#     /usr ou /var. Avant ce chantier, la liste ne testait QUE « amovible » et
#     « pas le disque racine » : un disque amovible portant /home serait
#     apparu, pour être refusé au dernier moment.
#
#  3. RIEN N'EST PRÉSÉLECTIONNÉ. Sur un écran qui efface des disques, un
#     choix par défaut est un accident qui attend.
#
#  4. LA CONFIRMATION SE TAPE. Un clic ne suffit pas : il faut recopier le
#     nom du support. Même doctrine que lexos-install et que le mode terminal.
#
#  5. SANS AGENT POLKIT, ON LE DIT — avant le clic, pas après. Le dépôt a
#     déjà payé ce silence : « les boutons dans les paramètres ne
#     fonctionnaient pas », parce que pkexec ne dessine pas lui-même la
#     fenêtre du mot de passe et échoue sans rien afficher s'il n'y a pas
#     d'agent dans la session.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMAT="$RACINE/config/includes.chroot/usr/bin/lexos-format"
SET_PY="$RACINE/config/includes.chroot/usr/lib/lexos"
APPJS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
REGLE="$RACINE/config/includes.chroot/etc/polkit-1/rules.d/49-lexos-format.rules"
HOOK400="$RACINE/config/hooks/normal/0400-lexos-desktop.hook.chroot"
BANC="$(mktemp -d)"
BOUCLE=""
nettoyer() { [ -n "$BOUCLE" ] && losetup -d "$BOUCLE" 2>/dev/null; rm -rf "$BANC"; }
trap nettoyer EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$FORMAT" "$APPJS" "$REGLE" "$HOOK400" "$SET_PY/settings.py"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

#  ═══ LE DÉCOR : QUATRE DISQUES, ET UN SEUL EST FORMATABLE ═══
#    sda      disque système (RM=0, porte /)
#    sdb      clé USB (RM=1)               <- le seul éligible
#    sdc      disque externe (RM=1) qui porte /home
#    sdd      disque interne (RM=0)
mkdir -p "$BANC/bin"
cat > "$BANC/bin/lsblk" <<'SH'
#!/bin/sh
a="$*"
case "$a" in
  *"-dno NAME,RM"*) printf 'sda 0\nsdb 1\nsdc 1\nsdd 0\n'; exit 0 ;;
  *"-no PKNAME"*)
     case "$a" in *sda1*) echo sda;; *sdc1*) echo sdc;; *) echo "";; esac; exit 0 ;;
  *"-dno RM"*) case "$a" in *sdb*|*sdc*) echo 1;; *) echo 0;; esac; exit 0 ;;
  *"-dno SIZE"*) case "$a" in *sdb*) echo "57,3G";; *sdc*) echo "931,5G";; *) echo "476,9G";; esac; exit 0 ;;
  *"-dno MODEL"*) case "$a" in *sdb*) echo "SanDisk Ultra";; *sdc*) echo "Seagate";; *) echo "Samsung";; esac; exit 0 ;;
  *"-no LABEL"*) case "$a" in *sdb*) printf 'PHOTOS "Alex"\n';; *) printf '\n';; esac; exit 0 ;;
  *"-no MOUNTPOINT"*) case "$a" in *sdb*) printf '/media/alex/PHOTOS\n';; *sdc*) printf '/home\n';; *) printf '\n';; esac; exit 0 ;;
  *"-no NAME,SIZE,LABEL,MOUNTPOINT"*) printf 'sdb 57,3G PHOTOS /media/alex/PHOTOS\n'; exit 0 ;;
esac
exit 0
SH
cat > "$BANC/bin/findmnt" <<'SH'
#!/bin/sh
case "$*" in
  *"SOURCE /home"*) echo /dev/sdc1; exit 0 ;;
  *"-no SOURCE /"*) echo /dev/sda1; exit 0 ;;
esac
exit 1
SH
chmod +x "$BANC/bin"/*
LISTE="$(PATH="$BANC/bin:$PATH" LEXOS_SANS_SBIN=1 bash "$FORMAT" --json 2>/dev/null)"

# =============================================================================
titre "1. LA LISTE : un seul juge, et le disque système n'y est jamais"
# =============================================================================
if [ -z "$LISTE" ]; then
	non "« lexos-format --json » n'a rien rendu : rien de ce qui suit ne prouve quoi que ce soit"
else
	if python3 -c 'import json,sys; json.load(sys.stdin)' <<< "$LISTE" 2>/dev/null; then
		ok "« --json » rend du JSON valide, même avec une étiquette qui porte des guillemets"
	else
		non "« --json » rend du JSON invalide — la page resterait blanche, sans message"
	fi
	NOMS="$(python3 -c '
import json,sys
d=json.load(sys.stdin)
print(" ".join(s["nom"] for s in d.get("supports",[])))' <<< "$LISTE" 2>/dev/null)"
	[ "$NOMS" = "sdb" ] \
		&& ok "seule la clé USB est proposée (« $NOMS »)" \
		|| non "la liste propose « $NOMS » au lieu de la seule clé « sdb »"
	grep -q 'sda' <<< "$NOMS" \
		&& non "LE DISQUE SYSTÈME EST DANS LA LISTE" \
		|| ok "le disque système n'y est pas"
	grep -q 'sdc' <<< "$NOMS" \
		&& non "le disque amovible qui porte /home est dans la liste" \
		|| ok "…ni le disque amovible qui porte /home"
	SYS="$(python3 -c '
import json,sys
d=json.load(sys.stdin)
print(" ".join(s["cle"] for s in d.get("systemes",[])))' <<< "$LISTE" 2>/dev/null)"
	[ "$SYS" = "vfat exfat ext4" ] \
		&& ok "les trois systèmes de fichiers sont là, dans l'ordre (« $SYS »)" \
		|| non "les systèmes de fichiers rendus sont « $SYS »"
fi

# =============================================================================
titre "2. LE MODE NON INTERACTIF REFUSE UNE CIBLE NON AMOVIBLE"
# =============================================================================
#  On lui donne un VRAI périphérique bloc — une boucle losetup — que le faux
#  lsblk déclare NON amovible. Sans un vrai bloc, le programme sortirait bien
#  avant le contrôle qui nous intéresse, et le banc serait vert pour la
#  mauvaise raison.
if ! command -v losetup >/dev/null 2>&1; then
	saute "losetup absent : le refus d'une cible non amovible n'a PAS été éprouvé"
else
	dd if=/dev/zero of="$BANC/d.img" bs=1M count=8 status=none 2>/dev/null
	BOUCLE="$(losetup -f --show "$BANC/d.img" 2>/dev/null)"
	if [ -z "$BOUCLE" ]; then
		saute "aucune boucle libre : le refus d'une cible non amovible n'a PAS été éprouvé"
	else
		N="$(basename "$BOUCLE")"
		cat > "$BANC/bin/lsblk" <<SH
#!/bin/sh
a="\$*"
case "\$a" in
  *"-dno NAME,RM"*) printf '$N %s\n' "\${FAUX_RM:-0}"; exit 0 ;;
  *"-no PKNAME"*) echo ""; exit 0 ;;
  *"-dno RM"*) echo "\${FAUX_RM:-0}"; exit 0 ;;
  *"-dno SIZE"*) echo "8M"; exit 0 ;;
  *"-dno MODEL"*) echo "essai"; exit 0 ;;
  *"-no LABEL"*|*"-no MOUNTPOINT"*) printf '\n'; exit 0 ;;
  *"-no NAME,SIZE,LABEL,MOUNTPOINT"*) printf '$N 8M - -\n'; exit 0 ;;
esac
exit 0
SH
		printf '#!/bin/sh\nexit 1\n' > "$BANC/bin/findmnt"
		for T in mkfs.vfat mkfs.ext4 mkfs.exfat parted wipefs udevadm; do
			printf '#!/bin/sh\nexit 0\n' > "$BANC/bin/$T"
		done
		chmod +x "$BANC/bin"/*
		SORTIE="$(PATH="$BANC/bin:$PATH" LEXOS_SANS_SBIN=1 NO_COLOR=1 FAUX_RM=0 \
			timeout 30 bash "$FORMAT" "$BOUCLE" --fs=vfat --confirme </dev/null 2>&1)"
		if grep -q "n'est pas un support amovible" <<< "$SORTIE"; then
			ok "une cible NON amovible est refusée même avec « --confirme », et pour la bonne raison"
		else
			non "cible non amovible : réponse inattendue — $(tail -1 <<< "$SORTIE")"
		fi
		#  ET LE CONTRAIRE : sans ce contrôle, un refus qui tomberait pour
		#  n'importe quelle raison (nom rogné, outil absent) passerait pour
		#  une réussite du précédent.
		SORTIE2="$(PATH="$BANC/bin:$PATH" LEXOS_SANS_SBIN=1 NO_COLOR=1 FAUX_RM=1 \
			timeout 30 bash "$FORMAT" "$BOUCLE" --fs=vfat --confirme </dev/null 2>&1)"
		if grep -q "n'est pas un support amovible" <<< "$SORTIE2"; then
			non "le même support DÉCLARÉ amovible est refusé aussi : le contrôle précédent ne prouvait rien"
		else
			ok "…et déclaré amovible, il passe le contrôle — c'est bien « amovible » qui décide"
		fi
		#  Le nom du périphérique n'est pas rogné en chemin (mmcblk0 -> mmcblk).
		grep -q "/dev/$N" <<< "$SORTIE" \
			&& ok "le nom du périphérique est repris entier (« $N »), pas rogné" \
			|| non "le nom du périphérique a été rogné : $(head -1 <<< "$SORTIE")"
	fi
fi

# =============================================================================
titre "3. LE MOTEUR NE PREND PAS LA PAGE AU MOT"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le moteur des Paramètres n'a PAS été éprouvé"
else
	mkdir -p "$BANC/faux"
	cat > "$BANC/faux/lexos-format" <<'SH'
#!/bin/sh
[ "$1" = "--json" ] && { printf '{"supports":[{"nom":"sdb","chemin":"/dev/sdb","taille":"57,3G","modele":"SanDisk","etiquette":"","montages":""}],"systemes":[{"cle":"vfat","titre":"FAT32","texte":"x"},{"cle":"exfat","titre":"exFAT","texte":"x"},{"cle":"ext4","titre":"ext4","texte":"x"}]}\n'; exit 0; }
echo "LANCE $*"; exit 0
SH
	#  « pgrep » qui ne trouve rien : aucun agent d'authentification.
	printf '#!/bin/sh\nexit 1\n' > "$BANC/faux/pgrep"
	chmod +x "$BANC/faux"/*
	SORTIE="$(cd "$RACINE" && PATH="$BANC/faux:$PATH" python3 - "$SET_PY" <<'PY' 2>/dev/null
import sys
sys.path.insert(0, sys.argv[1])
import settings
#  On se fait passer pour un compte ORDINAIRE : c'est le cas d'Alex, et le
#  seul où l'agent polkit compte. En root, tout passe et le banc ne verrait
#  rien.
settings.os.geteuid = lambda: 1000
settings.os.getuid = lambda: 1000
def dit(bon, m): print(("OK|" if bon else "NON|") + m)

r = settings.act_formatage("liste")
dit(r.get("ok") is True, "la page reçoit la liste")
dit(len(r.get("supports", [])) == 1, "…avec le seul support éligible")
dit(len(r.get("systemes", [])) == 3, "…et les trois systèmes de fichiers")
dit(r.get("agent") is False,
    "l'absence d'agent polkit voyage AVEC la liste — la page peut le dire avant le clic")

r = settings.act_formatage("lancer:/dev/sda:vfat")
dit(r.get("ok") is False and "liste" in (r.get("erreur") or ""),
    "une cible absente de la liste est refusée, avec un motif")
r = settings.act_formatage("lancer:/dev/sdb:ntfs")
dit(r.get("ok") is False and "ntfs" in (r.get("erreur") or ""),
    "un système de fichiers inconnu est refusé, avec un motif")
r = settings.act_formatage("lancer:/dev/sdb:vfat")
dit(r.get("ok") is False and "agent polkit" in (r.get("erreur") or ""),
    "sans agent polkit : un MOTIF, pas un silence")
dit("nimporte" not in str(settings.act_formatage("nimportequoi")),
    "une valeur inattendue est refusée sans être renvoyée telle quelle")
print("FIN|")
PY
)"
	grep -q '^FIN|' <<< "$SORTIE" || non "le moteur n'est pas allé au bout"
	while IFS='|' read -r V M; do
		case "$V" in OK) ok "$M" ;; NON) non "$M" ;; esac
	done <<< "$SORTIE"
fi

# =============================================================================
titre "4. LA PAGE : rien de présélectionné, et la confirmation se tape"
# =============================================================================
JS_NU="$BANC/app.nu.js"
sed -e 's#^\s*//.*##' "$APPJS" > "$JS_NU"

grep -qE 'choisi:\s*null' "$JS_NU" && grep -qE 'fs:\s*null' "$JS_NU" \
	&& ok "au départ, aucun support et aucun format ne sont choisis" \
	|| non "l'état de départ présélectionne quelque chose"

#  La confirmation compare la saisie au NOM du support. Sans cette
#  comparaison, le bouton serait actif d'emblée.
if grep -qE 'fmt\.saisie\.trim\(\)\s*===\s*s\.nom' "$JS_NU"; then
	ok "le bouton n'est actif que si le nom du support est recopié exactement"
else
	non "la confirmation ne compare plus la saisie au nom du support"
fi

grep -q 'fmt.systemes.map' "$JS_NU" \
	&& ok "les systèmes de fichiers affichés viennent de l'outil, pas d'une liste recopiée dans la page" \
	|| non "la page réécrit sa propre liste de systèmes de fichiers"

grep -q '\["formatage"' "$JS_NU" \
	&& ok "la section « Formater un support » est dans le menu de gauche" \
	|| non "la page n'est atteignable par aucun menu"

grep -q "allerA('formatage')" "$JS_NU" \
	&& ok "le bouton « ⚠ Formater… » de la page USB mène à la page, plus à un terminal" \
	|| non "le bouton « Formater… » ne mène pas à la nouvelle page"

#  Et la page NE REFAIT PAS le tri : aucune mention des disques système ni de
#  « removable » côté JavaScript. Un deuxième juge se reconnaît à ça.
if grep -qiE 'ROOT_DISK|/dev/sda|is_?removable|amovible\s*\?' "$JS_NU"; then
	non "la page a l'air de juger elle-même ce qui est formatable — un deuxième juge"
else
	ok "la page ne juge rien : elle affiche ce que lexos-format lui donne"
fi

# =============================================================================
titre "5. LES DROITS : une règle étroite, et pas de silence"
# =============================================================================
grep -q 'org.freedesktop.policykit.exec' "$REGLE" \
	&& ok "la règle polkit vise l'action de pkexec" \
	|| non "la règle polkit ne vise pas l'action de pkexec"
grep -q '"/usr/bin/lexos-format"' "$REGLE" \
	&& ok "…et le chemin COMPLET du seul programme concerné" \
	|| non "la règle ne nomme pas exactement /usr/bin/lexos-format"
grep -q 'subject.active' "$REGLE" && grep -q 'subject.local' "$REGLE" \
	&& ok "…pour une session ACTIVE et LOCALE seulement (une session SSH ne gagne rien)" \
	|| non "la règle ne se restreint pas aux sessions actives et locales"
#  ON DÉCOMMENTE D'ABORD. Ce contrôle est né rouge : l'en-tête de la règle
#  EXPLIQUE pourquoi on n'emploie pas « polkit.Result.YES », et le grep
#  tombait sur son propre commentaire d'explication. C'est le piège le plus
#  fréquent de ce dépôt — « le contrôle lit la prose ».
REGLE_NU="$BANC/regle.nu"
sed -e 's#//.*##' "$REGLE" > "$REGLE_NU"
grep -q 'polkit.Result.YES' "$REGLE_NU" \
	&& non "la règle accorde le formatage SANS mot de passe — décision d'Alex, pas la nôtre" \
	|| ok "le mot de passe reste demandé (AUTH_ADMIN_KEEP, pas YES)"

# =============================================================================
titre "6. LE CLIC DROIT ET LE LANCEUR MÈNENT À LA PAGE"
# =============================================================================
grep -q '<command>lexos-settings formatage</command>' "$HOOK400" \
	&& ok "le clic droit « Formater ce support… » de Thunar ouvre la page" \
	|| non "le clic droit de Thunar ne mène pas à la page"
grep -q '^Exec=lexos-settings formatage' "$HOOK400" \
	&& ok "le lanceur du menu aussi" \
	|| non "le lanceur du menu ne mène pas à la page"
#  ET LE CHEMIN TERMINAL N'A PAS DISPARU : sur une machine qu'on répare,
#  c'est souvent le seul.
#  On vise la BRANCHE du dispatcheur, pas une mention quelconque : sa ligne
#  d'aide contient déjà le mot « format », et un grep large resterait vert
#  même si la commande n'était plus câblée.
grep -qE '^[[:space:]]*format\)[[:space:]]+exec lexos-format' \
	"$RACINE/config/includes.chroot/usr/bin/lexos" \
	&& ok "« lexos format » reste branché dans le dispatcheur — le chemin sans bureau existe toujours" \
	|| non "« lexos format » a disparu du dispatcheur — plus de chemin sans bureau"

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
