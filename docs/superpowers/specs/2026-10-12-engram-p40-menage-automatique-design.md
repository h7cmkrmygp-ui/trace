# P40 — Le ménage automatique des dossiers

Quatrième des quatre améliorations choisies par le propriétaire (« Ménage automatique »). Il avait demandé :
« qu'il le fasse tout seul, de manière super intelligente, sans perdre aucune note ».

## Ce qui change

Une fois par semaine, au retour dans l'app (Réglages › Intelligence › « Ménage des dossiers » pour le lancer tout de
suite), une étape à la fois :

1. **Les doublons sont fusionnés** (`TidyPlanner.merges`).
   - Ce sont des dossiers d'un même niveau qui veulent dire la même chose : Auto, Automobile, Voiture, car ; Assurance,
     Insurance ; Épicerie, Groceries…
   - Ils vont dans le dossier du propriétaire, sinon le plus gros (à égalité : le nom français, puis le plus ancien).
   - Un dossier du propriétaire n'est jamais fusionné dans un autre.
2. **Les noms anglais deviennent français** (`TidyPlanner.renames`) : « car part » devient « Pièces auto », « Groceries »
   devient « Épicerie ». C'est fait sur l'iPhone, avec une liste de noms courants, et jamais quand le nom français existe
   déjà à côté ni pour un dossier nommé par le propriétaire.
3. **Les petits sous-dossiers sont repliés** (`TidyPlanner.folds`). Un sous-dossier créé par l'IA qui a encore moins de
   3 notes après deux semaines rejoint son dossier. Ce n'est jamais fait s'il a des sous-dossiers ou une note rangée par
   le propriétaire.
4. **Les notes clairement mal rangées sont déplacées** (`TidyPlanner.moves`, 20 au plus par ménage).
   - Il faut au moins 3 de ses notes semblables dans un même autre dossier, et aucune dans le sien. Le vote se fait sur
     l'iPhone et ne compte jamais la note elle-même.
   - La raison est notée : « Rangée avec ses notes semblables… ».

## Rien ne se perd

- Une note n'est jamais supprimée. Un dossier vidé est archivé, pas effacé.
- Chaque changement est noté (migration v18, `tidy_action`) avec une phrase (« « Auto » fusionné dans « Automobile »
  (2 notes). ») et de quoi le défaire : les dossiers touchés et tous les liens des notes touchées, tels qu'avant.
- « Annuler » remet tout comme avant ce changement. Les dossiers créés par le changement et restés vides sont archivés.
- Un choix du propriétaire n'est jamais touché, même si le changement le demandait : un dossier qu'il a créé ou nommé,
  une note qu'il a rangée ou confirmée.

## Limite

Les noms anglais rares ne sont pas traduits (liste de noms courants). La création de nouveaux sous-dossiers pour un sujet
qui revient viendra plus tard.
