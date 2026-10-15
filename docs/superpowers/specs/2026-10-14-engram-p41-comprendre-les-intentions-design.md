# P41 — Comprendre les intentions (listes automatiques)

## But

Une seule dictée mélangée doit aller au bon endroit, sans rien confirmer. Par exemple : « J'aimerais qu'on m'achète une gourde et des élastiques pour les cheveux. Il faut aussi que j'appelle mon manager demain. Ah, et l'anniversaire de Léa est le 3 novembre. » Cette dictée donne trois éléments :

- une liste de souhaits (Gourde, Élastiques pour les cheveux), sans note à part ;
- une tâche pour demain (Travail) ;
- une fête retenue (Anniversaires).

Engram doit comprendre l'intention, pas seulement les mots-clés :

| Ce qui est dit | Où ça va |
|---|---|
| « je dois acheter », « il me faut » | liste « épicerie » (nourriture, maison), sinon « achats » |
| « j'aimerais qu'on m'achète », « j'aimerais recevoir » | liste « souhaits » (ou « souhaits d'anniversaire », « souhaits de Noël ») |
| idée de cadeau pour quelqu'un | liste « cadeaux pour X », reliée à la personne |
| préférence (« X aime les parfums ») | une préférence sur la personne, jamais une liste |
| « je dois », « il faut que » | une tâche |
| « j'aimerais faire », « peut-être » | une idée |
| « j'ai décidé » | une décision |

## Ce qui change

- **L'IA (Gemini, Groq, Apple)** :
  - reçoit une section « intentions » ;
  - reçoit deux champs par élément : `list` (le nom de la liste, en minuscules, sans « liste de ») et `listItems` (les choses, une par case) ;
  - reçoit les noms des listes existantes (« Listes existantes : épicerie ; souhaits d'anniversaire »). Gemini (palier gratuit) ne voit que les noms sans nom de personne ni nom propre.
  - Versions des consignes : `p41-cloud-v1` et `p41-v1`.
- **Validation (sur l'iPhone)** :
  - le nom de la liste est nettoyé (« Liste de souhaits » devient « souhaits ») ;
  - une chose n'est gardée que si au moins la moitié de ses mots porteurs de sens sont dans la dictée. L'IA range ce qui est dit, elle n'ajoute rien ;
  - 20 choses au plus, 60 caractères chacune ;
  - sans chose gardée, ce n'est pas une liste.
- **Liste existante retrouvée même dite autrement** (`ListResolver`) :
  - même nom (sans accents ni majuscules) ;
  - ou même genre de liste (« courses » pour « épicerie », « wishlist » pour « souhaits ») ;
  - ou les mêmes mots, à un mot près (« anniversaire » pour « souhaits d'anniversaire ») ;
  - il faut une seule liste candidate. Sinon, aucun lien n'est inventé et une nouvelle liste est créée (« cadeaux pour Julie » ne rejoint jamais « cadeaux pour Marc »).
  - La commande « ajoute … à ma liste … » profite aussi de cette reconnaissance.
- **Classement** :
  - les choses vont dans la liste, créée la première fois (rangée dans le dossier choisi par l'IA) ;
  - aucune note à part n'est créée pour elles ;
  - une liste existante complétée est reliée aux personnes nommées ;
  - deux passages d'une même dictée peuvent compléter la même liste. Une dictée reclassée n'ajoute rien deux fois.
- **Une tâche datée reste une tâche** : « Je dois acheter du lait demain » garde son échéance et son rappel au lieu de disparaître dans la liste. Un souhait daté reste un souhait.
- **Résumé après la dictée** : chaque liste complétée affiche « Ajouté : Gourde, Élastiques pour les cheveux ». Toucher la carte ouvre la liste pour corriger.

## Hors de portée (sous-projets suivants)

- P42 : la mémoire du contexte récent (« lui », « elle », « cette liste »), sans lien inventé quand c'est ambigu.
- P43 : les connexions et les réponses. Exemples : « Qu'est-ce que Léa aime ? », le contenu d'une liste, ce qui est prévu pour un projet.
- P44 : la fête qui approche rappelle les idées de cadeaux, sans nouvelle notification.

## Tests

- `IntentListsTests` : reconnaissance des listes, jamais devinée, choses vraiment dites.
- `IntentPromptTests` : consignes, listes existantes, décodage, filtrage pour Gemini, modèle d'Apple.
- `IntentListsStoreTests` : liste sans note à part, complétée trois jours plus tard même dite autrement.
- `IntentPipelineTests` : la dictée d'exemple donne une liste, une tâche et une fête.
