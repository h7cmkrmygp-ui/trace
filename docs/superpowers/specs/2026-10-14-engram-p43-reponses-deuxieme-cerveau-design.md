# P43 — Retrouver répond comme un deuxième cerveau

## But

Retrouver (et Siri) répondent directement aux questions qu'on pose à un deuxième cerveau. Les réponses sont tirées des listes et des notes, sans rien inventer :

- « C'était quoi les affaires que je voulais pour mon anniversaire ? » donne « Dans ta liste de souhaits d'anniversaire : Gourde et Livre (1 déjà cochée). »
- « Qu'est-ce qu'il y a sur ma liste d'épicerie ? » donne ce qui reste à acheter.
- « Qu'est-ce que Julie aime ? » ou « Une idée de cadeau pour Julie ? » donne par exemple : « D'après tes notes, Julie aime les parfums et le chocolat. Julie n'aime pas le café. Idées de cadeaux pour Julie : Foulard. La fête de Julie, c'est le 12 mars, dans 5 jours. »
- « Qu'est-ce que je dois faire cette semaine ? » marchait déjà : ce sont les tâches et rendez-vous de la semaine.

## Ce qui change

- **`ListQuestion`** (sur l'iPhone) :
  - La question doit demander un contenu (« quoi », « qu'est-ce », « liste », « je voulais »…), pas un fait (« combien », « quand », « où », « numéro »…).
  - Tous les mots du nom de la liste doivent être dans la question :
    - « je voulais », « j'aimerais » comptent pour « souhaits » ;
    - « acheter », « courses » comptent pour « épicerie ».
  - La liste la plus précise l'emporte. En cas d'égalité, Engram ne devine pas.
  - La réponse donne ce qui reste, avec le nombre de choses cochées. Une liste privée n'est pas lue.
- **`PersonQuestion`** :
  - Une personne connue doit être nommée, et la question doit porter sur ses goûts ou sur un cadeau.
  - Ses goûts sont tirés des phrases de ses notes : « Julie aime / adore / préfère … », « Elle n'aime pas … », ou « aime pas » à la québécoise (mais « aime pas mal » veut dire qu'elle aime).
  - Ce que le propriétaire dit de lui-même (« j'aime ») ne compte pas.
  - Les idées de cadeaux sont ce qui reste dans les listes à son nom (« cadeaux pour Julie »).
  - Sa fête est ajoutée si elle est connue.
  - Si les notes ne disent rien, Engram ne fabrique pas de réponse : la recherche habituelle répond.
- **Page de la personne** : nouvelle section « Ce que tu as noté » (aime, n'aime pas, idées de cadeaux).
- Ordre des réponses dans Retrouver :
  1. la fête ;
  2. la liste ;
  3. la personne ;
  4. la réponse exacte (P39) ;
  5. le résumé.

## Tests

- `SecondBrainAnswersTests` : trouver la liste, la réponse, la personne, les goûts, la réponse complète ou aucune.
- `SecondBrainAnswersStoreTests` : la liste de souhaits répond ; Julie (goûts, cadeaux, fête).
