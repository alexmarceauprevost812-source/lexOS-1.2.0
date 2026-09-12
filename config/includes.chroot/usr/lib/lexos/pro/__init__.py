"""LEXOS PRO — application de bureau native (PySide6).

Découpage volontaire en trois étages, et la frontière compte :

  · services/  ne connaît AUCUN widget. Il lit le système et rend des
    objets simples. On peut donc l'éprouver sans serveur graphique, et
    c'est là que vivent les tests.
  · ui/        ne lit JAMAIS le système directement. Il affiche ce que
    les services rendent, y compris leurs refus.
  · app.py     assemble les deux.

LA RÈGLE QUI TRAVERSE TOUT LE FICHIER : une mesure qu'on n'a pas obtenue
s'affiche « Indisponible » AVEC SA RAISON. Jamais un zéro, jamais une
moyenne, jamais la valeur de la maquette. Un tableau de bord qui invente
un chiffre est pire qu'un tableau de bord vide : on le croit.
"""
