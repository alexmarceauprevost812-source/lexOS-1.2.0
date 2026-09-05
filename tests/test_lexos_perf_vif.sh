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

printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
