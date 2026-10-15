# P27 — « Ma journée » avec Siri

**But** : « Dis Siri, ma journée dans Engram » (ou « qu'est-ce que j'ai aujourd'hui dans Engram ») : Siri dit ce qui
est prévu aujourd'hui, ce qui est en retard, les fêtes du jour et les séries à garder.

## Ce que le propriétaire entend

- « Aujourd'hui : dentiste à 14 h et appeler le garage. 1 chose en retard : payer la facture. C'est la fête de Julie.
  Garde ta série : méditation. »
- Plus de 4 choses : « Aujourd'hui, 7 choses : …, … et 3 autres. » ; plusieurs retards : « 4 choses en retard. »
- Rien : « Rien de prévu aujourd'hui. »

## Règles

- Les rendez-vous et tâches avec une heure d'abord, dans l'ordre des heures ; une note privée s'appelle « une note
  privée ». iPhone déverrouillé exigé. Rien ne part de l'iPhone.

## Technique

- Core `DaySpeech.summary` ; App : `TodayIntent`, raccourci Siri, `AppModel.daySummary()`.
