#!/usr/bin/env bash
# =============================================================================
#  apt-sain.sh — rendre « apt-get update » fiable sur un coureur GitHub
# =============================================================================
#  ═══ CE QUE ÇA A COÛTÉ, DEUX FOIS ═══
#
#  1. LE 3 SEPTEMBRE : l'index pré-cuit dans l'image du coureur ne
#     correspondait plus au miroir.
#
#       E: Failed to fetch .../python3-pil_10.2.0-1ubuntu1.2_amd64.deb
#          404 Not Found
#
#     QUATRE étapes sont tombées d'un coup — dont une qui n'installait rien et
#     se contentait d'employer l'ImageMagick d'une étape précédente : elle a
#     annoncé « wallpaper.png n'est pas un lien symbolique », ce qui ne nomme
#     pas le vrai défaut. Une demi-journée de rouge pour une ligne.
#
#  2. LE 9 SEPTEMBRE, ET CELUI-CI A COÛTÉ UNE ISO ENTIÈRE :
#
#       E: Failed to fetch https://dl.google.com/linux/chrome-stable/deb/
#          dists/stable/main/binary-amd64/Packages.gz  Hash Sum mismatch
#          Last modification reported: Wed, 09 Sep 2026 09:41:12 +0000
#          Release file created at:    Wed, 09 Sep 2026 17:16:59 +0000
#
#     Le dépôt apt de Google Chrome avait publié un nouveau fichier Release
#     pendant que son réseau de diffusion servait encore l'ancien Packages.gz :
#     les empreintes ne concordaient plus. Rien à voir avec LexOS — ce dépôt
#     est ajouté par l'IMAGE DU COUREUR, et LexOS n'y prend RIEN.
#
#     Mais « apt-get update » rend 100 dès qu'UN SEUL index échoue, et
#     « bash -e » tue l'étape. La construction de l'ISO 120 est morte là, à
#     la sixième étape, avant même d'avoir commencé : une heure de
#     construction perdue pour un dépôt dont on n'a pas besoin.
#
#  ═══ D'OÙ LES DEUX MESURES, DANS CET ORDRE ═══
#
#  A. ON RETIRE LES DÉPÔTS TIERS QUE L'ON N'EMPLOIE PAS. Google Chrome,
#     Microsoft, Docker : l'image du coureur les ajoute pour d'autres projets.
#     Aucune étape de ce dépôt n'installe quoi que ce soit depuis eux — la
#     seule mention de google-chrome dans la CI est un « command -v », qui
#     interroge le BINAIRE déjà présent et se moque de la liste de sources.
#     Les garder, c'est accepter que la panne d'un tiers arrête nos
#     constructions. On ne les garde pas.
#
#     ON VISE PAR URL, PAS PAR NOM DE FICHIER. Sur Ubuntu 24.04 les sources
#     d'Ubuntu elles-mêmes vivent dans /etc/apt/sources.list.d/ubuntu.sources
#     (format deb822) : un « rm -rf sources.list.d/* » casserait apt en
#     entier. On lit donc le contenu, et on ne retire que ce qui pointe
#     ailleurs que chez Ubuntu.
#
#  B. ON RÉESSAIE, AVEC UNE ATTENTE QUI DOUBLE. Un miroir qui hoquète pendant
#     dix secondes ne doit pas coûter une heure de construction. Trois
#     nouvelles tentatives, 5 s puis 10 s puis 20 s.
#
#  CE QU'ON NE FAIT PAS, ET POURQUOI. On n'ajoute PAS « || true » et on ne
#  passe pas « --allow-unauthenticated » ni « -o APT::Update::Error-Mode=any ».
#  Faire taire l'erreur donnerait une étape verte et un paquet manquant plus
#  loin — exactement le 3 septembre, où le vrai défaut s'est annoncé sous un
#  nom qui n'avait rien à voir. Si l'index reste inaccessible après les
#  tentatives, on s'arrête et on le DIT.
# =============================================================================
set -uo pipefail

echo "── apt : préparation de l'index"

#  ── A. les dépôts tiers ──────────────────────────────────────────────────
#  ON GARDE CE QU'ON EMPLOIE, ON RETIRE LE RESTE — et pas l'inverse.
#
#  La première version de ce script nommait les coupables : Google, Microsoft,
#  Docker. Elle a été mise à l'épreuve pour de vrai dans la foulée, et elle a
#  échoué du premier coup — sur des dépôts qu'elle ne connaissait pas :
#
#    E: Failed to fetch https://ppa.launchpadcontent.net/deadsnakes/ppa/…
#       403 Forbidden
#    E: Failed to fetch https://ppa.launchpadcontent.net/ondrej/php/…
#       403 Forbidden
#
#  Deux domaines de plus à ajouter, une heure après en avoir ajouté trois.
#  Une liste de coupables est toujours en retard d'une image de coureur :
#  GitHub en change le contenu quand il veut, et chaque ajout est une panne
#  qui nous attend. On renverse donc la règle.
#
#  CE QUE LEXOS EMPLOIE VRAIMENT, ET RIEN D'AUTRE : l'archive Ubuntu du
#  coureur (shellcheck, xmllint, ImageMagick, ffmpeg, tmux, xvfb, python3-pil,
#  python3-psutil, librsvg2-bin…) et UN paquet .deb pris directement chez
#  deb.debian.org (live-build). Tout autre dépôt présent sur la machine est
#  un risque sans contrepartie : il ne peut rien nous apporter, il peut nous
#  arrêter. On le retire.
#
#  ET ON NE TOUCHE JAMAIS À CE QUI PORTE LE RESTE : sur Ubuntu 24.04 les
#  sources d'Ubuntu vivent elles aussi dans /etc/apt/sources.list.d/, dans
#  « ubuntu.sources » au format deb822. Un « rm -rf sources.list.d/* »
#  casserait apt en entier. On lit donc les ADRESSES de chaque fichier, et on
#  ne garde que celles d'Ubuntu et de Debian.
GARDES='ubuntu\.com|debian\.org'

RETIRES=0
for FICHIER in /etc/apt/sources.list.d/*; do
	[ -f "$FICHIER" ] || continue
	#  Les deux formats coexistent : « deb http://… » (une ligne) et deb822
	#  (« URIs: http://… »). Chercher les adresses couvre les deux.
	HOTES="$(grep -ohE 'https?://[^ ]+' "$FICHIER" 2>/dev/null \
	         | sed -E 's#https?://([^/]+).*#\1#' | sort -u)"
	#  Aucune adresse : rien à juger, on n'y touche pas.
	[ -n "$HOTES" ] || continue
	ETRANGER=0
	for HOTE in $HOTES; do
		grep -qE "$GARDES" <<< "$HOTE" || ETRANGER=1
	done
	if [ "$ETRANGER" = 1 ]; then
		sudo rm -f "$FICHIER"
		echo "   dépôt tiers retiré : $(basename "$FICHIER")  [$(tr '\n' ' ' <<< "$HOTES")]"
		RETIRES=$((RETIRES + 1))
	fi
done
[ "$RETIRES" = 0 ] && echo "   aucun dépôt tiers à retirer"

#  ── B. l'index, avec des tentatives ──────────────────────────────────────
ATTENTE=5
for ESSAI in 1 2 3 4; do
	if sudo apt-get update -qq; then
		echo "   index à jour (tentative $ESSAI)"
		exit 0
	fi
	if [ "$ESSAI" -lt 4 ]; then
		echo "   apt-get update a échoué (tentative $ESSAI) — on réessaie dans ${ATTENTE} s"
		sleep "$ATTENTE"
		ATTENTE=$((ATTENTE * 2))
	fi
done

echo "::error::apt-get update a échoué quatre fois de suite. Ce n'est plus un hoquet de miroir :"
echo "::error::lire l'erreur ci-dessus. Elle ne peut plus nommer qu'un dépôt Ubuntu ou Debian —"
echo "::error::les autres sont retirés au début de ce script. C'est donc une panne côté archive :"
echo "::error::attendre et relancer. Si une étape a VRAIMENT besoin d'un dépôt tiers, l'ajouter à"
echo "::error::GARDES dans .github/scripts/apt-sain.sh, en disant lequel et pourquoi."
exit 1
