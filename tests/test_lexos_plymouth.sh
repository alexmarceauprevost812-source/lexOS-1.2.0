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

		#  ═══ UN FAUX VERT, TROUVÉ EN PASSANT ═══
		#  Ce contrôle exigeait « Plymouth.GetTime() » dans le script — la
		#  fonction QUI N'EXISTE PAS, retirée depuis l'ISO 112 — et restait
		#  vert : l'en-tête du script la cite pour expliquer le bogue, et le
		#  grep lisait ce commentaire. Un contrôle qui aurait rougi si on
		#  avait RÉPARÉ le script, et qui passait parce qu'on l'expliquait.
		#  On lit les lignes de code : la fonction de rafraîchissement est
		#  branchée, et la cadence est imposée.
		CODE_SCRIPT="$(sed 's|//.*$||' "$SCRIPT")"
		if grep -q 'Plymouth.SetRefreshFunction(refresh_callback);' <<< "$CODE_SCRIPT" \
		   && grep -q 'Plymouth.SetRefreshRate(cadence);' <<< "$CODE_SCRIPT"; then
			ok "l'animation est pilotée par le compteur de rafraîchissements, à cadence imposée (lignes de code)"
		else
			non "pas de fonction de rafraîchissement branchée, ou pas de cadence imposée : les lettres ne bougeraient pas"
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
	#
	#  ET LE TEXTE NE REPART PAS DANS UN TUYAU. C'est un contrôle INVERSÉ —
	#  « si ce motif est là, rougis » — et c'est le sens où la course au tuyau
	#  cassé donne un FAUX VERT : « grep -q » sort au premier résultat, sed
	#  reçoit une erreur d'écriture, et sous pipefail le tuyau entier échoue
	#  alors que le motif interdit A ÉTÉ TROUVÉ. Le banc annoncerait que tout
	#  va bien au moment précis où il devrait crier. On garde donc le texte en
	#  mémoire, et grep le lit d'une chaîne.
	SANS_COMMENTAIRES="$(sed 's|//.*$||' "$BANC/theme1/lexos.script")"
	if grep -q 'GetTime' <<< "$SANS_COMMENTAIRES"; then
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
titre "7. De GRUB à Plymouth : la chaîne est entière, maillon par maillon"
# =============================================================================
#  ALEX, CONSIGNE « RECTANGLE BLEU », PARTIE 3 : vérifier que Plymouth prend
#  bien le relais de GRUB. Un thème parfait ne sert à rien si un maillon de
#  la chaîne manque, et chaque maillon est une CONDITION LUE DANS UN FICHIER
#  — pas une impression. Dans l'ordre où la machine les rencontre :
#    1. la ligne noyau porte « splash » (live : auto/config ; installé :
#       lexos.cfg) — sans lui, plymouthd ne se lance même pas ;
#    2. plymouth et plymouth-themes sont demandés (00-core.list), par une
#       liste que le hook 0250 pose pour TOUTES les saveurs ;
#    3. 0250 passe AVANT 0300 : le squelette « spinner » existe quand le
#       thème est construit ;
#    4. 0300 désigne le thème et CRIE s'il est refusé ;
#    5. l'initramfs est refait après nous (lb chroot_hacks) — dit dans 0300 ;
#    6. à l'extinction, plymouth-poweroff/reboot.service sont voulus par
#       poweroff/reboot.target et conditionnés par « splash » — lu dans les
#       unités du paquet, sur la machine qui l'a.
HOOK_0100="$RACINE/config/hooks/normal/0100-lexos-identity.hook.chroot"
HOOK_0250="$RACINE/config/hooks/normal/0250-lexos-optional.hook.chroot"
CORE_LIST="$RACINE/config/includes.chroot/usr/share/lexos/optional-packages/00-core.list"
STRICT_LIST="$RACINE/config/package-lists/lexos-core.list.chroot"
AUTO_CONFIG="$RACINE/auto/config"

#  1. « splash » sur la ligne noyau — lignes de CODE seulement, jamais les
#     commentaires (le piège du contrôle qui lit la prose).
CFG_CODE="$(sed -n '/^cat > \/etc\/default\/grub.d\/lexos.cfg <<EOF$/,/^EOF$/p' "$HOOK_0100" | grep -Ev '^[[:space:]]*(#|$)')"
if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\bsplash\b[^"]*"$' <<< "$CFG_CODE"; then
	ok "système installé : lexos.cfg met « splash » sur la ligne noyau (GRUB_CMDLINE_LINUX_DEFAULT)"
else
	non "système installé : « splash » manque dans GRUB_CMDLINE_LINUX_DEFAULT de lexos.cfg — plymouthd ne se lancerait pas"
fi
AUTO_CODE="$(grep -Ev '^[[:space:]]*(#|$)' "$AUTO_CONFIG" 2>/dev/null)"
if grep -qE '^BOOTAPPEND="[^"]*\bsplash\b[^"]*"$' <<< "$AUTO_CODE" \
   && grep -qE -- '--bootappend-live "\$\{BOOTAPPEND\}"' <<< "$AUTO_CODE"; then
	ok "session live : auto/config met « splash » dans BOOTAPPEND, passé à --bootappend-live"
else
	non "session live : « splash » n'atteint pas --bootappend-live dans auto/config"
fi
if grep -qE '^BOOTAPPEND_FAILSAFE="[^"]*\bnosplash\b[^"]*"$' <<< "$AUTO_CODE"; then
	ok "…et le mode sans échec dit « nosplash », à dessein : la console reste visible"
else
	non "le mode sans échec ne coupe pas Plymouth : en dépannage on ne verrait pas les messages"
fi

#  2. Les paquets sont demandés, et par une liste posée pour toutes les saveurs.
for P in plymouth plymouth-themes; do
	if grep -qxF "$P" < <(grep -Ev '^[[:space:]]*(#|$)' "$CORE_LIST"); then
		ok "« $P » est demandé par 00-core.list (ligne de code, pas un commentaire)"
	else
		non "« $P » n'est pas dans 00-core.list : sans lui, pas de thème du tout"
	fi
done
if grep -qE '^LISTS="[^"]*\b00-core\.list\b' "$HOOK_0250"; then
	ok "00-core.list est dans la liste de BASE du hook 0250 — posée même en saveur « minimal »"
else
	non "00-core.list n'est plus dans LISTS= du hook 0250 : une saveur pourrait partir sans Plymouth"
fi
#  CE QUE CETTE CHAÎNE A DE FRAGILE, DIT EN CLAIR. Le hook 0250 TOLÈRE un
#  paquet qui ne s'installe pas : il le note dans /etc/lexos/optional-report
#  et continue. Plymouth n'est pas au socle strict. Ce n'est pas un défaut
#  à corriger ici — c'est une décision qu'Alex prend en connaissance de cause.
if grep -qxF plymouth < <(grep -Ev '^[[:space:]]*(#|$)' "$STRICT_LIST"); then
	ok "plymouth est au socle STRICT (lexos-core.list.chroot) : un miroir qui hoquète ne peut pas l'emporter"
else
	saut "plymouth N'EST PAS au socle strict : posé par 00-core.list, dont le hook 0250 tolère l'échec (le hook 0300 crie alors, la construction continue)"
fi

#  3. L'ordre des hooks : les paquets avant le thème.
H1="$(basename "$HOOK_0250")"; H2="$(basename "$HOOK")"
if [ "$(printf '%s\n%s\n' "$H1" "$H2" | sort | head -1)" = "$H1" ] && [ "$H1" != "$H2" ]; then
	ok "0250 (paquets) passe avant 0300 (thème) : le squelette « spinner » existe quand on le copie"
else
	non "le hook des paquets ne passe plus avant celui du thème : « spinner » manquerait"
fi

#  4. Le thème est DÉSIGNÉ, et un refus est dit — pas avalé par « || true ».
FRAG="$(sed -n '/^# >>> banc: plymouth$/,/^# <<< banc: plymouth$/p' "$HOOK" | grep -Ev '^[[:space:]]*#')"
if grep -qE '^[[:space:]]*elif plymouth-set-default-theme lexos' <<< "$FRAG" \
   && ! grep -qE 'plymouth-set-default-theme lexos.*\|\|[[:space:]]*true' <<< "$FRAG"; then
	ok "0300 désigne « lexos » par plymouth-set-default-theme et traite le refus comme un cas à part"
else
	non "0300 ne désigne pas le thème, ou avale son refus : un thème écrit mais jamais choisi"
fi

#  5. L'initramfs : 0300 ne l'appelle pas, et dit POURQUOI (lb chroot_hacks).
if ! grep -qE '^[[:space:]]*update-initramfs' <<< "$FRAG" \
   && grep -q 'lb_chroot_hacks' "$HOOK"; then
	ok "0300 n'appelle pas update-initramfs et nomme celui qui le fait (lb chroot_hacks)"
else
	non "0300 appelle update-initramfs, ou ne dit plus qui refait l'initramfs après lui"
fi

#  6. L'extinction : lu dans les unités systemd du paquet plymouth.
UNITS=/usr/lib/systemd/system
if [ ! -r "$UNITS/plymouth-poweroff.service" ]; then
	saut "plymouth n'est pas installé ici : les unités d'extinction ne sont pas lues (elles le sont en CI)"
else
	for U in poweroff reboot; do
		S="$UNITS/plymouth-$U.service"
		if [ -e "$UNITS/$U.target.wants/plymouth-$U.service" ] \
		   && grep -qxF 'ConditionKernelCommandLine=splash' "$S" \
		   && grep -qE '^ExecStart=.*plymouthd --mode=(shutdown|reboot)' "$S"; then
			ok "plymouth-$U.service : voulu par $U.target, conditionné par « splash », lance plymouthd en mode $( [ "$U" = poweroff ] && echo shutdown || echo reboot )"
		else
			non "plymouth-$U.service : pas voulu par $U.target, ou sans condition « splash », ou n'est plus plymouthd"
		fi
	done
fi

# =============================================================================
titre "8. L'extinction — la vieille télé, en 2 secondes"
# =============================================================================
#  ALEX, consigne « fenêtre d'arrêt », partie 2 : à l'arrêt et au redémarrage,
#  l'écran s'écrase en une ligne blanche comme un vieux téléviseur, noir une
#  seconde, puis LEXOS. Ce que le banc mesure, sur le thème produit par le
#  VRAI fragment du hook (theme1, avec convert ; theme4, sans) :
#    · la branche s'ouvre sur Plymouth.GetMode(), pour « shutdown » ET
#      « reboot », en lignes de code ;
#    · les quatre durées sont nommées, en tête, et leur somme tient en 2 s ;
#    · blanc.png est UN pixel blanc opaque ; bye-bye.png est la composition
#      exacte des cinq lettres — comparée PIXEL PAR PIXEL à une composition
#      Pillow, pas « une image de 518 de large » ;
#    · l'écrasement passe par Image.Scale, le seul procédé du module pour
#      redessiner une image à une autre taille ;
#    · le démarrage est caché à l'extinction (mascotte, pluie, barre) ;
#    · sans convert, le script ne cite aucune des deux images, garde une
#      placer_extinction vide, et le journal le dit en « !! ».
if [ -z "$IM" ] || [ "$MANQUE" = 1 ] || [ ! -r "${SCRIPT:-/nonexistent}" ]; then
	saut "thème non généré plus haut : l'extinction n'est pas mesurée"
elif [ -z "$PY" ] || ! "$PY" -c 'import PIL' >/dev/null 2>&1; then
	#  Les sections 1 et 2 décodent les PNG à la main, à dessein. Ici on
	#  compare une composition d'images : Pillow est nécessaire, et son
	#  absence se DIT — sans elle, deux contrôles rougissaient avec un
	#  message faux (« blanc.png n'est pas un pixel blanc opaque » alors
	#  qu'elle l'était).
	saut "python3 ou Pillow absent : blanc.png et bye-bye.png ne sont PAS mesurées"
else
	CODE="$(sed 's|//.*$||' "$SCRIPT")"
	if grep -q 'mode = Plymouth.GetMode();' <<< "$CODE" \
	   && grep -q 'if (mode == "shutdown")' <<< "$CODE" \
	   && grep -q 'if (mode == "reboot")' <<< "$CODE"; then
		ok "la branche d'extinction s'ouvre sur Plymouth.GetMode(), pour « shutdown » ET « reboot »"
	else
		non "pas de branche sur GetMode() pour shutdown et reboot (lignes de code) — l'arrêt montrerait le démarrage"
	fi
	#  Les durées : nommées, en tête (avant la première « fun »), et lisibles
	#  comme des nombres.
	TETE="$(sed 's|//.*$||' "$SCRIPT" | sed '/^fun /q')"
	SOMME="$("$PY" - "$TETE" <<'PYSUM'
import re, sys
tete = sys.argv[1]; total = 0.0; n = 0
for nom in ("tele_ecrasement_duree", "tele_point_duree", "tele_noir_duree", "tele_adieu_duree"):
    m = re.search(r'^\s*' + nom + r'\s*=\s*([0-9.]+)\s*;', tete, re.M)
    if not m: print("MANQUE", nom); sys.exit(0)
    total += float(m.group(1)); n += 1
print("%.2f" % total)
PYSUM
)"
	case "$SOMME" in
		MANQUE*) non "une durée d'extinction n'est pas en tête du script, en variable nommée : $SOMME" ;;
		*) if "$PY" -c "import sys; sys.exit(0 if float(sys.argv[1]) <= 2.0 else 1)" "$SOMME"; then
			   ok "quatre durées nommées en tête, somme $SOMME s ≤ 2,0 s"
		   else
			   non "les quatre durées font $SOMME s : plus que les 2 s demandées"
		   fi ;;
	esac
	#  Les images, mesurées.
	if [ -r "$BANC/theme1/blanc.png" ] && [ "$("$PY" - "$BANC/theme1/blanc.png" <<'PYB'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
print(im.size == (1, 1) and im.getpixel((0, 0)) == (255, 255, 255, 255))
PYB
)" = "True" ]; then
		ok "blanc.png : un pixel, blanc, opaque"
	else
		non "blanc.png manque ou n'est pas un pixel blanc opaque — l'écrasement n'aurait rien à étirer"
	fi
	if [ -r "$BANC/theme1/bye-bye.png" ]; then
		DIFF="$("$PY" - "$BANC/theme1/bye-bye.png" "$BRANDING" <<'PYBB'
import sys
from PIL import Image
b = Image.open(sys.argv[1]).convert("RGBA")
dx = [0, 102, 202, 304, 418]
lettres = [Image.open("%s/lexos-lettre-%d.png" % (sys.argv[2], i)).convert("RGBA") for i in range(5)]
larg = max(x + l.size[0] for x, l in zip(dx, lettres)); haut = max(l.size[1] for l in lettres)
if b.size != (larg, haut): print("taille %dx%d au lieu de %dx%d" % (b.size[0], b.size[1], larg, haut)); sys.exit(0)
ref = Image.new("RGBA", (larg, haut), (0, 0, 0, 0))
for x, l in zip(dx, lettres): ref.alpha_composite(l, (x, 0))
diff = sum(1 for p, q in zip(ref.get_flattened_data() if hasattr(ref, "get_flattened_data") else ref.getdata(),
                                 b.get_flattened_data() if hasattr(b, "get_flattened_data") else b.getdata()) if p != q)
print(diff)
PYBB
)"
		if [ "$DIFF" = "0" ]; then
			ok "bye-bye.png est la composition EXACTE des cinq lettres aux décalages du logo (0 pixel d'écart avec Pillow)"
		else
			non "bye-bye.png diffère de la composition des lettres : $DIFF"
		fi
	else
		non "bye-bye.png n'a pas été fabriquée alors que convert est là"
	fi
	#  Le procédé, et ce qui est caché.
	#  ═══ ÉTIRER UNE FOIS, DÉCOUPER ENSUITE ═══
	#  Mesuré dans le vrai interpréteur : Image.Scale d'un pixel vers
	#  1920×1080 coûte ~50 ms, à 50 images par seconde — l'horloge du script
	#  compte des IMAGES, elle se serait donc étirée pendant l'écrasement.
	#  Le plein écran est étiré une seule fois, sous garde d'extinction, et
	#  chaque image n'en prend qu'une découpe (~5 ms).
	if grep -q 'tele_plein = tele_image.Scale(Window.GetWidth(), Window.GetHeight());' <<< "$CODE" \
	   && grep -q 'tele_sprite.SetImage(tele_plein.Crop(0, 0, largeur, h));' <<< "$CODE" \
	   && grep -q 'tele_sprite.SetImage(tele_plein.Crop(0, 0, l, tele_ligne_hauteur));' <<< "$CODE"; then
		ok "le blanc est étiré UNE fois (Image.Scale) puis découpé à chaque image (Image.Crop) — hauteur, puis largeur"
	else
		non "l'écrasement étire l'image à chaque passage, ou ne passe pas par Crop : ~50 ms par image, l'horloge dérive"
	fi
	SCALES="$(grep -c 'tele_image.Scale(' <<< "$CODE")"
	[ "${SCALES:-0}" = "1" ] \
		&& ok "…et le pixel blanc n'est étiré qu'à UN seul endroit du script" \
		|| non "tele_image.Scale apparaît $SCALES fois : le coût par image revient"
	#  ═══ PAS DE « | grep -q » : on capture, puis on lit d'une chaîne ═══
	#  Règle du dépôt : sous « set -o pipefail », un grep -q qui ferme le
	#  tuyau tôt fait échouer le producteur, et le verdict devient faux.
	#  Les blocs « if (extinction == 1) { … } » en ENTIER — il y en a
	#  plusieurs, de longueurs différentes (une ligne pour la mascotte,
	#  deux pour la barre) : un « grep -A1 » n'en verrait que le début, et
	#  déclarerait manquante une ligne qui est là.
	BLOC_EXT="$(awk '/if \(extinction == 1\) \{/{d=1} d{print} /^\}|^    \}|^\t*\}$/{if(d)d=0}' <<< "$CODE")"
	CACHES=1
	grep -q 'mascotte_sprite.SetOpacity(0);' <<< "$BLOC_EXT" || CACHES=0
	grep -q 'pluie_sprite.SetOpacity(0);'    <<< "$BLOC_EXT" || CACHES=0
	#  ═══ LA BARRE : CE QUE LA GARDE ENFERME, PAS SA PRÉSENCE ═══
	#  Premier jet : le contrôle se contentait de trouver la ligne « if
	#  (extinction == 0) { ». Mutation jouée par la revue : garde VIDE et
	#  corps de la barre déplacé dehors — le banc restait vert alors que la
	#  barre se dessinait à l'arrêt. On exige donc que les deux SetImage
	#  soient DANS la garde, et qu'aucun ne soit dehors.
	BARRE_CODE="$(sed -n '/^fun progress_callback/,/^}/p' <<< "$CODE")"
	GARDE="$(sed -n '/if (extinction == 0) {/,/^  }/p' <<< "$BARRE_CODE")"
	DEDANS="$(grep -c 'progress_[bf]g_sprite.SetImage(' <<< "$GARDE")"
	TOTAL="$(grep -c 'progress_[bf]g_sprite.SetImage(' <<< "$BARRE_CODE")"
	[ "${DEDANS:-0}" -ge 2 ] && [ "$DEDANS" = "$TOTAL" ] || CACHES=0
	#  Et les deux sprites de la barre sont RENDUS TRANSPARENTS : mesuré
	#  dans le vrai interpréteur, un Sprite naît opaque en (0,0) — sans
	#  ça, un pixel vert sur un pixel gris reste en haut à gauche pendant
	#  le noir et l'adieu, alors même que progress_callback ne dessine rien.
	grep -q 'progress_bg_sprite.SetOpacity(0);' <<< "$BLOC_EXT" || CACHES=0
	grep -q 'progress_fg_sprite.SetOpacity(0);' <<< "$BLOC_EXT" || CACHES=0
	if [ "$CACHES" = 1 ]; then
		ok "à l'extinction : mascotte et pluie cachées, les deux sprites de la barre à l'opacité 0, et tout son dessin sous la garde ($DEDANS/$TOTAL)"
	else
		non "le démarrage transparaît à l'extinction (mascotte, pluie, ou barre encore dessinée : $DEDANS SetImage sous garde sur $TOTAL)"
	fi
	if grep -q 'placer_extinction(ecoule);' <<< "$BLOC_EXT" \
	   && grep -q 'placer_lettre(0, ecoule);' <<< "$CODE"; then
		ok "refresh_callback aiguille : placer_extinction à l'arrêt, placer_lettre au démarrage"
	else
		non "refresh_callback n'aiguille pas entre extinction et démarrage"
	fi
	if grep -q 'adieu_sprite.SetOpacity(t);' <<< "$CODE" \
	   && grep -q 'adieu_image = Image("bye-bye.png");' <<< "$CODE" \
	   && grep -q 'adieu_sprite.SetZ(40);' <<< "$CODE"; then
		ok "LEXOS (bye-bye.png) monte en opacité au-dessus de tout (Z 40) après le noir"
	else
		non "bye-bye.png n'est pas affichée, ou pas au-dessus du reste"
	fi
	#  Les phases se décident par des « if » successifs. « && », « || »,
	#  « else if » et « return » EXISTENT dans le module (table des symboles
	#  de script.so, sondés dans l'interpréteur) : ce n'est pas une réserve
	#  sur le langage, c'est un choix de lisibilité — chaque ligne se lit
	#  seule, et une phase de plus s'ajoute sans toucher aux autres.
	TELE_CODE="$(sed -n '/^fun placer_extinction/,/^}/p' <<< "$CODE")"
	if [ -n "$TELE_CODE" ] && ! grep -qE '&&|\|\||else if|return' <<< "$TELE_CODE"; then
		ok "placer_extinction se lit en « if » successifs, sans &&, ||, else if ni return"
	else
		non "placer_extinction a perdu sa forme en « if » successifs"
	fi
	#  Sans convert : rien de cité qui n'existe pas, une fonction vide, et un cri.
	if [ -r "${S4:-/nonexistent}" ]; then
		S4_CODE="$(sed 's|//.*$||' "$S4")"
		if ! grep -qE 'Image\("(blanc|bye-bye)\.png"\)' <<< "$S4_CODE" \
		   && grep -q 'fun placer_extinction(ecoule)' <<< "$S4_CODE" \
		   && grep -q 'placer_extinction(ecoule);' <<< "$S4_CODE"; then
			ok "sans convert : aucune des deux images n'est citée, placer_extinction existe (vide) et reste appelée"
		else
			non "sans convert : le script cite une image absente, ou n'a plus de placer_extinction"
		fi
		if grep -qi 'extinction' <<< "$J4" && grep -q '!!' <<< "$J4"; then
			ok "…et le journal dit en « !! » que l'extinction sera sans animation"
		else
			non "…mais le journal ne dit pas que l'extinction est dégradée"
		fi
		[ -e "$BANC/theme4/blanc.png" ] || [ -e "$BANC/theme4/bye-bye.png" ] \
			&& non "sans convert, une image d'extinction traîne quand même dans le thème" \
			|| ok "sans convert, aucune image d'extinction n'est laissée dans le thème"
	else
		saut "le passage sans convert n'a pas tourné : la dégradation de l'extinction n'est pas mesurée"
	fi
fi

# =============================================================================
titre "9. Le harnais réel — FAIRE TOURNER le script dans le module de Plymouth"
# =============================================================================
#  ═══ POURQUOI CE QUI PRÉCÈDE NE SUFFIT PAS ═══
#  Toutes les sections précédentes LISENT le script produit : elles cherchent
#  des lignes, comptent des accolades, comparent des motifs. C'est ainsi que
#  l'ISO 112 est partie sans logo — le script appelait « GetTime() », une
#  fonction absente du module, l'interpréteur rendait une valeur nulle sans
#  un mot, et un banc qui ne lit que du texte ne pouvait rien voir : le
#  fichier était bien formé, bien copié, le thème bien le thème animé.
#
#  Cette section EXÉCUTE le script dans le vrai module de Plymouth
#  (/usr/lib/*/plymouth/script.so, celui que Plymouth charge lui-même) grâce
#  à tests/aide/plymouth-harnais.c, compilé ici. On avance l'horloge du
#  thème (l'équivalent du temps qui passe), on demande l'état de n'importe
#  quel sprite, et on compare à ce que la consigne « fenêtre d'arrêt »
#  demande — pas à ce que le fichier source ÉCRIT.
HARNAIS_SRC="$RACINE/tests/aide/plymouth-harnais.c"
HARNAIS="$BANC/harnais"
SCRIPT_SO=""
for c in /usr/lib/*/plymouth/script.so /usr/lib/plymouth/script.so; do
	[ -r "$c" ] && { SCRIPT_SO="$c"; break; }
done
LIBPLY=""
for c in /usr/lib/*/libply.so.5 /usr/lib/libply.so.5; do
	[ -r "$c" ] && { LIBPLY="$c"; break; }
done
if [ -z "$IM" ] || [ "$MANQUE" = 1 ] || [ ! -r "${SCRIPT:-/nonexistent}" ]; then
	saut "thème non généré plus haut : rien à faire tourner"
elif ! command -v gcc >/dev/null 2>&1; then
	saut "gcc absent : le harnais n'est pas compilé, la section 9 est sautée"
elif [ -z "$SCRIPT_SO" ] || [ -z "$LIBPLY" ]; then
	saut "script.so ou libply.so.5 absent (paquets plymouth / libplymouth5) : rien à charger"
elif ! gcc -O0 -o "$HARNAIS" "$HARNAIS_SRC" -ldl 2>"$BANC/harnais.err"; then
	non "le harnais ne compile pas : $(head -1 "$BANC/harnais.err")"
else
	#  Fenêtre factice : sans backend graphique, Window.GetWidth()/GetHeight()
	#  rendent 0. On les remplace AVANT de charger le script — exactement ce
	#  que Plymouth fournit lui-même à l'exécution.
	FENETRE='Window.GetWidth = fun () { return 1920; }; Window.GetHeight = fun () { return 1080; };'

	#  sonder <mode> <compteur> <nom1> <expr1> [<nom2> <expr2> …] -> une
	#  ligne « nom = valeur » par sonde. Chaque « nom » DOIT être un simple
	#  identifiant : « -q » du harnais cherche une variable GLOBALE par ce
	#  nom exact dans la table de hachage — lui passer une expression
	#  composée (« tele_sprite.GetImage().GetWidth() ») ne trouverait rien,
	#  d'où l'étape « nom = expression; » qui crée d'abord une variable
	#  simple. Chaque appel recharge le script à froid : le compteur est
	#  une horloge ABSOLUE (rafraichissements = 0 au départ), pas un delta
	#  — la même façon de compter que le script lui-même.
	sonder() {
		local mode="$1" n="$2"; shift 2
		local sondes="" args=()
		while [ "$#" -ge 2 ]; do
			sondes="${sondes}$1 = ${2};"
			args+=(-q "$1")
			shift 2
		done
		"$HARNAIS" -m "$mode" -i "$BANC/theme1" -s "$FENETRE" -f "$SCRIPT" \
			-r "$n" -s "$sondes" "${args[@]}" 2>"$BANC/sonde.err"
	}
	valeur() { sed -n "s/^$2 = //p" <<< "$1" | tail -1; }

	#  ─── L'EXTINCTION, LES QUATRE PHASES, DANS L'INTERPRÉTEUR ───
	R0="$(sonder 1 0 ext extinction md mode \
		masc 'mascotte_sprite.GetOpacity()' pluie 'pluie_sprite.GetOpacity()' \
		bgop 'progress_bg_sprite.GetOpacity()' fgop 'progress_fg_sprite.GetOpacity()')"
	if [ "$(valeur "$R0" ext)" = "1" ] && [ "$(valeur "$R0" md)" = '"shutdown"' ]; then
		ok "Plymouth.GetMode() rend bien « shutdown », et extinction s'arme en conséquence"
	else
		non "à l'arrêt, extinction ne s'arme pas (mode=$(valeur "$R0" md))"
	fi
	TOUT_CACHE=1
	for V in masc pluie bgop fgop; do
		[ "$(valeur "$R0" "$V")" = "0" ] || TOUT_CACHE=0
	done
	[ "$TOUT_CACHE" = 1 ] \
		&& ok "dès la première image de l'extinction : mascotte, pluie et barre sont à l'opacité 0 (mesuré dans l'interpréteur, pas lu dans le script)" \
		|| non "quelque chose du démarrage reste visible dès la première image de l'extinction (masc=$(valeur "$R0" masc) pluie=$(valeur "$R0" pluie) bg=$(valeur "$R0" bgop) fg=$(valeur "$R0" fgop))"

	#  Phase 1 — ÉCRASEMENT : le blanc perd sa HAUTEUR, sa largeur ne bouge
	#  pas. Deux images séparées pour prouver que ça BOUGE, pas seulement
	#  que la formule est plausible à un instant.
	SONDE_TELE="op tele_sprite.GetOpacity() w tim.GetWidth() h tim.GetHeight()"
	P1A="$(sonder 1 8  tim 'tele_sprite.GetImage()' $SONDE_TELE)"
	P1B="$(sonder 1 16 tim 'tele_sprite.GetImage()' $SONDE_TELE)"
	H1A="$(valeur "$P1A" h)"; H1B="$(valeur "$P1B" h)"; W1A="$(valeur "$P1A" w)"
	if [ "$(valeur "$P1A" op)" = "1" ] && [ "$W1A" = "1920" ] \
	   && [ "${H1A:-0}" -lt 1080 ] && [ "${H1B:-1080}" -lt "${H1A:-0}" ]; then
		ok "phase ÉCRASEMENT : le blanc est visible, pleine largeur (1920), et sa hauteur RÉTRÉCIT avec le temps ($H1A → $H1B)"
	else
		non "phase ÉCRASEMENT : hauteur $H1A puis $H1B (largeur $W1A) — ne rétrécit pas comme attendu"
	fi

	#  Phase 2 — POINT : la hauteur est BLOQUÉE à tele_ligne_hauteur (4), et
	#  c'est la LARGEUR qui rétrécit maintenant.
	P2A="$(sonder 1 22 tim 'tele_sprite.GetImage()' w tim.GetWidth\(\) h tim.GetHeight\(\))"
	P2B="$(sonder 1 27 tim 'tele_sprite.GetImage()' w tim.GetWidth\(\) h tim.GetHeight\(\))"
	W2A="$(valeur "$P2A" w)"; W2B="$(valeur "$P2B" w)"; H2A="$(valeur "$P2A" h)"; H2B="$(valeur "$P2B" h)"
	if [ "$H2A" = "4" ] && [ "$H2B" = "4" ] && [ "${W2B:-9999}" -lt "${W2A:-0}" ] && [ "${W2A:-0}" -lt "$W1A" ]; then
		ok "phase POINT : la hauteur est bloquée à 4 px, la largeur continue de rétrécir ($W2A → $W2B)"
	else
		non "phase POINT : hauteur $H2A/$H2B (attendu 4/4), largeur $W2A → $W2B — ne suit pas le point attendu"
	fi

	#  Phase 3 — NOIR : plus rien du blanc, et l'adieu n'a pas commencé.
	P3="$(sonder 1 60 top 'tele_sprite.GetOpacity()' aop 'adieu_sprite.GetOpacity()')"
	if [ "$(valeur "$P3" top)" = "0" ] && [ "$(valeur "$P3" aop)" = "0" ]; then
		ok "phase NOIR : le blanc a disparu, LEXOS n'est pas encore apparu"
	else
		non "phase NOIR : blanc=$(valeur "$P3" top), adieu=$(valeur "$P3" aop) — l'écran n'est pas noir"
	fi

	#  Phase 4 — ADIEU : LEXOS monte en opacité, puis PLAFONNE à 1 — jamais
	#  au-delà, même largement après la fin du cycle.
	P4A="$(sonder 1 90  aop 'adieu_sprite.GetOpacity()')"
	P4B="$(sonder 1 110 aop 'adieu_sprite.GetOpacity()')"
	A4A="$(valeur "$P4A" aop)"; A4B="$(valeur "$P4B" aop)"
	if awk -v a="$A4A" 'BEGIN{exit !(a > 0 && a < 1)}' && [ "$A4B" = "1" ]; then
		ok "phase ADIEU : LEXOS monte en opacité ($A4A à mi-parcours) puis reste à 1, sans jamais dépasser"
	else
		non "phase ADIEU : opacité $A4A puis $A4B — ne monte pas vers 1 comme attendu"
	fi

	#  ─── LE REDÉMARRAGE PREND LA MÊME BRANCHE QUE L'EXTINCTION ───
	RB="$(sonder 2 0 ext extinction md mode)"
	[ "$(valeur "$RB" ext)" = "1" ] && [ "$(valeur "$RB" md)" = '"reboot"' ] \
		&& ok "Plymouth.GetMode() rend « reboot », et extinction s'arme pareil qu'à l'arrêt" \
		|| non "le redémarrage ne prend pas la branche d'extinction (mode=$(valeur "$RB" md))"

	#  ─── LE DÉMARRAGE : LA MASCOTTE, LES LETTRES, LA BARRE — VRAIMENT ───
	BT0="$(sonder 0 0  ext extinction md mode \
		masc 'mascotte_sprite.GetOpacity()' pluie 'pluie_sprite.GetOpacity()' l0 'lettre_sprite[0].GetOpacity()')"
	BT1="$(sonder 0 60 l0 'lettre_sprite[0].GetOpacity()' l4 'lettre_sprite[4].GetOpacity()')"
	if [ "$(valeur "$BT0" ext)" = "0" ] && [ "$(valeur "$BT0" md)" = '"boot"' ] \
	   && [ "$(valeur "$BT0" masc)" = "1" ] && [ "$(valeur "$BT0" pluie)" = "1" ] \
	   && [ "$(valeur "$BT0" l0)" = "0" ]; then
		ok "au démarrage : mascotte et pluie visibles dès la première image, les lettres pas encore arrivées"
	else
		non "l'état de la première image du démarrage ne correspond pas à ce qui est attendu"
	fi
	if [ "$(valeur "$BT1" l0)" = "1" ] && [ "$(valeur "$BT1" l4)" = "1" ]; then
		ok "…et les cinq lettres sont bien arrivées (opacité 1) après leur temps de glissement"
	else
		non "les lettres ne sont pas toutes arrivées à l'opacité 1 après 60 images"
	fi
	FGW1="$("$HARNAIS" -m 0 -i "$BANC/theme1" -s "$FENETRE" -f "$SCRIPT" -p 0.1 -s 'x = progress_fg_sprite.GetImage().GetWidth();' -q x 2>/dev/null | sed -n 's/^x = //p')"
	FGW2="$("$HARNAIS" -m 0 -i "$BANC/theme1" -s "$FENETRE" -f "$SCRIPT" -p 0.9 -s 'x = progress_fg_sprite.GetImage().GetWidth();' -q x 2>/dev/null | sed -n 's/^x = //p')"
	if [ "${FGW2:-0}" -gt "${FGW1:-0}" ]; then
		ok "…et la barre RÉAGIT à une vraie progression (10 % → ${FGW1} px, 90 % → ${FGW2} px) — pas une animation minutée"
	else
		non "la barre ne réagit pas à la progression : 10 % → $FGW1 px, 90 % → $FGW2 px"
	fi

	#  ─── SANS CONVERT : PAS DE SPRITE FANTÔME, PAS DE PLANTAGE ───
	#  theme4 (section 5 bis) n'a ni blanc.png ni bye-bye.png : SCRIPT_TELE_SANS
	#  ne DÉCLARE MÊME PAS tele_sprite. Le vérifier dans l'interpréteur, pas
	#  seulement par grep : une variable ABSENTE et une variable à l'opacité 0
	#  ne sont pas la même preuve.
	if [ -r "${S4:-/nonexistent}" ]; then
		R4="$("$HARNAIS" -m 1 -i "$BANC/theme4" -s "$FENETRE" -f "$S4" -r 10 -s 'a = extinction;' -q a -q tele_sprite 2>"$BANC/sonde4.err")"
		if grep -qi 'erreur' <<< "$R4$(cat "$BANC/sonde4.err" 2>/dev/null)"; then
			non "sans convert, le script en extinction lève une erreur dans le vrai interpréteur : $R4"
		elif [ "$(sed -n 's/^tele_sprite = //p' <<< "$R4")" = "ABSENTE" ] && [ "$(sed -n 's/^a = //p' <<< "$R4")" = "1" ]; then
			ok "sans convert : tele_sprite n'existe même pas dans l'interpréteur (pas un sprite invisible qui traînerait) — aucune erreur à l'exécution"
		else
			non "sans convert : tele_sprite existe quand même, ou le script a mal réagi ($R4)"
		fi
	else
		saut "le passage sans convert n'a pas produit de script : le sans-sprite-fantôme n'est pas mesuré"
	fi
fi

# =============================================================================
printf '\n\033[1m%d réussis, %d échoués\033[0m\n' "$reussis" "$echoues"
[ "$echoues" -eq 0 ] || exit 1
printf '  \033[32mLa mascotte se tient, le logo s'\''écrit, la pluie tombe, la barre est verte.\033[0m\n'
