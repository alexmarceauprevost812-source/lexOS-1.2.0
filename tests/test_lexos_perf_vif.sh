#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — le profil « vif » et l'arrondi de la RAM
# =============================================================================
#  CE QU'IL GARDE, ET POURQUOI ÇA VAUT UN BANC.
#
#  1. L'ARRONDI DE LA RAM. detect_profile() tronquait au lieu d'arrondir :
#     MemTotal est toujours inférieur à la capacité annoncée (noyau, microcode,
#     mémoire réservée au GPU intégré), donc 8 Go rapportait 7,66 Gio → 7 →
#     « medium ». AUCUNE machine de 8 Go n'atteignait « performant ». C'est le
#     genre de bogue qui ne fait jamais planter personne et que personne ne
#     remarque : il faut donc une machine pour le remarquer à notre place.
#
#  2. LA COHÉRENCE DE « VIF ». Le profil ne vaut que si ses deux moitiés
#     tiennent ensemble — processeur à fond ET zéro fioriture. Un jour,
#     quelqu'un remettra P_COMPOSITING=1 « pour que ce soit plus joli » et le
#     profil ne servira plus à rien. Le banc refuse ce changement-là.
#
#  3. zram ET SWAPPINESS VONT ENSEMBLE. Poser zram sans monter la swappiness
#     laisse le noyau ignorer le swap compressé. C'est une erreur naturelle,
#     parce que « swappiness basse = bon » est le conseil qu'on lit partout —
#     conseil qui vise le swap sur DISQUE.
#
#  Aucun de ces contrôles n'exige un bureau graphique ni les droits root : on
#  lit le script, on ne l'exécute pas.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERF="$RACINE/config/includes.chroot/usr/bin/lexos-perf"
APPJS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
REGLAGES="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
POLKIT="$RACINE/config/includes.chroot/usr/share/polkit-1/actions/org.lexos.perf.policy"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0

ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

verifie() { # description, motif
	if grep -qE "$2" "$PERF"; then ok "$1"; else non "$1"; fi
}
refuse() { # description, motif qui ne doit PAS être là
	if grep -qE "$2" "$PERF"; then non "$1"; else ok "$1"; fi
}

# -----------------------------------------------------------------------------
titre "1. Le fichier est là et il se tient debout"
if [[ -r "$PERF" ]]; then ok "lexos-perf lisible"; else
	non "lexos-perf introuvable ($PERF)"; printf '\n'; exit 1
fi
if bash -n "$PERF" 2>/dev/null; then ok "syntaxe bash valide"
else non "erreur de syntaxe bash"; fi

# -----------------------------------------------------------------------------
titre "2. L'arrondi de la RAM"
refuse "la troncature 'ram_kb / 1024 / 1024' a disparu" \
       'ram_gb=\$\(\( *ram_kb */ *1024 */ *1024 *\)\)'
verifie "l'arrondi au demi-Gio est en place (524288)" \
        'ram_gb=\$\(\( *\( *ram_kb *\+ *524288 *\) */ *1048576 *\)\)'

#  On rejoue le calcul sur des tailles réelles plutôt que de croire le motif :
#  ce sont les VALEURS qui comptent, pas la forme de la ligne.
titre "3. Le calcul donne le bon palier sur du vrai matériel"
palier() { # kB -> Go arrondis
	printf '%s' "$(( ( $1 + 524288 ) / 1048576 ))"
}
for essai in "4008000:4:4 Go" "8039000:8:8 Go" "12210000:12:12 Go" \
             "16310000:16:16 Go" "32780000:31:32 Go"; do
	kb="${essai%%:*}"; reste="${essai#*:}"
	attendu="${reste%%:*}"; nom="${reste#*:}"
	obtenu="$(palier "$kb")"
	if [[ "$obtenu" == "$attendu" ]]; then
		ok "$nom → palier $obtenu"
	else
		non "$nom → $obtenu, attendu $attendu"
	fi
done

# -----------------------------------------------------------------------------
titre "4. Le profil « vif » existe partout où il doit"
verifie "reconnu par normalize()"        '\|vif\||vif\|'
verifie "un libellé dans label()"        'vif\).*printf'
verifie "un bloc dans load_profile()"    '^[[:space:]]*vif\)'

titre "5. « vif » tient ses deux promesses"
bloc="$(sed -n '/^[[:space:]]*vif)/,/;;/p' "$PERF")"
verifie_bloc() { # description, motif
	if grep -qE "$2" <<< "$bloc"; then ok "$1"; else non "$1"; fi
}
verifie_bloc "gouverneur 'performance'"          'P_GOVERNOR="performance"'
verifie_bloc "turbo débloqué (P_NO_TURBO=0)"     'P_NO_TURBO=0'
verifie_bloc "composition coupée"                'P_COMPOSITING=0'
verifie_bloc "effets CRT coupés"                 'P_CRT="off"'
verifie_bloc "zoom du dock coupé"                'P_DOCK_ZOOM=false'
verifie_bloc "vignettes coupées"                 'P_THUMBNAILS=0'

titre "6. zram et swappiness vont ensemble"
zram="$(grep -oE 'P_ZRAM=[0-9]+' <<< "$bloc" | head -1 | cut -d= -f2)"
swap="$(grep -oE 'P_SWAPPINESS=[0-9]+' <<< "$bloc" | head -1 | cut -d= -f2)"
if [[ -n "$zram" && "$zram" -gt 0 ]]; then
	ok "zram activé (${zram} %)"
	if [[ -n "$swap" && "$swap" -ge 80 ]]; then
		ok "swappiness à $swap — assez haute pour que le zram serve"
	else
		non "swappiness à ${swap:-?} : trop basse, le noyau ignorera le zram"
	fi
else
	non "zram désactivé dans « vif » — c'est pourtant la moitié du profil"
fi

# -----------------------------------------------------------------------------
titre "7. Les profils existants n'ont pas bougé"
for p in petit medium performant max; do
	if grep -qE "^[[:space:]]*${p}\)" "$PERF"; then ok "« $p » toujours là"
	else non "« $p » a disparu"; fi
done
for p in performant max; do
	b="$(sed -n "/^[[:space:]]*${p})/,/;;/p" "$PERF")"
	if grep -qE 'P_ZRAM=0' <<< "$b"; then ok "« $p » garde P_ZRAM=0"
	else non "« $p » ne devrait pas activer zram"; fi
done

# -----------------------------------------------------------------------------
titre "8. Le panneau des Paramètres connaît « vif »"
if [[ -r "$APPJS" ]]; then
	#  Frontière de mot obligatoire : « vif » se cache dans des mots français
	#  ordinaires (« vif » dans un commentaire, « vive »…), et un grep nu
	#  passait au vert sans que le profil soit déclaré nulle part.
	if grep -qE '"vif"|\bvif:' "$APPJS"; then ok "app.js déclare « vif »"
	else non "app.js ne connaît pas « vif » — la liste du panneau est incomplète"; fi
	if grep -qE 'PERF_RPM *=.*vif' "$APPJS"; then
		ok "PERF_RPM a une valeur pour « vif »"
	else
		non "PERF_RPM n'a pas de valeur pour « vif » : l'aiguille restera à zéro"
	fi
else
	non "app.js introuvable ($APPJS)"
fi

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
titre "9. « vif » est bien SUGGÉRÉ aux portables — la raison d'être du profil"
# -----------------------------------------------------------------------------
#  ═══ ON EXÉCUTE detect_profile(), ON NE RELIT PAS SA FORME ═══
#  Une mutation qui retirait la suggestion aux portables est restée VERTE sur
#  la première version de ce banc : tout y était vérifié SAUF le cœur de la
#  demande. Et le rejeu du calcul, plus haut, recopie la formule — il
#  éprouve la copie, pas le code.
#  On extrait donc les deux vraies fonctions et on les lance sur un faux
#  matériel, par les coutures LEXOS_PERF_MEMINFO et LEXOS_PERF_POWER.
FONCS="$(sed -n '/^on_battery()/,/^}/p;/^detect_profile()/,/^}/p' "$PERF")"
BANC_VIF="$(mktemp -d)"
trap 'rm -rf "$BANC_VIF"' EXIT

suggere() { # suggere <ram_kb> <coeurs> <portable:oui|non>
	rm -rf "$BANC_VIF/faux"; mkdir -p "$BANC_VIF/faux/power"
	printf 'MemTotal:       %s kB\n' "$1" > "$BANC_VIF/faux/meminfo"
	[ "$3" = "oui" ] && mkdir -p "$BANC_VIF/faux/power/BAT0"
	LEXOS_PERF_MEMINFO="$BANC_VIF/faux/meminfo" \
	LEXOS_PERF_POWER="$BANC_VIF/faux/power" \
		bash -c "nproc() { printf '%s' $2; }
$FONCS
detect_profile" 2>/dev/null
}

#  Les cas qui comptent, et pourquoi chacun est là.
for CAS in \
	"2000000:4:oui:petit:2 Go, portable" \
	"8039000:2:oui:petit:8 Go mais 2 fils — les cœurs priment" \
	"4008000:4:oui:medium:4 Go, portable" \
	"8039000:4:oui:vif:8 Go portable — LE cas qui a motivé le profil" \
	"8039000:4:non:performant:8 Go en tour — elle garde performant" \
	"12210000:4:oui:vif:12 Go portable" \
	"16310000:8:non:max:16 Go, tour" \
	"32780000:8:oui:max:32 Go, portable puissant" \
; do
	KB="${CAS%%:*}"; R1="${CAS#*:}"
	COEURS="${R1%%:*}"; R2="${R1#*:}"
	BAT="${R2%%:*}"; R3="${R2#*:}"
	ATTENDU="${R3%%:*}"; NOM="${R3#*:}"
	VU="$(suggere "$KB" "$COEURS" "$BAT")"
	if [ "$VU" = "$ATTENDU" ]; then
		ok "$NOM → $VU"
	else
		non "$NOM → « $VU », attendu « $ATTENDU »"
	fi
done

# -----------------------------------------------------------------------------
titre "10. Les deux listes de profils disent la même chose"
# -----------------------------------------------------------------------------
#  ═══ LE BOGUE QUI A MOTIVÉ CETTE SECTION ═══
#  PERFS, dans settings.py, valait { petit, medium, performant, max }. « vif »
#  y manquait — et nulle part ailleurs. Le bouton partait, la réponse revenait
#  « profil inconnu », et le seul profil que detect_profile() RECOMMANDE à un
#  portable de 8 Go était le seul qu'on refusait de lui appliquer.
#
#  ON EXTRAIT LES DEUX LISTES ET ON LES COMPARE. Chercher « vif » dans
#  settings.py aurait été vert dès le premier commentaire qui le nomme : ce
#  fichier en contient plusieurs. On lit donc la ligne PERFS elle-même, et les
#  sorties de normalize() dans lexos-perf.
if [[ -r "$REGLAGES" ]]; then
	#  Côté page : le contenu de l'accolade de PERFS.
	COTE_PAGE="$(sed -n 's/^PERFS *= *{\(.*\)}.*/\1/p' "$REGLAGES" \
	            | tr -d '"' | tr ',' '\n' | tr -d ' ' | grep . | sort -u)"
	#  Côté outil : tout ce que normalize() peut IMPRIMER, c'est-à-dire les
	#  noms canoniques — pas les alias, qui sont à gauche du « ) ».
	#  normalize() écrit « printf 'vif' » — le nom canonique est le SEUL
	#  argument. Les alias (« snappy », « rapide-sobre »…) sont à gauche du
	#  « ) » et ne doivent pas entrer dans la comparaison : la page n'a pas à
	#  les connaître.
	COTE_OUTIL="$(sed -n "/^normalize()/,/^}/p" "$PERF" \
	             | sed -n "s/.*printf '\([a-z]*\)'.*/\1/p" | sort -u)"
	if [[ -z "$COTE_PAGE" ]]; then
		non "PERFS n'a pas pu être extrait de settings.py — le contrôle ne contrôle rien"
	elif [[ -z "$COTE_OUTIL" ]]; then
		non "normalize() n'a pas pu être extrait de lexos-perf — le contrôle ne contrôle rien"
	elif [[ "$COTE_PAGE" == "$COTE_OUTIL" ]]; then
		ok "les $(printf '%s' "$COTE_PAGE" | grep -c .) profils sont les mêmes des deux côtés"
	else
		non "PERFS et normalize() divergent :"
		diff <(printf '%s\n' "$COTE_OUTIL") <(printf '%s\n' "$COTE_PAGE") \
			| sed 's/^/      /' >&2
	fi
	#  Et le cas précis, nommé, pour que le message soit lisible s'il revient.
	if grep -qx 'vif' <<< "$COTE_PAGE"; then
		ok "settings.py accepte « vif »"
	else
		non "PERFS refuse « vif » : le bouton rendra « profil inconnu »"
	fi
else
	non "settings.py introuvable ($REGLAGES)"
fi

# -----------------------------------------------------------------------------
titre "11. Le plan système peut demander son mot de passe depuis une fenêtre"
# -----------------------------------------------------------------------------
#  sudo demande le mot de passe SUR UN TERMINAL. Depuis les Paramètres il n'y
#  en a pas : sudo renonce, et le bouton « ne fait rien ». La règle polkit rend
#  la demande possible dans une fenêtre — c'est la voie de LexOS Boost.
if [[ -r "$POLKIT" ]]; then
	ok "la règle polkit existe"
	if command -v python3 >/dev/null 2>&1; then
		if python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" \
		           "$POLKIT" 2>/dev/null; then
			ok "elle est du XML bien formé"
		else
			non "XML mal formé : polkitd l'ignorera en silence"
		fi
	fi
	if grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/bin/lexos-perf<' "$POLKIT"; then
		ok "elle désigne bien /usr/bin/lexos-perf"
	else
		non "l'annotation exec.path ne désigne pas /usr/bin/lexos-perf"
	fi
else
	non "org.lexos.perf.policy manquant : le plan système restera muet en fenêtre"
fi
refuse "plus de « sudo \$0 » en dur : le choix passe par elevateur()" \
       'sudo "\$0" apply-system'
verifie "elevateur() existe"                     '^elevateur\(\)'
verifie "self_path() rend un chemin absolu"      '^self_path\(\)'
verifie "la couture de banc LEXOS_ELEVATEUR est là" 'LEXOS_ELEVATEUR'

#  ═══ ON EXÉCUTE LE CHOIX, ON NE RELIT PAS SA FORME ═══
#  Un faux sudo et un faux pkexec, un PATH qui ne contient qu'eux, et on
#  demande à elevateur() ce qu'il choisit. Aucun mot de passe n'est demandé à
#  personne : les deux faux outils rendent 0 sans rien faire.
BANC_ELEV="$(mktemp -d)"
trap 'rm -rf "$BANC_VIF" "$BANC_ELEV"' EXIT
mkdir -p "$BANC_ELEV/bin"
FONCS_ELEV="$(sed -n '/^elevateur()/,/^}/p' "$PERF")"
pose() { rm -f "$BANC_ELEV/bin/sudo" "$BANC_ELEV/bin/pkexec"
         for n in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$BANC_ELEV/bin/$n"
                           chmod +x "$BANC_ELEV/bin/$n"; done; }
#  ═══ LE PATH DOIT ÊTRE RÉDUIT AU FAUX RÉPERTOIRE ═══
#  Sinon le vrai /usr/bin/pkexec de la machine répond à la place du nôtre, et
#  le banc mesure la machine au lieu de mesurer le code. Attrapé ici même :
#  « sudo seul » rendait « pkexec » tant que le vrai PATH suivait derrière.
#  bash, lui, est appelé par son chemin absolu — il n'est pas dans le faux
#  répertoire, et le mettre dans le PATH d'essai ferait revenir le défaut.
#
#  On écrit la fonction dans un fichier plutôt que de la passer à « bash -c » :
#  ses commentaires sont en français et contiennent des apostrophes, qui
#  refermaient la chaîne au milieu.
printf '%s\nelevateur\n' "$FONCS_ELEV" > "$BANC_ELEV/choix.sh"
choix() { env -i PATH="$BANC_ELEV/bin" "$BASH" "$BANC_ELEV/choix.sh" < /dev/null; }
choix_tty() {
	script -qec "env -i PATH=$BANC_ELEV/bin $BASH $BANC_ELEV/choix.sh" /dev/null \
		2>/dev/null | tr -d '\r\n'
}
attend() { # description, obtenu, attendu
	if [[ "$2" == "$3" ]]; then ok "$1 → ${2:-（rien）}"; else non "$1 → « $2 », attendu « $3 »"; fi
}
pose sudo pkexec; attend "sans terminal, les deux présents" "$(choix)" "pkexec"
if command -v script >/dev/null 2>&1; then
	pose sudo pkexec
	attend "avec terminal, les deux présents" "$(choix_tty)" "sudo"
else
	ok "avec terminal : « script » absent de cette machine, contrôle sauté"
fi
pose pkexec;      attend "sans sudo"        "$(choix)" "pkexec"
pose sudo;        attend "sans pkexec"      "$(choix)" "sudo"
pose;             attend "aucun des deux"   "$(choix)" ""

# -----------------------------------------------------------------------------
titre "12. Un plan système refusé n'emporte plus le plan session"
# -----------------------------------------------------------------------------
#  ═══ CE QUE CETTE SECTION EMPÊCHE DE REVENIR ═══
#  Il y avait « || die » : un mot de passe refusé et on abandonnait TOUT, y
#  compris la composition, les effets CRT, le zoom du dock et les vignettes,
#  qui ne demandent aucun droit. Sur la machine d'Alex, « vif » n'éteignait
#  donc même pas la composition — la moitié la plus visible du profil.
refuse "le « die » sur le plan système a disparu" \
       'apply-system "\$PROFILE" \|\| die'
#  ═══ CE CONTRÔLE ÉTAIT CREUX, ET LA MUTATION L'A DIT ═══
#  Première version : « ^[[:space:]]*[[ "$SCOPE" != "system" ]] && apply_user »
#  sur tout le fichier. Or cette ligne existe DEUX fois — dans set_profile, et
#  dans la branche « apply ) » du répartiteur, à deux tabulations. Remettre
#  apply_user à l'intérieur du bloc système laissait donc l'autre satisfaire le
#  motif, et le banc restait vert sur exactement la régression qu'il surveille.
#
#  On lit maintenant le corps de set_profile SEUL, et on exige UNE SEULE
#  tabulation : c'est le premier niveau de la fonction. Deux tabulations ou
#  plus voudraient dire « imbriqué dans le if », c'est-à-dire le défaut.
#  LA TABULATION PASSE PAR printf, PAS PAR LE MOTIF. « \t » n'est pas une
#  échappée de grep -E : GNU grep y lit un « t » ordinaire, et le motif ne
#  correspondait donc à rien — le contrôle rougissait sur du code juste. Même
#  famille que le « \Q\E » d'un autre banc, qui n'existe qu'en PCRE.
CORPS_SP="$(sed -n '/^set_profile() {/,/^}/p' "$PERF")"
MOTIF_AU="$(printf '^\t\\[\\[ "\\$SCOPE" != "system" \\]\\] && apply_user')"
if grep -qE "$MOTIF_AU" <<< "$CORPS_SP"; then
	ok "dans set_profile, apply_user est au premier niveau — hors du bloc système"
else
	non "dans set_profile, apply_user est imbriqué (ou absent) : un refus l'emporterait encore"
fi

#  On le JOUE, sous un uid quelconque, avec un faux élévateur qui ÉCHOUE.
BANC_REF="$BANC_ELEV/refus"; mkdir -p "$BANC_REF/bin" "$BANC_REF/home"
printf '#!/bin/sh\necho "Request dismissed" >&2\nexit 126\n' > "$BANC_REF/bin/refus"
chmod +x "$BANC_REF/bin/refus"
if [[ "$EUID" -ne 0 ]]; then
	SORTIE="$(HOME="$BANC_REF/home" XDG_CONFIG_HOME="$BANC_REF/home/.config" \
		PATH="$BANC_REF/bin:$PATH" LEXOS_ELEVATEUR=refus \
		DISPLAY= WAYLAND_DISPLAY= \
		bash "$PERF" vif 2>/dev/null)"; CODE=$?
	if [[ "$CODE" -ne 0 ]]; then
		ok "l'échec du plan système se voit dans le code de sortie ($CODE)"
	else
		non "code 0 alors que le plan système a été refusé — la page croira à un succès"
	fi
	if [[ -r "$BANC_REF/home/.config/lexos/perf" ]]; then
		ok "le plan session s'est appliqué quand même ($(cat "$BANC_REF/home/.config/lexos/perf"))"
	else
		non "le plan session n'a rien écrit : le refus l'a encore emporté"
	fi
	#  LA DERNIÈRE LIGNE DE stdout EST CE QUE LA PAGE AFFICHE. settings.py,
	#  _run() : « sortie = (stdout or stderr) », puis « splitlines()[-1] ».
	#  Dès que stdout contient quelque chose — et apply_user vient d'écrire —
	#  stderr est JETÉ. Un motif posé seulement sur stderr n'arriverait jamais
	#  à l'écran. Ce contrôle tient les deux bouts ensemble.
	DERNIERE="$(printf '%s\n' "$SORTIE" | grep . | tail -1)"
	if [[ "$DERNIERE" == *"plan système refusé"* ]]; then
		ok "le motif est la dernière ligne de stdout — la page pourra l'afficher"
	else
		non "dernière ligne de stdout : « $DERNIERE » — la page dira « commande refusée »"
	fi
else
	ok "lancé en root : le chemin d'élévation ne s'exerce pas, contrôle sauté"
	ok "(relancer ce banc sous un compte ordinaire pour l'éprouver)"
fi
#  Et le lecteur, côté Python, doit bien être celui qu'on suppose.
if grep -q 'sortie = (r.stdout or r.stderr)' "$REGLAGES"; then
	ok "settings.py lit toujours « (stdout or stderr) » — l'hypothèse tient"
else
	non "settings.py ne lit plus « (stdout or stderr) » : revoir où lexos-perf écrit son motif"
fi
#  LES DEUX MOITIÉS D'UNE MÊME PHRASE. act_perf() n'ajoute son message sur
#  l'agent polkit que s'il RECONNAÎT la phrase de lexos-perf. Changer l'une
#  sans l'autre ne casse rien de visible : le message cesse simplement
#  d'apparaître, en silence. On les compare donc ici.
PHRASE='plan système refusé'
if grep -qF "$PHRASE" "$PERF" && grep -qF "$PHRASE" "$REGLAGES"; then
	ok "lexos-perf écrit « $PHRASE » et settings.py le reconnaît"
else
	non "« $PHRASE » n'est plus des deux côtés : le message sur l'agent polkit ne sortira plus"
fi
#  ET IL NE DOIT PAS SORTIR À TORT. Un profil refusé pour une autre raison —
#  outil absent, /etc non inscriptible — ne doit pas envoyer chercher un agent
#  polkit. La garde est ce filtre-là.
if grep -q 'in (r.get("erreur") or "")' "$REGLAGES"; then
	ok "le message n'est ajouté que sur CETTE cause, pas sur n'importe quel échec"
else
	non "act_perf() met le message du mot de passe sur tout échec, même sans rapport"
fi

# -----------------------------------------------------------------------------
titre "13. L'aiguille balaie au lieu de sauter"
# -----------------------------------------------------------------------------
#  La transition CSS existait depuis toujours et n'a jamais joué : setPerf()
#  passait par rendSection(), qui refait « content.innerHTML = … ». Le <g
#  class="needle"> était détruit puis recréé DÉJÀ tourné à sa valeur
#  d'arrivée — et une transition n'interpole qu'entre deux valeurs
#  successives d'un même élément.
if [[ -r "$APPJS" ]]; then
	#  ═══ PAS DE TUYAU VERS grep -q, ET ICI ÇA COMPTE DOUBLE ═══
	#  grep -q ferme le tuyau au premier résultat ; sous « pipefail », sed
	#  reçoit une erreur d'écriture et TOUT le tuyau échoue alors que le
	#  motif A ÉTÉ TROUVÉ. Ce contrôle-ci est INVERSÉ — « si rendSection est
	#  là, rougis » — donc la course y donnerait un faux VERT sur exactement
	#  la régression qu'il surveille. La substitution de processus sort sed
	#  du tuyau : son code ne compte plus dans PIPESTATUS.
	if grep -qE 'async function setPerf' "$APPJS" && \
	   grep -q 'rendSection()' < <(sed -n '/^async function setPerf/,/^}/p' "$APPJS"); then
		non "setPerf() reconstruit encore la section : l'aiguille sautera"
	else
		ok "setPerf() ne reconstruit plus la section"
	fi
	if grep -qE 'querySelector\("\.needle"\)|querySelector\(.\.needle.\)' "$APPJS"; then
		ok "l'aiguille EXISTANTE est retrouvée puis retournée"
	else
		non "personne ne va chercher le <g class=\"needle\"> déjà en place"
	fi
	if grep -qE '\belse\b' < <(sed -n '/^async function setPerf/,/^}/p' "$APPJS"); then
		ok "setPerf() lit la réponse au lieu de la jeter"
	else
		non "setPerf() jette encore l'échec : un refus resterait sans message"
	fi
else
	non "app.js introuvable ($APPJS)"
fi

# -----------------------------------------------------------------------------
titre "14. Le jeu d'icônes figées est parti en entier"
# -----------------------------------------------------------------------------
#  branding/icon-perf-*.svg : quatre cadrans DESSINÉS À LA MAIN, pour quatre
#  profils sur cinq — « vif » n'en a jamais eu. Rien ne les référençait : ni
#  lexos-theme-gen (sa liste d'icônes teintées est fixe et ne les nomme pas),
#  ni un .desktop, ni un hook. Ils partaient pourtant sur chaque ISO, puisque
#  build.sh recopie branding/*.svg en entier. Le compte-tours de la page est
#  un VRAI cadran en SVG, calculé — c'est lui qui les a remplacés.
RESTES="$(find "$RACINE/branding" -maxdepth 1 -name 'icon-perf-*.svg' 2>/dev/null | wc -l)"
if [[ "$RESTES" -eq 0 ]]; then
	ok "aucun icon-perf-*.svg ne traîne plus dans branding/"
else
	non "$RESTES icon-perf-*.svg subsistent — jeu incomplet, embarqué pour rien"
fi

printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
