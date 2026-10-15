# P18 — « Ta semaine »

**But** : une page qui montre la semaine d'un coup d'œil, lue sur l'iPhone : combien de notes, ce qui a été fait, le
jour le plus actif, les dossiers, les personnes et les lieux, les habitudes, l'évolution des suivis. Le résumé du
dimanche l'ouvre (au lieu de poser une question à Retrouver).

## Ce que le propriétaire voit

- **Notes › Plus › Ta semaine**, ou toucher « Ta semaine » le dimanche à 18 h.
- En haut : « Semaine du 10 au 16 janvier », trois chiffres (notes, faites, à faire), et « 3 notes de plus que la
  semaine d'avant ».
- « Chaque jour » : une barre par jour ; « Ton jour le plus actif : mercredi ».
- « Dossiers » (les dossiers principaux, les plus remplis d'abord), « Avec » (personnes et lieux ; toucher ouvre leur
  page), « Habitudes » (« Méditation 5/7 jours »), « Suivis » (« Poids −1,2 lb », « Sommeil 7 h 10 en moyenne »).
- Les flèches remontent les semaines (et reviennent jusqu'à celle-ci).

## Règles

- La semaine va du lundi au dimanche, comme le Calendrier d'Engram.
- Une tâche qui revient (P16) compte chaque fois qu'elle est faite ; le résumé du dimanche compte pareil.
- La corbeille et les dictées à vérifier ne comptent pas. Rien n'est envoyé.

## Technique

- Core `WeeklyReview.swift` : `WeeklyReview` (`Count`, `HabitCount`), `WeeklyReviewText` (`title`, `comparison`,
  `busiestDay`).
- `MemoryStore.weeklyReview(containing:)` ; `weekStats` compte les tâches qui reviennent ; dans l'app, `MemoryStore`
  prend la semaine du lundi.
