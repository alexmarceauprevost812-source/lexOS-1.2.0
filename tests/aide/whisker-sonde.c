/* =============================================================================
   whisker-sonde — QUE RÉSOUT GTK POUR UNE RANGÉE DU MENU WHISKER ?
   =============================================================================
   POURQUOI CE PROGRAMME EXISTE. Une règle CSS posée sur un nœud imaginaire ne
   fait rien du tout, et aucun « grep » ne s'en aperçoit : le sélecteur est
   bien dans le fichier, le contrôle passe au vert, et le défaut arrive chez
   Alex. On ne lit donc pas la feuille — on rebâtit l'arbre réel, on charge le
   thème réellement généré, et on DEMANDE À GTK la couleur qu'il résout.

   ═══ LE RELEVÉ DES VRAIS NŒUDS, SOURCE PAR SOURCE ═══
   Tout ce qui suit vient du binaire livré, xfce4-whiskermenu-plugin 2.8.3
   (la version de trixie), et non d'une lecture de documentation.

   1. LES DEUX SEULS NOMS QUE LE GREFFON POSE LUI-MÊME.
      « strings libwhiskermenu.so | grep whiskermenu- » ne rend que :

          whiskermenu-button      (le bouton dans la barre)
          whiskermenu-window      (la fenêtre du menu)

      Tout le reste de l'arbre porte donc les noms de nœuds STANDARD de GTK.
      C'est ce qui rend le relevé nécessaire : il n'y a rien à deviner, mais
      rien non plus à supposer.

   2. QUELS WIDGETS LE GREFFON CONSTRUIT VRAIMENT.
      « nm -D -u libwhiskermenu.so | grep '^gtk_.*_new' » :

          gtk_tree_view_new  et  gtk_tree_view_new_with_model   -> treeview
          gtk_icon_view_new                                     -> iconview
          gtk_entry_new, gtk_search_entry_new                   -> entry
          gtk_scrolled_window_new                               -> scrolledwindow

      ET SURTOUT CE QUI N'Y EST PAS : ni gtk_list_box_new, ni gtk_flow_box_new.
      Les sélecteurs « list » et « list row » de la feuille du panneau ne
      peuvent donc atteindre AUCUN nœud de ce menu. Ils ne gênent pas — un
      sélecteur qui ne matche rien ne coûte rien — mais il ne faut pas
      compter dessus : c'est exactement le genre de règle qui rassure à tort.

   3. POURQUOI LE SURVOL SUFFIT, SANS CLIQUER.
      ALEX : « pas besoin de cliquer, juste passer la souris ». Le binaire le
      confirme : il appelle gtk_tree_view_set_hover_selection. Passer la
      souris SÉLECTIONNE la rangée — l'état qui se déclenche est donc
      « :selected », pas « :hover ». Une correction écrite sur le seul
      « :hover » n'aurait rien changé à l'écran.

   4. LE CHEMIN CSS, RENDU PAR GTK LUI-MÊME (gtk_widget_path_to_string) :

          window(whiskermenu-window):dir-ltr.background
            scrolledwindow:dir-ltr
              treeview:dir-ltr.view

   ═══ CE QUE LA SONDE A MESURÉ AVANT LE CORRECTIF ═══
   Thème LexOS-Noir généré pour l'accent orange, avec le squelette du dépôt :

       au repos ............... texte #FFFFFF   fond transparent (alpha 0)
       survolé (:hover) ....... texte #FFFFFF   fond transparent (alpha 0)
       sélectionné ............ texte #000000   fond transparent (alpha 0)
       sélectionné + focus .... texte #000000   fond transparent (alpha 0)

   Du NOIR sur le #121214 de la fenêtre : 1,12:1. La photo d'Alex.

   La cause tient en une phrase : la feuille du panneau force le fond des
   sous-nœuds à transparent avec un sélecteur d'ID — elle bat donc le fond
   « sélectionné » du thème — mais ne dit rien de la couleur du texte, que le
   thème continue de poser. lexos-theme-gen écrit
   « treeview.view:selected { background: accent; color: BTN_FG } », et
   BTN_FG vaut #000000 pour l'orange. Une couleur choisie pour aller sur
   l'orange, appliquée sur le fond qu'on venait d'effacer.

   ═══ USAGE ═══
       whisker-sonde <chemin d'un gtk.css>     (sous un DISPLAY, Xvfb suffit)
   Compilé et lancé par tests/test_lexos_menu_whisker.sh, section 8.
   ============================================================================= */

#include <gtk/gtk.h>

static void dis(const char *quoi, GtkStyleContext *c, GtkStateFlags s) {
    GdkRGBA fg, bg;
    gtk_style_context_save(c);
    gtk_style_context_set_state(c, s);
    gtk_style_context_get_color(c, s, &fg);
    gtk_style_context_get_background_color(c, s, &bg);
    g_print("%-28s texte #%02X%02X%02X (a=%.2f)   fond #%02X%02X%02X (a=%.2f)\n",
            quoi,
            (int)(fg.red*255+0.5), (int)(fg.green*255+0.5), (int)(fg.blue*255+0.5), fg.alpha,
            (int)(bg.red*255+0.5), (int)(bg.green*255+0.5), (int)(bg.blue*255+0.5), bg.alpha);
    gtk_style_context_restore(c);
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    /*  Le theme genere fait « @import resource:///com/ubuntu/themes/... » :
        cette ressource n'existe que si le gresource de Yaru est enregistre.
        Sans ca, GTK refuse toute la feuille — et on mesurerait le vide.   */
    GResource *yaru = g_resource_load(
        "/usr/share/themes/Yaru-dark/gtk-3.0/gtk.gresource", NULL);
    if (yaru) g_resources_register(yaru);
    else g_printerr("!! gresource Yaru introuvable : mesure non fiable\n");
    GtkCssProvider *p = gtk_css_provider_new();
    GError *e = NULL;
    if (!gtk_css_provider_load_from_path(p, argv[1], &e)) {
        g_printerr("CSS refuse : %s\n", e->message); return 2;
    }
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(p), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    GtkWidget *w = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_widget_set_name(w, "whiskermenu-window");        /* le nom mesure */
    GtkWidget *sw = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget *tv = gtk_tree_view_new();                 /* gtk_tree_view_new */
    gtk_container_add(GTK_CONTAINER(sw), tv);
    gtk_container_add(GTK_CONTAINER(w), sw);
    gtk_widget_show_all(w);

    GtkStyleContext *c = gtk_widget_get_style_context(tv);
    char *chemin = gtk_widget_path_to_string(gtk_style_context_get_path(c));
    g_print("chemin CSS reel de la vue : %s\n\n", chemin);

    dis("au repos",              c, GTK_STATE_FLAG_NORMAL);
    dis("survole (:hover)",      c, GTK_STATE_FLAG_PRELIGHT);
    dis("selectionne (:selected)", c, GTK_STATE_FLAG_SELECTED);
    dis("selectionne + focus",   c, GTK_STATE_FLAG_SELECTED | GTK_STATE_FLAG_FOCUSED);
    return 0;
}
