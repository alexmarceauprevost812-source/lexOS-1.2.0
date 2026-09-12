"""Services système de LEXOS PRO — aucun widget ici.

Tout ce qui touche au système passe par ce paquet, et tout ce qui sort du
processus passe par execution.lancer(). Deux raisons :

  · on peut éprouver l'ensemble sans serveur graphique ;
  · il n'y a qu'UN endroit où vérifier qu'on n'utilise jamais shell=True,
    qu'il y a toujours un délai maximal, et qu'un échec rend une raison
    lisible plutôt qu'un silence.
"""
