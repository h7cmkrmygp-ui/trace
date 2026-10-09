# P23 — Doublons possibles

**But** : quand la même pensée est dite deux fois (« appeler l'assurance pour la voiture », puis « il faut appeler
l'assurance pour la voiture »), Engram propose de réunir les deux notes, sans rien perdre.

## Ce que le propriétaire voit

- **Notes** : la carte « Doublons possibles » (« 1 paire à vérifier ») quand il y en a ; aussi dans Plus (…).
- **Une paire** : « À garder » (la plus ancienne) et « Doublon » (toucher ouvre chaque note), puis « Réunir les deux
  notes » ou « Ce n'est pas un doublon ».

## Règles

- Même genre de note (tâche, idée…), à moins de 30 jours d'écart, au moins deux mots qui portent l'idée, et au moins
  75 % de mots en commun (sans accents, au singulier, sans les petits mots ni « il faut »).
- Seulement les notes vivantes des 90 derniers jours (400 au plus), jamais les listes (P15).
- **Réunir** : le texte du doublon s'ajoute s'il dit quelque chose de plus ; ses dossiers, tags, personnes et lieux, son
  épingle, son rappel de lieu et son rythme passent à la note gardée (si elle n'en a pas) ; son échéance aussi si la
  note gardée n'en a pas. Le doublon va à la corbeille (il se récupère) ; la paire n'est plus proposée.
- **Ce n'est pas un doublon** : la paire n'est plus jamais proposée.

## Technique

- Core `Duplicates.swift` : `DuplicateFinder` (`pairs`, `key`, `mergedBody`).
- Migration v14 : `duplicate_dismissal`. `MemoryStore` : `duplicatePairs`, `mergeDuplicate`, `dismissDuplicate`.
