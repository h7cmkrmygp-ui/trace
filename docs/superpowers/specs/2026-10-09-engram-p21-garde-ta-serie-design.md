# P21 — Garde ta série

**But** : aider à tenir ses habitudes (P17) : un objectif par semaine (« mon objectif : méditer 5 fois par semaine »)
et un petit rappel à 20 h quand une série de deux jours et plus n'est pas encore faite aujourd'hui.

## Ce que le propriétaire voit

- **Objectif** : dit dans une note (« objectif d'aller au gym trois fois par semaine », « mon but c'est de courir 2
  fois par semaine », « objectif : lire tous les jours », « goal: meditate 4 times a week ») ou fixé sur la page de
  l'habitude (1 à 7 fois par semaine, « Retirer l'objectif »). La carte dit « 3/5 cette semaine » avec une barre, puis
  « Objectif de la semaine atteint ».
- **Garde ta série** : à 20 h, « Méditation : 3 jours d'affilée. Pas encore aujourd'hui. » (plusieurs habitudes : une
  seule notification). Toucher ouvre les Suivis. Réglages › Rappels › « Garde ta série (habitudes, 20 h) ».

## Règles

- Pas de rappel pour une seule journée, pour une habitude déjà faite aujourd'hui, ni après 20 h.
- Une habitude dite dans la journée retire le rappel (recalculé à chaque habitude).
- Engram verrouillé : « Une habitude t'attend aujourd'hui. », sans nom.
- « J'ai médité 5 fois cette semaine » (ce qui a été fait), « mon objectif : 155 livres » (un suivi, P11), « 9 fois
  par semaine » ne sont pas des objectifs d'habitude. Le plus récent l'emporte.

## Technique

- Core `HabitGoals.swift` : `ParsedHabitGoal`, `HabitGoalParser`, `HabitNudgePlanner`.
- Migration v13 : `habit_goal`. `MeasurementStore` : `habitGoals`, `setHabitGoal`, `removeHabitGoal`,
  `recordHabitGoals` ; l'export inclut `habit_goals`. Rappels `.habit`.
