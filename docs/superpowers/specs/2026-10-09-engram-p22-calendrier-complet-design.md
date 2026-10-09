# P22 — Calendrier plus complet

**But** : le Calendrier d'Engram montre aussi les fêtes (P20) et les prochaines fois des tâches qui reviennent (P16),
pas seulement l'échéance actuelle.

## Ce que le propriétaire voit

- Un point sous chaque jour qui a une fête ou une prochaine fois.
- Le jour choisi : « 🎁 Fête de Julie (35 ans) » (toucher ouvre sa page) ; « ↻ Sortir les poubelles — Revient ce
  jour-là » (toucher ouvre la note).

## Règles

- Seulement après l'échéance actuelle (elle est déjà montrée parmi les échéances), jamais avant ; au plus 62 fois par
  tâche dans un mois. Une tâche faite (Archives) ou à la corbeille n'est plus projetée.
- Une prochaine fois n'est pas à cocher : « Fait » sur l'échéance actuelle passe à la suivante.
- Né un 29 février : la fête est le 28 les autres années.

## Technique

- Core `CalendarProjection.swift` : `Recurring`, `Occurrence`, `BirthdayDay`, `occurrences(_:from:to:calendar:)`,
  `birthdays(_:from:to:calendar:)`.
- `MemoryStore.recurringTasks()` (et flux). Le Calendrier écoute aussi les fêtes.
