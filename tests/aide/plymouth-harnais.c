/* ============================================================================
 *  plymouth-harnais — FAIRE TOURNER le thème LexOS dans le VRAI interpréteur
 * ============================================================================
 *  POURQUOI CE FICHIER EXISTE. Le thème de démarrage est un programme écrit
 *  dans le langage du greffon « script » de Plymouth. Jusqu'ici, les bancs le
 *  LISAIENT : ils cherchaient des lignes dans le fichier produit. C'est ainsi
 *  que l'ISO 112 est partie sans logo — le script appelait « GetTime() », une
 *  fonction qui n'existe pas, l'interpréteur rendait une valeur nulle sans un
 *  mot, et tous les contrôles étaient verts.
 *
 *  Un contrôle qui lit ne peut pas voir ça. Celui-ci EXÉCUTE : il charge
 *  le script.so de /usr/lib (le module que Plymouth emploie lui-même) —
 *  monte les mêmes bibliothèques (Image, Math, String, Sprite, Plymouth), joue
 *  le thème, avance l'horloge d'autant d'images qu'on veut, et rend la valeur
 *  de n'importe quelle variable. On mesure alors ce que l'écran montrerait :
 *  l'opacité d'un sprite, la taille de son image, sa position.
 *
 *  RIEN N'EST DESSINÉ, ET C'EST VOULU : aucun tampon de pixels n'est attaché,
 *  donc aucun écran n'est touché. On observe l'état du programme, pas l'image.
 *
 *  EMPLOI
 *      plymouth-harnais -m <mode> -i <dossier-images> \
 *          [-s "<script>"] [-f <fichier>] [-r <images>] [-p <progression>]
 *          [-q <variable>] …
 *    · -m  0 = démarrage, 1 = extinction, 2 = redémarrage (l'ordre de
 *          Plymouth : Plymouth.GetMode() rend « boot », « shutdown »,
 *          « reboot ») ; -m et -i doivent précéder le reste ;
 *    · -s  exécute un bout de script (poser des sondes, par exemple) ;
 *    · -f  exécute un fichier (le thème) ;
 *    · -r  appelle la fonction de rafraîchissement N fois — l'horloge du
 *          thème compte des images, c'est donc ainsi qu'on avance le temps ;
 *    · -p  appelle la fonction de progression du démarrage ;
 *    · -q  imprime la valeur d'une variable globale.
 *
 *  LA DISPOSITION DE « script_state_t » EST RELEVÉE, PAS DEVINÉE : lue dans le
 *  désassemblage de script_state_new (malloc de 0x20 : user_data, global,
 *  local, this). Si un jour Plymouth la change, ce harnais lira n'importe
 *  quoi — le banc s'en aperçoit parce que ses sondes ne rendent plus les
 *  valeurs attendues, jamais parce qu'il devine.
 * ========================================================================== */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

typedef struct script_obj script_obj_t;
typedef struct {
	void *user_data;
	script_obj_t *global;
	script_obj_t *local;
	script_obj_t *this;
} script_state_t;
typedef struct { int type; script_obj_t *object; } script_return_t;

static script_state_t *(*p_script_state_new)(void *);
static void *(*p_script_parse_string)(const char *, const char *);
static void *(*p_script_parse_file)(const char *);
static script_return_t (*p_script_execute)(script_state_t *, void *);
static script_obj_t *(*p_script_obj_hash_peek_element)(script_obj_t *, const char *);
static bool (*p_script_obj_is_null)(script_obj_t *);
static bool (*p_script_obj_is_number)(script_obj_t *);
static bool (*p_script_obj_is_string)(script_obj_t *);
static double (*p_script_obj_as_number)(script_obj_t *);
static char *(*p_script_obj_as_string)(script_obj_t *);
static void *(*p_script_lib_image_setup)(script_state_t *, const char *);
static void *(*p_script_lib_math_setup)(script_state_t *);
static void *(*p_script_lib_string_setup)(script_state_t *);
static void *(*p_script_lib_sprite_setup)(script_state_t *, void *);
static void *(*p_script_lib_plymouth_setup)(script_state_t *, int);
static void (*p_script_lib_plymouth_on_refresh)(script_state_t *, void *);
static void (*p_script_lib_plymouth_on_boot_progress)(script_state_t *, void *, double, double);
static void *(*p_ply_list_new)(void);

#define CHARGE(h, n) do { \
	*(void **)&p_##n = dlsym(h, #n); \
	if (!p_##n) { fprintf(stderr, "symbole absent : %s (%s)\n", #n, dlerror()); exit(2); } \
} while (0)

static void montrer(script_state_t *st, const char *nom)
{
	script_obj_t *o = p_script_obj_hash_peek_element(st->global, nom);
	if (!o) { printf("%s = ABSENTE\n", nom); return; }
	if (p_script_obj_is_null(o)) printf("%s = NULL\n", nom);
	else if (p_script_obj_is_number(o)) printf("%s = %.17g\n", nom, p_script_obj_as_number(o));
	else if (p_script_obj_is_string(o)) {
		char *s = p_script_obj_as_string(o);
		printf("%s = \"%s\"\n", nom, s);
		free(s);
	} else printf("%s = (autre)\n", nom);
}

int main(int argc, char **argv)
{
	void *ply = dlopen("libply.so.5", RTLD_NOW | RTLD_GLOBAL);
	if (!ply) { fprintf(stderr, "libply.so.5 : %s\n", dlerror()); return 2; }
	void *h = NULL;
	const char *chemins[] = {
		"/usr/lib/x86_64-linux-gnu/plymouth/script.so",
		"/usr/lib/plymouth/script.so",
		NULL
	};
	for (int i = 0; chemins[i] && !h; i++) h = dlopen(chemins[i], RTLD_NOW | RTLD_GLOBAL);
	if (!h) { fprintf(stderr, "script.so introuvable : %s\n", dlerror()); return 2; }

	CHARGE(h, script_state_new); CHARGE(h, script_parse_string); CHARGE(h, script_parse_file);
	CHARGE(h, script_execute); CHARGE(h, script_obj_hash_peek_element);
	CHARGE(h, script_obj_is_null); CHARGE(h, script_obj_is_number); CHARGE(h, script_obj_is_string);
	CHARGE(h, script_obj_as_number); CHARGE(h, script_obj_as_string);
	CHARGE(h, script_lib_image_setup); CHARGE(h, script_lib_math_setup);
	CHARGE(h, script_lib_string_setup); CHARGE(h, script_lib_sprite_setup);
	CHARGE(h, script_lib_plymouth_setup); CHARGE(h, script_lib_plymouth_on_refresh);
	CHARGE(h, script_lib_plymouth_on_boot_progress); CHARGE(ply, ply_list_new);

	int mode = 0;
	const char *images = ".";
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-m") && i + 1 < argc) mode = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-i") && i + 1 < argc) images = argv[++i];
	}

	script_state_t *st = p_script_state_new(NULL);
	p_script_lib_image_setup(st, images);
	p_script_lib_math_setup(st);
	p_script_lib_string_setup(st);
	p_script_lib_sprite_setup(st, p_ply_list_new());
	void *ply_data = p_script_lib_plymouth_setup(st, mode);

	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-m") || !strcmp(argv[i], "-i")) { i++; continue; }
		if (!strcmp(argv[i], "-s") && i + 1 < argc) {
			const char *src = argv[++i];
			void *op = p_script_parse_string(src, "-s");
			if (!op) { printf("ERREUR DE LECTURE : %s\n", src); continue; }
			p_script_execute(st, op);
		} else if (!strcmp(argv[i], "-f") && i + 1 < argc) {
			const char *f = argv[++i];
			void *op = p_script_parse_file(f);
			if (!op) { printf("ERREUR DE LECTURE : %s\n", f); return 3; }
			p_script_execute(st, op);
		} else if (!strcmp(argv[i], "-r") && i + 1 < argc) {
			int n = atoi(argv[++i]);
			for (int k = 0; k < n; k++) p_script_lib_plymouth_on_refresh(st, ply_data);
		} else if (!strcmp(argv[i], "-p") && i + 1 < argc) {
			p_script_lib_plymouth_on_boot_progress(st, ply_data, 1.0, atof(argv[++i]));
		} else if (!strcmp(argv[i], "-q") && i + 1 < argc) {
			montrer(st, argv[++i]);
		} else {
			fprintf(stderr, "argument inconnu : %s\n", argv[i]);
			return 2;
		}
	}
	return 0;
}
