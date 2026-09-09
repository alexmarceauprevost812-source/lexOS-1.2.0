/* =============================================================================
   panneau-sonde — QUE RÉSOUT GTK POUR LE FOND D'UN GREFFON DE LA BARRE ?
   =============================================================================
   POURQUOI CE PROGRAMME EXISTE. Le banc du panneau lit du texte : il vérifie
   que la règle est écrite. Or une règle posée sur un nœud IMAGINAIRE est
   écrite tout pareil et ne fait rien — le contrôle passe au vert et le gris
   revient chez Alex. C'est le piège nommé par la consigne, et un grep ne peut
   pas s'en sortir seul.

   ═══ CE QU'IL REBÂTIT, ET POURQUOI CET ARBRE-LÀ ═══
   Relevé sur le VRAI xfce4-panel lancé sous Xvfb avec la vraie configuration
   de LexOS : la barre lance ses greffons dans des processus à part
   (« wrapper-2.0 »), chacun avec sa propre fenêtre X. Cette fenêtre porte
   DEUX classes de style : « background », que GTK pose sur tout toplevel, et
   « xfce4-panel », que le panneau pose dans le processus du greffon.

   C'est ce couple qui a été trouvé à la sonde de couleur — 239 px de gris
   visés, 239 px atteints, pas un de plus. On le rebâtit donc ici : une
   GtkWindow portant les deux classes, et on DEMANDE À GTK la couleur qu'il
   résout pour son fond.

   Le fond doit être TRANSPARENT (alpha 0). S'il est opaque, le gris du thème
   de socle est de retour.

   ═══ USAGE ═══
       panneau-sonde <chemin d'un gtk.css>     (sous un DISPLAY, Xvfb suffit)
   Compilé et lancé par tests/test_lexos_menu_whisker.sh.
   ============================================================================= */
#include <gtk/gtk.h>

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    /*  Le thème généré importe la ressource du thème de socle : sans elle,
        GTK refuse toute la feuille et on mesurerait le vide. On enregistre
        les deux socles possibles, celui qui existe gagne. */
    const char *socles[] = {
        "/usr/share/themes/Arc-Dark/gtk-3.0/gtk.gresource",
        "/usr/share/themes/Yaru-dark/gtk-3.0/gtk.gresource", NULL };
    for (int i = 0; socles[i]; i++) {
        GResource *r = g_resource_load(socles[i], NULL);
        if (r) g_resources_register(r);
    }
    GtkCssProvider *p = gtk_css_provider_new();
    GError *e = NULL;
    if (!gtk_css_provider_load_from_path(p, argv[1], &e))
        g_printerr("!! CSS partiellement refuse : %s\n", e->message);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(p), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    /*  La fenêtre d'un greffon externe : les deux classes ensemble. */
    GtkWidget *w = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GtkStyleContext *c = gtk_widget_get_style_context(w);
    gtk_style_context_add_class(c, "xfce4-panel");   /* posee par le panneau */
    gtk_style_context_add_class(c, "background");    /* posee par GTK        */
    gtk_widget_show(w);

    GdkRGBA bg;
    gtk_style_context_get_background_color(c, GTK_STATE_FLAG_NORMAL, &bg);
    g_print("greffon: fond #%02X%02X%02X alpha=%.2f\n",
            (int)(bg.red*255+0.5), (int)(bg.green*255+0.5),
            (int)(bg.blue*255+0.5), bg.alpha);

    /*  Et le bouton d'un greffon : transparent au repos, visible au survol.
        Les deux dans la même mesure, parce que c'est la paire qui compte. */
    GtkWidget *b = gtk_button_new_with_label("greffon");
    gtk_container_add(GTK_CONTAINER(w), b);
    gtk_widget_show(b);
    GtkStyleContext *cb = gtk_widget_get_style_context(b);
    GdkRGBA repos, survol;
    /*  ON POSE L'ÉTAT AVANT DE LIRE. Passer l'état en argument ne suffit
        pas : sans set_state, GTK résout la règle de l'état COURANT et le
        survol ressort à zéro — mesuré, et ça donnait un faux « le survol ne
        se peint plus ». */
    gtk_style_context_save(cb);
    gtk_style_context_set_state(cb, GTK_STATE_FLAG_NORMAL);
    gtk_style_context_get_background_color(cb, GTK_STATE_FLAG_NORMAL, &repos);
    gtk_style_context_restore(cb);
    gtk_style_context_save(cb);
    gtk_style_context_set_state(cb, GTK_STATE_FLAG_PRELIGHT);
    gtk_style_context_get_background_color(cb, GTK_STATE_FLAG_PRELIGHT, &survol);
    gtk_style_context_restore(cb);
    g_print("bouton: repos alpha=%.2f  survol alpha=%.2f\n",
            repos.alpha, survol.alpha);
    return 0;
}
