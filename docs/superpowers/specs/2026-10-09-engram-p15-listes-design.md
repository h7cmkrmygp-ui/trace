# P15 — Listes

**But** : « Ajoute du lait et des œufs à ma liste d'épicerie » complète **une** note « Liste d'épicerie » (des cases
à cocher), au lieu de créer une nouvelle note à chaque fois.

## Ce que le propriétaire voit

- **Dicté** : « ajoute / rajoute / mets … à (ou sur, dans) ma liste d'épicerie », « sur ma liste de cadeaux, ajoute … »,
  « liste d'épicerie : lait, café », « add … to my grocery list ». Sans nom (« mets du pain sur la liste »), c'est la
  liste d'épicerie ; « courses », « commissions », « grocery » aussi.
- **La liste** est une vraie note : titre « Liste d'épicerie », une case par chose. Elle se coche, se modifie, se range
  dans un dossier, peut avoir un rappel de lieu (P14 : « en arrivant · Costco »).
- **Notes › Listes** : chaque liste, ce qui reste à faire et ce qui est coché.
- **Dans une note** : … › « Retirer les cases cochées ».

## Règles

- Une chose déjà dans la liste (pas cochée) n'est pas ajoutée deux fois ; cochée, elle redevient à faire.
- La dictée qui complète une liste ne laisse pas de note à elle.
- Une même dictée n'est jamais ajoutée deux fois à une liste (reclassée : une case cochée depuis le reste).
- La liste appartient au propriétaire : elle n'est jamais remplacée quand sa première dictée est reclassée.
- Une liste jetée à la corbeille : la prochaine demande en crée une nouvelle. Une liste archivée redevient active.
- Une dictée peut mêler une liste et une note (« ajoute du lait à ma liste, et appeler le garage »).

## Technique

- Core `Lists.swift` : `ListCommand`, `ListCommandParser` (`parse`, `title(for:)`, `key`, `displayName`), `ListMerge`
  (`adding`, `removingChecked`).
- Migration v9 : `memory_list` (une note par nom de liste) et `memory_list_addition` (les dictées déjà ajoutées).
- `ListStore` (`lists`, `listsStream`, `add` au classement) ; `ThoughtFiler` complète la liste au lieu de créer une
  note ; l'export inclut `lists` et `list_additions`.
