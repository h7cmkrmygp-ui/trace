# P32 — Le choix de la catégorie : fait par l'IA, réfléchi et visible

**Demande du propriétaire** : « Assure-toi que c'est vraiment l'IA qui choisit quelle catégorie mettre, de façon
intelligente. »

## Ce qui a été vérifié dans le code

- **Seuls deux chemins posent une catégorie sur une note.**
  - Le classement par l'IA : `ThoughtFiler.classify`, avec le chemin proposé par Gemini, Groq ou le modèle d'Apple.
  - Le choix du propriétaire : `CategoryPicker`.
- **Aucune règle ne choisit une catégorie à la place de l'IA.**
  - Les catégories de départ (`seedDefaultsIfNeeded`) ne sont jamais créées.
  - Celles qui restent d'une ancienne version et sont vides sont archivées au lancement.
- **Engram peut seulement refuser un choix de l'IA, jamais en imposer un.** Un suivi comme « Poids » refuse une note
  sans mesure (P31) : elle reste « À classer ».
- **« Assurance » retrouve « Assurances »** : accents, majuscules et pluriel étaient déjà ignorés pour réutiliser une
  catégorie existante.

## Ce qui manquait pour que le choix soit intelligent

- L'IA ne voyait que le **nom** des catégories, pas ce qu'elles contiennent. « Automobile › car part » ne dit pas ce
  qu'on y range.
- L'IA choisissait directement, sans réfléchir à voix haute.
- Le propriétaire ne pouvait pas voir pourquoi une note était dans un dossier.

## Ce qui change

1. **L'IA lit ce que contient chaque catégorie** : sa description, écrite quand la catégorie a été créée ou ajoutée
   plus tard par le modèle d'Apple.
   - Le modèle d'Apple (sur l'iPhone) les reçoit toutes.
   - Groq les reçoit seulement sans coordonnées, numéros ni montants.
   - **Gemini (palier gratuit) n'en reçoit aucune.**
2. **L'IA explique son choix avant de le faire.**
   - Le champ `categoryReason` vient avant `category` dans la réponse : elle écrit d'abord ce dont parle la note et
     pourquoi elle va dans telle catégorie existante, ou pourquoi aucune ne convient.
   - Elle choisit ensuite, en accord avec cette phrase.
   - Consignes : `p32-cloud-v1`, `p32-v1`.
3. **La raison est gardée avec la note** (migration v16, `memory_category.reason`, 300 caractères au plus). Elle est
   affichée dans la note › Détails › « Pourquoi ce dossier ».
   - Un dossier retiré par le propriétaire n'affiche plus de raison.
   - Un chemin refusé par Engram n'a pas de raison.
4. **L'évaluation sur l'iPhone** (Réglages › Intelligence › Évaluer le classement) :
   - elle fonctionne comme une vraie note : ce qu'Engram reconnaît et la description des catégories déjà créées ;
   - elle affiche la raison de l'IA sous chaque phrase ;
   - elle ajoute deux fêtes et une assurance : 49 phrases inventées.

## Limite honnête

Aucun modèle d'IA ne tourne sur le PC de développement : la qualité réelle des choix se vérifie sur l'iPhone, avec
« Pourquoi ce dossier » et l'évaluation. Rien n'est déclaré « testé sur iPhone » sans le propriétaire.
