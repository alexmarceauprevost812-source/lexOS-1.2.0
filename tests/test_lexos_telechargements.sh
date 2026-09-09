#!/usr/bin/env bash
# =============================================================================
#  Éprouver la veille des téléchargements — la brique du dessous
# =============================================================================
#  ═══ POURQUOI CE BANC ÉPROUVE LE CAS DIFFICILE EN PREMIER ═══
#  La consigne le demande, et elle a raison : le cas facile (taille connue)
#  marche presque tout seul. C'est le cas « taille inconnue » qui décide de la
#  qualité de la chose — parce que la tentation est d'inventer un pourcentage,
#  et qu'un anneau qui ment est pire qu'un anneau qui tourne sans fin.
#
#  ON NE LIT PAS LE CODE, ON FAIT DE VRAIS FICHIERS. Chaque cas est joué avec
#  de vraies écritures sur un vrai dossier surveillé par le vrai programme :
#  un fichier qui grossit sans qu'on sache où il va, un fichier PRÉALLOUÉ à sa
#  taille finale, un fichier effacé en cours de route, et deux à la fois.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/lib/lexos/telechargements.py"
BANC="$(mktemp -d)"
nettoyer() { pkill -f 'lexos/telechargements.py' 2>/dev/null; rm -rf "$BANC"; return 0; }
trap nettoyer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut() { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[ -r "$OUTIL" ] || { echo "telechargements.py introuvable"; exit 1; }

# --- L'interpréteur qui a vraiment python3-gi -------------------------------
#  ═══ ON CHERCHE, ON NE SUPPOSE PAS ═══
#  Sur cette machine de développement, /usr/bin/python3 est en 3.11 alors que
#  le module « gi » est compilé pour 3.12 : « import gi » échoue. Ce n'est pas
#  un défaut de LexOS (sur l'ISO les deux vont ensemble), mais un banc qui
#  s'arrêterait là ne prouverait rien. On prend donc le premier interpréteur
#  qui sait vraiment importer Gio.
PY=""
for C in python3 python3.12 python3.11 python3.13 python3.10; do
	command -v "$C" >/dev/null 2>&1 || continue
	if "$C" -c 'import gi; gi.require_version("Gio","2.0"); from gi.repository import Gio' 2>/dev/null; then
		PY="$C"; break
	fi
done
if [ -z "$PY" ]; then
	saut "aucun python avec python3-gi : la veille n'est pas éprouvée"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
	[ "$ECHOUES" -eq 0 ]
	exit
fi

#  Lance la veille sur un dossier neuf et rend le chemin du journal.
veiller() { # veiller <duree>
	rm -rf "${BANC:?}/dl" "$BANC/journal"
	mkdir -p "$BANC/dl"
	LEXOS_DL_DIR="$BANC/dl" LEXOS_DL_PAS_MS=120 LEXOS_DL_ABANDON=3 \
		timeout "$1" "$PY" "$OUTIL" > "$BANC/journal" 2>"$BANC/erreurs" &
	#  Le PID n'est pas relu : « timeout » borne la veille et le piège de
	#  sortie la tue de toute façon. On ne le garde pas pour rien.
	disown 2>/dev/null || true
	#  On attend que la veille DISE qu'elle veille : dormir un temps fixe
	#  ferait un banc qui rougit au hasard sur une machine chargée.
	for _ in $(seq 1 100); do
		grep -q '"veille"' "$BANC/journal" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}
#  Extrait les champs d'un événement, en JSON — pas au grep : « total: null »
#  et « total: 0 » se ressemblent trop pour être distingués à l'œil.
champs() { # champs <ev> <champ>
	"$PY" - "$BANC/journal" "$1" "$2" <<'PYC' 2>/dev/null
import json, sys
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    l = l.strip()
    if not l:
        continue
    try:
        e = json.loads(l)
    except ValueError:
        continue
    if e.get("ev") == sys.argv[2]:
        print(json.dumps(e.get(sys.argv[3])))
PYC
}

# =============================================================================
titre "1. TAILLE INCONNUE — on n'invente jamais de pourcentage"
# =============================================================================
if ! veiller 8; then
	non "la veille n'a pas démarré : $(head -2 "$BANC/erreurs")"
else
	( for _ in $(seq 1 8); do
		dd if=/dev/zero bs=64k count=1 >> "$BANC/dl/film.mkv.part" 2>/dev/null
		sleep 0.25
	  done
	  mv "$BANC/dl/film.mkv.part" "$BANC/dl/film.mkv" ) >/dev/null 2>&1
	sleep 1.5

	if [ -n "$(champs debut nom)" ]; then
		ok "le début du téléchargement est vu"
	else
		non "aucun « debut » : la veille n'a pas repéré le fichier"
	fi
	#  LE CONTRÔLE QUI COMPTE : pas un seul pourcentage inventé.
	PC="$(champs avance pourcent | sort -u | tr '\n' ' ')"
	if [ "$(echo "$PC" | tr -d ' ')" = "null" ]; then
		ok "taille inconnue : « pourcent » vaut null partout — aucun chiffre inventé"
	else
		non "un pourcentage a été inventé alors que la taille est inconnue : $PC"
	fi
	TOT="$(champs avance total | sort -u | tr -d '\n ')"
	[ "$TOT" = "null" ] \
		&& ok "…et « total » reste null : rien n'est deviné" \
		|| non "« total » vaut « $TOT » alors que rien ne l'annonce"
	#  Les octets reçus doivent MONTER : c'est ce qu'on affiche à la place.
	RECUS="$(champs avance recu | tr -d '"')"
	PREM="$(echo "$RECUS" | head -1)"; DERN="$(echo "$RECUS" | tail -1)"
	if [ -n "$PREM" ] && [ -n "$DERN" ] && [ "$DERN" -gt "$PREM" ]; then
		ok "les octets reçus montent ($PREM -> $DERN) : c'est ce qu'on montre à la place"
	else
		non "les octets reçus ne montent pas ($PREM -> $DERN)"
	fi
	#  Le renommage vers le nom final EST la fin.
	if [ "$(champs fini nom | tr -d '"')" = "film.mkv" ]; then
		ok "le renommage vers le nom final est vu comme la fin"
	else
		non "la fin n'a pas été vue (le renommage doit la signaler)"
	fi
fi

# =============================================================================
titre "2. TAILLE CONNUE — un fichier préalloué donne un vrai pourcentage"
# =============================================================================
#  Le seul cas où la taille finale est CONNUE sans que personne ne l'annonce :
#  le navigateur réserve le fichier à sa taille finale. st_size ne bouge plus,
#  et les blocs réellement écrits montent. C'est mesurable, et c'est mesuré.
if ! veiller 8; then
	non "la veille n'a pas démarré (cas préalloué)"
else
	truncate -s 4194304 "$BANC/dl/iso.img.crdownload"
	for i in $(seq 1 6); do
		dd if=/dev/urandom of="$BANC/dl/iso.img.crdownload" bs=512k count=1 \
			seek=$((i-1)) conv=notrunc 2>/dev/null
		sleep 0.3
	done
	mv "$BANC/dl/iso.img.crdownload" "$BANC/dl/iso.img"
	sleep 1.2

	TOT="$(champs avance total | sort -u | grep -v null | head -1)"
	if [ "$TOT" = "4194304" ]; then
		ok "la taille finale est reconnue (4194304) sans que personne ne l'annonce"
	else
		non "taille finale non reconnue : « $TOT »"
	fi
	PC="$(champs avance pourcent | grep -v null | tr -d '"')"
	if [ -n "$PC" ]; then
		ok "…et un vrai pourcentage est calculé ($(echo "$PC" | head -1) % au début)"
	else
		non "aucun pourcentage alors que la taille est connue"
	fi
	#  ═══ LE POURCENTAGE NE RECULE JAMAIS ═══
	#  Défaut vécu : avant correction, la toute première mesure annonçait la
	#  taille RÉSERVÉE comme « reçue » — la pastille montrait 4 Mo puis
	#  retombait à 12,5 %. Un indicateur qui recule est pire qu'un indicateur
	#  lent : on croit que le téléchargement a raté.
	RECULE="$("$PY" - "$BANC/journal" <<'PYC'
import json, sys
prec = {}
recule = 0
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        e = json.loads(l)
    except ValueError:
        continue
    if e.get("ev") != "avance":
        continue
    i = e.get("id")
    r = e.get("recu") or 0
    if i in prec and r < prec[i]:
        recule += 1
    prec[i] = r
print(recule)
PYC
)"
	[ "$RECULE" = "0" ] \
		&& ok "les octets reçus ne reculent jamais" \
		|| non "$RECULE recul(s) dans les octets reçus : la pastille reculerait"
fi

# =============================================================================
titre "3. ANNULÉ EN COURS DE ROUTE"
# =============================================================================
if ! veiller 7; then
	non "la veille n'a pas démarré (cas annulé)"
else
	dd if=/dev/zero bs=256k count=1 of="$BANC/dl/gros.zip.part" 2>/dev/null
	sleep 0.8
	rm -f "$BANC/dl/gros.zip.part"
	sleep 1.2
	if [ "$(champs annule nom | tr -d '"')" = "gros.zip" ]; then
		ok "le fichier effacé en cours de route est annoncé « annule »"
	else
		non "l'annulation n'a pas été vue"
	fi
	if [ -z "$(champs fini nom)" ]; then
		ok "…et surtout pas « fini » : un téléchargement annulé n'est pas terminé"
	else
		non "un téléchargement annulé a été annoncé comme terminé"
	fi
fi

# =============================================================================
titre "4. DEUX TÉLÉCHARGEMENTS EN MÊME TEMPS"
# =============================================================================
if ! veiller 8; then
	non "la veille n'a pas démarré (cas double)"
else
	( for _ in $(seq 1 7); do dd if=/dev/zero bs=64k count=1 >> "$BANC/dl/a.iso.part" 2>/dev/null; sleep 0.25; done
	  mv "$BANC/dl/a.iso.part" "$BANC/dl/a.iso" ) >/dev/null 2>&1 &
	( sleep 0.4
	  for _ in $(seq 1 6); do dd if=/dev/zero bs=32k count=1 >> "$BANC/dl/b.pdf.part" 2>/dev/null; sleep 0.25; done
	  mv "$BANC/dl/b.pdf.part" "$BANC/dl/b.pdf" ) >/dev/null 2>&1 &
	wait
	sleep 1.2

	NOMS="$(champs debut nom | tr -d '"' | sort -u | tr '\n' ' ')"
	if grep -q 'a.iso' <<< "$NOMS" && grep -q 'b.pdf' <<< "$NOMS"; then
		ok "les deux téléchargements sont vus : $NOMS"
	else
		non "les deux ne sont pas vus : « $NOMS »"
	fi
	#  Chacun doit avoir SON identifiant : sans ça la pastille mélangerait
	#  les deux avancements dans un seul anneau.
	IDS="$(champs debut id | sort -u | wc -l)"
	[ "$IDS" -ge 2 ] \
		&& ok "…et chacun a son propre identifiant ($IDS)" \
		|| non "les deux partagent un identifiant : leurs avancements se mélangeraient"
	FINIS="$(champs fini nom | tr -d '"' | sort -u | wc -l)"
	[ "$FINIS" -ge 2 ] \
		&& ok "…et les deux fins sont annoncées séparément" \
		|| non "seulement $FINIS fin(s) annoncée(s) sur 2"
fi

# =============================================================================
titre "5. CE QU'ELLE NE FAIT PAS"
# =============================================================================
#  Un fichier caché n'est jamais un téléchargement visible : les navigateurs
#  et les éditeurs en sèment, et une pastille pour chacun serait insupportable.
if ! veiller 5; then
	non "la veille n'a pas démarré (cas fichiers cachés)"
else
	dd if=/dev/zero bs=64k count=1 of="$BANC/dl/.cache-truc" 2>/dev/null
	sleep 1.2
	if [ -z "$(champs debut nom)" ]; then
		ok "un fichier caché ne déclenche aucune pastille"
	else
		non "un fichier caché a déclenché un téléchargement"
	fi
fi

#  Aucune dépendance nouvelle : c'est la promesse de la consigne.
#  ═══ ON RETIRE LES COMMENTAIRES AVANT DE CHERCHER ═══
#  Premier jet : un grep sur le fichier entier. Rouge — et à tort : le
#  commentaire du programme EXPLIQUE pourquoi on n'utilise pas inotify, et le
#  mot y est. Le contrôle lisait la prose au lieu du code. C'est la même
#  faute que ce dépôt a déjà corrigée ailleurs ; elle revient dès qu'on
#  cherche un mot plutôt qu'un appel.
CODE_NU="$BANC/telechargements-sans-commentaires.py"
sed 's/#.*$//' "$OUTIL" > "$CODE_NU"
if grep -qE '(^|[^A-Za-z_])(inotifywait|pyinotify)' "$CODE_NU"; then
	non "la veille appelle un outil inotify : c'est une dépendance en plus"
else
	ok "aucune dépendance nouvelle : Gio.FileMonitor, déjà fourni par python3-gi"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
