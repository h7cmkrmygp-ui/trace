# P37 — La transcription connaît tes noms

Première des quatre améliorations choisies par le propriétaire (« Whisper connaît tes noms »).

## Pourquoi

Whisper et la reconnaissance d'Apple ne connaissaient que des mots courants : un prénom, un magasin ou un nom de dossier
pouvaient être mal écrits (une lettre de travers). Un nom mal écrit gêne le classement (la personne n'est pas reconnue),
la recherche et les fêtes.

## Ce qui change

- **Les noms du propriétaire** (`EntityStore.transcriptionVocabulary`, 30 au plus) :
  - d'abord les personnes et les lieux les plus souvent cités dans ses notes, puis les noms de ses dossiers ;
  - jamais une personne ou un lieu masqué ;
  - sans doublon.
- **Whisper** : ces noms s'ajoutent à son amorce (« …see you then. Julie, Marc, Costco. »), en 300 caractères au plus et
  sans nom d'une lettre (`WhisperPrompt.make`). Si Whisper répète la liste sur un silence, c'est reconnu comme un écho et
  ignoré.
- **Reconnaissance d'Apple** : les mêmes noms lui sont donnés comme mots à connaître (`AnalysisContext.contextualStrings`).
  Ce n'est qu'une indication : si elle est refusée, la transcription se fait quand même.
- Les questions dictées à Retrouver en profitent aussi.

Rien ne quitte l'iPhone : les deux moteurs tournent sur l'iPhone. Aucune migration.
