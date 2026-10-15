# P45 — « Qu'est-ce que j'avais prévu pour ce projet ? »

## But

Retrouver (et Siri) répondent avec ce qui reste à faire pour un projet et avec ce qui y est noté :

- « Qu'est-ce que j'avais prévu pour le chalet ? » donne « Pour « Projets › Chalet », à faire : Réparer le quai et Acheter du bois. Aussi noté : Budget du chalet. »
- « Qu'est-ce qu'il reste à faire pour ce projet ? » parle du projet de la dernière dictée.

## Ce qui change

- **`ProjectQuestion.folder`** (sur l'iPhone) :
  - La question doit demander ce qui est prévu (« prévu », « reste », « à faire », « plan »…), pas un fait (« combien », « quand », « numéro »…).
  - Un projet nommé : le dernier niveau du dossier (« Chalet ») doit être dans la question. Le dossier le plus profond l'emporte. En cas d'égalité, Engram ne devine pas.
  - « Ce projet » : seulement le seul projet de la dernière dictée (`MemoryStore.latestContext()`). Engram ne le devine jamais à partir du mot « projet ».
- **`CategoryStore.projectAnswer`** :
  - Il prend les notes vivantes du dossier et de ses sous-dossiers, sans les listes.
  - Il les met de la plus ancienne à la plus récente.
  - D'abord les tâches et rendez-vous, puis le reste, 8 au plus de chaque.
- Ordre dans Retrouver :
  1. la fête ;
  2. la liste ;
  3. la personne ;
  4. le projet ;
  5. la réponse exacte ;
  6. le résumé.

## Tests

- `ProjectQuestionTests` : un projet nommé ; « ce projet » avec ou sans dictée récente ; une autre question ; les réponses.
- `ProjectAnswerStoreTests` : le chalet ; « ce projet » des heures plus tard ; une autre question.
