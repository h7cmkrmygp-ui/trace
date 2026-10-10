# P16 — Tâches qui reviennent

**But** : « Sortir les poubelles tous les lundis » est une tâche qui revient. « Fait » ne la range pas dans les
Archives : elle passe au lundi suivant, et ses rappels suivent.

## Ce que le propriétaire voit

- **Dicté** : « tous les jours », « chaque matin » (8 h), « chaque soir » (19 h), « tous les lundis », « les mardis et
  jeudis », « chaque vendredi », « en semaine », « les fins de semaine », « chaque semaine », « une fois par semaine »,
  « aux deux semaines » (comme au Québec), « une semaine sur deux », « tous les 3 mois », « le 1er de chaque mois »,
  « chaque année », et l'anglais (« every Friday », « every other week »). « à 18 h » donne l'heure.
- **La note** porte la pastille « Tous les lundis » (puis « · faite 3 fois »). Sans date dite, elle prend la prochaine
  fois.
- **Fait** (menu, glissement, notification) : l'échéance passe à la prochaine fois ; le menu dit « Fait : à la
  prochaine fois ».
- **À la main** : … › « Répéter… » : Jamais, Chaque jour, Chaque semaine (les jours), Aux deux semaines, Chaque mois
  (un jour précis), Chaque année.

## Règles

- Seulement les tâches et les rendez-vous ; « je vais au gym tous les lundis » (une info) ne se répète pas.
- Pièges : « le lundi de Pâques », « chaque fois que », « tous les deux », « deux fois par semaine » (quels jours ?).
- Le 31 de chaque mois : le dernier jour d'un mois plus court. Aux deux semaines : compté depuis la première fois.
- Faite en avance, la tâche passe après la fois prévue ; faite en retard, à la prochaine fois après aujourd'hui.
- « Jamais » retire le rythme : « Fait » range de nouveau la tâche dans les Archives. La corbeille reste la corbeille.
- Un rythme posé à la main est une décision du propriétaire : la note n'est plus remplacée par un nouveau classement.

## Technique

- Core `Recurrence.swift` : `RecurrenceRule`, `RecurrenceParser.parse`, `Recurrence.next(after:rule:anchor:calendar:)`,
  `Recurrence.describe`.
- Migration v10 : `memory_recurrence` (la règle en JSON, la première fois, combien de fois faite).
- `MemoryStore` reçoit le fuseau des journées (`calendar`) ; `setStatus(.archived)` par le propriétaire avance une
  tâche qui revient ; `ThoughtFiler` pose le rythme dicté ; l'export inclut `recurrences`.
