# =============================================================================
#  LexOS — le terminal tel qu'on le veut (invite, alias, touche Tab)
# =============================================================================
#  POURQUOI CE FICHIER EXISTE, ET PAS SEULEMENT /etc/profile.d/lexos.sh
#
#  Tout ceci vivait dans /etc/profile.d/lexos.sh. Or /etc/profile.d n'est lu
#  QUE par un shell de connexion. Le terminal du bureau (xfce4-terminal)
#  démarre un shell interactif SANS connexion : il lit /etc/bash.bashrc puis
#  ~/.bashrc, et jamais /etc/profile.d. Autrement dit, l'invite verte et
#  orange de LexOS et les alias (ll, maj, infos) n'apparaissaient QUE dans la
#  console texte — c'est-à-dire presque jamais, puisqu'on ouvre le terminal
#  depuis le bureau.
#
#  Le contenu est donc ici, et trois chargeurs le lisent (hook 0120) :
#    · /etc/profile.d/lexos.sh   → shells de connexion (console texte, ssh)
#    · /etc/bash.bashrc          → tous les shells interactifs, root compris
#    · /etc/skel/.bashrc         → à la FIN, pour les comptes utilisateurs
#
#  Cette dernière ligne n'est pas un doublon : le ~/.bashrc de Debian pose SA
#  propre invite PS1, et il est lu APRÈS /etc/bash.bashrc. Sans un rappel à la
#  fin de ~/.bashrc, l'invite de LexOS serait posée puis aussitôt écrasée par
#  celle de Debian. D'où la règle suivie ici : l'invite et les alias se
#  REPOSENT à chaque passage (c'est sans effet de bord), tandis que ce qui ne
#  doit se produire qu'une fois — le logo d'accueil, le chargement de la
#  complétion — est tenu par le garde-fou LEXOS_SHELL_CHARGE.
# =============================================================================
# shellcheck shell=sh

# --- Confort (utile même hors interactif) ------------------------------------
export EDITOR="${EDITOR:-nano}"
export LESS="-R"
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth

# Tout ce qui suit n'a de sens que dans un shell INTERACTIF. Un script qui
# source ce fichier ne doit hériter ni de l'invite, ni des alias, ni du logo.
case "$-" in
	*i*) ;;
	*)   return 0 ;;
esac

# --- Où l'invite prend ses couleurs -----------------------------------------
#  Elles ne sont plus écrites ici. lexos-theme-gen les dépose dans ce fichier,
#  en même temps qu'il peint le terminal, et l'invite les relit à CHAQUE
#  affichage. Deux conséquences voulues :
#
#    · « lexos terminal jour » repeint les shells DÉJÀ ouverts, à la ligne
#      suivante — sans « source ~/.bashrc », sans rouvrir de fenêtre ;
#    · le vert de l'invite et le vert du fond de terminal sont désormais la
#      MÊME valeur écrite une seule fois. Avant, 38;5;35 d'un côté et
#      #00AF5F de l'autre disaient la même couleur dans deux langues, libres
#      de diverger — et sur le fond crème du thème de jour, les deux
#      devenaient illisibles ensemble.
#
#  __LEXOS_C_TEXTE s'appelait __LEXOS_C_SAISIE et valait l'orange de
#  l'accent. Il porte maintenant le BLANC de la frappe (voir la règle de
#  couleur plus bas). L'orange n'a pas quitté le terminal pour autant : il
#  est resté le curseur, la sélection et l'onglet actif — mais il ne touche
#  plus à l'invite, et c'est pour ça que le nom a changé avec lui.
#
#  Les valeurs de repli ci-dessous sont exactement celles d'avant (LexOS
#  Noir) : sans thème généré, rien ne change pour personne.
LEXOS_TERM_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/lexos/terminal.env"

__lexos_couleurs() {
	__LEXOS_C_MACHINE='38;5;35'
	__LEXOS_C_TEXTE='38;5;15'
	__LEXOS_C_ERREUR='1;38;5;196'
	__LEXOS_C_DIM='2'
	[ -r "$LEXOS_TERM_ENV" ] || return 0
	# shellcheck disable=SC1090
	. "$LEXOS_TERM_ENV" 2>/dev/null || return 0
	#  Couleurs vraies quand le terminal les annonce, palette 256 sinon.
	#  La console texte et les vieux ssh ne comprennent pas 38;2;r;g;b et
	#  afficheraient les chiffres en clair au milieu de l'invite.
	case "${COLORTERM:-}" in
		truecolor|24bit)
			__LEXOS_C_MACHINE="${LEXOS_PS_MACHINE:-$__LEXOS_C_MACHINE}"
			__LEXOS_C_TEXTE="${LEXOS_PS_TEXTE:-$__LEXOS_C_TEXTE}"
			__LEXOS_C_ERREUR="${LEXOS_PS_ERREUR:-$__LEXOS_C_ERREUR}"
			__LEXOS_C_DIM="${LEXOS_PS_DIM:-$__LEXOS_C_DIM}"
			;;
		*)
			__LEXOS_C_MACHINE="${LEXOS_PS_MACHINE_256:-$__LEXOS_C_MACHINE}"
			__LEXOS_C_TEXTE="${LEXOS_PS_TEXTE_256:-$__LEXOS_C_TEXTE}"
			__LEXOS_C_ERREUR="${LEXOS_PS_ERREUR_256:-$__LEXOS_C_ERREUR}"
			__LEXOS_C_DIM="${LEXOS_PS_DIM_256:-$__LEXOS_C_DIM}"
			;;
	esac
}
__lexos_couleurs

# --- Invite de commande ------------------------------------------------------
#  Reposée à chaque passage, exprès : voir l'explication en tête de fichier.
#
#  LA RÈGLE DE COULEUR, de jour comme de nuit — ALEX, PHOTO DU TERMINAL :
#  « écriture blanc pour écriture de utilisateur, vert pour lexos » :
#    · vert    — tout ce que la MACHINE écrit : le nom, la machine, le
#                CHEMIN et le CHEVRON. L'invite entière, donc.
#    · blanc   — tout ce que VOUS tapez
#    · rouge   — ce qui n'a pas marché (fausse commande, commande en échec)
#
#  Le chemin et le chevron étaient orange. Ils sont écrits par la MACHINE :
#  ils passent au vert. Le chevron garde son rouge quand la commande
#  précédente a échoué — c'est le seul signal que porte l'invite, on n'y
#  touche pas.
#
#  De jour, ce sont les mêmes trois rôles, en versions assombries : c'est
#  lexos-theme-gen qui fait la conversion, l'invite ne s'en occupe pas. Le
#  blanc y devient l'encre foncée, sans quoi la frappe disparaîtrait sur le
#  crème.
#
#  Le blanc de la frappe tient à un détail : PS1 se termine par une couleur
#  qu'on ne referme PAS. Elle déborde donc sur ce qui est saisi ensuite —
#  c'est voulu. PS0, affiché juste après Entrée et avant l'exécution, remet
#  le tout à zéro pour que la sortie de la commande retrouve le vert.
#
#  UNE SEULE LIGNE. ALEX, PHOTO DU TERMINAL : « l'écriture, la ligne est pas
#  complète et a déjà une espace — faire en sorte que ça suive ---> ». PS1
#  portait un saut de ligne juste avant le chevron : le nom, la machine et
#  le chemin sur une ligne, le chevron seul sur la suivante. Il est remplacé
#  par une espace. Celle qui SUIT le chevron était déjà là — c'est ce
#  qu'Alex avait relevé — et elle n'a pas été doublée.
if [ -n "${BASH_VERSION:-}" ]; then
	case "${TERM:-dumb}" in
		dumb|linux-m|unknown) ;;
		*)
			__lexos_git_branch() {
				git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's/^/ ⎇ /'
			}
			#  Le code de sortie doit être saisi AVANT toute autre chose :
			#  $(__lexos_git_branch) s'exécute pendant le calcul de l'invite
			#  et écrase $? au passage. PROMPT_COMMAND, lui, tourne avant.
			#  On en profite pour relire les couleurs : c'est ce qui rend la
			#  bascule jour/nuit visible sans relancer le shell. La lecture
			#  est une commande interne de bash sur un fichier de dix lignes,
			#  elle ne crée aucun processus.
			__lexos_etat() { __lexos_code=$?; __lexos_couleurs; }
			case "${PROMPT_COMMAND:-}" in
				*__lexos_etat*) ;;
				"")  PROMPT_COMMAND="__lexos_etat" ;;
				*)   PROMPT_COMMAND="__lexos_etat; $PROMPT_COMMAND" ;;
			esac
			#  Le chevron : VERT quand tout va bien — c'est la machine qui
			#  l'écrit, comme le nom et le chemin —, ROUGE quand la commande
			#  précédente a échoué. Une commande qui n'existe pas rend 127,
			#  et l'invite suivante s'ouvre donc en rouge.
			__lexos_fleche() {
				if [ "${__lexos_code:-0}" = "0" ]; then
					printf '\033[%sm' "$__LEXOS_C_MACHINE"
				else
					printf '\033[%sm' "$__LEXOS_C_ERREUR"
				fi
			}
			#  PS1 est en apostrophes simples : bash le REDÉVELOPPE à chaque
			#  affichage, donc les ${__LEXOS_C_*} suivent le thème courant.
			PS1='\[\033[${__LEXOS_C_MACHINE}m\]\u\[\033[2m\]@\[\033[0m\033[${__LEXOS_C_MACHINE}m\]\h\[\033[0m\] \[\033[${__LEXOS_C_MACHINE}m\]\w\[\033[0m\]\[\033[${__LEXOS_C_DIM}m\]$(__lexos_git_branch)\[\033[0m\] \[$(__lexos_fleche)\]❯\[\033[0m\] \[\033[${__LEXOS_C_TEXTE}m\]'
			PS0='\e[0m'
			;;
	esac
fi

# --- Une commande qui n'existe pas : le dire en rouge, et en français --------
#  bash répond « commande introuvable » dans la couleur courante — donc en
#  vert, comme une réponse normale. On la repeint en rouge et on rappelle le
#  mot qui ouvre l'aide. On ne remplace jamais un gestionnaire déjà posé
#  (Debian en installe un avec le paquet command-not-found).
if [ -n "${BASH_VERSION:-}" ] \
	&& ! command -v command_not_found_handle >/dev/null 2>&1; then
	command_not_found_handle() {
		printf '\033[%sm✗ commande inconnue : %s\033[0m\n' \
			"${__LEXOS_C_ERREUR:-1;38;5;196}" "$1" >&2
		printf '\033[%sm Tape « aide » pour la liste des commandes.\033[0m\n' \
			"${__LEXOS_C_DIM:-2}" >&2
		return 127
	}
fi

# --- Alias -------------------------------------------------------------------
alias ll='ls -alh --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'

#  Debian nomme la commande de « bat » BATCAT (conflit de nom avec Bacula) :
#  l'outil était installé et personne ne le trouvait. Même chose pour
#  git-delta, dont la commande est « delta » — celle-là porte déjà le bon
#  nom, on ne fait que le rappeler ici. Les gardes : ne jamais masquer un
#  vrai « bat » si l'utilisateur en installe un.
if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
	alias bat='batcat'
fi
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias maj='lexos upgrade'
alias infos='lexfetch'
# « aide » tout court : le premier mot qu'un francophone tape quand il est
# perdu. Il ouvre le sommaire des commandes.
alias aide='lexos aide'
# Les deux raccourcis du terminal jour / nuit, pour ne pas avoir à retenir
# la phrase complète.
alias jour='lexos terminal jour'
alias nuit='lexos terminal nuit'
#  « multi » : plusieurs volets dans un seul terminal (tmux).
#  ═══ ON NE LANCE PAS tmux D'OFFICE ICI, ET C'EST UN PIÈGE À TROIS DÉTENTES ═══
#  La tentation est forte — « comme ça tous les terminaux sont en volets » :
#    · un shell ouvert PAR UN PROGRAMME (Claude Code, un éditeur, le
#      gestionnaire de fichiers) se retrouverait dans tmux, où il n'a rien à
#      faire ;
#    · une session SSH ouvrirait un tmux DANS un tmux, où le préfixe de
#      l'extérieur mange celui de l'intérieur ;
#    · et qui n'aime pas tmux serait coincé dedans à chaque fenêtre, sans
#      savoir en sortir.
#  C'est une commande qu'on tape quand on en veut, pas un état imposé.
alias multi='lexos-multi'

# =============================================================================
#  À partir d'ici : une seule fois par shell.
# =============================================================================
[ -n "${LEXOS_SHELL_CHARGE:-}" ] && return 0
LEXOS_SHELL_CHARGE=1

# --- Terminal de jour ou de nuit : appliquer l'heure à l'ouverture ----------
#  En mode « auto », la minuterie systemd repasse tous les quarts d'heure —
#  mais si la session vient de s'ouvrir, ou si la machine a dormi tout
#  l'après-midi, le terminalrc sur le disque peut encore être celui de la
#  nuit. On rattrape ici, une seule fois, et en arrière-plan : la commande
#  réécrit deux petits fichiers, l'ouverture du terminal ne doit pas
#  l'attendre.
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] \
   && [ "$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/lexos/terminal-mode" 2>/dev/null)" = "auto" ] \
   && command -v lexos-terminal >/dev/null 2>&1; then
	( lexos-terminal --appliquer >/dev/null 2>&1 & ) 2>/dev/null
fi

# --- La touche Tab -----------------------------------------------------------
#  bash-completion est installé (lexos-core.list.chroot) et le ~/.bashrc de
#  Debian le charge déjà. Mais root n'a pas ce ~/.bashrc, et un utilisateur qui
#  a réécrit le sien se retrouverait sans rien — or la complétion « lexos » est
#  justement ce qui remplace le manuel pour un débutant. On s'assure donc
#  qu'elle est là, sans la charger deux fois.
if [ -n "${BASH_VERSION:-}" ] \
   && ! command -v _comp_load >/dev/null 2>&1 \
   && ! command -v _completion_loader >/dev/null 2>&1; then
	if [ -r /usr/share/bash-completion/bash_completion ]; then
		# shellcheck disable=SC1091
		. /usr/share/bash-completion/bash_completion
	fi
fi

# --- Bienvenue en console (pas dans les scripts, pas dans le terminal graphique)
if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && [ -z "${DISPLAY:-}" ] \
   && [ -z "${LEXOS_NO_BANNER:-}" ] && command -v lexfetch >/dev/null 2>&1; then
	lexfetch
fi
