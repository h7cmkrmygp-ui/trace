# Engram P4 — « Vraie IA » : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (exécution en ligne, TDD via la CI).

- **Goal :**
  - des Notes, un Cerveau et une Corbeille simples et justes ;
  - une transcription Whisper bilingue sur l'iPhone ;
  - un classement intelligent qui respecte la confidentialité : Gemini pour le neutre, Groq pour le personnel, l'iPhone pour le secret.
- **Spec :** `docs/superpowers/specs/2026-10-08-engram-p4-vraie-ia-design.md` (sections 10 et 11 prioritaires).
- **Forme (ruling, comme P2 et P3) :** les tâches fixent les fichiers, les interfaces et les tests ; le code est écrit une seule fois, en TDD via la CI (pas de Mac).

## Global Constraints
- Contraintes P1 à P3 inchangées : dépôt public, données de test fictives, identité `noreply`, Swift 6 strict, Swift Testing, interface en français.
- **Migration v3** : uniquement des ajouts (`ALTER TABLE … ADD COLUMN`). v1 et v2 ne sont jamais modifiées.
- **Aucune clé ni aucun jeton dans le code, la CI ou l'IPA.** Les clés sont collées par le propriétaire et rangées dans le trousseau (`ThisDeviceOnly`), et passées dans un en-tête HTTP, jamais dans l'adresse.
- **Aucun contenu de note dans les journaux** (`print`, `Logger`) ni dans les messages d'erreur.
- **Une note personnelle ne va jamais chez Gemini. Une note secrète ne quitte jamais l'iPhone. Le doute va toujours vers le niveau le plus protégé.**
- **Les mots-clés ne peuvent jamais déclarer une note neutre.**
- **Whisper** : tâche `transcribe`, jamais `translate`. Le français n'est pas imposé.
- **Aucun changement de modèle Whisper sans la validation du propriétaire.**
- **0 $** : aucune facturation, aucun service payant. Quota atteint : traitement local.
- **Aucune fonctionnalité existante retirée.** Seule l'option OpenAI, jamais livrée, est abandonnée.
- **Aucune réécriture de l'historique Git, aucune poussée forcée.**

## Review Focus
1. **Confidentialité :**
   - une note qui contient un nom de personne, une donnée de santé ou d'argent n'atteint jamais Gemini, même si le jugement d'Apple dit « neutre » ;
   - si le jugement d'Apple est indisponible, la note reste sur l'iPhone.
2. **Panne :** quota atteint ou réseau absent, et la note est classée sur l'iPhone. Rien n'est perdu, et le reclassement ultérieur ne touche jamais une note modifiée par le propriétaire.
3. **Notes modifiées :** la retranscription et le reclassement ne remplacent jamais une note modifiée par le propriétaire. Le texte original reste intact.
4. **« À vérifier » :** une note qui attend d'être vérifiée n'est jamais classée automatiquement, et elle survit à une fermeture de l'app.
5. **Catégories vides :** une catégorie sans note n'apparaît ni dans Notes ni dans le Cerveau. Un parent dont un enfant contient des notes reste visible.

## Phase A — Notes, Cerveau, Corbeille
1. **Catégories non vides (Store).**
   - `librarySummary` et `brainSnapshot` ne gardent que les catégories qui contiennent au moins une note vivante (`active` ou `unsorted`), elles ou leurs descendants ;
   - `CategorySummary` expose `description` et `totalCount` (descendants compris).
   - Tests : catégorie vide exclue, parent d'un enfant non vide gardé, Cerveau vide après mise à la corbeille.
2. **Vider la corbeille (Store et App).** `MemoryStore.emptyTrash() -> [PermanentDeletion]`, et `AppModel.emptyTrash()`, qui supprime aussi les fichiers audio devenus orphelins. Test : toutes les notes `trashed` disparaissent, les autres restent.
3. **App** (vérifiée par la compilation) :
   - **Corbeille** : balayer donne « Restaurer » et « Supprimer » (avec confirmation) ; bouton « Tout supprimer » (avec confirmation) ; boutons destructifs `.tint(.red)` ;
   - **Notes** : recherche, puis des cartes-dossiers (icône, nom, description ou nombre de notes) ; cartes « À faire » et « À classer » si elles ne sont pas vides ; menu en haut avec Archives, Corbeille et Réglages ;
   - **Dans une catégorie** : intertitres de sous-catégories.
4. **Exemples fictifs.** Les phrases tirées de la vie du propriétaire sont remplacées dans les tests, le jeu d'évaluation, les consignes de l'IA et les documents actuels. Suite verte.

## Phase B — Whisper
5. **Moteurs de transcription (Capture).**
   - `TranscriptionEngine` : `whisper` (par défaut) et `apple` ;
   - retrait d'OpenAI : son code et les parties de tests qui le concernent ;
   - `FileTranscriber` conforme à `AudioTranscriber` ;
   - `retranscribe` et `voiceSources` du stockage : les tests RED existants passent au vert.
6. **Stratégie bilingue (Capture, logique pure testée).**
   - `WhisperModel` : `.largeV3Turbo` (`openai_whisper-large-v3-v20240930_626MB`, par défaut) et `.largeV3` (`openai_whisper-large-v3_947MB`) ;
   - `LanguagePlan.decide(probabilities:) -> .single(code) | .both`, limité au français et à l'anglais, seuil 0,85 ;
   - `HypothesisPicker.best(_:)`, qui choisit la meilleure log-probabilité moyenne ;
   - `WhisperPrompt.bilingual` ;
   - `WhisperTranscriber` (WhisperKit 1.1.0) : découpage par détection de la voix, décision de langue par morceau, double décodage si mélange, téléchargement avec progression, dossier exclu de la sauvegarde, vérification de la prise en charge par l'appareil.
   - Tests : seuils, langues hors fr/en ignorées, choix d'hypothèse, assemblage du texte.
7. **« À vérifier » (Store, migration v3).**
   - `source.needs_review` ;
   - `attachTranscript(..., needsReview:)` ;
   - `sourcesAwaitingReview()` ;
   - `confirmReview(sourceID:text:)`, qui garde `originalText`, range la correction dans `correctedText` et libère l'analyse ;
   - `discardReview` ;
   - `sourcesAwaitingAnalysis` exclut les notes à vérifier.
   - Tests : pas d'analyse avant la confirmation, la note survit à une réouverture, l'original est conservé.
8. **App** :
   - **Transcription** : moteur choisi, puis Apple en secours ;
   - **Réglages › Transcription** : modèle, téléchargement, état, « Classer sans vérifier » ;
   - **Enregistrement** : carte « Vérifie ta note » (modifier, Classer, Annuler) ;
   - **Notes vocales** : « Retranscrire » dans le détail d'une note, « Tout retranscrire » dans Réglages.
9. **Banc d'essai.**
   - **Core** :
     - `WordErrorRate` (normalisation : casse et ponctuation ignorées, accents gardés ; distance d'édition sur les mots) ;
     - `EnglishRetention` (part des mots anglais de la référence retrouvés tels quels) ;
     - `PairedBootstrap` (intervalle de confiance à 95 %, graine fixe en test) ;
     - `ModelRecommendation` (règle de la section 11.3) ;
     - `BilingualTestSet` (environ 40 phrases fictives).
   - **App** : `BenchmarkView`.
     - Le propriétaire lit chaque phrase, puis l'app compare 2 modèles × 3 stratégies : vitesse, batterie, résultats et recommandation.
     - Le changement de modèle ou de stratégie n'est appliqué que si le propriétaire le valide.
     - Les enregistrements restent sur l'iPhone.

## Phase C — Confidentialité et classement
10. **`PrivacyGate` (Intelligence et Core, logique testée).**
    - `PrivacyLevel` : `neutral`, `personal`, `secret` ;
    - `SensitiveDetectors` :
      - courriels, téléphones et adresses (`NSDataDetector`) ;
      - cartes (contrôle de Luhn), NAS, IBAN et longs numéros ;
      - mots de passe et NIP ;
      - montants ;
      - noms de personnes, de lieux et d'organisations (`NLTagger`) ;
    - `SensitiveLexicon` FR/EN : il ne fait que monter le niveau ;
    - protocole `PrivacyJudge`, qui renvoie le niveau, la confiance et le motif ;
    - `PrivacyGate.evaluate(...) -> PrivacyDecision` avec les règles de la section 11.1 : « Garder sur l'iPhone » et le réglage santé, juge indisponible → secret, doute vers le haut.
    - Tests avec un juge factice.
11. **Clients en ligne (Intelligence, avec un transport HTTP injecté).**
    - Clients :
      - `GeminiClient` : `generateContent`, schéma JSON, en-tête `x-goog-api-key`, enchaînement Flash puis Flash-Lite ;
      - `GroqClient` : `chat/completions`, `json_schema` strict, `openai/gpt-oss-120b`.
    - Partagés :
      - `CloudPrompt` (consignes et exemples génériques) ;
      - `CloudSchema` ;
      - décodage vers `AnalyzedThought`, avec la description de catégorie.
    - Erreurs : 401/403 → clé invalide, 429 → quota (délai lu dans la réponse), 5xx, réseau absent.
    - Tests : requête construite sans historique ni clé dans l'adresse, réponses valides et invalides, erreurs.
12. **Routage (Pipeline et Store, migration v3).**
    - `RoutedAnalyzer: MemoryAnalyzer` (porte, puis services, puis secours) ;
    - `AnalysisRoute` (niveau, service, motif) rangé sur la source ;
    - `needs_cloud_retry` et un travail de reclassement des notes non touchées ;
    - compteur de quota par service et par jour du Pacifique ;
    - `ThoughtFiler` enregistre la description d'une catégorie qu'il crée.
    - Tests : neutre → Gemini, personnel → Groq, secret → iPhone, quota → secours puis reprise, aucune note personnelle chez Gemini.
13. **Classement local amélioré.**
    - consignes d'Apple `p4-v1` : plus d'invitation à découper, règles et exemples ;
    - fusion des rappels qui parlent de la même chose ;
    - `ApplePrivacyJudge` (FoundationModels) ;
    - suggestion de catégorie par proximité de sens (`NLEmbedding`, sur l'iPhone).
    - Tests du jeu d'évaluation mis à jour.
14. **App** :
    - **Réglages › Intelligence** : clés Gemini et Groq, « Tester », réglage santé, statistiques et quotas, liens vers AI Studio et vers la console Groq ;
    - **Carte de vérification** : « Garder sur l'iPhone » ;
    - **Détail d'une note** : « Classée par … — motif ».

## Phase D — Fin
15. **Relecture complète** de la branche (auto-relecture), puis corrections avec TDD.
16. **Documents** (`IMPLEMENTATION_PROGRESS`, `ROADMAP`), IPA et liste de vérification groupée pour l'iPhone (P2, P3 et P4).
