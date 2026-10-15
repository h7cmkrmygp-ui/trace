# P38 — Corriger une fois partout

Deuxième des quatre améliorations choisies par le propriétaire.

## Pourquoi

Quand le propriétaire déplace une note mal rangée, sa correction aide les prochaines notes (P34 : ses choix comptent
triple), mais les anciennes notes du même genre restaient dans le mauvais dossier.

## Ce qui change

- **Une proposition.** Dans une note, « Changer » le dossier : si la note quitte un dossier pour un autre, Engram cherche,
  sur l'iPhone et par le sens, les notes qui lui ressemblent vraiment (ressemblance d'au moins 0,75, 8 au plus) et que
  l'IA avait rangées dans le dossier quitté (`MoveSuggestions.candidates`, `SimilarNotesEvidence.closest`). Il propose :
  « Déplacer aussi 3 notes semblables dans « Finances › Assurances » ? », avec leurs titres.
- **Un toucher.** « Déplacer » les range toutes dans le nouveau dossier (`CategoryStore.moveNotes`), comme un choix du
  propriétaire : confirmé, l'IA ne le défera pas. « Non merci » ne change rien.
- **Jamais** une note que le propriétaire a rangée ou confirmée lui-même ; jamais la note elle-même.

Rien ne quitte l'iPhone. Aucune migration.
