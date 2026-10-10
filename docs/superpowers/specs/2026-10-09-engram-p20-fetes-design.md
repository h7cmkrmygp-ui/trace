# P20 — Fêtes

**But** : « L'anniversaire de Julie est le 12 mars », « Marc a sa fête le 3 juin » : la fête va sur la page de la
personne, et Engram la rappelle la veille et le jour même.

## Ce que le propriétaire voit

- **Dicté** : « l'anniversaire de … est le … », « la fête de …, c'est le … », « … a sa fête le … », « … est née le 24
  décembre 1990 », « l'anniversaire de ma mère est le 4 mai », « Julie's birthday is March 12 ».
- **Page d'une personne** : section « Fête » : « 12 mars · dans 5 jours · 35 ans » ; « Ajouter sa fête », « Changer
  la fête » (mois, jour, l'année si on la connaît), « Retirer la fête ».
- **Notes › Personnes** : « Fêtes à venir » (le prochain mois) en haut.
- **Rappels** : la veille à 19 h « Demain : la fête de Julie » (« Julie aura 35 ans. »), et le jour même à 9 h.
  Toucher ouvre la page de la personne. Engram verrouillé : « Demain : une fête », sans nom.

## Règles

- « La fête de Noël », « l'anniversaire de mariage », « ma fête préférée », « le 31 février » ne sont pas des fêtes.
- Une personne nommée seulement dans la phrase de la fête est créée et reliée à la note.
- La plus récente l'emporte (dite de nouveau avec l'année, l'année s'ajoute) ; né un 29 février : le 28 les autres
  années.
- Fusionner deux personnes garde la fête ; une personne masquée n'a plus de rappel.
- Seulement les fêtes des 60 prochains jours sont programmées (iOS garde 64 notifications au plus).

## Technique

- Core `Birthdays.swift` : `ParsedBirthday`, `Birthday`, `BirthdayParser`, `BirthdayPlanner` (`next`, `age`, `plan`,
  `describe`).
- Migration v12 : `person_birthday`. `EntityStore` : `birthday`, `setBirthday`, `removeBirthday`, `birthdays` (et
  flux) ; `ThoughtFiler` pose la fête dictée ; la fusion la garde ; l'export inclut `person_birthdays`.
- App : rappels `.birthday` (ouvrent la personne), section « Fête », « Fêtes à venir », `BirthdaySheet`.
