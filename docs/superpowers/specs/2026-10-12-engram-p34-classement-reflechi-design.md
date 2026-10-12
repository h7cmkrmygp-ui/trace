# P34 — Le classement réfléchi

**Demande du propriétaire** : « Si je donnais ma pensée à ChatGPT, Claude ou Gemini pour la classer, ils feraient la job
à la perfection : c'est ça que je veux dire par l'app est stupide. » Il a validé le plan en trois étapes (« si tu penses
que ça va être mieux, on l'applique »). P34 est la première étape. Viendront ensuite moins de « À classer » (P35) et le
ménage automatique des dossiers (P36).

## Ses choix

- Peu de grands dossiers, une dizaine. Un sous-dossier seulement quand au moins 3 notes parlent de la même chose.
- Seuls les **noms** des dossiers peuvent sortir de l'iPhone pour aider l'IA, jamais d'autres notes.
- Ménage automatique, sans perdre de note (P36).

## Pourquoi l'app classait moins bien qu'une conversation

- L'IA classait chaque note seule, avec seulement la liste des dossiers : elle ne savait ni ce qu'ils contiennent, ni
  comment le propriétaire range.
- Elle ne voyait pas la taille des dossiers.
- Les règles du propriétaire n'étaient pas dans ses consignes.
- Groq ne réfléchissait qu'à moitié : réglage par défaut.

## Ce qui change

1. **Les notes semblables** (`SimilarNotesEvidence`, sur l'iPhone) :
   - avant l'IA, l'iPhone compare la nouvelle note, par le sens et avec le modèle de langue d'Apple, aux notes déjà
     rangées (actives ou faites) ;
   - les 8 plus proches votent pour leur dossier. Une ressemblance d'au moins 0,55 est nécessaire, et une note rangée
     ou confirmée par le propriétaire compte triple ;
   - l'IA reçoit seulement : « Les notes les plus semblables déjà rangées sont dans : Automobile › Corolla (2 notes,
     dont 1 rangée par le propriétaire) ; Finances (1 note) » ;
   - Gemini ne reçoit que les grands dossiers, additionnés et sans nom de personne. Groq reçoit les dossiers
     partageables. Le modèle d'Apple, sur l'iPhone, reçoit tout.
2. **La taille des dossiers** : chaque dossier de la liste porte son nombre de notes, sous-dossiers compris
   (« - Automobile (12) : … »), avec les mêmes règles de partage.
3. **Les règles du propriétaire dans les consignes** (`p34-cloud-v1`, `p34-v1`) :
   - peu de grands dossiers, et un dossier existant de préférence à un nouveau ;
   - suivre les notes semblables quand le sujet correspond vraiment, sinon décider par le sens et le dire dans la
     raison ;
   - un nouveau sous-dossier seulement pour un sujet qui réunira au moins 3 notes.
4. **Groq réfléchit davantage** (`reasoning_effort: high`). Si le service refuse ce réglage (erreur 400), un second
   essai part sans lui. Le délai d'attente passe à 90 secondes.

## Ce qui ne change pas

- Le choix du service (Gemini, Groq ou l'iPhone) selon la confidentialité.
- Aucune migration.
- Gemini Flash-Lite reste en secours de Gemini Flash : il vaut mieux que le petit modèle de l'iPhone.

## Limite honnête

Les vrais modèles ne tournent pas sur le PC de développement : la qualité se voit sur l'iPhone, avec « Pourquoi ce
dossier » et l'Évaluation.
