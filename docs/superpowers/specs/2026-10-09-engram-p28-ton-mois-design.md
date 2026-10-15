# P28 — « Ton mois »

**But** : la page « Ta semaine » (P18) montre aussi un mois entier : Semaine | Mois en haut.

## Ce que le propriétaire voit

- « Janvier 2027 », les notes, les choses faites, ce qui reste ; « 10 notes de plus que le mois d'avant » ; une barre
  par jour du mois ; « Ton jour le plus actif : le 14 janvier » ; dossiers, personnes, habitudes, suivis du mois.
- Les flèches remontent les mois (ou les semaines) ; changer de période revient à celle en cours.

## Technique

- Core : `ReviewPeriod` (`interval`, `previousStart`) ; `WeeklyReviewText.title/comparison/busiestDay(… period:)`.
- `MemoryStore.review(_:containing:)` (la semaine reste `weeklyReview(containing:)`, 7 jours).
