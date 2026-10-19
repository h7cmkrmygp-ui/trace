# Moteur fiable — rapport de la mission F01 à F29

Branche : `moteur-fiable`, issue de `p2-je-parle` au commit a45ba3d (celui de l'audit du 16 octobre 2026), fusionnée
dans `p2-je-parle` le 19 octobre 2026 à la demande du propriétaire (demande de fusion #3, commit 3040a47). `main` n'est
pas touchée. Le suivi constat par constat (fichiers, tests, résultat de la CI, limites) est dans
[`MOTEUR_FIABLE_SUIVI.md`](MOTEUR_FIABLE_SUIVI.md).

Chaque correction a suivi le même chemin : un test qui échoue sur le défaut, poussé sur la CI (rouge vérifié : seuls les
nouveaux tests échouent), puis le code (vert : tests, recherche de secrets et construction de l'app).

## Le nouveau chemin d'une dictée

1. **Capture et révisions (A).** Chaque source porte une révision, une empreinte du texte, une version de sa politique de
   confidentialité, le fuseau de la capture et la confiance de la transcription. Un partage n'est jamais retiré de sa
   boîte avant d'être enregistré. Une transcription incertaine dont le sens dépend d'un mot fragile (négation, nombre,
   date, nom) passe par « Vérifie ta note ».
2. **Interprétation (B).** Le modèle (Apple, Gemini ou Groq) reçoit un contrat commun : pour chaque pensée, l'extrait exact,
   l'intention (obligation, achat, souhait, cadeau, ajout à une liste, récit, hypothèse, citation, correction…), la
   polarité, le sujet, l'action, l'objet, le bénéficiaire et les dates avec leur rôle. Il ne reçoit que ce que la
   provenance de chaque dossier, liste et dictée récente permet, et un reçu est écrit avant chaque envoi.
3. **Validation.** Chaque chose, personne, lieu et date doit venir de la phrase de sa propre pensée ; un titre ou un résumé
   qui ajoute un nombre ou un nom est écarté. Une réponse hors contrat reçoit un seul nouvel essai avec ses erreurs
   précises ; sinon la dictée reste « À classer » (plus de « sauvetage »). Chaque passage oublié reste visible.
4. **Décision et cible (C).** Le planificateur d'actions transforme une pensée validée en opérations typées (note, ajout,
   coche, retrait). Une opération de liste exige une intention de liste affirmative, sans négation, condition, question
   ni citation, et une phrase qui porte vraiment l'opération (familles de verbes et de tournures, aucune règle propre à
   un mot). Un dossier d'action (« Achats », « À faire ») n'accepte que ses intentions. Une correction remplace la seule
   note qu'elle corrige, sinon elle reste à classer.
5. **Dossiers (D).** Le voisinage n'impose un dossier qu'avec des notes rangées par toi et une marge nette ; le ménage
   propose les déplacements sans les faire seul ; les dossiers donnés au modèle sont choisis selon le sens.
6. **Stockage transactionnel (E).** Le classement n'est écrit que sur la version lue de la source, avec sa décision de
   confidentialité, dans une seule transaction. Chaque chose d'une liste garde ses contributions (dictée, acteur réel) ;
   chaque date garde son rôle ; les goûts sont des assertions qui se remplacent. Chaque tentative laisse une trace locale.
7. **Effets externes (F).** Le calendrier passe par une boîte d'envoi durable avec une marque Engram dans l'événement ; la
   restauration d'une sauvegarde vérifie un manifeste et suit un journal de reprise.

## Migrations et reprise

Les migrations publiées (v1 à v18) ne sont pas modifiées. Les nouvelles :

| Migration | Contenu | Reprise des données existantes |
|---|---|---|
| v19 | base de la confidentialité, identifiant d'import, interdictions par liste, consentements, reçus d'envoi | base déduite seulement quand elle est certaine ; sinon inconnue (aucune sortie automatique) |
| v20 | révision, version de politique, fuseau, délai d'essai ; opérations de liste ; bail des travaux | valeurs par défaut sûres ; anciens ajouts comptés comme déjà faits |
| v21 | choses des listes et leurs contributions | les cases existantes deviennent des choses ; provenance inconnue si aucune opération notée |
| v22 | dates avec rôle ; note remplacée par | aucune ; les échéances existantes restent, sans rôle connu |
| v23 | confiance de la transcription | inconnue pour les anciennes dictées |
| v24 | boîte d'envoi du calendrier ; ce qui a été écrit dans l'événement | les anciens liens ne sont jamais modifiés ni supprimés automatiquement |
| v25 | trace des tentatives de classement | aucune (les classements d'avant n'ont pas de trace) |

Aucune réanalyse massive ni suppression n'est faite par les migrations. Pour les anciennes données ambiguës, le contenu
est gardé et la qualité est signalée inconnue.

## Commandes

```bash
bash scripts/ci.sh
```

Pousse la branche et attend la CI (tests de tous les modules, dont le corpus d'évaluation avec la bonne lecture et les
lectures fausses ; recherche de secrets ; construction de l'app).

Évaluation des vrais modèles : workflow « Apple evaluation » (lancement manuel sur GitHub), qui exécute
`ModelEvaluationTests` avec `ENGRAM_RUN_MODEL_EVAL=1`. Gemini et Groq demandent en plus `ENGRAM_ALLOW_CLOUD_EVAL=1` et
leurs clés, seulement avec ton accord explicite.

## Évaluation (F20)

- Corpus : 326 dictées inventées (prénoms fictifs), 16 familles de paires minimales, un cas sur quatre de chaque famille mis
  de côté comme jeu de contrôle.
- Déterministe (CI, à chaque envoi) : la bonne lecture donne les effets attendus pour tous les cas ; les lectures fausses
  (achat proposé pour une tâche, commande niée lue comme affirmative…) ne produisent aucun effet bloquant.
- Modèles réels : **non exécuté**. Le modèle d'Apple ne tournait pas dans le simulateur de la CI (constaté le 8 octobre
  2026) ; Gemini et Groq n'ont pas été appelés (aucun appel sans ton accord). Aucun score n'est inventé.

## Ce qui reste à vérifier sur ton iPhone

Rien n'est déclaré « testé sur iPhone ». À vérifier par toi :

- le calendrier réel (EventKit) : marque Engram, modification et suppression d'un événement, calendrier « Sur mon
  iPhone » ou synchronisé ;
- une interruption réelle de l'app pendant un classement, une restauration ou une transcription ;
- le modèle d'Apple sur l'appareil (contrat d'intention p50) ;
- Whisper sur de vrais enregistrements (seuil de confiance, « dois/deux », franglais) ;
- la pression mémoire et le démarrage à froid avec une grande bibliothèque.

## Limites connues

- Les règles de forme (négation, condition, question, citation, rôle d'une valeur) lisent des tournures, pas une analyse
  syntaxique complète : une négation partielle (« du lait, pas de crème ») n'écrit rien par prudence.
- Les assertions ne couvrent que les goûts ; les corrections reconnaissent une seule cible par ressemblance de mots.
- Les seuils (voisinage, confiance de transcription, réussite des évaluations) ne sont pas calibrés sur des données
  réelles.
- Un rendez-vous déjà lié au calendrier n'est pas remplacé par une correction.
- Les traces d'analyse n'ont pas encore de durée de conservation automatique.
