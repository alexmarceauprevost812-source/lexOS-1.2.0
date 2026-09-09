#!/usr/bin/env bash
# =============================================================================
#  Éprouver les UTILISATEURS — la page qui affichait des comptes inventés
# =============================================================================
#  ALEX : « le contenu comme Ubuntu ». La page « Utilisateurs » d'Ubuntu
#  permet d'ajouter un compte, de le renommer, de donner ou retirer les droits
#  d'administrateur, de changer le mot de passe, d'allumer la connexion
#  automatique. Ici : une liste, et une phrase disant d'aller au terminal.
#
#  ET LA LISTE ELLE-MÊME MENTAIT DE DEUX FAÇONS.
#
#  1. LE BOUTON « Détail » imprimait deux comptes ÉCRITS EN DUR dans
#     settings.py — « lex — Principal, administrateur » et « invite ». Pas
#     lus, pas vérifiés. Sur la machine d'Alex, aucun des deux n'existe.
#
#  2. LA DÉFINITION D'« ADMINISTRATEUR » N'ÉTAIT PAS LA NÔTRE. La page
#     comptait sudo, wheel OU adm. Or « adm » ne donne que la lecture des
#     journaux : quelqu'un qui n'est que dans « adm » s'affichait
#     « administrateur » sans pouvoir lancer un seul sudo.
#
#  CE BANC INVENTE UNE MACHINE — son /etc/passwd, son /etc/group, l'état de
#  ses mots de passe — et fait tourner l'outil dessus. C'est la seule façon
#  d'éprouver « le dernier administrateur », « c'est toi » ou un nom complet
#  avec des guillemets : aucune de ces situations n'existe sur la machine qui
#  fait tourner le banc, et un banc qui attend qu'elles arrivent n'éprouve rien.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTIL="$RACINE/config/includes.chroot/usr/bin/lexos-utilisateurs"
MOTEUR="$RACINE/config/includes.chroot/usr/lib/lexos/settings.py"
PAGE="$RACINE/config/includes.chroot/usr/share/lexos/settings/web/app.js"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

REUSSIS=0; ECHOUES=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  \033[31m❌\033[0m %s\n' "$1"; ECHOUES=$((ECHOUES+1)); }
saute(){ printf '  \033[33m•\033[0m %s\n' "$1"; }
titre(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

for F in "$OUTIL" "$MOTEUR" "$PAGE"; do
	[ -r "$F" ] || { echo "introuvable : $F"; exit 1; }
done

# =============================================================================
#  LA MACHINE INVENTÉE
# =============================================================================
#  Chaque compte y est là pour une raison précise :
#
#    banc-alex .... groupe PRINCIPAL sudo. Administrateur SANS figurer dans la
#                   liste des membres du groupe — le cas qui, oublié, ferait
#                   compter zéro administrateur là où il y en a un.
#    banc-marie ... membre de sudo, et son mot de passe est VERROUILLÉ.
#    banc-jo ...... dans « adm » SEULEMENT : c'est lui que l'ancienne page
#                   appelait « administrateur » à tort. Et il n'a AUCUN mot
#                   de passe.
#    banc-bloque .. UID 1003 mais shell nologin : l'ancienne règle des
#                   Paramètres l'écartait, celle de l'outil le garde. Deux
#                   listes de comptes possibles pour la même machine — c'est
#                   exactement ce qu'on vient de supprimer.
#    banc-serveur . UID 998, et « nobody » 65534 : ni l'un ni l'autre n'est
#                   quelqu'un qui s'assoit devant la machine.
#
#  Le nom complet de banc-alex porte des guillemets et un antislash. Un seul
#  guillemet non échappé, et la page reste blanche sans message.
mkdir -p "$BANC/bin"
cat > "$BANC/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
banc-serveur:x:998:998:Service du banc,,,:/srv:/usr/sbin/nologin
banc-alex:x:1000:27:Alex "le grand" \ Prevost,,,:/home/banc-alex:/bin/bash
banc-marie:x:1001:1001:Marie Tremblay,,,:/home/banc-marie:/bin/bash
banc-jo:x:1002:1002::/home/banc-jo:/bin/bash
banc-bloque:x:1003:1003:Compte bloque,,,:/home/banc-bloque:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
PASSWD
cat > "$BANC/group" <<'GROUP'
root:x:0:
adm:x:4:banc-jo
sudo:x:27:banc-marie
banc-marie:x:1001:
banc-jo:x:1002:
banc-bloque:x:1003:
GROUP
cat > "$BANC/shadow-etat" <<'ETAT'
banc-alex P
banc-marie L
banc-jo NP
ETAT

#  LES OUTILS DU SYSTÈME, REMPLACÉS PAR DES DOUBLURES qui lisent ces
#  fichiers-là. On ne touche évidemment pas au vrai /etc/passwd.
cat > "$BANC/bin/getent" <<'SH'
#!/bin/sh
f="${BANC_DECOR:?}/$1"
[ -r "$f" ] || exit 2
if [ -n "${2:-}" ]; then grep "^$2:" "$f" || exit 2; else cat "$f"; fi
SH
cat > "$BANC/bin/id" <<'SH'
#!/bin/sh
P="${BANC_DECOR:?}/passwd"; G="${BANC_DECOR}/group"
case "$1" in
  -u)  awk -F: -v n="$2" '$1==n {print $3; f=1} END{exit !f}' "$P" ;;
  -un) printf '%s\n' "${BANC_MOI:-banc-alex}" ;;
  -nG) n="$2"
       gid="$(awk -F: -v n="$n" '$1==n {print $4}' "$P")"
       { awk -F: -v g="$gid" '$3==g {print $1}' "$G"
         awk -F: -v n="$n" '{split($4,m,","); for(i in m) if(m[i]==n) print $1}' "$G"
       } | sort -u | tr '\n' ' ' ;;
  *) exit 1 ;;
esac
SH
cat > "$BANC/bin/passwd" <<'SH'
#!/bin/sh
[ "$1" = "-S" ] || exit 1
awk -v n="$2" '$1==n {print n" "$2" 01/01/2026 0 99999 7 -1"; f=1} END{exit !f}' \
	"${BANC_DECOR:?}/shadow-etat"
SH
cat > "$BANC/bin/lastlog" <<'SH'
#!/bin/sh
printf 'Username         Port     From             Latest\n'
printf '%s                                          **Never logged in**\n' "${2:-}"
SH
#  LE TERMINAL AUSSI EST UNE DOUBLURE, et c'est LUI le témoin principal de la
#  section 3 : tous les gestes sur les comptes s'y déroulent, et ce qu'on veut
#  prouver, c'est la LIGNE DE COMMANDE exacte qui y part.
cat > "$BANC/bin/xfce4-terminal" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "${BANC_TRACE:?}"
printf -- '---\n' >> "$BANC_TRACE"
SH
chmod +x "$BANC/bin"/*
: > "$BANC/trace"

#  ═══ LightDM VIENT DU DÉCOR, PAS DE LA MACHINE ═══
#  Ce banc vérifie que « connexion automatique » ouvre un terminal avec la
#  bonne commande. L'outil refuse ce geste quand LightDM n'est pas là — et il
#  a raison. Mais le banc lisait le VRAI /etc/lightdm : présent sur la machine
#  de développement, ABSENT sur le coureur de la CI. Vert ici, ROUGE là-bas,
#  et c'est exactement ce qui est arrivé à la construction de l'ISO 105.
#  Un banc qui mesure la machine n'éprouve pas le dépôt.
mkdir -p "$BANC/etc/lightdm"
printf '[Seat:*]\n' > "$BANC/etc/lightdm/lightdm.conf"
export LEXOS_LIGHTDM_CONF="$BANC/etc/lightdm/lightdm.conf"

export BANC_DECOR="$BANC" BANC_TRACE="$BANC/trace"
CHEMIN="$BANC/bin:$RACINE/config/includes.chroot/usr/bin:$PATH"
lexutil() { PATH="$CHEMIN" bash "$OUTIL" "$@"; }

# =============================================================================
titre "1. « --json » — les comptes, tels que l'outil les voit"
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : le JSON n'a PAS été éprouvé"
	ETAT=""
else
	ETAT="$(lexutil --json 2>/dev/null)"
	printf '%s' "$ETAT" > "$BANC/etat.json"
	if printf '%s' "$ETAT" | python3 -m json.tool >/dev/null 2>&1; then
		ok "« lexos-utilisateurs --json » rend du JSON valide"
	else
		non "« --json » ne rend pas du JSON valide :\\n$ETAT"
		ETAT=""
	fi
fi

if [ -n "$ETAT" ]; then
	#  « root » décide de ce qu'on peut exiger de l'état des mots de passe :
	#  il se lit dans /etc/shadow. Hors root, l'outil doit dire « inconnu »
	#  PLUTÔT QUE D'INVENTER — un compte verrouillé qu'on croit ouvert, c'est
	#  une porte qu'on pense fermée. Les deux branches éprouvent donc quelque
	#  chose ; aucune n'est un laissez-passer.
	LU="$(python3 - "$BANC/etat.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
c = {x["nom"]: x for x in d.get("comptes", [])}
noms = list(c)
print("NOMS", "oui" if noms == ["banc-alex", "banc-marie", "banc-jo", "banc-bloque"]
      else "NON:%s" % noms)
print("SERVICE", "oui" if not ({"root", "daemon", "nobody", "banc-serveur"} & set(noms))
      else "NON")
#  L'ANTISLASH ET LES GUILLEMETS, CARACTÈRE POUR CARACTÈRE.
print("ECHAPPE", "oui" if c.get("banc-alex", {}).get("complet") == 'Alex "le grand" \\ Prevost'
      else "NON:%r" % c.get("banc-alex", {}).get("complet"))
#  LE GROUPE PRINCIPAL COMPTE : banc-alex n'est PAS dans la liste des membres
#  de sudo, sudo est son groupe principal. L'oublier ferait compter un
#  administrateur de moins, et la protection du dernier sauterait au pire moment.
print("PRINCIPAL", "oui" if c.get("banc-alex", {}).get("admin") else "NON")
#  ET « adm » N'EST PAS « administrateur » : c'est l'erreur exacte de
#  l'ancienne page.
print("ADM", "oui" if c.get("banc-jo", {}).get("admin") is False else "NON")
print("NBADMIN", d.get("nb_admins"))
print("MOI", "oui" if (c.get("banc-alex", {}).get("moi") and
                       not c.get("banc-marie", {}).get("moi")) else "NON")
print("ROOT", "oui" if d.get("root") else "non")
print("VERROUS", ",".join("%s=%s" % (n, c[n].get("verrou")) for n in noms))
print("REGEX", d.get("nom_regex", ""))
PY
)"
	dit() { case "$LU" in *"$1 oui"*) ok "$2" ;; *) non "$3 (${LU#*$1 })" ;; esac; }
	dit NOMS      "les quatre comptes de personnes sont publiés, dans l'ordre des UID" \
	              "la liste des comptes n'est pas celle attendue"
	dit SERVICE   "root, daemon, nobody et le compte de service sont écartés" \
	              "un compte de service s'est glissé dans la liste"
	dit ECHAPPE   "un nom complet à guillemets et antislash traverse le JSON intact" \
	              "le nom complet n'a pas survécu à l'échappement"
	dit PRINCIPAL "un compte dont sudo est le groupe PRINCIPAL est bien administrateur" \
	              "le groupe principal n'est pas compté : il manquerait un administrateur"
	dit ADM       "« adm » seul n'est PAS « administrateur » — l'erreur de l'ancienne page" \
	              "un compte du groupe adm est encore annoncé administrateur"
	dit MOI       "« c'est toi » désigne le compte courant, et lui seul" \
	              "« moi » ne désigne pas le bon compte"
	case "$LU" in
		*"NBADMIN 2"*) ok "deux administrateurs comptés (le membre du groupe et celui par groupe principal)" ;;
		*) non "le nombre d'administrateurs n'est pas 2 (${LU#*NBADMIN })" ;;
	esac
	case "$LU" in
		*"REGEX ^[a-z_][a-z0-9_-]*\$"*) ok "la règle des noms de compte est publiée, pas devinée" ;;
		*) non "la règle des noms n'est pas publiée telle quelle" ;;
	esac
	VER="$(printf '%s\n' "$LU" | sed -n 's/^VERROUS //p')"
	if grep -q '^ROOT oui' <<< "$LU" ; then
		ATTENDU="banc-alex=actif,banc-marie=verrouille,banc-jo=sans-mot-de-passe,banc-bloque=inconnu"
		[ "$VER" = "$ATTENDU" ] \
			&& ok "en root, l'état de chaque mot de passe est lu : $VER" \
			|| non "états de mot de passe inattendus : $VER"
	else
		case "$VER" in
			*actif*|*verrouille*|*sans-mot-de-passe*)
				non "hors root, l'outil prétend connaître /etc/shadow : $VER" ;;
			*) ok "hors root, l'outil dit « inconnu » au lieu d'inventer un état" ;;
		esac
	fi
fi

# =============================================================================
titre "2. LES GESTES — la commande exacte qui part dans le terminal"
# =============================================================================
#  Tout ce qui touche aux comptes demande les droits d'administrateur, et
#  lexos-utilisateurs ne s'élève JAMAIS de lui-même. Chaque geste ouvre donc
#  un terminal où la commande est écrite en clair.
#
#  CE QUE CE BANC SURVEILLE VRAIMENT : cette commande part dans une CHAÎNE que
#  xfce4-terminal redécoupe comme un shell — au contraire de _run(), qui reçoit
#  une liste. Un nom venu de la page ne peut donc pas y entrer sans contrôle.
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : les gestes n'ont PAS été éprouvés"
else
	cat > "$BANC/gestes.py" <<'PY'
import sys, time
sys.path.insert(0, sys.argv[1])
import settings

try:
    trace = sys.argv[2]

    def lire_trace():
        try:
            return open(trace, encoding="utf-8").read()
        except OSError:
            return ""

    def derniere_commande(brut=None):
        """La commande de la DERNIÈRE fenêtre ouverte — celle qui vient de partir."""
        blocs = [b for b in (brut if brut is not None else lire_trace()).split("---\n") if b.strip()]
        if not blocs:
            return ""
        for ligne in blocs[-1].splitlines():
            if ligne.startswith("sudo "):
                return ligne
        return ""

    def geste(arg):
        """Le geste, PUIS ce qui est vraiment parti dans le terminal.

        ON ATTEND LA TRACE, ET C'EST NÉCESSAIRE. _terminal() lance la fenêtre en
        detach=True : Popen rend la main tout de suite, le processus écrit quand
        il veut. Lire le fichier dans la foulée, c'est lire AVANT l'écriture — la
        première version de ce banc a ainsi comparé chaque commande à celle du
        geste PRÉCÉDENT, et annoncé dix rouges décalés d'un cran. On attend donc
        que le fichier bouge, avec une limite : un geste refusé n'écrit rien, et
        il ne faut pas attendre une seconde pour chaque refus.
        """
        avant = lire_trace()
        r = settings.act_utilisateur(arg)
        if r.get("ok"):
            for _ in range(200):
                maintenant = lire_trace()
                if maintenant != avant and maintenant.endswith("---\n"):
                    break
                time.sleep(0.01)
        return r, derniere_commande()

    #  ═══ CE QUI DOIT PARTIR, MOT POUR MOT ═══
    for arg, attendue, quoi in (
            ("motdepasse:banc-marie",
             "sudo lexos-utilisateurs motdepasse banc-marie; bash",
             "changer un mot de passe"),
            ("admin-on:banc-jo",
             "sudo lexos-utilisateurs admin banc-jo on; bash",
             "donner les droits d'administrateur"),
            ("admin-off:banc-marie",
             "sudo lexos-utilisateurs admin banc-marie off; bash",
             "les retirer"),
            ("verrouiller:banc-jo",
             "sudo lexos-utilisateurs verrouiller banc-jo; bash",
             "verrouiller un compte"),
            ("deverrouiller:banc-marie",
             "sudo lexos-utilisateurs deverrouiller banc-marie; bash",
             "le déverrouiller"),
            ("supprimer:banc-jo",
             "sudo lexos-utilisateurs supprimer banc-jo; bash",
             "supprimer un compte"),
            ("ajouter:banc-neuf",
             "sudo lexos-utilisateurs ajouter banc-neuf; bash",
             "créer un compte"),
            ("auto:banc-marie",
             "sudo lexos-utilisateurs auto-connexion banc-marie; bash",
             "allumer la connexion automatique"),
            ("auto:off",
             "sudo lexos-utilisateurs auto-connexion off; bash",
             "l'éteindre"),
            ("nom-complet:banc-jo:Jo Tremblay",
             "sudo lexos-utilisateurs nom-complet banc-jo 'Jo Tremblay'; bash",
             "changer le nom affiché")):
        r, cmd = geste(arg)
        print(("OK|" if (r.get("ok") and cmd == attendue) else "NON|") +
              "%s → %s" % (quoi, cmd or r.get("erreur", "AUCUNE FENÊTRE")))

    #  ═══ LE TEXTE LIBRE EST CITÉ ═══
    #  Le nom affiché est le SEUL morceau de texte libre qui entre dans cette
    #  commande. On y met de quoi la casser : un point-virgule, une commande, des
    #  apostrophes. Ce qui doit en sortir, c'est UN SEUL argument cité.
    avant = derniere_commande()
    r, cmd = geste("nom-complet:banc-jo:Jo ; rm -rf / 'x'")
    attendue = ("sudo lexos-utilisateurs nom-complet banc-jo "
                "'Jo ; rm -rf / '\"'\"'x'\"'\"''; bash")
    print(("OK|" if (r.get("ok") and cmd == attendue) else "NON|") +
          "un nom affiché piégé ressort en UN argument cité (%s)" % cmd)

    #  ═══ CE QUI DOIT ÊTRE REFUSÉ, ET SANS OUVRIR DE FENÊTRE ═══
    #  Un terminal qui s'ouvre pour mourir aussitôt ressemble à une panne : le
    #  refus doit arriver AVANT, avec un motif que la page peut montrer.
    for arg, bout, quoi in (
            ("motdepasse:banc-inexistant", "n'est pas un compte", "un compte qui n'existe pas"),
            ("motdepasse:banc-serveur",    "n'est pas un compte", "un compte de service"),
            ("supprimer:root",             "n'est pas un compte", "root"),
            ("effacer:banc-jo",            "geste inattendu",     "un geste inventé"),
            ("motdepasse:",                "n'est pas un compte", "un nom vide"),
            ("ajouter:Banc-Majuscule",     "nom de compte invalide", "un nom aux majuscules"),
            ("ajouter:2banc",              "nom de compte invalide", "un nom qui commence par un chiffre"),
            ("ajouter:banc jo",            "nom de compte invalide", "un nom avec une espace"),
            ("ajouter:banc-jo",            "existe déjà",         "un nom déjà pris"),
            ("ajouter:",                   "il faut un nom",      "aucun nom"),
            ("auto:banc-inexistant",       "n'est pas un compte", "une connexion automatique pour personne"),
            ("nom-complet:banc-jo:",       "il faut un nom à afficher", "un nom affiché vide"),
            ("nom-complet:banc-inexistant:Jo", "n'est pas un compte", "renommer un compte absent")):
        avant = derniere_commande()
        r, cmd = geste(arg)
        print(("OK|" if (not r.get("ok") and bout in r.get("erreur", "") and cmd == avant)
               else "NON|") +
              "refusé sans ouvrir de fenêtre : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))

    #  ═══ LE RETOUR À LA LIGNE FINAL ═══
    #  En Python, « $ » accepte un retour à la ligne à la fin : « banc-neuf\n »
    #  passerait re.match(« ^…$ ») et se retrouverait cité dans la commande. Il
    #  faut re.fullmatch. Ce contrôle-là est la seule chose qui distingue les deux.
    avant = derniere_commande()
    r, cmd = geste("ajouter:banc-neuf\n")
    print(("OK|" if (not r.get("ok") and cmd == avant) else "NON|") +
          "un nom suivi d'un retour à la ligne est refusé (%s)" % r.get("erreur", "ACCEPTÉ !"))
except Exception as _e:
    #  UN PLANTAGE EST UN ROUGE, PAS UN SILENCE. Sans ce filet, une exception
    #  au milieu du script emporte tous les contrôles qui suivent : le banc
    #  affiche moins de coches et reste vert.
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")

PY
	SORTIE_G="$(cd "$RACINE" && PATH="$CHEMIN" \
		python3 "$BANC/gestes.py" \
		"$RACINE/config/includes.chroot/usr/lib/lexos" "$BANC/trace" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	#  LA SENTINELLE. Sans elle, un banc qui S'ARRÊTE au milieu reste VERT :
	#  les contrôles déjà écrits passent, ceux qui n'ont jamais été atteints
	#  disparaissent en silence — il y a juste moins de coches. C'est ce qui
	#  est arrivé ici : retirer la vérification du nom de compte faisait lever
	#  une KeyError au contrôle suivant, et le banc n'a rien vu du tout.
	#  Le script rend une dernière ligne « FIN| » ; son absence est un rouge.
	if [ -z "$SORTIE_G" ]; then
		non "les gestes n'ont rien rendu — le moteur n'a pas pu être appelé"
	elif ! grep -q '^FIN|' <<< "$SORTIE_G"; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_G
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in
				OK)  ok "$M" ;;
				NON) non "$M" ;;
			esac
		done <<EOF
$SORTIE_G
EOF
	fi
fi

#  ═══ ET SANS LightDM, LE GESTE EST REFUSÉ ═══
#  L'autre sens du même contrôle : un réglage qui ne s'appliquerait à rien ne
#  doit pas être offert.
#
#  ═══ « SANS LightDM » ÉTAIT SUBI, IL EST MAINTENANT FABRIQUÉ ═══
#  Ce contrôle comptait sur le coureur de la CI, qui n'a pas LightDM : il
#  passait ici en déplaçant seulement LEXOS_LIGHTDM_CONF. Mais
#  lightdm_present() (lexos-utilisateurs) répond aussi OUI si « lightdm »
#  est dans le PATH — et CHEMIN se termine par le vrai $PATH. Sur une
#  machine où LightDM est installé, le banc rougissait pour une raison qui
#  ne regarde pas le dépôt. Mesuré : installer le paquet ici suffisait à le
#  faire tomber.
#  On fabrique donc l'absence, comme ailleurs pour convert et ffmpeg : un
#  PATH de liens symboliques d'où « lightdm » est retiré. ET « LEXOS_SANS_SBIN
#  =1 » avec, parce que lexos-utilisateurs REMET /usr/sbin dans son PATH à sa
#  ligne 51 — sans ce second verrou, le farm ne servait à rien : le vrai
#  /usr/sbin/lightdm était retrouvé juste après. Mesuré, les deux sont
#  nécessaires.
SANS_LDM="$BANC/sans-lightdm-bin"
rm -rf "$SANS_LDM"; mkdir -p "$SANS_LDM"
for d in /usr/bin /bin /usr/sbin /sbin; do
	[ -d "$d" ] || continue
	for f in "$d"/*; do
		b="$(basename "$f")"
		case "$b" in lightdm) continue ;; esac
		[ -e "$SANS_LDM/$b" ] || ln -s "$f" "$SANS_LDM/$b" 2>/dev/null
	done
done
CHEMIN_SANS_LDM="$BANC/bin:$RACINE/config/includes.chroot/usr/bin:$SANS_LDM"
#  LES AFFECTATIONS VONT DANS LA SUBSTITUTION, PAS DEVANT « grep ». Une
#  substitution de processus tourne dans un sous-shell de l'environnement
#  COURANT : un préfixe « VAR=… » posé devant grep ne l'atteint JAMAIS.
#
#  Mesuré ici même, et le piège est double : la ligne 145 EXPORTE
#  LEXOS_LIGHTDM_CONF vers le décor « avec LightDM », dont le répertoire
#  existe. Préfixe mal placé → l'outil hérite de CET export, trouve le
#  répertoire, et répond « lightdm: true ». Le contrôle rougissait donc en
#  accusant la ferme de liens, qui n'y était pour rien.
if command -v python3 >/dev/null 2>&1 \
   && grep -q '"lightdm": true' \
      < <(PATH="$CHEMIN_SANS_LDM" LEXOS_SANS_SBIN=1 \
          LEXOS_LIGHTDM_CONF="$BANC/sans-lightdm/lightdm.conf" \
          bash "$OUTIL" --json 2>/dev/null); then
	non "l'absence de LightDM n'a pas pu être fabriquée : le contrôle suivant ne prouverait rien"
elif command -v python3 >/dev/null 2>&1; then
	MSG="$(cd "$RACINE" && PATH="$CHEMIN_SANS_LDM" LEXOS_SANS_SBIN=1 LEXOS_LIGHTDM_CONF="$BANC/sans-lightdm/lightdm.conf" \
		python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import settings
print(settings.act_utilisateur("auto:banc-marie").get("erreur", "ACCEPTÉ"))
' "$RACINE/config/includes.chroot/usr/lib/lexos" 2>/dev/null)"
	case "$MSG" in
		*"LightDM n'est pas installé"*)
			ok "sans LightDM, la connexion automatique est refusée avec son motif" ;;
		*) non "sans LightDM, réponse inattendue (« $MSG »)" ;;
	esac
fi

#  ═══ L'OUTIL MUET N'EST PAS L'OUTIL ABSENT ═══
#  Deux pannes différentes, deux messages. Dire « introuvable » d'un programme
#  installé envoie chercher au mauvais endroit — et c'est ce que le moteur
#  répondait dans les deux cas.
if command -v python3 >/dev/null 2>&1; then
	mkdir -p "$BANC/muet"
	printf '#!/bin/sh\nprintf "pas du json\\n"\n' > "$BANC/muet/lexos-utilisateurs"
	chmod +x "$BANC/muet/lexos-utilisateurs"
	MSG="$(cd "$RACINE" && PATH="$BANC/muet:$BANC/bin:$PATH" python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import settings
print(settings.act_utilisateur("motdepasse:banc-marie").get("erreur", ""))
' "$RACINE/config/includes.chroot/usr/lib/lexos" 2>/dev/null)"
	case "$MSG" in
		*"n'a pas répondu"*) ok "un outil présent mais muet est dit « n'a pas répondu », pas « introuvable »" ;;
		*) non "outil muet : message inattendu (« $MSG »)" ;;
	esac
	MSG="$(cd "$RACINE" && PATH="$BANC/bin:/usr/bin:/bin" python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import settings
print(settings.act_utilisateur("motdepasse:banc-marie").get("erreur", ""))
' "$RACINE/config/includes.chroot/usr/lib/lexos" 2>/dev/null)"
	case "$MSG" in
		*introuvable*) ok "et un outil absent est dit « introuvable »" ;;
		*) non "outil absent : message inattendu (« $MSG »)" ;;
	esac
fi

# =============================================================================
titre "3. LE DERNIER ADMINISTRATEUR — la seule interdiction dure"
# =============================================================================
#  Une machine sans administrateur ne se répare plus depuis le bureau : il
#  faut redémarrer en mode maintenance. lexos-utilisateurs refuse donc de
#  rétrograder, de verrouiller ou d'effacer le dernier — mais il le fait
#  APRÈS avoir ouvert une fenêtre et demandé un mot de passe. Les Paramètres
#  le disent tout de suite.
#
#  ON CHANGE LA MACHINE INVENTÉE pour n'y laisser qu'un seul administrateur :
#  banc-alex perd son groupe principal sudo, il ne reste que banc-marie.
sed 's/^banc-alex:x:1000:27:/banc-alex:x:1000:1000:/' "$BANC/passwd" > "$BANC/passwd.1"
mv "$BANC/passwd.1" "$BANC/passwd"
if ! command -v python3 >/dev/null 2>&1; then
	saute "python3 absent : la protection du dernier admin n'a PAS été éprouvée"
else
	NB="$(lexutil --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["nb_admins"])' 2>/dev/null)"
	[ "${NB:-0}" = "1" ] \
		&& ok "la machine inventée n'a plus qu'un administrateur" \
		|| non "le décor n'a pas basculé : ${NB:-?} administrateur(s), le contrôle suivant ne prouverait rien"
	cat > "$BANC/dernier.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import settings
try:
    trace = sys.argv[2]

    def nb_fenetres():
        try:
            return open(trace, encoding="utf-8").read().count("---\n")
        except OSError:
            return -1

    for arg, quoi in (("admin-off:banc-marie", "lui retirer les droits"),
                      ("verrouiller:banc-marie", "verrouiller son compte"),
                      ("supprimer:banc-marie", "le supprimer")):
        avant = nb_fenetres()
        r = settings.act_utilisateur(arg)
        print(("OK|" if (not r.get("ok") and "seul administrateur" in r.get("erreur", "")
                         and nb_fenetres() == avant) else "NON|") +
              "refusé : %s (%s)" % (quoi, r.get("erreur", "ACCEPTÉ !")))

    #  ET CE QUI RESTE PERMIS. Un refus trop large est un défaut aussi : on doit
    #  toujours pouvoir changer le mot de passe du dernier administrateur.
    r = settings.act_utilisateur("motdepasse:banc-marie")
    print(("OK|" if r.get("ok") else "NON|") +
          "mais son mot de passe reste changeable (%s)" % r.get("erreur", "ouvert"))

    #  ON NE SUPPRIME PAS LE COMPTE OUVERT EN CE MOMENT — même quand il n'est pas
    #  le dernier administrateur. banc-alex n'est plus admin ici : c'est bien la
    #  règle « c'est toi » qui doit parler, pas celle du dernier admin.
    r = settings.act_utilisateur("supprimer:banc-alex")
    print(("OK|" if (not r.get("ok") and "en ce moment" in r.get("erreur", "")) else "NON|") +
          "refusé : supprimer le compte ouvert (%s)" % r.get("erreur", "ACCEPTÉ !"))
except Exception as _e:
    #  UN PLANTAGE EST UN ROUGE, PAS UN SILENCE. Sans ce filet, une exception
    #  au milieu du script emporte tous les contrôles qui suivent : le banc
    #  affiche moins de coches et reste vert.
    print("NON|le banc s'est arrêté : %s: %s" % (type(_e).__name__, _e))
print("FIN|")

PY
	SORTIE_D="$(cd "$RACINE" && PATH="$CHEMIN" \
		python3 "$BANC/dernier.py" \
		"$RACINE/config/includes.chroot/usr/lib/lexos" "$BANC/trace" 2>/dev/null \
		| grep -E '^(OK|NON|FIN)\|' || true)"
	#  LA SENTINELLE. Sans elle, un banc qui S'ARRÊTE au milieu reste VERT :
	#  les contrôles déjà écrits passent, ceux qui n'ont jamais été atteints
	#  disparaissent en silence — il y a juste moins de coches. C'est ce qui
	#  est arrivé ici : retirer la vérification du nom de compte faisait lever
	#  une KeyError au contrôle suivant, et le banc n'a rien vu du tout.
	#  Le script rend une dernière ligne « FIN| » ; son absence est un rouge.
	if [ -z "$SORTIE_D" ]; then
		non "la protection du dernier administrateur n'a rien rendu"
	elif ! grep -q '^FIN|' <<< "$SORTIE_D"; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_D
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in
				OK)  ok "$M" ;;
				NON) non "$M" ;;
			esac
		done <<EOF
$SORTIE_D
EOF
	fi
fi

# =============================================================================
titre "4. LA PAGE — on la rend, avec des comptes qu'on a choisis"
# =============================================================================
#  Les contrôles de cette page dépendent des DONNÉES : le dernier
#  administrateur n'a pas les mêmes boutons que les autres, un compte
#  verrouillé propose « Déverrouiller », le compte ouvert n'a pas de bouton
#  « Supprimer ». Un grep du code serait vert sur une page qui n'affiche
#  jamais aucun de ces cas.
if ! command -v node >/dev/null 2>&1; then
	saute "node absent : la page n'a PAS été rendue"
else
	cat > "$BANC/rendu.js" <<'JS'
"use strict";
const fs = require("fs"), vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  + "\n;globalThis.__banc = { contenu, pose: e => { etat = e; } };\n";
const el = () => ({ innerHTML:"", textContent:"", hidden:true, style:{}, dataset:{},
                    classList:{add(){},remove(){},toggle(){}},
                    querySelectorAll:()=>[], appendChild(){}, focus(){} });
const bac = vm.createContext({
  document:{ getElementById:()=>el(), querySelectorAll:()=>[], body:el(),
             documentElement:{style:{setProperty(){}},dataset:{}}, addEventListener(){} },
  location:{hash:""}, window:{confirm:()=>true},
  fetch:()=>Promise.reject(new Error("pas de pont dans le banc")),
  requestAnimationFrame:()=>0, setTimeout, clearTimeout, console });
bac.globalThis = bac;
vm.runInContext(source, bac, {filename:"app.js"});
const T = bac.__banc;
const dit = (bon, m) => console.log((bon ? "OK|" : "NON|") + m);

try {

  /*  DEUX ADMINISTRATEURS : chacun garde tous ses boutons. */
  const deux = {dispo:true, nb_admins:2, auto:"", lightdm:true, groupe_admin:"sudo",
    comptes:[
      {nom:"banc-alex", complet:'Alex "le grand"', uid:1000, admin:true, moi:true,
       verrou:"actif", derniere:"jamais", groupes:"sudo (administrateur)"},
      {nom:"banc-marie", complet:"Marie Tremblay", uid:1001, admin:true, moi:false,
       verrou:"verrouille", derniere:"hier", groupes:"sudo (administrateur)"},
      {nom:"banc-jo", complet:"", uid:1002, admin:false, moi:false,
       verrou:"inconnu", derniere:"jamais", groupes:"aucun droit particulier"}]};
  T.pose({utilisateurs: deux});
  let h = T.contenu("utilisateurs");

  dit(h.includes("utilGeste('admin-off','banc-marie')"),
      "un administrateur qui n'est pas le dernier peut être rétrogradé");
  dit(h.includes("utilGeste('admin-on','banc-jo')"),
      "un compte ordinaire peut être promu");
  dit(h.includes("utilGeste('deverrouiller','banc-marie')") &&
      !h.includes("utilGeste('verrouiller','banc-marie')"),
      "un compte verrouillé propose « Déverrouiller », pas « Verrouiller »");
  dit(h.includes("utilGeste('verrouiller','banc-jo')"),
      "un compte actif propose « Verrouiller »");
  dit(!h.includes("utilGeste('supprimer','banc-alex')") &&
      h.includes("utilGeste('supprimer','banc-jo')"),
      "le compte ouvert n'a pas de bouton « Supprimer », les autres si");
  dit(h.includes("utilGeste('motdepasse','banc-alex')") &&
      h.includes("utilGeste('motdepasse','banc-marie')") &&
      h.includes("utilGeste('motdepasse','banc-jo')"),
      "chaque compte peut changer son mot de passe");
  dit(h.includes('id="nomAff-banc-jo"') && h.includes("utilNomComplet('banc-jo')"),
      "chaque compte a un champ pour son nom affiché, branché");
  dit(h.includes('id="utilNouveau"') && h.includes("utilAjouter()"),
      "la page a de quoi créer un compte");
  dit(h.includes("— c'est toi"), "le compte ouvert est signalé");
  dit(!/Alex "le grand"/.test(h) && h.includes("&quot;le grand&quot;"),
      "un nom à guillemets est échappé dans le HTML");
  dit(h.includes("état inconnu"),
      "un état de mot de passe illisible est dit « inconnu », pas « actif »");
  dit(h.includes('<option value="off" selected'),
      "la connexion automatique est présentée comme éteinte quand elle l'est");

  /*  UN SEUL ADMINISTRATEUR : ses boutons dangereux DISPARAISSENT. C'est le
      contrôle qui ne peut pas être vrai par hasard — le même compte, deux
      rendus, deux résultats. */
  const seul = JSON.parse(JSON.stringify(deux));
  seul.nb_admins = 1;
  seul.comptes[0].admin = false;
  seul.auto = "banc-marie";
  T.pose({utilisateurs: seul});
  h = T.contenu("utilisateurs");
  dit(!h.includes("utilGeste('admin-off','banc-marie')") &&
      !h.includes("utilGeste('supprimer','banc-marie')") &&
      !h.includes("utilGeste('verrouiller','banc-marie')") &&
      !h.includes("utilGeste('deverrouiller','banc-marie')"),
      "le dernier administrateur n'affiche aucun bouton qui ne pourrait que refuser");
  dit(h.includes("utilGeste('motdepasse','banc-marie')"),
      "…mais son mot de passe reste changeable depuis la page");
  dit(h.includes("Seul administrateur"),
      "et la page explique pourquoi ces boutons manquent");
  dit(h.includes('value="banc-marie" selected') && h.includes("s'ouvre sans mot de passe"),
      "une connexion automatique active est dite, et le compte est coché");

  /*  LIGHTDM ABSENT : on ne propose pas un réglage qui ne s'appliquerait pas. */
  const sansLightdm = JSON.parse(JSON.stringify(deux));
  sansLightdm.lightdm = false;
  T.pose({utilisateurs: sansLightdm});
  h = T.contenu("utilisateurs");
  dit(!h.includes("utilGeste('auto'") && h.includes("LightDM n'est pas installé"),
      "sans LightDM, la connexion automatique est dite indisponible au lieu d'être offerte");

  /*  L'OUTIL MUET NE DONNE PAS UNE PAGE VIDE. */
  T.pose({utilisateurs: {}});
  dit(T.contenu("utilisateurs").includes("lexos-utilisateurs n'a pas répondu"),
      "si l'outil ne répond pas, la page le dit au lieu de rester blanche");
} catch (e) {
  /*  UN PLANTAGE EST UN ROUGE, PAS UN SILENCE. Sans ce filet, une exception au
      milieu du rendu emporte tous les contrôles qui suivent : le banc affiche
      moins de coches et reste vert. */
  console.log("NON|le rendu s'est arrêté : " + (e && e.message || e));
}
console.log("FIN|");
JS
	SORTIE_P="$(node "$BANC/rendu.js" "$PAGE" 2>&1 | grep -E '^(OK|NON|FIN)\|' || true)"
	#  LA SENTINELLE. Sans elle, un banc qui S'ARRÊTE au milieu reste VERT :
	#  les contrôles déjà écrits passent, ceux qui n'ont jamais été atteints
	#  disparaissent en silence — il y a juste moins de coches. C'est ce qui
	#  est arrivé ici : retirer la vérification du nom de compte faisait lever
	#  une KeyError au contrôle suivant, et le banc n'a rien vu du tout.
	#  Le script rend une dernière ligne « FIN| » ; son absence est un rouge.
	if [ -z "$SORTIE_P" ]; then
		non "la page n'a rien rendu — app.js n'a pas pu être chargé"
	elif ! grep -q '^FIN|' <<< "$SORTIE_P"; then
		non "le banc s'est arrêté avant la fin — des contrôles n'ont jamais tourné"
		while IFS='|' read -r V M; do
			[ "$V" = "NON" ] && non "$M"
		done <<EOF
$SORTIE_P
EOF
	else
		while IFS='|' read -r V M; do
			case "$V" in
				OK)  ok "$M" ;;
				NON) non "$M" ;;
			esac
		done <<EOF
$SORTIE_P
EOF
	fi
fi

# =============================================================================
titre "5. UNE SEULE SOURCE — les Paramètres ne relisent plus /etc/passwd"
# =============================================================================
#  C'est là qu'était la faute : deux définitions d'« administrateur » dans le
#  même système, et c'est la fausse qu'on montrait.
#  On greppe un FICHIER, pas un tuyau : « printf … | grep -q » sous
#  « pipefail » rend 141 quand grep ferme le tuyau, et c'est une course — ce
#  dépôt a déjà payé ce piège.
sed 's|#.*$||' "$MOTEUR" > "$BANC/moteur.py"

grep -q 'lexos-utilisateurs' "$BANC/moteur.py" \
	&& ok "le moteur demande les comptes à lexos-utilisateurs" \
	|| non "le moteur ne passe pas par lexos-utilisateurs"

if grep -qE '"(wheel|adm)"' "$BANC/moteur.py"; then
	non "les Paramètres définissent encore « administrateur » de leur côté"
else
	ok "aucune deuxième définition d'« administrateur » dans les Paramètres"
fi

if grep -qE 'ETC_DIR / "(passwd|group)"' "$BANC/moteur.py"; then
	non "les Paramètres relisent /etc/passwd ou /etc/group eux-mêmes"
else
	ok "les Paramètres ne relisent ni /etc/passwd ni /etc/group"
fi

#  LE BOUTON « Détail » IMPRIMAIT DEUX COMPTES INVENTÉS.
#  ON LIT LE CODE, COMMENTAIRES RETIRÉS : l'explication ci-dessus cite
#  justement les deux comptes inventés, et un grep du fichier entier serait
#  rouge à cause du commentaire qui raconte le correctif.
if grep -qE "lex +— Principal|invite +— Invité" "$BANC/moteur.py"; then
	non "« Détail » affiche encore des comptes écrits en dur"
else
	ok "« Détail » ne montre plus de comptes inventés"
fi
grep -q '"utilisateur": act_utilisateur' "$BANC/moteur.py" \
	&& ok "le moteur connaît l'action « utilisateur »" \
	|| non "l'action « utilisateur » n'est pas dans la table ACTIONS"

#  ACTIONS est évaluée À L'IMPORT : une fonction définie après la table donne
#  un NameError au chargement, et les Paramètres ne s'ouvrent plus du tout.
LIG_ACT="$(grep -n '^def act_utilisateur' "$MOTEUR" | head -1 | cut -d: -f1)"
LIG_TAB="$(grep -n '^ACTIONS = {' "$MOTEUR" | head -1 | cut -d: -f1)"
if [ -n "$LIG_ACT" ] && [ -n "$LIG_TAB" ] && [ "$LIG_ACT" -lt "$LIG_TAB" ]; then
	ok "act_utilisateur est définie AVANT la table ACTIONS"
else
	non "act_utilisateur est définie après ACTIONS : le module ne s'importerait pas"
fi

printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$REUSSIS" "$ECHOUES"
[ "$ECHOUES" -eq 0 ]
