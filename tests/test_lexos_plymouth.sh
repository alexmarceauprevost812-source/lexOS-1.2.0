#!/usr/bin/env bash
# =============================================================================
#  L'écran de démarrage — la mascotte se tient, le logo s'écrit, la pluie tombe
# =============================================================================
#  ALEX : mascotte fixe en haut, « LEXOS » qui s'écrit lettre par lettre en
#  dessous, pluie Matrix verte en fond, barre de progression passée au vert.
#
#  ═══ CE QUE CET ÉCRAN AVAIT DE CASSÉ ═══
#  La mascotte s'agitait en 16 images de 240×240 sur un écran de 1920×1080 :
#  un timbre-poste, flou dès qu'on l'agrandit, où l'on ne distinguait ni le
#  masque ni le geste de la main. Et deux animations en même temps — la
#  mascotte ET la barre — laissaient l'œil sans point d'accroche.
#
#  ═══ POURQUOI CE BANC EXISTE ═══
#  UN ÉCRAN DE DÉMARRAGE NE SE REGARDE QU'AU DÉMARRAGE SUIVANT. Une lettre de
#  la mauvaise taille décale tout l'alignement ; une lettre au fond opaque
#  découpe ses voisines pendant le glissement ; une courbe linéaire donne un
#  mouvement de robot — et RIEN de tout ça ne se voit avant d'avoir gravé une
#  clé, redémarré une machine et regardé une seconde et demie d'animation.
#  C'est le pire cycle de retour du dépôt.
#
#  ═══ CE BANC N'INSPECTE PAS LE HOOK : IL LE FAIT TOURNER ═══
#  Le fragment entre les marqueurs « banc: plymouth » est DÉCOUPÉ du hook 0300
#  et EXÉCUTÉ sur un faux thème, un faux dossier de marque et un vrai
#  ImageMagick. On regarde ensuite le thème PRODUIT, pas le code qui prétend
#  le produire. Trois passages, parce que ce sont les trois états qui
#  comptent :
#
#    · tout est là          -> thème complet, avec la pluie ;
#    · la pluie manque      -> thème complet SANS elle. Une décoration ne doit
#                              jamais pouvoir casser l'écran de démarrage ;
#    · une lettre manque    -> repli « two-step », et le journal le DIT.
#
#  S'y ajoutent les deux mesures que seule une lecture d'image donne : les
#  dimensions (en-tête PNG) et le détourage (canal alpha décodé pixel par
#  pixel).
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$RACINE/config/hooks/normal/0300-lexos-assets.hook.chroot"
BRANDING="$RACINE/branding"
GEN="$RACINE/config/includes.chroot/usr/bin/lexos-theme-gen"
BANC="$(mktemp -d)"
trap 'rm -rf "$BANC"' EXIT

reussis=0; echoues=0
ok()    { printf '  \033[32m✅\033[0m %s\n' "$1"; reussis=$((reussis+1)); }
non()   { printf '  \033[31m❌\033[0m %s\n' "$1"; echoues=$((echoues+1)); }
saut()  { printf '  \033[33m—\033[0m  %s\n' "$1"; }
titre() { printf '\n\033[1m═══ %s ═══\033[0m\n' "$1"; }

PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
IM=""
for c in magick convert; do command -v "$c" >/dev/null 2>&1 && { IM="$c"; break; }; done

# =============================================================================
titre "1. Les images sont là, aux dimensions EXACTES"
# =============================================================================
#  Les décalages du logo (0/102/202/304/418) ont été mesurés sur ces images-là.
#  Une lettre plus large ou plus étroite, et le mot se disloque — visible
#  seulement au démarrage suivant.
#
#  ON LIT L'EN-TÊTE PNG, on n'appelle pas ImageMagick : largeur et hauteur
#  sont aux octets 16 à 23, en gros boutiste, juste après la signature et
#  l'amorce du bloc IHDR. Aucune dépendance, et la même mesure qu'un outil
#  d'image.
dim_png() { # dim_png <fichier> -> « LxH »
	od -An -tu1 -j16 -N8 "$1" 2>/dev/null | awk '
		{ printf "%dx%d",
			$1*16777216 + $2*65536 + $3*256 + $4,
			$5*16777216 + $6*65536 + $7*256 + $8 }'
}

verifie_image() { # verifie_image <fichier> <LxH attendu>
	if [ ! -r "$BRANDING/$1" ]; then
		non "$1 absent de branding/"
		return 1
	fi
	VU="$(dim_png "$BRANDING/$1")"
	if [ "$VU" = "$2" ]; then
		ok "$1 : $VU"
		return 0
	fi
	non "$1 fait $VU au lieu de $2"
	return 1
}

MANQUE=0
verifie_image lexos-lettre-0.png  "98x138"   || MANQUE=1
verifie_image lexos-lettre-1.png  "98x138"   || MANQUE=1
verifie_image lexos-lettre-2.png  "100x138"  || MANQUE=1
verifie_image lexos-lettre-3.png  "112x138"  || MANQUE=1
verifie_image lexos-lettre-4.png  "100x138"  || MANQUE=1
verifie_image mascotte-splash.png "449x540"  || MANQUE=1
verifie_image pluie-demarrage.png "1920x1080" || true   # décoration : non bloquante

# =============================================================================
titre "2. Les lettres sont VRAIMENT détourées"
# =============================================================================
#  L'ASSERTION QUI COMPTE LE PLUS, ET LA MOINS VISIBLE. Une lettre au fond
#  NOIR OPAQUE se confond avec le fond noir de l'écran : elle a l'air
#  parfaite… jusqu'à ce qu'elle passe DEVANT sa voisine pendant le glissement
#  et lui découpe un rectangle. On ne verrait ça que sur une vidéo du
#  démarrage, image par image.
#
#  On ne se contente donc pas de « le PNG a un canal alpha » — un canal alpha
#  entièrement opaque en est un aussi. On décode les pixels et on COMPTE les
#  transparents.
if [ -z "$PY" ]; then
	saut "python3 absent : le détourage n'a PAS été mesuré"
elif [ "$MANQUE" = 1 ]; then
	saut "images manquantes : le détourage n'a PAS été mesuré"
else
	"$PY" - "$BRANDING" <<'PYEOF' > "$BANC/alpha.txt" 2>/dev/null || true
import sys, zlib, struct, os

def pixels(chemin):
    d = open(chemin, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    pos, idat, ihdr = 8, b'', None
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        data = d[pos+8:pos+8+ln]
        if typ == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', data[:13])
        elif typ == b'IDAT':
            idat += data
        pos += 12 + ln
    if ihdr is None:
        return None
    w, h, depth, ctype, comp, filt, entrelace = ihdr
    #  On ne traite que le cas qui nous intéresse : 8 bits, RVB+alpha, non
    #  entrelacé. Tout le reste rend None et le banc le DIT au lieu de deviner.
    if depth != 8 or ctype != 6 or entrelace != 0:
        return None
    brut = zlib.decompress(idat)
    bpp, stride = 4, w * 4
    sortie, prec = bytearray(), bytearray(stride)
    i = 0
    for _ in range(h):
        f = brut[i]; i += 1
        ligne = bytearray(brut[i:i+stride]); i += stride
        for x in range(stride):
            a = ligne[x-bpp] if x >= bpp else 0
            b = prec[x]
            c = prec[x-bpp] if x >= bpp else 0
            if f == 1:   ligne[x] = (ligne[x] + a) & 255
            elif f == 2: ligne[x] = (ligne[x] + b) & 255
            elif f == 3: ligne[x] = (ligne[x] + (a + b) // 2) & 255
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                ligne[x] = (ligne[x] + pr) & 255
        sortie += ligne
        prec = ligne
    return w, h, bytes(sortie)

racine = sys.argv[1]
for n in range(5):
    f = os.path.join(racine, 'lexos-lettre-%d.png' % n)
    r = pixels(f)
    if r is None:
        print('%d ERREUR 0' % n)
        continue
    w, h, px = r
    transp = sum(1 for i in range(3, len(px), 4) if px[i] == 0)
    print('%d %d %d' % (n, transp, w * h))
PYEOF
	if [ ! -s "$BANC/alpha.txt" ]; then
		non "le décodage des lettres n'a rien rendu — détourage NON vérifié"
	else
		while read -r NUM TRANSP TOTAL; do
			if [ "$TRANSP" = "ERREUR" ]; then
				non "lexos-lettre-$NUM.png : pas du 8 bits RVB+alpha non entrelacé — illisible ici"
			elif [ "$TRANSP" -gt 0 ] 2>/dev/null; then
				ok "lexos-lettre-$NUM.png : $(( 100 * TRANSP / TOTAL )) % de pixels transparents — vraiment détourée"
			else
				non "lexos-lettre-$NUM.png n'a AUCUN pixel transparent : elle découperait ses voisines"
			fi
		done < "$BANC/alpha.txt"
	fi
fi

# =============================================================================
titre "3. Le hook 0300 est DÉCOUPÉ et EXÉCUTÉ"
# =============================================================================
FRAGMENT="$BANC/fragment.sh"
sed -n '/^# >>> banc: plymouth$/,/^# <<< banc: plymouth$/p' "$HOOK" > "$FRAGMENT"
if [ "$(grep -c . "$FRAGMENT")" -lt 60 ]; then
	non "fragment « banc: plymouth » introuvable dans le hook 0300 — rien à éprouver"
	printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
	exit 1
fi
ok "fragment découpé du hook 0300 ($(grep -c . "$FRAGMENT") lignes) — c'est le vrai code qui tourne"

#  Le fragment attend trois choses que le hook lui donne plus haut : le
#  dossier de marque, le logo du watermark, et « have ». On les fournit,
#  et RIEN D'AUTRE — si le fragment se met un jour à dépendre d'autre chose,
#  il échouera ici au lieu de le faire en pleine construction d'ISO.
prelude() { # prelude <dossier-de-marque>
	printf '#!/bin/sh\nset -e\nBRAND="%s"\nLOGO_SRC=""\nhave() { command -v "$1" >/dev/null 2>&1; }\n' "$1"
}

#  ═══ UN « plymouth-set-default-theme » FACTICE, ET POURQUOI ═══
#  Le hook DÉSIGNE le thème par défaut après l'avoir écrit, et crie s'il n'y
#  arrive pas — un thème écrit mais jamais choisi ne s'affiche jamais.
#  Deux raisons de le simuler ici plutôt que d'employer le vrai :
#    · sur une machine sans Plymouth, le hook crierait à chaque passage et le
#      banc prendrait cet avertissement pour un défaut du dépôt ;
#    · sur une machine AVEC Plymouth — l'intégration continue en installe un
#      pour lire l'API du module — le vrai binaire changerait pour de bon
#      l'écran de démarrage de la machine qui lance le banc. Un banc ne
#      touche pas au système qui l'héberge.
#  Dans la vraie construction, il est là : le paquet plymouth fournit aussi le
#  thème « spinner » dont ce hook se sert de squelette.
STUB="$BANC/stub"
mkdir -p "$STUB"
printf '#!/bin/sh\nexit 0\n' > "$STUB/plymouth-set-default-theme"
chmod 755 "$STUB/plymouth-set-default-theme"

lance() { # lance <dossier-de-marque> <destination> -> journal sur stdout
	rm -rf "$2"
	{ prelude "$1"; cat "$FRAGMENT"; } > "$BANC/run.sh"
	PATH="$STUB:$PATH" LEXOS_PLYMOUTH_SRC="$BANC/spinner" LEXOS_PLYMOUTH_DST="$2" \
		sh "$BANC/run.sh" 2>&1
}

#  Un faux thème « spinner » : le hook en part par copie. Deux fichiers
#  suffisent — on éprouve ce que LexOS écrit, pas ce que Debian livre.
mkdir -p "$BANC/spinner"
: > "$BANC/spinner/spinner.plymouth"
: > "$BANC/spinner/throbber.png"

if [ -z "$IM" ]; then
	saut "ni magick ni convert : le thème n'a PAS été généré, les contrôles 3 à 5 sont sautés"
elif [ "$MANQUE" = 1 ]; then
	saut "images manquantes : le thème n'a PAS été généré"
else
	# --- Passage 1 : tout est là --------------------------------------------
	mkdir -p "$BANC/brand"
	cp "$BRANDING"/lexos-lettre-*.png "$BRANDING/mascotte-splash.png" "$BANC/brand/"
	[ -r "$BRANDING/pluie-demarrage.png" ] && cp "$BRANDING/pluie-demarrage.png" "$BANC/brand/"
	JOURNAL="$(lance "$BANC/brand" "$BANC/theme1")"
	SCRIPT="$BANC/theme1/lexos.script"

	if [ -r "$SCRIPT" ]; then
		ok "le thème « script » est produit ($(grep -c . "$SCRIPT") lignes)"
	else
		non "aucun lexos.script produit : l'écran de démarrage serait celui de Debian"
	fi

	if [ -r "$BANC/theme1/lexos.plymouth" ] && grep -q 'ModuleName=script' "$BANC/theme1/lexos.plymouth"; then
		ok "lexos.plymouth déclare bien le module « script »"
	else
		non "lexos.plymouth ne déclare pas le module « script »"
	fi

	#  ═══ LE CAS NOMINAL DOIT ÊTRE MUET ═══
	#  « !! » est le format des replis, et ce passage-ci n'en a aucun : toutes
	#  les images sont là, convert est là. Si un « !! » apparaissait quand même,
	#  ce serait soit un repli qui se déclenche sans raison — donc une ISO
	#  dégradée sans que personne ne l'ait voulu — soit un avertissement crié
	#  pour rien, ce qui apprend à ignorer les autres. Les deux comptent.
	if [ -z "$JOURNAL" ]; then
		#  Vert sur du vide : sans cette garde, un journal muet parce que le
		#  fragment n'a rien exécuté du tout passerait pour un succès.
		non "le fragment n'a rien écrit dans le journal — contrôle sans objet"
	elif grep -q '!!' <<< "$JOURNAL"; then
		non "un repli crie alors que tout est là : $(grep -m1 '!!' <<< "$JOURNAL")"
	else
		ok "aucun repli ne se déclenche quand tout est en place"
	fi

	#  Les six images sont VRAIMENT posées à côté du script — Plymouth les
	#  cherche dans son ImageDir, pas dans branding/.
	POSEES=0
	for F in lexos-lettre-0.png lexos-lettre-1.png lexos-lettre-2.png \
	         lexos-lettre-3.png lexos-lettre-4.png mascotte-splash.png; do
		[ -r "$BANC/theme1/$F" ] && POSEES=$((POSEES+1))
	done
	if [ "$POSEES" = 6 ]; then
		ok "les six images sont posées dans le thème, à côté du script"
	else
		non "$POSEES image(s) sur 6 posées dans le thème — Plymouth n'en trouverait pas"
	fi

	#  ET ELLES NE SONT PAS RETOUCHÉES. Le logo est du pixel carré : un
	#  passage dans convert le lisserait et lui ferait perdre son air d'écran
	#  cathodique. On compare octet pour octet.
	INTACTES=1
	for I in 0 1 2 3 4; do
		cmp -s "$BRANDING/lexos-lettre-$I.png" "$BANC/theme1/lexos-lettre-$I.png" || INTACTES=0
	done
	if [ "$INTACTES" = 1 ]; then
		ok "les lettres sont copiées OCTET POUR OCTET — jamais rééchantillonnées"
	else
		non "une lettre a été modifiée en chemin : le logo serait flou"
	fi

	# --- Ce que le script produit contient ----------------------------------
	if [ -r "$SCRIPT" ]; then
		ATTENDUS="0 102 202 304 418"
		VUS=""
		for I in 0 1 2 3 4; do
			VUS="$VUS $(sed -n "s/^lettre_dx\[$I\][[:space:]]*=[[:space:]]*\([0-9]\+\);.*/\1/p" "$SCRIPT" | head -1)"
		done
		VUS="${VUS# }"
		if [ "$VUS" = "$ATTENDUS" ]; then
			ok "les cinq décalages sont ceux mesurés sur le logo ($VUS)"
		else
			non "décalages « $VUS » au lieu de « $ATTENDUS » — le mot ne serait plus aligné"
		fi

		#  Le total 518 n'est pas un nombre écrit à côté : c'est le décalage
		#  de la DERNIÈRE lettre plus SA largeur réelle. Si Alex remplace un
		#  jour le S par un dessin plus large sans toucher au reste, ce
		#  contrôle le dit.
		DECL="$(sed -n 's/^logo_largeur[[:space:]]*=[[:space:]]*\([0-9]\+\);.*/\1/p' "$SCRIPT" | head -1)"
		L4="$(dim_png "$BRANDING/lexos-lettre-4.png")"; L4="${L4%x*}"
		SOMME=$(( 418 + L4 ))
		if [ "$SOMME" = "${DECL:-0}" ] && [ "$SOMME" = "518" ]; then
			ok "418 + la largeur réelle du S ($L4) = $SOMME, et c'est bien logo_largeur"
		else
			non "418 + $L4 = $SOMME, mais le script déclare logo_largeur=${DECL:-vide} (attendu 518)"
		fi

		#  LA COURBE EST CUBIQUE, ET C'EST TOUT L'EFFET : p = 1 − (1−t)³. La
		#  lettre part vite et se pose en douceur. Une interpolation linéaire
		#  donnerait un mouvement de robot avec un arrêt net — indiscernable
		#  dans un diff, évident à l'écran.
		if grep -qE '1[[:space:]]*-[[:space:]]*reste[[:space:]]*\*[[:space:]]*reste[[:space:]]*\*[[:space:]]*reste' "$SCRIPT"; then
			ok "le glissement suit une courbe CUBIQUE (1 − (1−t)³)"
		else
			non "pas de courbe cubique : le mouvement serait celui d'un robot"
		fi

		if grep -q 'SetOpacity(opacite)' "$SCRIPT" && grep -qE 'opacite[[:space:]]*=[[:space:]]*p[[:space:]]*\*' "$SCRIPT"; then
			ok "la lettre monte en opacité pendant son trajet"
		else
			non "l'opacité ne suit pas le trajet : la lettre surgirait au bord de l'écran"
		fi

		NB="$(grep -c 'lettre_sprite\[[0-4]\][[:space:]]*=[[:space:]]*Sprite()' "$SCRIPT")"
		if [ "$NB" = "5" ]; then
			ok "les cinq lettres ont chacune leur Sprite — elles n'arrivent pas ensemble"
		else
			non "$NB Sprite(s) de lettre au lieu de 5"
		fi

		NB="$(grep -c 'Image("lexos-lettre-[0-4].png")' "$SCRIPT")"
		if [ "$NB" = "5" ]; then
			ok "les cinq images de lettres sont chargées"
		else
			non "$NB image(s) de lettre chargée(s) au lieu de 5"
		fi

		if grep -q 'Plymouth.SetRefreshFunction' "$SCRIPT" && grep -q 'Plymouth.GetTime()' "$SCRIPT"; then
			ok "l'animation est pilotée par l'horloge de Plymouth"
		else
			non "aucune fonction de rafraîchissement : les lettres ne bougeraient pas"
		fi

		#  Une barre minutée qui avance toute seule est un mensonge poli, et
		#  elle ment surtout le jour où le démarrage bloque.
		if grep -q 'Plymouth.SetBootProgressFunction(progress_callback)' "$SCRIPT"; then
			ok "la barre est branchée sur la progression RÉELLE du démarrage"
		else
			non "la barre n'est plus branchée sur Plymouth : elle ferait semblant"
		fi

		if grep -q 'mascot-anim' "$SCRIPT"; then
			non "le thème produit référence encore mascot-anim-*.png"
		else
			ok "aucune référence aux 16 images : la mascotte est fixe"
		fi

		if grep -q 'Image("mascotte-splash.png")' "$SCRIPT"; then
			ok "la mascotte affichée est bien mascotte-splash.png"
		else
			non "le script n'affiche pas mascotte-splash.png"
		fi

		#  L'ordre de superposition. Une barre sous la mascotte disparaîtrait
		#  derrière elle ; une pluie au-dessus des lettres les voilerait.
		Z=1
		grep -q 'pluie_sprite.SetZ(1);'        "$SCRIPT" || Z=0
		grep -q 'mascotte_sprite.SetZ(10);'    "$SCRIPT" || Z=0
		grep -q 'SetZ(15);'                    "$SCRIPT" || Z=0
		grep -q 'progress_bg_sprite.SetZ(20);' "$SCRIPT" || Z=0
		grep -q 'progress_fg_sprite.SetZ(21);' "$SCRIPT" || Z=0
		if [ "$Z" = 1 ]; then
			ok "superposition : pluie 1, mascotte 10, lettres 15, barre 20/21"
		else
			non "l'ordre de superposition n'est pas 1 / 10 / 15 / 20 / 21"
		fi

		# --- La pluie -------------------------------------------------------
		if [ -r "$BANC/theme1/pluie-demarrage.png" ]; then
			ok "la pluie est copiée dans le thème, à côté du script"
		else
			non "la pluie n'est pas copiée dans le thème : Plymouth ne la trouverait pas"
		fi
		if grep -q 'pluie_image.Scale(Window.GetWidth(), Window.GetHeight())' "$SCRIPT"; then
			ok "la pluie est étirée à la fenêtre — elle tient à toute résolution"
		else
			non "la pluie n'est pas mise à l'échelle de la fenêtre"
		fi
	fi

	# --- Passage 2 : SANS la pluie ------------------------------------------
	titre "4. La pluie est une DÉCORATION — on la retire pour de vrai"
	#  Une décoration ne doit jamais pouvoir casser l'écran de démarrage.
	#  On ne lit pas le code pour s'en convaincre : on enlève l'image et on
	#  regénère.
	rm -rf "$BANC/brand2"; mkdir -p "$BANC/brand2"
	cp "$BRANDING"/lexos-lettre-*.png "$BRANDING/mascotte-splash.png" "$BANC/brand2/"
	J2="$(lance "$BANC/brand2" "$BANC/theme2")"
	S2="$BANC/theme2/lexos.script"
	if [ -r "$S2" ] && [ "$(grep -c . "$S2")" -gt 80 ]; then
		ok "sans la pluie, le thème se génère quand même ($(grep -c . "$S2") lignes)"
	else
		non "sans la pluie, le thème ne se génère plus — une décoration casse l'écran"
	fi
	if [ -r "$S2" ] && grep -q 'Image("pluie-demarrage.png")' "$S2"; then
		non "le script charge une pluie qui n'existe pas : image nulle au démarrage"
	else
		ok "le script ne charge pas d'image de pluie absente"
	fi
	if grep -q 'pluie-demarrage.png absente' <<< "$J2" ; then
		ok "l'absence de la pluie se DIT dans le journal de construction"
	else
		non "la pluie manque en silence — on ne saurait pas pourquoi l'écran est nu"
	fi
	if [ -r "$BANC/theme2/lexos.plymouth" ] && grep -q 'ModuleName=script' "$BANC/theme2/lexos.plymouth"; then
		ok "sans la pluie, on reste sur le thème animé (pas de repli inutile)"
	else
		non "l'absence de la pluie a fait retomber sur le repli statique"
	fi

	# --- Passage 3 : une lettre manque --------------------------------------
	titre "5. Une lettre manquante ne donne PAS un thème vide"
	rm -rf "$BANC/brand3"; mkdir -p "$BANC/brand3"
	cp "$BRANDING"/lexos-lettre-*.png "$BRANDING/mascotte-splash.png" "$BANC/brand3/"
	[ -r "$BRANDING/pluie-demarrage.png" ] && cp "$BRANDING/pluie-demarrage.png" "$BANC/brand3/"
	rm -f "$BANC/brand3/lexos-lettre-3.png"
	J3="$(lance "$BANC/brand3" "$BANC/theme3")"
	if [ -r "$BANC/theme3/lexos.plymouth" ] && grep -q 'ModuleName=two-step' "$BANC/theme3/lexos.plymouth"; then
		ok "le repli statique « two-step » est écrit — l'écran n'est pas vide"
	else
		non "pas de repli : une lettre absente donnerait un écran de démarrage nu"
	fi
	if [ ! -f "$BANC/theme3/lexos.script" ]; then
		ok "aucun lexos.script orphelin n'est laissé derrière"
	else
		non "un lexos.script traîne alors qu'on est en repli"
	fi
	#  ═══ LE REPLI DOIT CRIER, ET IL DOIT NOMMER ═══
	#  Un « echo » ordinaire noyé dans mille lignes de journal de construction
	#  ne vaut rien : c'est comme ça qu'une ISO est partie sans logo animé, et
	#  qu'on l'a découvert À L'ÉCRAN après avoir gravé et redémarré. Deux
	#  exigences, donc, et la seconde est la vraie : le format VOYANT « !! »
	#  employé partout ailleurs dans les hooks, ET le nom du fichier fautif.
	if grep -q '!!' <<< "$J3" ; then
		ok "le repli emploie le format voyant « !! »"
	else
		non "le repli chuchote — un echo ordinaire se perd dans le journal"
	fi
	if grep -q 'lexos-lettre-3.png' <<< "$J3" ; then
		ok "le repli NOMME le fichier manquant (lexos-lettre-3.png)"
	else
		non "le repli ne dit pas LEQUEL des sept fichiers manque"
	fi
	#  Nommer un fichier qui ne manque pas serait pire que se taire.
	if grep -q 'lexos-lettre-0.png' <<< "$J3" ; then
		non "le repli nomme lexos-lettre-0.png, qui est pourtant là"
	else
		ok "il ne nomme que ce qui manque vraiment"
	fi
	if grep -qE 'sans logo|SANS LOGO|two-step|statique' <<< "$J3" ; then
		ok "le repli dit ce qu'on perd (l'écran sortira sans le logo animé)"
	else
		non "le repli ne dit pas la conséquence — on ne sait pas ce qu'on livre"
	fi
	if grep -qE 'branding|À FAIRE|dimensions' <<< "$J3" ; then
		ok "le repli dit quoi faire pour corriger"
	else
		non "le repli ne dit pas comment s'en sortir"
	fi

	# --- Passage 4 : convert absent -----------------------------------------
	#  ═══ LE BOGUE DE L'ISO 112, ET LE CONTRÔLE QUI L'AURAIT PRIS ═══
	#  Tout le bloc « mascotte + lettres » était conditionné à « have convert ».
	#  Or les lettres sont posées par cp : elles n'ont aucun besoin
	#  d'ImageMagick — seules les deux images d'un pixel de la barre en ont un.
	#  Et imagemagick n'est PAS au socle : il ne vit que dans trois listes
	#  facultatives, posées par un hook qui tolère l'échec à dessein. Un miroir
	#  qui hoquète, et l'écran de démarrage partait sans mascotte et sans LEXOS.
	titre "5 bis. Sans ImageMagick, le logo s'affiche quand même"
	#  On ne PARLE pas de convert au hook : on le lui RETIRE. Un PATH sans
	#  convert, fabriqué par liens symboliques — lire la condition dans le
	#  fichier prouverait la forme de la ligne, pas le comportement.
	SANS="$BANC/sans-convert"
	rm -rf "$SANS"; mkdir -p "$SANS"
	for d in /usr/bin /bin /usr/sbin /sbin; do
		[ -d "$d" ] || continue
		for f in "$d"/*; do
			b="$(basename "$f")"
			case "$b" in convert|magick|convert-im6*|magick-im6*) continue ;; esac
			[ -e "$SANS/$b" ] || ln -s "$f" "$SANS/$b" 2>/dev/null
		done
	done
	if [ -x "$SANS/sh" ] && ! PATH="$SANS" command -v convert >/dev/null 2>&1; then
		rm -rf "$BANC/theme4"; mkdir -p "$BANC/theme4"
		{ prelude "$BRANDING"; cat "$FRAGMENT"; } > "$BANC/run4.sh"
		J4="$(env -i PATH="$SANS" \
			LEXOS_PLYMOUTH_SRC="$BANC/spinner" LEXOS_PLYMOUTH_DST="$BANC/theme4" \
			"$SANS/sh" "$BANC/run4.sh" 2>&1)"
		S4="$BANC/theme4/lexos.script"
		#  C'EST L'ASSERTION QUI COMPTE : sans convert, on reste sur le thème
		#  ANIMÉ. C'est exactement ce que l'ISO 112 ne faisait pas.
		if [ -r "$BANC/theme4/lexos.plymouth" ] \
		   && grep -q 'ModuleName=script' "$BANC/theme4/lexos.plymouth"; then
			ok "sans convert, le thème ANIMÉ est quand même écrit"
		else
			non "sans convert, tout retombe sur le thème statique — le bogue de l'ISO 112"
		fi
		for I in 0 1 2 3 4; do
			[ -r "$BANC/theme4/lexos-lettre-$I.png" ] \
				&& ok "la lettre $I est posée sans ImageMagick" \
				|| non "la lettre $I manque alors que cp n'a besoin de rien"
		done
		[ -r "$BANC/theme4/mascotte-splash.png" ] \
			&& ok "la mascotte est posée sans ImageMagick" \
			|| non "la mascotte manque alors que cp n'a besoin de rien"
		#  Même précaution que pour la pluie : ne pas écrire dans le script le
		#  nom d'une image qui n'existe pas. Plymouth se retrouverait avec une
		#  image nulle et un Sprite qui n'affiche rien.
		if [ -r "$S4" ] && grep -qE 'Image\("progress-(bg|fg)\.png"\)' "$S4"; then
			non "le script charge une image de barre inexistante"
		else
			ok "le script ne charge aucune image de barre absente"
		fi
		if grep -q '!!' <<< "$J4"; then
			ok "l'absence de convert est signalée en « !! »"
		else
			non "convert manque en silence — la barre disparaîtrait sans un mot"
		fi
	else
		saut "PATH sans convert impossible à fabriquer ici — contrôle sauté"
	fi
fi

# =============================================================================
titre "5 ter. Le script n'appelle que des fonctions qui EXISTENT"
# =============================================================================
#  ═══ LE BOGUE QUI A COÛTÉ L'ISO 112, ET QUE RIEN NE POUVAIT VOIR ═══
#  L'animation lisait son horloge dans « Plymouth.GetTime() ». CETTE FONCTION
#  N'EXISTE PAS. Elle n'est dans aucun binaire de Plymouth — ni dans script.so,
#  ni dans plymouthd, ni dans les greffons de rendu.
#
#  Et l'interpréteur de Plymouth NE SE PLAINT PAS d'une fonction inconnue : il
#  rend une valeur nulle et continue. Le temps écoulé restait donc nul, les
#  cinq lettres gardaient l'opacité 0 hors écran, et l'écran de démarrage
#  affichait la mascotte — fixe, elle — SANS le logo. Exactement le symptôme
#  rapporté : « je vois la mascotte, pas LEXOS ».
#
#  AUCUN CONTRÔLE NE POUVAIT LE PRENDRE : le fichier était bien écrit, bien
#  formé, bien copié, et le thème était bien le thème animé. Tout était vert.
#  Le seul contrôle qui mord est celui-ci — confronter chaque appel du script
#  produit à la LISTE RÉELLE des fonctions du module.
#
#  ET ON LIT CETTE LISTE DANS LE BINAIRE quand il est là, plutôt que de la
#  recopier : une liste recopiée vieillit en silence, et c'est précisément une
#  supposition sur l'API qui a produit ce bogue.
SO_SCRIPT=""
for c in /usr/lib/*/plymouth/script.so /usr/lib/plymouth/script.so; do
	[ -r "$c" ] && { SO_SCRIPT="$c"; break; }
done

#  La liste gelée sert quand Plymouth n'est pas installé sur la machine qui
#  lance le banc. Elle a été RELEVÉE dans script.so 24.004.60, pas recopiée
#  d'une documentation : ce sont les fonctions natives du module.
API_GELEE="SetRefreshRate SetRefreshFunction SetBootProgressFunction
SetRootMountedFunction SetKeyboardInputFunction SetUpdateStatusFunction
SetDisplayNormalFunction SetDisplayPasswordFunction SetDisplayQuestionFunction
SetDisplayPromptFunction SetDisplayMessageFunction SetDisplayHotplugFunction
SetHideMessageFunction SetMessageFunction SetQuitFunction
SetSystemUpdateFunction SetValidateInputFunction GetMode GetCapslockState"

if [ -n "$SO_SCRIPT" ]; then
	API="$(strings "$SO_SCRIPT" 2>/dev/null | grep -xE '(Get|Set)[A-Za-z]+')"
	ok "API relevée dans le vrai module ($SO_SCRIPT)"
else
	API="$(printf '%s\n' $API_GELEE)"
	saut "plymouth absent : liste d'API gelée (relevée dans script.so 24.004.60)"
fi

if [ -r "$BANC/theme1/lexos.script" ]; then
	#  On extrait les appels « Plymouth.Xxx( » du script PRODUIT. Les
	#  commentaires du script sont retirés d'abord : ils citent les noms de
	#  fonctions pour les expliquer, et un contrôle qui lit la prose se
	#  déclenche sur sa propre justification.
	APPELS="$(sed 's|//.*$||' "$BANC/theme1/lexos.script" \
		| grep -oE 'Plymouth\.[A-Za-z_]+' | sed 's/^Plymouth\.//' | sort -u)"
	if [ -z "$APPELS" ]; then
		non "aucun appel Plymouth.* trouvé dans le script — contrôle sans objet"
	else
		inconnus=""
		for f in $APPELS; do
			grep -qx "$f" <<< "$API" || inconnus="$inconnus $f"
		done
		if [ -z "$inconnus" ]; then
			ok "les $(printf '%s\n' $APPELS | grep -c .) appels Plymouth.* existent tous dans le module"
		else
			non "le script appelle des fonctions qui n'existent pas :$inconnus"
		fi
	fi
	#  Nommément, parce que c'est CE nom-là qui a coûté une ISO.
	if sed 's|//.*$||' "$BANC/theme1/lexos.script" | grep -q 'GetTime'; then
		non "« GetTime » est de retour — cette fonction n'existe pas dans Plymouth"
	else
		ok "aucun appel à « GetTime » (la fonction qui n'existe pas)"
	fi
	#  Une horloge, il en faut bien une : la cadence de rafraîchissement.
	if grep -q 'SetRefreshRate' "$BANC/theme1/lexos.script"; then
		ok "la cadence de rafraîchissement est imposée, pas devinée"
	else
		non "aucune cadence imposée — l'animation dépend d'un défaut non garanti"
	fi
	#  ET ELLE DOIT AVANCER. Un compteur qui n'est jamais incrémenté redonne
	#  le bogue à l'identique, en plus discret.
	if grep -qE 'rafraichissements *= *rafraichissements *\+' "$BANC/theme1/lexos.script"; then
		ok "le compteur de rafraîchissements avance à chaque passage"
	else
		non "rien n'incrémente le compteur — le temps resterait figé, comme avant"
	fi
else
	non "pas de lexos.script produit — rien à confronter à l'API"
fi

# =============================================================================
titre "5 quater. Le hook dit ce qu'il ne fait pas"
# =============================================================================
#  ═══ CODE DÉCOMMENTÉ ═══ Toute cette section PARLE de « have convert » et
#  d'« update-initramfs » pour expliquer les décisions. Chercher ces mots dans
#  le fichier brut se déclencherait sur les explications elles-mêmes. C'est la
#  famille d'erreur la plus fréquente de ce dépôt : le contrôle lit la prose.
CODE_PLY="$(sed 's/[[:space:]]*#.*$//' "$FRAGMENT")"
if [ "$(grep -c . <<< "$CODE_PLY")" -lt 40 ]; then
	non "le décommentage n'a presque rien laissé — contrôle invalide"
else
	#  LE CONTRÔLE QUI COMPTE : la copie des lettres ne doit plus être
	#  conditionnée à ImageMagick. cp n'a besoin de rien.
	if grep -qE 'PLY_LETTRES_OK.*=.*1.*&&.*have +convert' <<< "$CODE_PLY"; then
		non "les lettres dépendent encore de « have convert » — le bogue de l'ISO 112"
	else
		ok "la copie des lettres ne dépend plus d'ImageMagick"
	fi
	#  convert doit rester employé QUELQUE PART : la barre en a vraiment besoin.
	#  Sans ce second volet, supprimer convert du hook passerait pour un progrès.
	if grep -q 'convert' <<< "$CODE_PLY"; then
		ok "convert sert toujours à ce qui en a besoin (la barre)"
	else
		non "convert a disparu du hook — la barre ne peut plus être fabriquée"
	fi
fi
#  update-initramfs : soit il est appelé, soit le hook explique pourquoi il ne
#  l'est pas. « Le thème est sur le disque mais Plymouth en affiche un autre »
#  est la panne classique, et elle vient de là.
if grep -q 'update-initramfs' <<< "$CODE_PLY"; then
	ok "le hook régénère lui-même l'initramfs"
elif grep -qE 'update-initramfs' "$FRAGMENT" && grep -qE 'chroot_hacks|live-build' "$FRAGMENT"; then
	ok "le hook explique pourquoi l'initramfs n'est pas régénéré ici (live-build le fait)"
else
	non "ni appel à update-initramfs, ni explication : le thème pourrait ne jamais s'afficher"
fi

# =============================================================================
titre "6. La barre est VERTE — et elle le reste quel que soit l'accent"
# =============================================================================
if [ -n "$IM" ] && [ -r "$BANC/theme1/progress-fg.png" ] && [ -n "$PY" ]; then
	#  ON MESURE LE PIXEL PRODUIT, pas la ligne de commande qui prétend
	#  l'écrire. C'est un PNG d'un seul pixel : on lit sa couleur.
	COUL="$("$PY" - "$BANC/theme1" <<'PYEOF' 2>/dev/null
import sys, zlib, struct, os

#  ImageMagick n'ecrit PAS ces images d'un pixel en RVB. MESURE sur la vraie
#  sortie de « convert -size 1x1 xc:'#1F9E3D' » : c'est un PNG a PALETTE, un
#  seul bit de profondeur, dont la couleur vit dans le bloc PLTE. Une premiere
#  version ne lisait que le cas RVB et rendait « ? » — un controle qui ne
#  mesurait rien. On traite donc les deux formes, et on refuse de deviner pour
#  tout le reste.
def couleur(chemin):
    d = open(chemin, 'rb').read()
    pos, idat, plte, ihdr = 8, b'', None, None
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        data = d[pos+8:pos+8+ln]
        if typ == b'IHDR':   ihdr = struct.unpack('>IIBB', data[:10])
        elif typ == b'PLTE': plte = data
        elif typ == b'IDAT': idat += data
        pos += 12 + ln
    if ihdr is None:
        return '?'
    w, h, depth, ctype = ihdr
    brut = zlib.decompress(idat)
    if len(brut) < 2:
        return '?'
    octet = brut[1]                      # brut[0] = octet de filtre
    if ctype == 3 and plte:
        #  L'index du premier pixel occupe les bits de poids fort.
        idx = (octet >> (8 - depth)) & ((1 << depth) - 1)
        if len(plte) < 3 * (idx + 1):
            return '?'
        return '#%02X%02X%02X' % tuple(plte[3*idx:3*idx+3])
    if ctype in (2, 6) and depth == 8:
        return '#%02X%02X%02X' % tuple(brut[1:4])
    return '?'

r = sys.argv[1]
print(couleur(os.path.join(r, 'progress-fg.png')),
      couleur(os.path.join(r, 'progress-bg.png')))
PYEOF
)"
	VERT="${COUL%% *}"; GRIS="${COUL##* }"
	if [ "$VERT" = "#1F9E3D" ]; then
		ok "le pixel de remplissage MESURÉ est vert : $VERT"
	else
		non "le remplissage de la barre vaut « $VERT » au lieu de #1F9E3D"
	fi
	if [ "$GRIS" = "#1A1A1C" ]; then
		ok "le pixel de fond MESURÉ est le gris voulu : $GRIS"
	else
		non "le fond de la barre vaut « $GRIS » au lieu de #1A1A1C"
	fi
else
	saut "thème non généré ou python3 absent : les couleurs de la barre n'ont PAS été mesurées"
fi

#  ═══ LE PIÈGE, ET POURQUOI CE CONTRÔLE VAUT PLUS QU'IL N'EN A L'AIR ═══
#  #E8590C n'est pas une couleur, c'est un JETON : lexos-theme-gen le remplace
#  par l'accent courant (« lexos accent bleu »), et le hook 0600 fait pareil
#  pour l'écran de connexion. Si la barre de démarrage était écrite avec ce
#  jeton, elle changerait de couleur avec l'accent — un défaut qu'on ne
#  verrait qu'au démarrage suivant, longtemps après le changement qui l'a
#  causé.
#
#  ON DÉCOUPE SUR DES ANCRES ASCII, ET C'EST UNE LEÇON PAYÉE ICI MÊME. La
#  première version bornait le bloc sur « # --- Thème Plymouth ». Hors d'une
#  locale UTF-8, le « . » d'un sed ne couvre qu'UN OCTET et le « è » en fait
#  deux : la plage ne s'ouvrait jamais, le bloc sortait VIDE, et les grep qui
#  y cherchent une absence passaient au vert sans rien avoir lu. Un faux vert,
#  exactement ce que ce dépôt traque.
BLOC_PLY="$(awk '/^# >>> banc: plymouth$/{d=1} d{print} /^# <<< banc: plymouth$/{exit}' "$HOOK")"
if [ "$(printf '%s' "$BLOC_PLY" | grep -c .)" -lt 60 ]; then
	non "bloc Plymouth du hook 0300 introuvable — les contrôles suivants seraient vides"
	BLOC_PLY="__VIDE__"
else
	ok "bloc Plymouth découpé du hook ($(printf '%s' "$BLOC_PLY" | grep -c .) lignes)"
fi

if grep -q "xc:'#E8590C'" <<< "$BLOC_PLY" ; then
	non "la barre de démarrage est peinte avec le JETON d'accent : elle suivrait « lexos accent »"
else
	ok "la barre n'emploie pas le jeton d'accent — elle est hors du chemin de substitution"
fi

#  ET ON LE VÉRIFIE DE L'AUTRE CÔTÉ : aucun des deux programmes qui font la
#  substitution ne connaît Plymouth. Le jour où quelqu'un y ajoute le thème de
#  démarrage, ce contrôle rougit avant l'ISO.
SUBST=1
grep -qi 'plymouth' "$GEN" && SUBST=0
grep -qi 'plymouth' "$RACINE/config/hooks/normal/0600-lexos-theme.hook.chroot" && SUBST=0
if [ "$SUBST" = 1 ]; then
	ok "ni lexos-theme-gen ni le hook 0600 ne touchent au thème Plymouth"
else
	non "un programme de substitution d'accent nomme Plymouth — la barre pourrait changer de couleur"
fi

#  LA MESURE DEMANDÉE PAR ALEX : on lance vraiment le générateur avec un
#  accent NON-ORANGE et on regarde si le vert a bougé.
if [ -r "$GEN" ]; then
	AVANT="$(grep -c "xc:'#1F9E3D'" "$HOOK")"
	rm -rf "$BANC/accent"; mkdir -p "$BANC/accent"
	LEXOS_PANNEAU_CSS="$RACINE/config/includes.chroot/usr/share/lexos/gtk-panneau.css" \
		bash "$GEN" --target "$BANC/accent" bleu >/dev/null 2>&1 || true
	APRES="$(grep -c "xc:'#1F9E3D'" "$HOOK")"
	FUITE=0
	grep -rq '#1F9E3D' "$BANC/accent" 2>/dev/null && FUITE=1
	if [ "$AVANT" = "$APRES" ] && [ "$AVANT" -gt 0 ] && [ "$FUITE" = 0 ]; then
		ok "« lexos accent bleu » lancé pour de vrai : le vert de la barre est intact"
	else
		non "le vert de la barre a bougé après un changement d'accent (avant=$AVANT après=$APRES)"
	fi
else
	saut "lexos-theme-gen illisible : le changement d'accent n'a PAS été mesuré"
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLa mascotte se tient, le logo s'\''écrit, la pluie tombe, la barre est verte.\033[0m\n'
