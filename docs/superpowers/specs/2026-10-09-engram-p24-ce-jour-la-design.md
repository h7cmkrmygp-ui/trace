# P24 — « Ce jour-là »

**But** : retrouver sans chercher ce que tu notais le même jour, il y a un mois, six mois, un an, deux ans…

## Ce que le propriétaire voit

- **Notes** : la carte « Ce jour-là » (« Il y a un an : Premier jour au nouveau bureau ») quand il y a quelque chose.
- **La page** : une section par moment (« Il y a un mois », « Il y a six mois », « Il y a un an », « Il y a 2 ans »…),
  trois notes au plus chacune ; toucher ouvre la note.

## Règles

- Le même jour du mois seulement : le 31 mars ne rappelle pas le 28 février.
- Jamais une note privée (gardée sur l'iPhone ou jugée secrète), jamais la corbeille. Jusqu'à 10 ans.

## Technique

- Core `OnThisDay.swift` : `OnThisDay.groups(_:today:calendar:perDay:)`. App : `AppModel.onThisDay()`,
  `OnThisDayView`, carte dans les Notes.
