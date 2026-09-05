#!/usr/bin/env bash
# =============================================================================
#  Banc d'essai — les volets et les onglets du terminal (lexos-multi + tmux)
# =============================================================================
#  CE QU'IL GARDE, ET POURQUOI CHAQUE CONTRÔLE EST LÀ.
#
#  1. LA CONFIGURATION SE CHARGE. C'est LE contrôle du fichier. Un .conf tmux
#     ne se compile pas et ne se vérifie pas à la lecture : une seule option
#     mal orthographiée, et tmux affiche une erreur au démarrage puis IGNORE
#     LA SUITE DU FICHIER. Le terminal s'ouvre quand même, la souris ne marche
#     plus, et rien ne dit pourquoi. On ne peut donc pas relire le fichier ni
#     y chercher des motifs : il faut le donner à un vrai tmux et regarder ce
#     qu'il en fait.
#
#  2. LES RÉGLAGES SONT RELUS DEPUIS LE SERVEUR, pas depuis le fichier. La
#     nuance est tout : « set -g mouse on » peut être présent dans le fichier
#     ET sans effet, s'il est placé après une ligne qui a fait échouer le
#     chargement, ou écrasé plus bas. Interroger le serveur (tmux show) répond
#     à la seule question qui compte — la souris marche-t-elle, oui ou non.
#
#  3. LES RACCOURCIS AUSSI SONT RELUS DEPUIS LE SERVEUR. Et pas seulement leur
#     existence : leur TABLE. « bind | » et « bind -n M-Left » vivent dans deux
#     tables différentes (prefix et root). Perdre le « -n » ne casse rien de
#     visible — Alt+flèche cesse simplement de marcher, et il faut alors taper
#     Ctrl+B avant, ce que personne ne devinera. list-keys -T root le dit.
#
#  4. tmux EST UN PAQUET STRICT. La commande « multi » est promise dans l'aide
#     et posée dans le dock : si tmux atterrit dans une liste facultative, une
#     ISO sortira un jour où le lanceur du dock ne fait qu'afficher « tmux
#     n'est pas installé ».
#
#  5. lexos-multi NE SE LANCE PAS TOUT SEUL. Le banc vérifie qu'aucun appel à
#     tmux ne traîne dans interactive.sh (commentaires retirés — le fichier
#     PARLE de tmux longuement, c'est voulu), et qu'un lexos-multi appelé
#     depuis une session déjà en volets s'arrête au lieu d'empiler un tmux dans
#     un tmux.
#
#  Le banc a besoin de tmux pour tourner. Il n'a besoin ni de bureau graphique,
#  ni des droits root : tmux démarre sans terminal grâce à « -d », et sur une
#  PRISE À PART (-L) pour ne jamais toucher aux sessions de qui exécute le banc.
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARBRE="$RACINE/config/includes.chroot"
MULTI="$ARBRE/usr/bin/lexos-multi"
CONF="$ARBRE/usr/share/lexos/tmux/lexos.conf"
INTER="$ARBRE/usr/share/lexos/shell/interactive.sh"
BUREAU="$ARBRE/usr/share/applications/lexos-multi.desktop"
DOCK="$ARBRE/etc/skel/.config/plank/dock1/launchers/02-multi.dockitem"
LISTE="$RACINE/config/package-lists/lexos-core.list.chroot"

VERT=$'\033[32m'; ROUGE=$'\033[31m'; JAUNE=$'\033[33m'; GRAS=$'\033[1m'; FIN=$'\033[0m'
REUSSIS=0; ECHOUES=0; ECHECS=()

ok()   { printf '  %s✓%s %s\n' "$VERT" "$FIN" "$1"; REUSSIS=$((REUSSIS+1)); }
non()  { printf '  %s✗%s %s\n' "$ROUGE" "$FIN" "$1"; ECHOUES=$((ECHOUES+1)); ECHECS+=("$1"); }
titre(){ printf '\n%s%s%s\n' "$GRAS" "$1" "$FIN"; }

#  Une prise tmux à nous, dans un nom qui ne peut pas croiser celui d'un
#  utilisateur, et un serveur qu'on tue quoi qu'il arrive — y compris si le
#  banc est interrompu au milieu. Un tmux oublié en arrière-plan sur une
#  machine d'intégration continue est le genre de saleté qui survit à tout.
PRISE="lexos-banc-$$"
BAC=""
nettoyer() {
	tmux -L "$PRISE" kill-server >/dev/null 2>&1
	[[ -n "$BAC" && -d "$BAC" ]] && rm -rf "$BAC"
	return 0
}
trap nettoyer EXIT INT TERM
BAC="$(mktemp -d)"

# -----------------------------------------------------------------------------
titre "1. Les fichiers sont là"
for cible in "$MULTI:lexos-multi" "$CONF:lexos.conf" "$BUREAU:lexos-multi.desktop" \
             "$DOCK:02-multi.dockitem"; do
	f="${cible%%:*}"; nom="${cible#*:}"
	if [[ -r "$f" ]]; then ok "$nom présent"; else non "$nom introuvable ($f)"; fi
done
if [[ -x "$MULTI" ]]; then ok "lexos-multi est exécutable"
else non "lexos-multi n'est pas exécutable (chmod 755)"; fi
if [[ -r "$MULTI" ]] && bash -n "$MULTI" 2>/dev/null; then ok "syntaxe bash de lexos-multi valide"
else non "erreur de syntaxe bash dans lexos-multi"; fi

if [[ ! -r "$CONF" ]]; then
	printf '\n%sSans lexos.conf, le reste du banc n'"'"'a plus de sujet.%s\n\n' "$ROUGE" "$FIN"
	exit 1
fi

# -----------------------------------------------------------------------------
titre "2. tmux est un paquet strict, pas un souhait"
#  On regarde d'abord la liste stricte, puis on vérifie qu'aucune liste
#  facultative ne le reprend : un paquet présent des deux côtés est un paquet
#  dont personne ne sait plus s'il sera là.
if grep -qx 'tmux' "$LISTE"; then ok "tmux est dans lexos-core.list.chroot"
else non "tmux absent de la liste stricte (lexos-core.list.chroot)"; fi

facultatives=()
while IFS= read -r f; do
	grep -qx 'tmux' "$f" && facultatives+=("$(basename "$f")")
done < <(find "$RACINE/config/package-lists" -name '*.list.chroot' ! -name 'lexos-core.list.chroot' 2>/dev/null)
if (( ${#facultatives[@]} == 0 )); then ok "tmux n'est demandé que par la liste stricte"
else non "tmux est aussi dans : ${facultatives[*]}"; fi

# -----------------------------------------------------------------------------
titre "3. La configuration se charge — pour de vrai"
if ! command -v tmux >/dev/null 2>&1; then
	printf '  %s!%s tmux absent de cette machine : les contrôles 3 à 5 sont impossibles.\n' \
		"$JAUNE" "$FIN"
	non "tmux introuvable — le banc ne peut pas juger la configuration"
	printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
	exit 1
fi

#  tmux se plaint sur sa SORTIE D'ERREUR et rend malgré tout la main dans
#  certains cas : on retient les deux, le code de retour ET ce qui a été dit.
SORTIE="$(tmux -L "$PRISE" -f "$CONF" new-session -d -s essai 2>&1)"; RC=$?
if (( RC == 0 )); then ok "tmux démarre avec lexos.conf (code $RC)"
else non "tmux refuse lexos.conf (code $RC) : ${SORTIE:-aucun message}"; fi
if [[ -z "$SORTIE" ]]; then ok "aucun message d'erreur au chargement"
else non "tmux a protesté : $SORTIE"; fi

vivant=0
if tmux -L "$PRISE" has-session -t essai 2>/dev/null; then
	ok "la session « essai » existe"; vivant=1
else
	non "la session ne s'est pas ouverte — rien à interroger"
fi

# -----------------------------------------------------------------------------
titre "4. Les réglages sont relus depuis le serveur"
reglage() { # description, commande-show, valeur attendue
	local desc="$1" opt="$2" attendu="$3" vu
	if (( ! vivant )); then non "$desc (pas de serveur)"; return; fi
	#  read -a : « show -gv » ne prend pas de motif, chaque appel est explicite.
	vu="$(tmux -L "$PRISE" $opt 2>/dev/null)"
	if [[ "$vu" == "$attendu" ]]; then ok "$desc = $vu"
	else non "$desc vaut « ${vu:-rien} », attendu « $attendu »"; fi
}
#  La souris : le réglage qui rend tmux utilisable sans rien connaître.
reglage "souris (mouse)"                "show -gv mouse"           "on"
#  10 ms : au-delà, Échap dans nano ou dans Claude Code donne l'impression
#  exacte que la machine lague. C'est une option de SERVEUR (-s), pas de
#  session : la relire avec -g renverrait vide et le contrôle passerait à côté.
reglage "délai d'échappement (escape-time)" "show -sv escape-time" "10"
#  Les fenêtres comptent à partir de 1 : la touche 0 est à l'autre bout du
#  clavier, la 1 est sous l'index.
reglage "première fenêtre (base-index)"   "show -gv base-index"     "1"
reglage "premier volet (pane-base-index)" "show -gwv pane-base-index" "1"

# -----------------------------------------------------------------------------
titre "5. Les raccourcis existent, et dans la bonne table"
touche() { # description, table, touche, morceau attendu de la commande
	local desc="$1" table="$2" cle="$3" motif="$4" ligne
	if (( ! vivant )); then non "$desc (pas de serveur)"; return; fi
	#  On repère la ligne PAR CHAMPS, pas par expression régulière : les touches
	#  s'appellent « | », « - » et « c », c'est-à-dire exactement les caractères
	#  qu'une expression régulière interprète. awk compare le champ qui suit le
	#  nom de la table, littéralement — rien à échapper, rien à deviner.
	ligne="$(tmux -L "$PRISE" list-keys -T "$table" 2>/dev/null \
	         | awk -v t="$table" -v k="$cle" \
	           '{ for (i = 1; i < NF; i++) if ($i == "-T" && $(i+1) == t && $(i+2) == k) { print; next } }')"
	if [[ -z "$ligne" ]]; then non "$desc : aucune touche « $cle » dans la table $table"; return; fi
	if grep -qF -- "$motif" <<< "$ligne"; then ok "$desc"
	else non "$desc : « $cle » fait « ${ligne#*"$cle"} », pas « $motif »"; fi
}
#  La barre coupe en COLONNES, le tiret en RANGÉES. Les lettres -h et -v de
#  tmux disent le contraire de ce qu'on attend, d'où les séparateurs dessinés.
touche "Ctrl+B puis | coupe en deux colonnes" prefix '|' 'split-window -h'
touche "Ctrl+B puis - coupe en deux rangées"  prefix '-' 'split-window -v'
#  'new-window' TOUT COURT serait le réglage d'usine de tmux : le contrôle
#  passerait même si notre ligne disparaissait. C'est le -c qui est à nous — le
#  nouvel onglet s'ouvre dans le dossier où l'on était.
touche "Ctrl+B puis c ouvre un onglet ici"     prefix 'c' 'new-window -c'
#  ROOT, pas prefix : Alt+flèches doit marcher SANS préfixe. Perdre le « -n »
#  ne casse rien de visible, ça rend juste le raccourci indevinable.
for sens in "Left:-L:gauche" "Right:-R:droite" "Up:-U:haut" "Down:-D:bas"; do
	fleche="${sens%%:*}"; reste="${sens#*:}"; drapeau="${reste%%:*}"; nom="${reste#*:}"
	touche "Alt+flèche $nom, sans préfixe" root "M-$fleche" "select-pane $drapeau"
done
#  Le dossier courant suit le nouveau volet : sans -c, chaque division repart
#  du dossier personnel et on repasse son temps à retaper le même cd.
if grep -q 'pane_current_path' "$CONF"; then ok "les nouveaux volets gardent le dossier courant"
else non "les divisions ne transmettent pas le dossier courant (-c)"; fi

# -----------------------------------------------------------------------------
titre "6. lexos-multi passe bien NOTRE configuration à tmux"
#  Un tmux témoin : il n'ouvre rien, il écrit ce qu'on lui a demandé. C'est la
#  seule façon de savoir ce qui est RÉELLEMENT passé en ligne de commande —
#  relire le script ne prouve que ce qu'il contient comme texte.
mkdir -p "$BAC/bin"
cat > "$BAC/bin/tmux" <<'TEMOIN'
#!/bin/sh
printf '%s\n' "$*" >> "$TEMOIN_ARGV"
exit 0
TEMOIN
chmod 755 "$BAC/bin/tmux"
export TEMOIN_ARGV="$BAC/argv.txt"

: > "$TEMOIN_ARGV"
PATH="$BAC/bin:$PATH" LEXOS_TMUX_CONF="$CONF" TMUX="" "$MULTI" </dev/null >/dev/null 2>&1
VU="$(cat "$TEMOIN_ARGV")"
if grep -qF -- "-f $CONF" <<< "$VU"; then ok "lexos-multi donne lexos.conf à tmux (-f)"
else non "lexos-multi n'a pas passé « -f $CONF » — il a lancé : ${VU:-rien}"; fi
#  attach-or-create : on retape « multi » sans se demander si on l'a déjà tapé.
if grep -qF -- "new-session -A -s lexos" <<< "$VU"; then ok "il reprend la session « lexos » si elle tourne (-A)"
else non "lexos-multi n'empile pas/ne reprend pas correctement : ${VU:-rien}"; fi

# -----------------------------------------------------------------------------
titre "7. Il ne se lance pas dans lui-même"
: > "$TEMOIN_ARGV"
PATH="$BAC/bin:$PATH" LEXOS_TMUX_CONF="$CONF" TMUX="/faux/tmux,1,0" \
	"$MULTI" </dev/null >/dev/null 2>&1
RC=$?
if (( RC == 0 )); then ok "dans une session en volets, il sort sans erreur (code 0)"
else non "dans une session en volets, il sort en code $RC — ce n'est pas une panne"; fi
if [[ ! -s "$TEMOIN_ARGV" ]]; then ok "et il n'a lancé aucun tmux"
else non "il a lancé un tmux dans un tmux : $(cat "$TEMOIN_ARGV")"; fi

# -----------------------------------------------------------------------------
titre "8. Le terminal ordinaire reste ordinaire"
#  interactive.sh PARLE longuement de tmux — c'est le commentaire qui explique
#  pourquoi on ne le lance pas. Chercher le mot « tmux » dans le fichier brut
#  serait donc un faux rouge permanent : on retire les commentaires d'abord.
#  C'est la même famille d'erreur que « le contrôle lit de la prose, pas du
#  code », déjà rencontrée assez souvent pour mériter cette ligne.
if [[ ! -r "$INTER" ]]; then
	non "interactive.sh introuvable ($INTER)"
else
	CODE="$(sed 's/[[:space:]]*#.*$//' "$INTER")"
	if [[ "$(wc -l <<< "$CODE")" -lt 50 ]]; then
		#  Une garde contre le vert sur du vide : si le décommentage rendait un
		#  fichier quasi nul, l'absence ci-dessous ne prouverait plus rien.
		non "le décommentage d'interactive.sh n'a presque rien laissé — contrôle invalide"
	elif grep -qE '(^|[;&|(`[:space:]])tmux([[:space:]]|$)' <<< "$CODE"; then
		non "interactive.sh appelle tmux : $(grep -nE '(^|[;&|(`[:space:]])tmux([[:space:]]|$)' <<< "$CODE" | head -3)"
	else
		ok "interactive.sh n'appelle jamais tmux"
	fi
	if grep -q "alias multi='lexos-multi'" "$INTER"; then ok "l'alias « multi » est posé"
	else non "l'alias « multi » manque dans interactive.sh"; fi
fi

# -----------------------------------------------------------------------------
titre "9. L'aide dit comment s'en servir et comment en sortir"
AIDE="$(PATH="$BAC/bin:$PATH" LEXOS_TMUX_CONF="$CONF" TMUX="" "$MULTI" aide 2>&1)"
for attendu in "Ctrl+B:le préfixe" "|:la division en colonnes" \
               "Alt:le déplacement entre volets" "c:le nouvel onglet"; do
	motif="${attendu%%:*}"; nom="${attendu#*:}"
	if grep -qF -- "$motif" <<< "$AIDE"; then ok "l'aide mentionne $nom"
	else non "l'aide ne mentionne pas $nom (« $motif »)"; fi
done
#  Entrer sans savoir sortir est le piège classique de tmux : « d » est la
#  seule touche qui compte pour qui a paniqué.
if grep -qF -- 'Ctrl+B puis d' <<< "$AIDE"; then ok "l'aide dit comment sortir (Ctrl+B puis d)"
else non "l'aide ne dit pas comment sortir de la session"; fi

# -----------------------------------------------------------------------------
titre "10. Le lanceur du bureau et celui du dock"
if [[ -r "$BUREAU" ]]; then
	grep -qE '^Exec=.*lexos-multi' "$BUREAU" \
		&& ok "le .desktop lance bien lexos-multi" \
		|| non "le .desktop ne lance pas lexos-multi"
	#  tmux a besoin d'un terminal pour s'afficher, et il y a DEUX façons de lui
	#  en donner un — dont une seule est la bonne ici.
	#
	#  « Terminal=true » laisse XFCE choisir l'émulateur, d'après une clé de
	#  xfconf que rien ne garantit : sur une machine où quelqu'un a installé
	#  puis désinstallé un autre terminal, le lanceur ne montre plus rien.
	#  « Exec=xfce4-terminal … -e lexos-multi » nomme le terminal de LexOS, avec
	#  son titre et son thème. C'est ce qu'on veut, et le contrôle exige donc
	#  l'un OU l'autre — jamais un Exec nu, qui est la seule vraie panne.
	if grep -qE '^Exec=[a-z0-9_-]*terminal' "$BUREAU"; then
		ok "le .desktop fournit lui-même la fenêtre (xfce4-terminal -e)"
		grep -qiE '^Terminal=true' "$BUREAU" \
			&& non "Terminal=true EN PLUS du terminal nommé : deux fenêtres emboîtées" \
			|| ok "et il ne demande pas en plus un terminal à XFCE"
	elif grep -qiE '^Terminal=true' "$BUREAU"; then
		ok "le .desktop demande un terminal à XFCE (Terminal=true)"
	else
		non "le .desktop lance lexos-multi sans aucune fenêtre : rien ne s'afficherait"
	fi
fi
if [[ -r "$DOCK" ]]; then
	grep -q 'lexos-multi' "$DOCK" \
		&& ok "l'entrée du dock pointe sur lexos-multi" \
		|| non "l'entrée du dock ne pointe pas sur lexos-multi"
fi

# -----------------------------------------------------------------------------
titre "11. Le banc ne se tire pas dans le pied"
#  Le tuyau « producteur | grep -q » est une course : grep -q sort au premier
#  résultat, le producteur reçoit EPIPE, et sous pipefail une correspondance
#  TROUVÉE devient une condition FAUSSE. On l'a mesuré à 18 % sur ce dépôt.
#  D'où « grep motif <<< "$VAR" » partout ci-dessus, et ce contrôle pour que
#  ça le reste.
MOTIF_TUYAU='(printf|echo|cat)[^|]*[|][[:space:]]*grep'
if grep -nE "$MOTIF_TUYAU" <<< "$(sed 's/[[:space:]]*#.*$//' "${BASH_SOURCE[0]}")" >/dev/null; then
	non "un tuyau « texte | grep » traîne dans ce banc — course au tuyau cassé"
else
	ok "aucun « texte | grep » dans ce banc"
fi

# -----------------------------------------------------------------------------
if (( ECHOUES > 0 )); then
	printf '\n%sCe qui ne va pas :%s\n' "$GRAS" "$FIN"
	for e in "${ECHECS[@]}"; do printf '  %s·%s %s\n' "$ROUGE" "$FIN" "$e"; done
fi
printf '\n%s%d réussis, %d échoués%s\n\n' "$GRAS" "$REUSSIS" "$ECHOUES" "$FIN"
[[ "$ECHOUES" -eq 0 ]]
