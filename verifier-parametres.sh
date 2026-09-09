#!/usr/bin/env bash
# =============================================================================
#  verifier-parametres.sh — contrôle 16 de LexOS
#
#  Répond à une seule question, mécaniquement :
#
#    « Est-ce que TOUS les outils lexos-* sont bien branchés — Paramètres,
#      dispatcheur, aide, lanceur — et le moteur de scan matériel aussi ? »
#
#      ./verifier-parametres.sh              # rapport complet
#      ./verifier-parametres.sh --strict     # sort en erreur s'il reste un trou
#      ./verifier-parametres.sh --csv        # sortie tableau
#
#  ADAPTÉ AU DÉPÔT RÉEL depuis la version reçue d'Alex. La première mouture
#  annonçait 80 erreurs dont ~75 fausses, et un contrôle qui crie au loup
#  finit ignoré — c'est comme ça qu'on rate le vrai. Ce qui a changé, et
#  pourquoi, écrit ici pour ne pas refaire le chemin inverse un jour :
#
#    · le hook 0250 déclare ses listes dans LISTS= et BUREAU_COMPLET=,
#      pas dans OUTILS= (27 fausses erreurs d'un coup) ;
#    · une branche du case porte des ALIAS (« son|audio|volume) ») : on
#      vérifie donc « le dispatcheur exécute-t-il lexos-X quelque part »,
#      pas un motif sur le nom de la branche ;
#    · l'aide écrit ses commandes dans ${A}…${R} : on retire l'habillage
#      avant de chercher, et on accepte N'IMPORTE QUEL alias de la branche
#      (« ecran » suffit pour lexos-display) ;
#    · les lanceurs .desktop sont générés par les hooks (0400, 0420…), pas
#      posés dans usr/share/applications : on cherche dans les deux ;
#    · « lexos-1 » dans « lexos-1.0v- » n'est pas un outil : un nom suivi
#      d'un point-chiffre est ignoré, et les faux amis connus sont listés.
#
#  Aucun paquet à installer. Bash + grep + find. Zéro avertissement shellcheck.
# =============================================================================

# shellcheck disable=SC1003
set -uo pipefail

#  LOCALE FIGÉE, ET CE N'EST PAS UN DÉTAIL. La première version employait la
#  classe [à-ÿ] pour attraper les alias accentués (« température », « écran »).
#  Un INTERVALLE de caractères non ASCII dépend de la locale : sur le runner
#  de la CI, grep et sed ont répondu « Invalid collation character » — sur
#  DEUX LIGNES perdues au milieu de la sortie — et l'extraction des alias a
#  rendu du vide. Résultat : trois outils déclarés « absents de l'aide »
#  alors que l'aide les nomme, et une CI rouge pour rien. Le motif ci-dessous
#  n'emploie plus aucun intervalle non ASCII, et la locale est figée pour que
#  le même dépôt donne le même verdict partout.
export LC_ALL=C

STRICT=0
CSV=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --csv)    CSV=1 ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "option inconnue : $a" >&2; exit 2 ;;
  esac
done

BIN="config/includes.chroot/usr/bin"
LIB="config/includes.chroot/usr/lib/lexos"
LISTES="config/includes.chroot/usr/share/lexos/optional-packages"
APPS="config/includes.chroot/usr/share/applications"
HOOKS="config/hooks/normal"
HOOK_OPT="$HOOKS/0250-lexos-optional.hook.chroot"
#  La Logithèque : c'est elle qui rend atteignables les familles qui ne sont
#  plus pré-installées (voir le contrôle 4).
LOGITHEQUE="config/includes.chroot/usr/bin/lexos-logitheque"
DISPATCH="$BIN/lexos"
SET_PY="$LIB/settings.py"
SET_JS="config/includes.chroot/usr/share/lexos/settings/web/app.js"
DEMO="web-demo/index.html"

[ -f lexos.conf ] || { echo "✗ à lancer à la racine du dépôt (lexos.conf introuvable)"; exit 2; }

ROUGE=$'\033[31m'; VERT=$'\033[32m'; JAUNE=$'\033[33m'; GRAS=$'\033[1m'; RAZ=$'\033[0m'
[ -t 1 ] || { ROUGE=""; VERT=""; JAUNE=""; GRAS=""; RAZ=""; }

NB_ERR=0; NB_AVERT=0
err()   { NB_ERR=$((NB_ERR+1));     printf '%s✗%s %s\n' "$ROUGE" "$RAZ" "$1"; }
avert() { NB_AVERT=$((NB_AVERT+1)); printf '%s⚠%s %s\n' "$JAUNE" "$RAZ" "$1"; }
ok()    {                          printf '%s✓%s %s\n' "$VERT"  "$RAZ" "$1"; }
titre() { printf '\n%s%s%s\n' "$GRAS" "$1" "$RAZ"; }

# L'aide du dispatcheur, sans son habillage ${A}…${R}, pour y chercher des mots.
#
# PRÉCALCULÉE, ET CHERCHÉE SANS PIPE. La première version faisait
# « printf | awk | grep -q » sous « set -o pipefail » : grep -q quitte à la
# première trouvaille, printf meurt en SIGPIPE, et le pipeline entier passe
# pour un échec — au hasard du timing. Les erreurs CHANGEAIENT d'une
# exécution à l'autre. Un contrôle non déterministe est pire qu'absent :
# on ne sait jamais si on a réparé quelque chose ou eu de la chance.
AIDE_NUE=$(sed 's/\${[A-Z]*}//g' "$DISPATCH" 2>/dev/null | awk '/^cmd_help\(\)/,0')

# Les branches du case : « alias1|alias2) exec lexos-X » → « lexos-X<TAB>alias1 alias2 ».
#  « tout ce qui précède la première parenthèse fermante », sans nommer les
#  caractères : les alias accentués passent parce qu'on ne cherche pas à les
#  décrire. On écarte les lignes de commentaire et celles qui contiennent
#  déjà une parenthèse ouvrante (une fonction, pas une branche).
BRANCHES=$(grep -E '^[[:space:]]*[^()#]+\)[[:space:]]*(exec[[:space:]]+lexos-|cmd_)' "$DISPATCH" \
  | sed -E 's/^[[:space:]]*([^)]*)\)[[:space:]]*(exec[[:space:]]+(lexos-[a-z0-9-]+)|cmd_[a-z_]+).*/\3\t\1/')

#  GARDE-FOU : si l'extraction ci-dessus rend du vide, tout le contrôle 1
#  devient un mensonge poli — chaque outil paraît « absent de l'aide » et on
#  cherche pendant une heure un défaut qui n'existe pas. C'est exactement ce
#  qui est arrivé sur le runner. Mieux vaut s'arrêter net et le dire.
if [ -z "$BRANCHES" ]; then
  printf '%s✗%s aucune branche lue dans %s — le motif ou la locale a changé.\n' \
    "$ROUGE" "$RAZ" "$DISPATCH" >&2
  printf '   (contrôle interrompu : il ne peut rien affirmer de fiable)\n' >&2
  exit 2
fi

dans_parametres() {  # les deux formes : « lexos-x » et « lexos x »
  local sous="$1" f
  for f in "$SET_PY" "$SET_JS" "$DEMO"; do
    [ -r "$f" ] || continue
    grep -qE "lexos[- ]$sous([^a-z0-9-]|\$)" "$f" && return 0
  done
  return 1
}

# =============================================================================
# 1. Chaque outil lexos-* est-il branché partout où il doit l'être ?
# =============================================================================
titre "1. Les outils lexos-* et leurs branchements"

# Sans section Paramètres NI branche : services, daemons, rouages internes.
# Les lister est un CHOIX écrit noir sur blanc, pas un oubli.
#   lexos-heure/-peripheriques : tuiles genmon de la barre (le panneau les lance)
#   lexos-volet                : lancé par les tuiles
#   lexos-wm                   : rouage des raccourcis fenêtre
#   lexos-app-settings          : rouage du raccourci Super+, — les réglages
#                                de la fenêtre active, jamais une section des
#                                Paramètres (c'est justement ce qu'elle n'est
#                                pas censée être)
#   lexos-theme-gen            : rouage de « lexos theme »
#   lexos-settings             : la fenêtre des Paramètres ELLE-MÊME (une
#                                « section Paramètres » n'aurait pas de sens ;
#                                elle a sa branche « parametres » et son dock)
#   lexos-boost-panneau        : amorce du greffon de barre de Boost
#   lexos-claude-installation  : autostart de session, même mécanisme que
#                                lexos-firstrun — rattrape la version de
#                                Claude Code, ne se tape pas
SANS_SECTION="
lexos-apercu
lexos-app-settings
lexos-claude-installation
lexos-firstrun
lexos-welcome
lexos-net-autoconnect
lexos-usb-notify
lexos-update-check
lexos-run-ins
lexos-install
lexos-install-chrome
lexos-boost-panneau
lexos-volet
lexos-fenetre
lexos-sticker
lexos-heure
lexos-peripheriques
lexos-wm
lexos-theme-gen
lexos-settings
lexos-ecran-telephone
lexos-unzip
"

# Applis AUTONOMES : leur maison est le menu et le dock, pas les Paramètres.
# Exiger une « section Paramètres » pour la bibliothèque de jeux ou le GPS
# serait inventer un besoin. On exige quand même la branche du case et la
# ligne d'aide — un outil qu'on ne peut pas taper n'existe qu'à moitié.
AUTONOMES="
lexos-assistants
lexos-cartes
lexos-chrome
lexos-pro-terminal
lexos-claude
lexos-claude-terminal
lexos-opencode
lexos-dev
#  Outil de DÉVELOPPEMENT, pour la machine d'Alex : il pose le dépôt sur
#  le système en marche sans reconstruire d'ISO. Il n'a rien à faire dans
#  les Paramètres — on n'expose pas un bouton « écrase /usr depuis un
#  clone git » à côté du réglage de la luminosité.
lexos-dev-sync
lexos-dualboot
#  Une REMISE EN ACCORD ponctuelle, pas un reglage : elle recale les icones
#  des raccourcis du bureau sur celles des lanceurs systeme, puis elle a fini.
#  Il n'y a rien a y regler — un bouton « recaler les icones » dans les
#  Parametres serait un bouton qu'on ne reclique jamais. Elle est atteinte par
#  « lexos icones-bureau », et son compte rendu est le terminal.
lexos-icones-bureau
lexos-game
lexos-gps
lexos-jeux
lexos-logitheque
lexos-meteo
#  Le terminal en volets (tmux). C'est une APPLI, pas un réglage : sa fenêtre
#  est le terminal lui-même. Elle est atteinte par « lexos multi », par l'alias
#  « multi » du shell, par son lanceur du menu et par le dock — quatre chemins.
#  Une section dans les Paramètres n'aurait rien à afficher : il n'y a aucun
#  réglage à régler, le fichier lexos.conf de tmux se recharge avec Ctrl+B r.
lexos-multi
#  La mise à jour de LexOS lui-même, depuis le dépôt. Elle est ATTEINTE par
#  le dispatcheur (« lexos maj ») et par l'enrobage « miss » ; elle n'a pas
#  de page dans les Paramètres, et c'est voulu : « écrase /usr depuis un
#  clone git » n'est pas un bouton qu'on met à côté de la luminosité.
lexos-mise-a-jour
#  L'enrobage d'Alex : « sudo miss a jour ». Dix lignes qui font exec vers
#  lexos-mise-a-jour, sans aucune logique — il est ici pour que le contrôle
#  16 sache qu'il est branché exprès et pas oublié.
miss
lexos-musique
lexos-studio
lexos-temp
lexos-tv
lexos-ia
lexos-ia-locale
lexos-boost
lexos-sauvegarde
lexos-disques
lexos-medecin
lexos-materiel
"

[ "$CSV" = 1 ] && echo "outil;parametres;dispatcher;aide;lanceur"

while IFS= read -r chemin; do
  outil=$(basename "$chemin")
  [ "$outil" = "lexos" ] && continue

  exempt=0
  case "$SANS_SECTION" in *"
$outil
"*) exempt=1 ;; esac
  autonome=0
  case "$AUTONOMES" in *"
$outil
"*) autonome=1 ;; esac

  sous=${outil#lexos-}
  alias_outil=$(printf '%s\n' "$BRANCHES" | awk -F'\t' -v o="$outil" '$1==o {print $2}' | tr '|' ' ')

  # a) une section / un appel dans les Paramètres ?
  if dans_parametres "$sous"; then p="oui"; else p="NON"; fi
  # b) le dispatcheur exécute-t-il cet outil quelque part ?
  if [ -n "$alias_outil" ] || grep -qE "(^|[^a-z-])$outil([^a-z-]|\$)" "$DISPATCH"; then d="oui"; else d="NON"; fi
  # c) au moins un de ses alias apparaît-il dans l'aide ?
  h="NON"
  for al in ${alias_outil:-$sous}; do
    if grep -qE "(^|[[:space:]])$al([[:space:]]|\$)" <<<"$AIDE_NUE"; then
      h="oui"; break
    fi
  done
  # d) un lanceur .desktop — fichier posé, ou généré par un hook ?
  if [ -f "$APPS/$outil.desktop" ] \
     || grep -rqlF "$outil.desktop" "$HOOKS" 2>/dev/null \
     || grep -rqlF "Exec=$outil" "$HOOKS" 2>/dev/null; then
    l="oui"
  else
    l="NON"
  fi

  if [ "$CSV" = 1 ]; then echo "$outil;$p;$d;$h;$l"; continue; fi
  [ "$exempt" = 1 ] && continue

  #  Les autonomes n'ont pas besoin d'une section Paramètres ; et un lanceur
  #  manquant est un avertissement, pas une erreur — beaucoup d'outils sont
  #  des commandes, leur fenêtre est le terminal.
  [ "$autonome" = 1 ] && p="oui"
  manques=""
  [ "$p" = "NON" ] && manques="$manques pas-de-section-Paramètres"
  [ "$d" = "NON" ] && manques="$manques pas-de-branche-case"
  [ "$h" = "NON" ] && manques="$manques absent-de-cmd_help"
  if [ -z "$manques" ]; then
    ok "$outil"
    #  Le lanceur ne se signale que pour les applis autonomes : un dorsal de
    #  réglage n'en a pas besoin, sa fenêtre EST la section des Paramètres.
    [ "$autonome" = 1 ] && [ "$l" = "NON" ] \
      && avert "$outil : appli autonome sans lanceur .desktop (choix à confirmer)"
  else
    err "$outil :$manques"
  fi
#  ═══ « *.wrapper » N'EST PAS UN OUTIL, C'EST UN PONT ═══
#  Un fichier « .wrapper » est la convention Debian pour l'aiguillage
#  d'update-alternatives : x-terminal-emulator pointe dessus, et son seul
#  travail est de traduire des arguments avant de passer la main. Personne
#  ne le tape jamais par son nom, il n'a pas de page de réglages, et il ne
#  doit PAS apparaître dans le menu — l'y mettre offrirait à l'utilisateur
#  une entrée qui ouvre exactement la même fenêtre que celle d'à côté.
#
#  On l'écarte donc par CATÉGORIE, pas par une exception nominative : la
#  règle vaut pour le prochain pont comme pour celui-ci, et elle ne peut pas
#  servir à cacher un vrai outil — un programme nommé « machin.wrapper » ne
#  serait de toute façon pas invocable comme sous-commande de « lexos ».
done < <(find "$BIN" -maxdepth 1 -name 'lexos-*' -type f ! -name '*.wrapper' | sort)

[ "$CSV" = 1 ] && exit 0

# =============================================================================
# 2. L'inverse : les Paramètres appellent-ils un outil qui n'existe pas ?
# =============================================================================
titre "2. Les Paramètres appellent-ils des outils qui n'existent pas ?"

# Faux amis connus — des chaînes qui ressemblent à un outil sans en être un.
#   lexos-reglages : nom d'icône (hicolor/…/lexos-reglages.png)
FAUX_AMIS="lexos-reglages"

TROUVE=0
for f in "$SET_PY" "$SET_JS" "$DEMO"; do
  [ -r "$f" ] || { avert "source des Paramètres illisible : $f"; continue; }
  while IFS= read -r appel; do
    [ -f "$BIN/$appel" ] && continue
    case " $FAUX_AMIS " in *" $appel "*) continue ;; esac
    # « lexos-1.0v- », « lexos-2.0.0 » : un nom suivi d'un point-chiffre est
    # une version, pas un outil.
    grep -qE "$appel\.[0-9]" "$f" && continue
    err "les Paramètres appellent « $appel » — aucun fichier $BIN/$appel  (vu dans ${f##*/})"
    TROUVE=1
    #  ═══ UN NOM DE FIL D'EXÉCUTION N'EST PAS UN APPEL DE PROGRAMME ═══
    #  settings.py baptise ses fils pour qu'un « ps » ou un vidage de pile
    #  soit lisible : « lexos-settings-http » pour le serveur local,
    #  « lexos-etat » pour la réserve qui interroge la machine de front.
    #  Ce contrôle les prenait pour des outils appelés — et réclamait un
    #  fichier /usr/bin/lexos-etat qui n'a aucune raison d'exister.
    #
    #  C'ÉTAIT DÉJÀ CONNU, ET TRAITÉ AU CAS PAR CAS : « lexos-settings-http »
    #  vivait dans la liste des faux amis. Nommer un fil de plus rendait donc
    #  la CI rouge, pour un défaut qui n'en est pas un — le genre de rouge
    #  qui apprend à ignorer les rouges. On retire la CLASSE entière plutôt
    #  que d'allonger la liste : ce qui est écrit dans « name= » ou
    #  « thread_name_prefix= » ne sera jamais exécuté.
  done < <(sed -E 's/thread_name_prefix[[:space:]]*=[[:space:]]*"[^"]*"//g; s/\bname[[:space:]]*=[[:space:]]*"lexos-[^"]*"//g' "$f" \
             | grep -ohE 'lexos-[a-z0-9-]+' | sort -u)
done
[ "$TROUVE" = 0 ] && ok "aucune section ne pointe vers un outil inexistant"

# =============================================================================
# 3. Le moteur de scan matériel (LexOS Boost)
# =============================================================================
titre "3. Le moteur de scan matériel (LexOS Boost)"

for m in "$LIB/boost/moteur.py" "$LIB/boost/materiel.py" "$LIB/boost/mesure.py" "$LIB/boost/journal.py"; do
  if [ -f "$m" ]; then ok "présent : ${m#config/includes.chroot}"
  else err "ABSENT : ${m#config/includes.chroot}"; fi
done

if dans_parametres "boost"; then
  ok "le moteur de scan a un chemin depuis les Paramètres"
else
  err "le moteur de scan n'est appelé NULLE PART dans les Paramètres"
fi

titre "3b. Les paquets dont le scan a besoin"
for pq in lm-sensors smartmontools nvme-cli hwinfo inxi fwupd pciutils usbutils; do
  if grep -rqE "^[[:space:]]*${pq}([[:space:]]|\|)*" "$LISTES" config/package-lists 2>/dev/null; then
    ok "$pq réclamé"
  else
    err "$pq n'est dans AUCUNE liste de paquets — le scan matériel n'aura rien à lire"
  fi
done

# =============================================================================
# 4. Une .list que personne ne réclame / réclamée mais absente
# =============================================================================
titre "4. Les listes de paquets et le hook 0250"

if [ ! -r "$HOOK_OPT" ]; then
  err "hook introuvable : $HOOK_OPT"
else
  #  Le hook déclare LISTS= (socle) puis BUREAU_COMPLET= (le reste) — pas
  #  OUTILS=. C'était la source des 27 fausses erreurs de la première version.
  #  « LISTS=00-core.list » : sans retirer le préfixe, la PREMIÈRE liste de
  #  chaque variable disparaissait du compte — 00-core et 15-essentiel
  #  passaient pour orphelines alors qu'elles ouvrent le bal.
  RECLAMEES=$(sed -n '/^LISTS="/,/"/p; /^BUREAU_COMPLET="/,/"/p' "$HOOK_OPT" \
    | tr -d '"\\' | tr -s ' \n' '\n' | sed 's/^[A-Z_]*=//' \
    | sed -n 's/\.list$//p' | grep -E '^[0-9]{2}-' | sort -u)
  PRESENTES=$(find "$LISTES" -name '*.list' -printf '%f\n' | sed 's/\.list$//' | sort -u)

  #  ═══ UN RETRAIT VOLONTAIRE N'EST PAS UN OUBLI ═══
  #  ALEX : « toutes les applications sont téléchargées dans l'ISO —
  #  j'aimerais, pour faire de la place, qu'elles restent dans la Logithèque
  #  et qu'on puisse les télécharger à partir de là. » Quatre familles ne
  #  sont donc plus pré-installées, EXPRÈS. Ce contrôle, écrit contre les
  #  oublis, les prenait pour des oublis — à juste titre tant qu'il n'y avait
  #  aucune autre façon de les atteindre.
  #
  #  La différence entre un oubli et un retrait volontaire n'est pas une
  #  déclaration d'intention : c'est qu'il existe un CHEMIN pour les
  #  installer. On l'exige donc — la liste doit être nommée dans
  #  lexos-logitheque. Une famille retirée ET introuvable reste une erreur,
  #  exactement comme avant.
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    if grep -q "$l\.list" "$LOGITHEQUE" 2>/dev/null; then
      ok "$l.list n'est pas pré-installée, mais « lexos logitheque famille » sait l'installer"
    else
      err "$l.list existe mais n'est réclamée nulle part dans le hook 0250 → jamais installée, en silence"
    fi
  done < <(comm -13 <(printf '%s\n' "$RECLAMEES") <(printf '%s\n' "$PRESENTES"))

  while IFS= read -r l; do
    [ -n "$l" ] || continue
    err "le hook 0250 réclame $l.list — le fichier N'EXISTE PAS"
  done < <(comm -23 <(printf '%s\n' "$RECLAMEES") <(printf '%s\n' "$PRESENTES"))

  n_r=$(printf '%s\n' "$RECLAMEES" | grep -c . || true)
  n_p=$(printf '%s\n' "$PRESENTES" | grep -c . || true)
  #  Les familles offertes par la Logithèque comptent comme atteignables :
  #  sans elles, les deux totaux ne concorderaient plus jamais.
  n_f=$(comm -13 <(printf '%s\n' "$RECLAMEES") <(printf '%s\n' "$PRESENTES") \
        | while IFS= read -r l; do [ -n "$l" ] && grep -q "$l\.list" "$LOGITHEQUE" 2>/dev/null && echo x; done | grep -c . || true)
  [ "$((n_r + n_f))" = "$n_p" ] \
    && ok "$n_r listes installées + $n_f offertes par la Logithèque = $n_p présentes"
fi

# =============================================================================
# 5. Ce que les documents attendent
# =============================================================================
titre "5. Listes prévues dans les documents"
for l in 41-reseau-plus 51-dev-outils 52-ia-locale 54-sauvegarde 59-diagnostic; do
  if [ -f "$LISTES/$l.list" ]; then ok "$l.list"
  else avert "$l.list prévue dans les documents, absente du dépôt"; fi
done
if [ -d config/archives ]; then ok "config/archives/ présent (backports ouverts et épinglés)"
else avert "config/archives/ absent — un paquet de trixie-backports serait ignoré EN SILENCE"; fi

titre "Bilan"
printf '%s erreurs, %s avertissements\n' "$NB_ERR" "$NB_AVERT"
if [ "$NB_ERR" -gt 0 ] && [ "$STRICT" = 1 ]; then exit 1; fi
exit 0
