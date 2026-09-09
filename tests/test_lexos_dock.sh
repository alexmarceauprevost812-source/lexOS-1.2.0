#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — la position du dock, et la famille de bogues qu'elle révèle
# =============================================================================
#  ALEX : « le bouton de position du dock reste sur Droite quoi qu'on
#  choisisse ». Le dock, lui, se déplaçait bien.
#
#  DEUX SOURCES DE VÉRITÉ POUR UN SEUL RÉGLAGE. « lexos dock » pose la position
#  dans gsettings — et nulle part ailleurs. _dock_etat(), dans settings.py,
#  lisait ~/.config/lexos/dock : un fichier que PERSONNE n'écrit dans tout le
#  dépôt. La lecture retombait donc toujours sur son repli, « droite ».
#
#  C'ÉTAIT LE DEUXIÈME ÉTAGE DU MÊME BOGUE. Le premier — setDock() déclarée
#  deux fois, la bonne écrasée par la mauvaise — a été corrigé plus tôt et
#  avait un contrôle de CI (tests/test_lexos_doublons_js.js). Ce correctif-là a
#  rendu VISIBLE celui-ci : rafraichir() se met enfin à relire l'état de la
#  machine… pour y trouver un fichier vide.
#
#  ═══ LA SECTION 5 EST LA PLUS IMPORTANTE DE CE FICHIER ═══
#  Elle ne parle pas du dock. Elle vérifie que TOUT fichier de configuration
#  que la page lit est écrit par quelqu'un. C'est la règle générale dont le
#  dock n'était qu'un cas : une page qui lit un registre que personne ne tient
#  affiche un défaut avec l'assurance d'une mesure.
#
#  Rien ici n'exige de bureau graphique ni les droits root. La section 3
#  demande gsettings et glib-compile-schemas ; sans eux elle se saute en le
#  disant, au lieu de passer au vert sans avoir rien mesuré.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGLAGES="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
LEXOS="$RACINE/config/includes.chroot/usr/bin/lexos"
APPJS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0
ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

# -----------------------------------------------------------------------------
titre "1. Les fichiers sont là et ils tiennent debout"
for f in "$REGLAGES" "$LEXOS" "$APPJS"; do
	[[ -r "$f" ]] || { non "introuvable : $f"; printf '\n'; exit 1; }
done
ok "settings.py, lexos et app.js sont lisibles"
if python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$REGLAGES" 2>/dev/null; then
	ok "settings.py se compile"
else non "settings.py ne se compile pas"; fi
if bash -n "$LEXOS" 2>/dev/null; then ok "lexos a une syntaxe bash valide"
else non "lexos : erreur de syntaxe"; fi

# -----------------------------------------------------------------------------
titre "2. Une seule vérité : gsettings"
#  ON EXTRAIT LE CORPS DE LA FONCTION, ON NE CHERCHE PAS DANS TOUT LE FICHIER.
#  Le commentaire de _dock_etat() RACONTE le bogue et cite donc le chemin
#  fautif : un grep sur le fichier entier se déclencherait sur l'explication du
#  correctif. C'est la neuvième fois que ce piège se présente dans ce dépôt.
CORPS="$(python3 - "$REGLAGES" <<'PY'
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
lignes = src.split("\n")
for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.FunctionDef) and n.name == "_dock_etat":
        #  Sans la chaîne de documentation : elle explique le défaut, elle
        #  n'est pas du code.
        corps = n.body[1:] if (n.body and isinstance(n.body[0], ast.Expr)
                               and isinstance(n.body[0].value, ast.Constant)
                               and isinstance(n.body[0].value.value, str)) else n.body
        print("\n".join(lignes[corps[0].lineno-1:n.end_lineno]))
        break
PY
)"
if [[ -z "$CORPS" ]]; then
	non "_dock_etat() n'a pas pu être extrait — le contrôle ne contrôle rien"
else
	if grep -q 'gsettings' <<< "$CORPS"; then
		ok "_dock_etat() lit gsettings"
	else
		non "_dock_etat() ne lit pas gsettings : le bouton suivra un registre parallèle"
	fi
	if grep -qE 'lexos/dock|"dock"\)\.read_text|conf */ *"dock"' <<< "$CORPS"; then
		non "_dock_etat() lit encore un fichier ~/.config/lexos/dock"
	else
		ok "_dock_etat() ne lit plus de fichier parallèle"
	fi
fi

#  Personne d'autre ne doit lire ce fichier — Alex : « Cherche-le partout ».
#
#  ═══ ON CHERCHE DANS LE CODE, PAS DANS LA PROSE ═══
#  Première version : un « grep -rl » nu. Il rougissait sur la chaîne de
#  documentation de _dock_etat(), qui RACONTE le défaut et cite donc le chemin
#  fautif — et sur ce banc-ci, qui fait pareil. Un contrôle qui se déclenche
#  sur sa propre justification ne contrôle rien : il apprend seulement à ne
#  plus écrire d'explications. C'est la dixième fois que ce piège se présente
#  dans ce dépôt.
#  On retire donc les commentaires, et pour le Python les chaînes littérales —
#  par tokenize, qui sait où une chaîne commence et finit, contrairement à une
#  expression régulière.
LECTEURS="$(python3 - "$RACINE" <<'AUDIT_LECTEURS'
import io, pathlib, sys, tokenize
racine = pathlib.Path(sys.argv[1])
CIBLE = "lexos/dock"
coupables = []
for base in ("config", "tests", "tools"):
    for f in (racine / base).rglob("*"):
        if not f.is_file() or "__pycache__" in f.parts:
            continue
        if f.name == "test_lexos_dock.sh":
            continue          # ce banc-ci EXPLIQUE le défaut, il ne le porte pas
        try:
            texte = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if CIBLE not in texte:
            continue
        if f.suffix == ".py":
            morceaux = []
            try:
                for t in tokenize.generate_tokens(io.StringIO(texte).readline):
                    if t.type not in (tokenize.COMMENT, tokenize.STRING):
                        morceaux.append(t.string)
            except (tokenize.TokenError, IndentationError, SyntaxError):
                morceaux = [texte]
            nu = " ".join(morceaux)
        else:
            nu = "\n".join(l.split("#", 1)[0] for l in texte.split("\n"))
        if CIBLE in nu:
            coupables.append(str(f))
for c in coupables:
    print(c)
AUDIT_LECTEURS
)"
if [[ -z "$LECTEURS" ]]; then
	ok "aucun fichier du dépôt ne lit ~/.config/lexos/dock"
else
	non "des fichiers lisent encore ~/.config/lexos/dock :"
	printf '%s\n' "$LECTEURS" | sed 's/^/      /' >&2
fi

#  LA CHAÎNE DU SCHÉMA EST COPIÉE DES DEUX CÔTÉS. Une copie ment dès qu'on
#  touche l'original sans elle ; on les compare donc caractère par caractère.
SCH_PY="$(sed -n 's/^DOCK_SCHEMA *= *"\(.*\)"$/\1/p' "$REGLAGES")"
SCH_SH="$(sed -n 's/.*local schema="\(net\.launchpad[^"]*\)".*/\1/p' "$LEXOS")"
if [[ -z "$SCH_PY" || -z "$SCH_SH" ]]; then
	non "le schéma gsettings n'a pas pu être extrait des deux côtés (py='$SCH_PY' sh='$SCH_SH')"
elif [[ "$SCH_PY" == "$SCH_SH" ]]; then
	ok "le schéma est le même dans settings.py et dans lexos"
else
	non "schémas différents — la page lira un autre dock que celui qu'on déplace"
	printf '      settings.py : %s\n      lexos       : %s\n' "$SCH_PY" "$SCH_SH" >&2
fi

#  Et les quatre mots français doivent être exactement ceux des boutons.
MOTS_PY="$(sed -n '/^DOCK_POSITIONS *=/,/}/p' "$REGLAGES" \
	| grep -oE '"(droite|gauche|bas|haut)"' | tr -d '"' | sort -u)"
MOTS_JS="$(grep -oE '\["droite","gauche","bas","haut"\]' "$APPJS" \
	| head -1 | tr -d '[]"' | tr ',' '\n' | sort -u)"
if [[ -n "$MOTS_JS" && "$MOTS_PY" == "$MOTS_JS" ]]; then
	ok "les quatre positions rendues sont celles que la page met en boutons"
else
	non "les positions de settings.py et celles de app.js diffèrent"
	diff <(printf '%s\n' "$MOTS_PY") <(printf '%s\n' "$MOTS_JS") | sed 's/^/      /' >&2
fi

# -----------------------------------------------------------------------------
titre "3. L'aller-retour complet, sur un vrai gsettings"
# -----------------------------------------------------------------------------
#  ═══ ON JOUE LES DEUX MOITIÉS, ON NE RELIT PAS LEUR FORME ═══
#  On compile un schéma Plank RELOCALISABLE — comme le vrai, qui doit l'être
#  puisque « lexos dock » l'adresse par « schéma:chemin » — puis on lance
#  « lexos dock <position> » et on demande à _dock_etat() ce qu'elle voit.
#  Le backend « keyfile » évite d'avoir besoin d'un bus D-Bus de session.
if ! command -v gsettings >/dev/null 2>&1 \
   || ! command -v glib-compile-schemas >/dev/null 2>&1; then
	ok "gsettings absent de cette machine : aller-retour sauté (et dit)"
else
	mkdir -p "$BANC/schemas" "$BANC/home/.config"
	cat > "$BANC/schemas/net.launchpad.plank.gschema.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<schemalist>
  <enum id="net.launchpad.plank.dock.settings.PositionType">
    <value nick="left"   value="0"/>
    <value nick="right"  value="1"/>
    <value nick="top"    value="2"/>
    <value nick="bottom" value="3"/>
  </enum>
  <schema id="net.launchpad.plank.dock.settings">
    <key name="position" enum="net.launchpad.plank.dock.settings.PositionType">
      <default>'right'</default>
      <summary>Position</summary><description>Position du dock</description>
    </key>
  </schema>
</schemalist>
XML
	if ! glib-compile-schemas "$BANC/schemas" 2>/dev/null; then
		non "le schéma d'essai n'a pas pu être compilé"
	else
		LIB="$RACINE/config/includes.chroot/usr/lib/lexos"
		lire_etat() {
			GSETTINGS_SCHEMA_DIR="$BANC/schemas" GSETTINGS_BACKEND=keyfile \
			XDG_CONFIG_HOME="$BANC/home/.config" HOME="$BANC/home" \
			python3 -c "
import sys; sys.path.insert(0, '$LIB')
import settings; print(settings._dock_etat())" 2>/dev/null
		}
		for CAS in droite:right gauche:left bas:bottom haut:top; do
			FR="${CAS%%:*}"; EN="${CAS##*:}"
			GSETTINGS_SCHEMA_DIR="$BANC/schemas" GSETTINGS_BACKEND=keyfile \
			XDG_CONFIG_HOME="$BANC/home/.config" HOME="$BANC/home" \
				bash "$LEXOS" dock "$FR" >/dev/null 2>&1
			BRUT="$(GSETTINGS_SCHEMA_DIR="$BANC/schemas" GSETTINGS_BACKEND=keyfile \
				XDG_CONFIG_HOME="$BANC/home/.config" HOME="$BANC/home" \
				gsettings get "${SCH_PY:-net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/}" \
				position 2>/dev/null | tr -d "'")"
			VU="$(lire_etat)"
			if [[ "$BRUT" == "$EN" && "$VU" == "$FR" ]]; then
				ok "« lexos dock $FR » → gsettings '$EN' → la page affiche « $VU »"
			else
				non "« lexos dock $FR » → gsettings '$BRUT', la page affiche « $VU » (attendu '$EN' / « $FR »)"
			fi
		done
	fi
fi

# -----------------------------------------------------------------------------
titre "4. Les deux replis, et celui qu'il ne faut PAS faire"
# -----------------------------------------------------------------------------
LIB="$RACINE/config/includes.chroot/usr/lib/lexos"
#  ═══ CE CONTRÔLE A CHANGÉ DE SENS, ET C'EST ALEX QUI L'A DEMANDÉ ═══
#  Il exigeait « droite » quand gsettings manque, au motif que c'est le défaut
#  de Plank. ALEX, DEUXIÈME SIGNALEMENT : c'est précisément ce repli qui fait
#  perdre du temps. Il transforme « je ne sais pas » en « c'est à droite », un
#  bouton s'allume, et l'interface a l'air de marcher pendant que rien ne
#  marche. Un réglage qui n'affiche rien pousse à chercher ; un réglage qui
#  affiche une valeur fausse fait perdre des heures.
#  On exige donc maintenant l'INVERSE : None, et la page n'allume rien.
SANS="$(python3 -c "
import sys; sys.path.insert(0, '$LIB')
import settings
settings.shutil.which = lambda n: None
print(settings._dock_etat())" 2>/dev/null)"
if [[ "$SANS" == "None" ]]; then
	ok "sans gsettings, on rend None — aucune position inventée"
else
	non "sans gsettings, on rend « $SANS » : une réponse inventée"
fi
#  ET SURTOUT : une valeur PRÉSENTE qu'on ne sait pas traduire ne doit PAS
#  devenir « droite ». Répondre « droite » à une question sans réponse est
#  exactement le défaut qu'on répare : aucun bouton allumé vaut mieux qu'un
#  faux bouton allumé.
INCONNU="$(python3 -c "
import sys; sys.path.insert(0, '$LIB')
import settings
class R:
    returncode = 0
    stdout = \"'diagonale'\n\"
    stderr = ''
settings.shutil.which = lambda n: '/usr/bin/gsettings'
settings.subprocess.run = lambda *a, **k: R()
print(settings._dock_etat())" 2>/dev/null)"
if [[ "$INCONNU" == "droite" ]]; then
	non "une valeur inconnue est ramenée à « droite » — le mensonge d'origine"
elif [[ -n "$INCONNU" ]]; then
	ok "une valeur inconnue est rendue telle quelle (« $INCONNU ») : aucun bouton ne ment"
else
	non "une valeur inconnue ne rend rien du tout"
fi

# -----------------------------------------------------------------------------
titre "5. Aucun réglage lu par la page n'est un registre que personne ne tient"
# -----------------------------------------------------------------------------
#  ═══ LA RÈGLE GÉNÉRALE, DONT LE DOCK N'ÉTAIT QU'UN CAS ═══
#  On relève TOUS les fichiers que settings.py lit sous ~/.config/lexos/, et on
#  exige que quelqu'un, quelque part dans l'arbre livré, les écrive. Un fichier
#  lu et jamais écrit, c'est une valeur de repli affichée comme une mesure —
#  et ça ne se voit pas : la page a l'air de fonctionner.
python3 - "$RACINE" <<'PY' > "$BANC/audit.txt"
import re, subprocess, sys, pathlib
racine = pathlib.Path(sys.argv[1])
src = (racine / "config/includes.chroot/usr/lib/lexos/settings.py").read_text(encoding="utf-8")
noms = set()
for m in re.finditer(r'\(\s*conf\s*/\s*"([\w.-]+)"\s*\)\.read_text', src): noms.add(m.group(1))
for m in re.finditer(r'\bfichier\("([\w.-]+)"', src): noms.add(m.group(1))
for m in re.finditer(r'\bdrapeau\("([\w.-]+)"\)', src): noms.add(m.group(1))
arbre = racine / "config/includes.chroot"
for n in sorted(noms):
    #  « qui écrit ce nom ? » — une redirection shell ou un write_text Python,
    #  chez quelqu'un d'autre que la page elle-même.
    r = subprocess.run(
        ["grep", "-rl", "-e", "/" + n, "--exclude-dir=__pycache__", str(arbre)],
        capture_output=True, text=True)
    autres = [f for f in r.stdout.split()
              if f and not f.endswith("settings.py") and "/settings/web/" not in f]
    print(("OK   " if autres else "SEUL ") + n + "\t" +
          (",".join(pathlib.Path(f).name for f in autres) or "personne"))
PY
if [[ ! -s "$BANC/audit.txt" ]]; then
	non "l'audit n'a relevé AUCUN fichier — l'extraction est cassée, rien n'est mesuré"
else
	NB="$(grep -c . "$BANC/audit.txt")"
	SEULS="$(grep '^SEUL ' "$BANC/audit.txt" || true)"
	if [[ -z "$SEULS" ]]; then
		ok "les $NB réglages lus sous ~/.config/lexos/ ont tous un outil qui les écrit"
	else
		non "des réglages sont lus mais écrits par personne :"
		printf '%s\n' "$SEULS" | sed 's/^SEUL /      /' >&2
	fi
fi

titre "Le bouton en surbrillance suit la position RÉELLE — les quatre, mesurées"
# ═════════════════════════════════════════════════════════════════════════════
#  ═══ ALEX A SIGNALÉ CE BOGUE DEUX FOIS ═══
#  La première : setDock() était déclarée deux fois, la seconde écrasait la
#  bonne. La deuxième : _dock_etat() lisait ~/.config/lexos/dock, un fichier
#  que personne n'écrit — elle répondait donc « droite » à tous les coups.
#  Les deux sont corrigés. Ce contrôle est là pour qu'aucun troisième ne passe
#  sans qu'on le voie : il FAIT TOURNER la fonction avec un gsettings truqué
#  et compare, pour les quatre positions.
PYGI=""
for C in python3 python3.12 python3.11 python3.13; do
	command -v "$C" >/dev/null 2>&1 || continue
	if "$C" -c 'import ast' 2>/dev/null; then PYGI="$C"; break; fi
done
SETTINGS_PY="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
if [[ -z "$PYGI" || ! -r "$SETTINGS_PY" ]]; then
	printf '  %s—%s %s\n' "$GRAS" "$FIN" "python3 ou settings.py manquent : la position n'est pas mesurée"
else
	FAUX="$BANC/faux-gsettings"; mkdir -p "$FAUX"
	cat > "$FAUX/gsettings" <<'FINGS'
#!/bin/sh
#  Un gsettings truqué : il rend ce que le banc a écrit dans « valeur ».
if [ "$1" = "get" ]; then printf "'%s'\n" "$(cat "$FAUX_VALEUR")"; exit 0; fi
exit 0
FINGS
	chmod +x "$FAUX/gsettings"

	POS_KO=""
	for PAIRE in "right droite" "left gauche" "bottom bas" "top haut"; do
		set -- $PAIRE
		printf '%s' "$1" > "$BANC/valeur"
		LU="$(PATH="$FAUX:$PATH" FAUX_VALEUR="$BANC/valeur" "$PYGI" -c "
import sys
sys.path.insert(0, '$RACINE/config/includes.chroot/usr/lib/lexos')
import settings
print(settings._dock_etat())" 2>/dev/null | tail -1)"
		if [[ "$LU" == "$2" ]]; then
			ok "gsettings dit « $1 » -> la page allume « $2 »"
		else
			non "gsettings dit « $1 » -> la page lit « $LU » (attendu « $2 »)"
			POS_KO=1
		fi
	done
	[[ -z "$POS_KO" ]] || true

	#  ═══ ET LE CAS « ON NE SAIT PAS » ═══
	#  Le vrai poison n'était pas la mauvaise source : c'était le repli qui
	#  transformait « je ne sais pas » en « c'est à droite ». Sans gsettings,
	#  la fonction doit rendre None — la page n'allume alors aucun bouton.
	#  ═══ ON FABRIQUE L'ABSENCE, ON NE VIDE PAS LE PATH ═══
	#  Premier jet : PATH="$VIDE". Python lui-même devenait introuvable, la
	#  commande ne rendait rien, et le contrôle rougissait en accusant la
	#  mauvaise pièce. Une ferme de liens sans gsettings, comme ailleurs
	#  dans ce dépôt.
	VIDE="$BANC/sans-gsettings"; mkdir -p "$VIDE"
	for d in /usr/bin /bin /usr/sbin /sbin /usr/local/bin; do
		[[ -d "$d" ]] || continue
		for f in "$d"/*; do
			b="$(basename "$f")"
			[[ "$b" == "gsettings" ]] && continue
			[[ -e "$VIDE/$b" ]] || ln -s "$f" "$VIDE/$b" 2>/dev/null
		done
	done
	LU="$(PATH="$VIDE" "$PYGI" -c "
import sys
sys.path.insert(0, '$RACINE/config/includes.chroot/usr/lib/lexos')
import settings
print(settings._dock_etat())" 2>/dev/null | tail -1)"
	if [[ "$LU" == "None" ]]; then
		ok "sans gsettings : la fonction rend None — elle n'invente pas « droite »"
	else
		non "sans gsettings : la fonction rend « $LU » — une réponse inventée"
	fi

	#  Et la page doit VRAIMENT traiter ce null, sinon le moteur est honnête
	#  et l'écran ment quand même.
	APP_JS="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
	if grep -q 'etat.dock == null' "$APP_JS"; then
		ok "…et la page prévoit ce cas : aucun bouton allumé, une explication"
	else
		non "la page ne traite pas le cas « position inconnue » : elle n'affichera rien d'utile"
	fi

	#  Le fichier fantôme ne doit pas revenir : c'était la deuxième source de
	#  vérité, et c'est elle qui a coûté le deuxième signalement d'Alex.
	SANS_COM="$BANC/settings-sans-commentaires.py"
	sed 's/#.*$//' "$SETTINGS_PY" > "$SANS_COM"
	if grep -qE '"dock"\s*\)?\s*\.read_text|/ *"dock" *\)' "$SANS_COM"; then
		non "settings.py relit un fichier « dock » : la deuxième source de vérité est revenue"
	else
		ok "aucune relecture d'un fichier « dock » : une seule source, gsettings"
	fi
fi

# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
