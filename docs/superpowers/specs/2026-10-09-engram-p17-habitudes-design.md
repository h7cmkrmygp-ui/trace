# P17 — Habitudes

**But** : « J'ai médité 10 minutes », « j'ai fait mon workout », « j'ai couru 5 km »… sont relevés dans les notes, sur
l'iPhone, et deviennent des habitudes avec leur série (« 5 jours d'affilée »), comme les mesures de la P10.

## Ce que le propriétaire voit

- **Notes › Suivis** : sous les mesures, « Habitudes » : une carte par habitude (série, 7 derniers jours, fois cette
  semaine). La carte « Suivis » des Notes dit aussi « Méditation 5 jours ».
- **Une habitude** : série, meilleure série, cette semaine, jours en tout ; une grille des 16 dernières semaines (une
  case par jour) ; chaque fois, avec sa quantité (« 10 min », « 5,5 km », « 2 L ») ; toucher ouvre la note.

## Habitudes reconnues

Méditation, sport (workout, gym, entraînement, yoga, musculation, cardio, vélo, natation), course, marche, lecture
(« j'ai lu 20 pages », « j'ai lu un chapitre »), eau (« j'ai bu 2 litres d'eau »), vitamines (« j'ai pris mes
vitamines »), en français et en anglais. « Hier » et « avant-hier » reculent le jour.

## Règles

- Seulement ce qui a été fait : « il faut que je médite », « je dois aller au gym », « j'ai pas médité », « je n'ai pas
  couru » ne comptent pas. Faux amis : « je suis allé au marché », « j'ai lu tes messages ».
- « à 7 h » est une heure, pas une durée.
- Une série reste vivante jusqu'à la fin de la journée qui suit le dernier jour fait. Deux fois le même jour comptent
  pour un jour.
- La corbeille ne compte pas. Les anciennes notes sont relues une fois en entier, puis avec les mesures.

## Technique

- Core `Habits.swift` : `Habit`, `ParsedHabit`, `HabitParser`, `HabitStats` (`streak`, `bestStreak`, `thisWeek`,
  `grid`).
- Migration v11 : `habit_entry` (recalculable depuis le texte, sans liste fermée d'habitudes dans la base).
- `MeasurementStore` : `habitEntries`, `habitSummaries`, `backfillHabits` ; `ThoughtFiler` relève les habitudes ;
  l'export inclut `habit_entries`.
