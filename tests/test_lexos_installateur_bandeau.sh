#!/usr/bin/env bash
# =============================================================================
#  Le bandeau de l'installateur : lisible, et pas seulement bien orthographié
# =============================================================================
#  ALEX, PHOTO DE L'INSTALLATEUR : le bandeau de gauche était ILLISIBLE. Pas
#  « peu contrasté » — invisible : seule l'étape courante se distinguait, les
#  autres n'apparaissaient pas du tout.
#
#  ═══ LA CAUSE, ET POURQUOI ELLE ÉTAIT MUETTE ═══
#  Les quatre clés de « style: » étaient écrites en minuscule initiale
#  (« sidebarBackground »…). Calamares 3.3 les compare aux noms de son enum
#  C++ Branding::StyleEntry, résolus par QMetaEnum::valueToKey — donc avec une
#  MAJUSCULE initiale. Établi deux fois, sans deviner :
#    · les seules chaînes présentes dans un libcalamaresui.so 3.3 installé
#      pour l'occasion sont SidebarBackground, SidebarBackgroundCurrent,
#      SidebarText, SidebarTextCurrent ; aucune variante en minuscule ;
#    · l'exemple officiel amont (src/branding/default/branding.desc) les écrit
#      avec la majuscule ;
#    · et dans la source au tag v3.3.14 — la version empaquetée par trixie —
#      Branding.h déclare « enum StyleEntry { SidebarBackground, SidebarText,
#      SidebarTextCurrent, SidebarBackgroundCurrent } », que Branding.cpp
#      compare aux clés du YAML SANS normaliser la casse.
#
#  ═══ D'OÙ VENAIT LA MAUVAISE CLÉ, ET POURQUOI PERSONNE N'EST FAUTIF ═══
#  Les noms en minuscule ET « sidebarTextSelect » sont ceux de Calamares 3.2.
#  Le passage en 3.3 a changé deux choses d'un coup : la casse, et le sens
#  (sidebarTextSelect est devenu SidebarTextCurrent, sidebarTextHighlight est
#  devenu SidebarBackgroundCurrent). Pire : un commentaire PÉRIMÉ subsiste
#  dans Branding.h en amont, qui affirme encore que SidebarTextCurrent
#  « s'appelle sidebarTextSelect dans le fichier de branding ». C'est faux
#  depuis 3.3 — suivre ce commentaire menait droit à la panne.
#
#  Une clé inconnue n'arrête RIEN : Calamares écrit « Unknown branding *style*
#  entry » dans un journal que personne ne lit, puis styleString() rend une
#  chaîne VIDE pour les quatre vraies entrées. QColor("") est invalide, et une
#  couleur invalide se peint en NOIR. D'où le noir sur noir, sans message.
#
#  ═══ CE QUE CE BANC GARDE ═══
#  L'orthographe exacte, oui — mais surtout le CONTRASTE. Écrire les bonnes
#  clés ne suffit pas : quelqu'un pourrait un jour poser un texte sombre sur un
#  fond sombre et refaire exactement la même panne, avec des clés valides
#  cette fois. On calcule donc le rapport de contraste des deux couples, comme
#  le ferait un œil.
# =============================================================================
set -uo pipefail

#  ═══ AUCUNE VARIABLE NE REPART DANS UN TUYAU VERS « grep -q » ═══
#  MESURÉ SUR CE BANC MÊME, ET ÇA MORDAIT DÉJÀ : le contrôle « le bloc style:
#  est bien dans le heredoc » extrayait 4 ko avec sed et les envoyait à
#  « grep -q ». Celui-ci s'arrête au premier résultat et ferme le tuyau ; sed,
#  qui écrivait encore, prend une erreur ; et « pipefail » transforme ça en
#  condition FAUSSE alors que le motif A ÉTÉ TROUVÉ.
#  54 échecs sur 300 essais — un faux rouge une fois sur cinq, depuis
#  toujours, sur un banc que la CI lançait à chaque construction.
#  La forme sûre est « grep motif <<< "$VAR" » : bash passe le texte par un
#  fichier, il n'y a plus de tuyau à casser.
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0500-lexos-installer.hook.chroot"

REUSSIS=0; ECHOUES=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()   { printf '  \033[31m❌\033[0m %b\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

[[ -r "$HOOK" ]] || { echo "hook 0500 introuvable : $HOOK"; exit 1; }

BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

# =============================================================================
#  ON EXÉCUTE LE HOOK, ON NE LE RELIT PAS
# =============================================================================
#  Ce banc lisait le texte du hook et vérifiait ce qui y était ÉCRIT. Ça ne
#  tient plus, et c'est tant mieux : les couleurs sont maintenant des
#  variables (« ${LEX_SIDE} »), et un contrôle qui lit « ${LEX_SIDE} » là où
#  Calamares lira « #0A0A0B » ne vérifie plus rien du tout.
#  On détourne donc la destination par la couture LEXOS_BRANDING_DIR et on
#  LANCE le bloc marqué. Ce qu'on mesure ensuite, ce sont les fichiers que
#  Calamares lira vraiment.
generer() { # generer  → écrit dans $BANC/br, rend 0 si le bloc s'exécute
	rm -rf "$BANC/br"; mkdir -p "$BANC/br"
	sed -n '/^# >>> banc: apparence$/,/^# <<< banc: apparence$/p' "$HOOK" > "$BANC/bloc.sh"
	[[ -s "$BANC/bloc.sh" ]] || return 1
	LEXOS_BRANDING_DIR="$BANC/br" \
	LEXOS_NAME="LexOS" LEXOS_VERSION="2.0.0" LEXOS_CODENAME="Nomad" \
	LEXOS_HOME_URL="https://exemple.invalid" LEXOS_BUG_URL="https://exemple.invalid/issues" \
		sh "$BANC/bloc.sh" >/dev/null 2>&1
}

titre "0. Le bloc d'apparence s'exécute, et pose ses trois fichiers"
if generer; then
	ok "le bloc marqué « banc: apparence » s'exécute sans erreur"
else
	non "le bloc marqué « banc: apparence » est introuvable ou échoue — rien n'a pu être mesuré"
fi

DESC="$BANC/br/branding.desc"
QSS="$BANC/br/stylesheet.qss"
QML="$BANC/br/show.qml"
for F in "$DESC" "$QSS" "$QML"; do
	if [[ -s "$F" ]]; then
		ok "$(basename "$F") est écrit et non vide"
	else
		non "$(basename "$F") MANQUE ou est vide — l'installateur retomberait sur le thème Qt ambiant"
	fi
done

#  ═══ ON RETIRE LES COMMENTAIRES, ET SEULEMENT LES LIGNES DE COMMENTAIRE ═══
#  Le grand commentaire sur la casse voyage AVEC le heredoc : il se retrouve
#  dans branding.desc, et il CITE les mauvaises clés (« sidebarTextSelect »)
#  pour les expliquer. Un grep naïf les compterait pour de vraies lignes.
#  Et on ne peut pas couper « tout ce qui suit un # » : les couleurs elles-
#  mêmes commencent par un dièse. On supprime donc les LIGNES qui commencent
#  par un dièse, pas les fins de ligne.
BLOC="$(sed '/^[[:space:]]*#/d' "$DESC" | sed -n '/^style:$/,$p' | sed '/^style:$/d')"

# =============================================================================
titre "1. Les quatre clés existent, avec LEUR casse"
# =============================================================================
#  Les seules valides dans Calamares 3.3, telles que livrées dans le .so.
VALIDES=(SidebarBackground SidebarBackgroundCurrent SidebarText SidebarTextCurrent)

declare -A COULEUR=()
for K in "${VALIDES[@]}"; do
	V="$(printf '%s' "$BLOC" | sed -n "s/^[[:space:]]*${K}:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" | head -1)"
	if [[ -n "$V" ]]; then
		ok "$K est posée (« $V »)"
		COULEUR[$K]="$V"
	else
		non "$K MANQUE ou est mal orthographiée — Calamares la lira vide, donc NOIRE"
	fi
done

# =============================================================================
titre "2. Aucune clé que Calamares ne connaît pas"
# =============================================================================
#  ═══ LE CONTRÔLE QUI AURAIT ÉVITÉ LA PANNE ═══
#  Une clé inconnue ne fait rien échouer : elle est notée dans un journal et
#  la vraie entrée reste vide, donc noire. C'est exactement ce qui s'est
#  produit — et rien, nulle part, ne le signalait.
INCONNUES=""
while IFS= read -r LIGNE; do
	[[ -z "${LIGNE// }" ]] && continue
	CLE="$(printf '%s' "$LIGNE" | sed -n 's/^[[:space:]]*\([A-Za-z]*\):.*$/\1/p')"
	[[ -z "$CLE" ]] && continue
	CONNUE=0
	for K in "${VALIDES[@]}"; do [[ "$CLE" == "$K" ]] && CONNUE=1; done
	(( CONNUE == 0 )) && INCONNUES="$INCONNUES $CLE"
done <<< "$BLOC"

if [[ -z "${INCONNUES// }" ]]; then
	ok "aucune clé inconnue dans le bloc « style: »"
else
	non "clés que Calamares ignorera EN SILENCE :$INCONNUES\n     (les vraies entrées resteraient vides, donc peintes en noir)"
fi

#  Le piège nommé : « sidebarTextSelect » vient de Calamares 3.2 et n'existe
#  plus. On le cite pour que le rouge dise quoi faire, pas seulement qu'il y
#  a un problème.
if grep -qi 'sidebarTextSelect' <<< "$BLOC"; then
	non "« sidebarTextSelect » est une clé de Calamares 3.2, disparue en 3.3 — la bonne est SidebarBackgroundCurrent"
else
	ok "la clé morte « sidebarTextSelect » (Calamares 3.2) n'est plus là"
fi

# =============================================================================
titre "3. LE CONTRASTE — écrire les bonnes clés ne suffit pas"
# =============================================================================
#  Rapport de contraste WCAG entre deux couleurs. 4,5 est le seuil courant
#  pour du texte ; on exige 4,5 pour l'étape courante comme pour les autres.
#  Sans ce contrôle, un texte sombre sur fond sombre referait la panne avec
#  des clés parfaitement valides.
contraste() { # contraste <#rrggbb> <#rrggbb>
	python3 - "$1" "$2" <<'PY'
import sys
def lum(c):
    c = c.lstrip('#')
    if len(c) != 6: return None
    v = []
    for i in (0, 2, 4):
        x = int(c[i:i+2], 16) / 255
        v.append(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4)
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
a, b = lum(sys.argv[1]), lum(sys.argv[2])
if a is None or b is None:
    print("0"); raise SystemExit
hi, lo = max(a, b), min(a, b)
print("%.2f" % ((hi + 0.05) / (lo + 0.05)))
PY
}

verifie_paire() { # verifie_paire <cle_texte> <cle_fond> <libelle>
	local T="${COULEUR[$1]:-}" F="${COULEUR[$2]:-}"
	if [[ -z "$T" || -z "$F" ]]; then
		non "$3 : couleurs absentes, contraste incalculable"
		return
	fi
	local R; R="$(contraste "$T" "$F")"
	if awk -v r="$R" 'BEGIN{exit !(r >= 4.5)}'; then
		ok "$3 : contraste ${R}:1 — lisible"
	else
		non "$3 : contraste ${R}:1 seulement ($T sur $F) — c'est la panne d'origine qui revient"
	fi
}

verifie_paire SidebarText        SidebarBackground        "étapes non courantes"
verifie_paire SidebarTextCurrent SidebarBackgroundCurrent "étape courante"

#  ET LES DEUX FONDS DOIVENT SE DISTINGUER, sinon l'étape courante ne se
#  repère plus, même avec un texte lisible.
if [[ -n "${COULEUR[SidebarBackground]:-}" && -n "${COULEUR[SidebarBackgroundCurrent]:-}" ]]; then
	if [[ "${COULEUR[SidebarBackground]}" == "${COULEUR[SidebarBackgroundCurrent]}" ]]; then
		non "les deux fonds sont identiques : on ne verrait plus OÙ on en est"
	else
		ok "le fond de l'étape courante se distingue de celui des autres"
	fi
fi

# =============================================================================
titre "4. Le bloc part bien dans branding.desc"
# =============================================================================
#  Écrit ailleurs que dans le heredoc, il n'atteindrait aucun fichier.
HEREDOC="$(sed -n '/cat > "\$BRANDING_DIR\/branding.desc" <<EOF/,/^EOF$/p' "$HOOK")"
if grep -q '^style:$' <<< "$HEREDOC"; then
	ok "le bloc « style: » est bien DANS le heredoc de branding.desc"
else
	non "le bloc « style: » est hors du heredoc : il n'atteindrait pas branding.desc"
fi

#  Et le hook doit rester du shell valide après l'édition.
if bash -n "$HOOK" 2>/dev/null; then
	ok "le hook 0500 garde une syntaxe shell valide"
else
	non "le hook 0500 ne se parse plus :\n$(bash -n "$HOOK" 2>&1 | head -3)"
fi

# =============================================================================
titre "5. Le ménage de fin d'installation ne fait pas ÉCHOUER l'installation"
# =============================================================================
#  ALEX, PHOTO : « L'installation a échoué — Erreur du gestionnaire de
#  paquets … code d'erreur 100 », à la toute dernière étape, après la copie du
#  système.
#
#  La liste de calamares-settings-debian nomme neuf paquets ; LexOS n'en
#  installe que trois. Et la FORME de l'opération décide de tout, comme le dit
#  le module livré (calamares/modules/packages/main.py) :
#    · « remove »     -> UN SEUL apt-get avec toute la liste : un nom absent
#      fait échouer l'appel entier, donc l'installation ;
#    · « try_remove » -> un par un, un échec ne donne qu'un avertissement.
#
#  C'est CE contrôle qui garde l'installation. Le reste du banc garde des
#  couleurs ; celui-ci garde le fait qu'on puisse installer LexOS.
BLOCP="$(sed -n '/cat > "\$PKGCONF" <<.PKGEOF./,/^PKGEOF$/p' "$HOOK")"

#  ET IL FAUT VÉRIFIER OÙ ÇA VA. Le heredoc écrit vers « $PKGCONF » : lire
#  son contenu ne dit rien de sa DESTINATION. Repéré en cassant exprès la
#  variable — le banc restait vert alors que le fichier serait parti dans le
#  vide, et la liste Debian se serait appliquée telle quelle.
if grep -qE '^PKGCONF="/etc/calamares/modules/packages\.conf"$' "$HOOK"; then
	ok "la liste est écrite au bon endroit (/etc/calamares/modules/packages.conf)"
else
	non "PKGCONF ne pointe pas sur /etc/calamares/modules/packages.conf — la liste Debian s'appliquerait"
fi

if [[ -z "$BLOCP" ]]; then
	non "le hook n'écrit pas packages.conf — la liste Debian s'appliquerait telle quelle"
else
	ok "le hook écrit sa propre liste de ménage (packages.conf)"

	if grep -qE '^[[:space:]]*-[[:space:]]*try_remove:' <<< "$BLOCP"; then
		ok "…et elle emploie « try_remove » : un paquet absent n'arrête plus rien"
	else
		non "la liste n'emploie pas « try_remove » — un seul paquet absent ferait ÉCHOUER l'installation"
	fi

	#  « remove: » tout court ne doit PAS revenir : c'est exactement la forme
	#  qui a cassé l'installation d'Alex.
	if grep -qE '^[[:space:]]*-[[:space:]]*remove:' <<< "$BLOCP"; then
		non "la forme fatale « remove: » est de retour dans la liste"
	else
		ok "…et la forme fatale « remove: » n'y est pas"
	fi

	#  Les trois paquets que LexOS installe VRAIMENT doivent être nommés,
	#  sinon le ménage ne se ferait plus et la clé laisserait ses traces sur
	#  le disque installé.
	for P in live-boot live-config calamares-settings-debian; do
		if grep -q "'$P'" <<< "$BLOCP"; then
			ok "…$P (installé par LexOS) est bien retiré du système installé"
		else
			non "$P est installé par LexOS mais n'est plus retiré : la clé laisserait ses traces"
		fi
	done

	if grep -q '^backend: apt$' <<< "$BLOCP"; then
		ok "…et le moteur déclaré est bien apt"
	else
		non "le moteur de paquets déclaré n'est pas apt"
	fi
fi

# =============================================================================
titre "6. La palette est celle du BUREAU, pas une palette d'installateur"
# =============================================================================
#  ═══ POURQUOI CE CONTRÔLE EXISTE ═══
#  L'installateur portait #141110 sur #F4EFEA — la vieille palette chaude, que
#  le bureau a abandonnée il y a des versions. Personne ne l'a vu, parce que
#  personne ne regarde l'installateur deux fois : on le traverse une fois, à
#  l'installation, et c'est justement la PREMIÈRE chose qu'on voit de LexOS.
#  On compare donc chaque couleur du hook à celle que ui.css déclare. Si
#  l'accent bouge là-bas, ce banc rougit ici — c'est tout l'intérêt.
UICSS="$RACINE/config/includes.chroot/usr/share/lexos/ui.css"

#  ui.css écrit « --ac-txt:#000 » en trois chiffres : on ramène tout à six,
#  sinon la comparaison échouerait sur une différence d'écriture, pas de
#  couleur.
six() { # six <#abc|#aabbcc>
	local c="${1#\#}"
	if [[ ${#c} -eq 3 ]]; then printf '#%c%c%c%c%c%c\n' "${c:0:1}" "${c:0:1}" "${c:1:1}" "${c:1:1}" "${c:2:1}" "${c:2:1}"
	else printf '#%s\n' "$c"; fi
}
maj() { tr '[:lower:]' '[:upper:]'; }

if [[ -r "$UICSS" ]]; then
	PAIRES=(
		"LEX_BG:--bg"        "LEX_SIDE:--bg-side"  "LEX_HI:--bg-hi"
		"LEX_FG:--fg"        "LEX_DIM:--fg-dim"    "LEX_BD:--bd"
		"LEX_AC:--ac"        "LEX_AC_HI:--ac-hi"   "LEX_AC_TXT:--ac-txt"
	)
	ECARTS=""
	for P in "${PAIRES[@]}"; do
		VAR="${P%%:*}"; CSS="${P##*:}"
		H="$(sed -n "s/^${VAR}=\"\([^\"]*\)\".*/\1/p" "$HOOK" | head -1)"
		C="$(sed -n "s/^[[:space:]]*${CSS}:[[:space:]]*\(#[0-9A-Fa-f]\{3,6\}\);.*/\1/p" "$UICSS" | head -1)"
		if [[ -z "$H" || -z "$C" ]]; then
			ECARTS="$ECARTS\n     $VAR / $CSS : introuvable (hook=«$H» ui.css=«$C»)"
			continue
		fi
		if [[ "$(six "$H" | maj)" != "$(six "$C" | maj)" ]]; then
			ECARTS="$ECARTS\n     $VAR=$H alors que ui.css dit $CSS=$C"
		fi
	done
	if [[ -z "$ECARTS" ]]; then
		ok "les neuf couleurs de l'installateur sont EXACTEMENT celles de ui.css"
	else
		non "l'installateur ne porte plus la palette du bureau :$ECARTS"
	fi
else
	non "ui.css introuvable — la palette de référence n'a pas pu être lue"
fi

# =============================================================================
titre "7. La feuille de style : aucune couleur en dehors de la palette"
# =============================================================================
#  Une couleur écrite en dur dans le QSS ne suivra jamais un changement
#  d'accent, et personne ne la retrouvera. On extrait tous les codes de
#  couleur du fichier PRODUIT et on exige que chacun soit l'un des neuf.
PALETTE="$(sed -n 's/^LEX_[A-Z_]*="\(#[0-9A-Fa-f]*\)".*/\1/p' "$HOOK" | maj | sort -u)"
TROUVEES="$(grep -oE '#[0-9A-Fa-f]{6}' "$QSS" | maj | sort -u)"
INTRUS=""
while IFS= read -r C; do
	[[ -z "$C" ]] && continue
	grep -qx "$C" <<< "$PALETTE" || INTRUS="$INTRUS $C"
done <<< "$TROUVEES"
if [[ -z "${INTRUS// }" ]]; then
	ok "les $(printf '%s\n' "$TROUVEES" | grep -c .) couleurs du QSS sortent toutes de la palette"
else
	non "couleurs écrites en dur dans le QSS, hors palette :$INTRUS"
fi

#  ═══ JAMAIS UNE COULEUR DE TEXTE SANS SON FOND ═══
#  lexos-install lance « sudo -E calamares » : selon la configuration de sudo,
#  le thème Qt sombre de la session suit ou ne suit pas. S'il ne suit pas,
#  Calamares se peint avec la palette Qt par défaut, qui est CLAIRE — et un
#  texte blanc posé dessus est invisible. C'est la panne du bandeau, dans
#  l'autre sens. La toute première règle doit donc poser les DEUX.
PREMIERE="$(sed -n '/^QWidget {/,/^}/p' "$QSS")"
#  ═══ « color: » EST CONTENU DANS « background-color: » ═══
#  Le premier jet cherchait « color: » tel quel : il trouvait la ligne
#  « background-color: #000000 » et se déclarait content d'une règle qui
#  n'avait AUCUNE couleur de texte. La mutation qui retirait le texte est
#  restée verte. On ancre donc en début de ligne.
if grep -qE '^[[:space:]]*background-color:' <<< "$PREMIERE" \
&& grep -qE '^[[:space:]]*color:' <<< "$PREMIERE"; then
	ok "la règle QWidget pose le fond ET le texte — rien ne retombe sur la palette Qt"
else
	non "la règle QWidget ne pose pas les deux : sur un thème Qt clair, l'installateur redevient illisible"
fi

#  ═══ LES IDENTIFIANTS VISÉS EXISTENT VRAIMENT ═══
#  Même piège que les quatre clés du bandeau : un « #sidebarapp » mal
#  orthographié ne fait rien échouer, il ne peint simplement rien. Les seuls
#  objectName présents dans le binaire livré sont ceux-là.
printf '%s\n' mainApp sidebarApp sidebarMenuApp logoApp backgroundWidget \
                aboutButton debugButton crashButton > "$BANC/connus.txt"
IDS="$(grep -oE '^#[A-Za-z]+' "$QSS" | tr -d '#' | sort -u)"
FANTOMES=""
while IFS= read -r I; do
	[[ -z "$I" ]] && continue
	grep -qx "$I" "$BANC/connus.txt" || FANTOMES="$FANTOMES $I"
done <<< "$IDS"
if [[ -z "${FANTOMES// }" ]]; then
	ok "les identifiants visés par le QSS existent tous dans Calamares"
else
	non "identifiants inconnus de Calamares (ils ne peindront RIEN) :$FANTOMES"
fi

#  Un QSS mal fermé est ignoré en bloc par Qt, sans un mot.
OUV="$(grep -o '{' "$QSS" | wc -l)"; FER="$(grep -o '}' "$QSS" | wc -l)"
if [[ "$OUV" -eq "$FER" && "$OUV" -gt 0 ]]; then
	ok "les accolades du QSS s'équilibrent ($OUV blocs)"
else
	non "accolades déséquilibrées ($OUV ouvrantes, $FER fermantes) — Qt ignorerait TOUTE la feuille"
fi

# =============================================================================
titre "8. La fenêtre et le diaporama"
# =============================================================================
TAILLE="$(sed -n 's/^windowSize:[[:space:]]*//p' "$DESC" | head -1)"
LARG="${TAILLE%%px,*}"; HAUT="${TAILLE##*,}"; HAUT="${HAUT%px}"
if [[ "$LARG" -ge 900 && "$HAUT" -ge 600 ]]; then
	ok "la fenêtre fait ${LARG}x${HAUT} — la page du partitionnement tient sans défiler"
else
	non "la fenêtre est revenue à ${TAILLE} : le partitionnement se défile, et c'est la page qui ne pardonne pas"
fi
#  ET ELLE DOIT TENIR SUR LE PLUS PETIT ÉCRAN VISÉ : 1366x768. Une fenêtre
#  plus haute que l'écran cache ses propres boutons de navigation.
if [[ "$HAUT" -le 720 ]]; then
	ok "…et elle tient sur un écran de 768 px de haut, barres comprises"
else
	non "${HAUT} px de haut : sur un écran 1366x768, les boutons du bas sortiraient de l'écran"
fi

NBS="$(grep -c 'Slide {' "$QML")"
if [[ "$NBS" -eq 4 ]]; then
	ok "le diaporama porte les quatre écrans"
else
	non "le diaporama porte $NBS écran(s) au lieu de 4"
fi

#  ═══ LE CHIFFRE DE LA DIAPOSITIVE DOIT ÊTRE LE VRAI ═══
#  Une ISO se grave, et son diaporama ne se corrige plus. Annoncer « treize
#  sections » — le chiffre de la maquette — alors que les Paramètres en
#  déclarent trente-six, c'est mentir à chaque installation.
APP="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
if command -v node >/dev/null 2>&1 && [[ -r "$APP" ]]; then
	cat > "$BANC/compte.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8") + "\n;globalThis.__nav = NAV;\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}}, addEventListener(){} },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
let n = 0; for (const g of bac.__nav) n += g.items.length;
console.log(n);
JS
	VRAI="$(node "$BANC/compte.js" "$APP" 2>/dev/null)"
	#  « Trente-sept » depuis que la page « Formater un support » existe.
	#  Le banc COMPTE les sections et compare : c'est le nombre qui décide,
	#  pas le mot — on ajoute seulement le mot à la liste reconnue.
	MOTS="$(grep -oE 'Trente-sept|Trente-six|Treize|Vingt|Quarante' "$QML" | head -1)"
	if [[ "$VRAI" == "37" && "$MOTS" == "Trente-sept" ]]; then
		ok "la diapositive dit « Trente-sept sections », et il y en a bien 37"
	elif [[ -z "$VRAI" ]]; then
		saut "les sections n'ont pas pu être comptées — le chiffre du diaporama n'est pas éprouvé"
	else
		non "le diaporama annonce « $MOTS » alors que les Paramètres déclarent $VRAI sections — corrigez la diapositive"
	fi
else
	saut "node ou app.js absent : le chiffre du diaporama n'est pas éprouvé"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[[ "$ECHOUES" -eq 0 ]]
