# Engram P2 — « Je parle, c'est classé » : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (exécution en ligne). Les étapes suivent le TDD : tests poussés d'abord, échec observé en CI, puis implémentation et passage au vert.

**Goal :** parler (ou écrire) une pensée sur l'iPhone, la voir transcrite, découpée, titrée et **classée automatiquement** dans des catégories et sous-catégories créées par l'IA, dans une interface monochrome à deux onglets.

**Architecture :**
- Nouveaux modules `EngramPipeline` (orchestration testée en CI avec un faux analyseur), `EngramIntelligence` (Foundation Models) et `EngramCapture` (AVAudioRecorder et SpeechAnalyzer).
- Le stockage gagne les chemins de catégories et le classement en une transaction.
- L'app passe à Enregistrer · Notes.

**Spec :** `docs/superpowers/specs/2026-10-08-engram-p2-je-parle-design.md` (prévaut sur la spec Phase 1 aux points indiqués).

**Note de forme (ruling) :** contrairement à P1, ce plan ne recopie pas le code. Planificateur et exécutant sont la même session, et le propriétaire a demandé d'aller vite sans coût inutile. Chaque tâche fixe les fichiers, les interfaces exactes et les tests attendus (noms et comportements). Le code est écrit une fois, en TDD.

## Global Constraints
- Mêmes contraintes que P1 :
  - iOS 27 ;
  - Swift 6 ;
  - GRDB 7.11.1 ;
  - dépôt public sans donnée personnelle ;
  - identité noreply ;
  - pas de `try!` ni de `fatalError` sur un chemin utilisateur ;
  - toute écriture multi-tables en une transaction.
- `analysis_version` des souvenirs analysés : `"p2-v1"`. Repli : la version reste `"interim-none"`.
- Chemin de catégorie : 1 ou 2 niveaux, séparateur d'affichage `" › "`, 40 caractères au plus par niveau.
- Enregistrement : 5 minutes maximum, CAF PCM 16 kHz mono, fichiers dans `Application Support/Engram/audio/`, et `audio_path` relatif au dossier Engram (`audio/<uuid>.caf`).
- Langue de transcription : `fr-CA`, avec repli `fr-FR` puis la langue de l'appareil, via `SpeechTranscriber.supportedLocale(equivalentTo:)`.
- Données d'évaluation **fictives** uniquement.

## Review Focus
1. **Un texte que l'IA renvoie avec un extrait inventé ou reformulé** : la pensée est rejetée. Si plus rien de valide ne reste, repli : le texte brut reste « À classer ».
2. **Une catégorie proposée sous une variante d'une catégorie existante** (« automobile », « Automobiles », « AUTOMOBILE ») : la catégorie existante est réutilisée.
3. **L'IA est indisponible** (Apple Intelligence désactivé, ou modèle en téléchargement) : la note reste visible dans « À classer » et sera retraitée plus tard, sans erreur bloquante.
4. **Le propriétaire a corrigé le texte d'une note interim avant l'analyse** : sa note n'est jamais supprimée ni réécrite.
5. **Un enregistrement interrompu** (appel) ou atteignant 5 minutes : l'audio est gardé et traité, et rien n'est perdu.

## Tâches

### Task 1 — Types d'analyse et validateur (EngramCore)
- **Create :**
  - `Sources/EngramCore/ThoughtAnalysis.swift` : `AnalyzedThought` (title, summary?, excerpt, kind: MemoryKind, tags, mentionedDates, category: String, subcategory: String?), `ThoughtAnalysis { thoughts }`, `protocol MemoryAnalyzer: Sendable { func analyze(text:existingCategories:) async throws -> ThoughtAnalysis }` et `enum AnalyzerError: Error, Equatable { unavailable(String), refused, invalidOutput, busy }` ;
  - `Sources/EngramCore/AnalysisValidator.swift` : `AnalysisValidator.validate(_:against:) throws -> [ValidThought]`, avec `ValidThought` (title, summary, excerpt, spanStart, spanEnd, kind, tags, categoryPath: [String], mentionedDates) ;
  - `TextNormalizer.containsPhrase(_:in:)` ;
  - `EngramTesting/FakeAnalyzer.swift`.
- **Tests (`AnalysisValidatorTests`) :**
  - accepte un extrait verbatim, sans tenir compte de la casse, des accents et de la ponctuation ;
  - rejette un extrait inventé ;
  - respecte les limites de mots (« lait » n'est pas trouvé dans « laitue ») ;
  - réduit un titre trop long à 80 caractères ;
  - remplace un titre vide par le titre de repli ;
  - nettoie la catégorie et ignore une sous-catégorie vide ou égale à la catégorie ;
  - dédoublonne les tags et en garde 3 ;
  - lève `invalidOutput` si aucune pensée n'est valide ;
  - calcule `spanStart`/`spanEnd` en UTF-16 quand l'extrait est retrouvé tel quel.

### Task 2 — Chemins de catégories et nettoyage des catégories de départ (EngramStore)
- **Modify :** `CategoryStore`, avec :
  - `resolvePath(_ names: [String], origin: Origin) throws -> EngramCategory`, ainsi qu'une variante interne `(db, …)` ;
  - `categoryPaths() throws -> [String]` (actives, triées, « Parent › Enfant ») ;
  - `archiveUnusedSeeds() throws -> Int`.
- **Modify :** `AppModel.launch`, qui n'appelle plus `seedDefaultsIfNeeded` mais `archiveUnusedSeeds`.
- **Tests (`CategoryPathTests`) :**
  - crée les deux niveaux ;
  - réutilise un niveau existant malgré accents, casse et pluriel ;
  - un même enfant sous deux parents donne deux catégories ;
  - `categoryPaths` est trié et formaté ;
  - `archiveUnusedSeeds` archive les catégories de départ vides et garde celles qui ont un lien.

### Task 3 — Source vocale, classement en une transaction et « À faire » (EngramStore)
- **Create :** `Sources/EngramStore/ThoughtFiler.swift`, avec :
  - `ThoughtFiler(database:dates:)` ;
  - `file(_ thoughts: [ValidThought], sourceID:) throws -> FilingSummary` (`FilingSummary { memories: [Memory], categoryPaths: [String] }`) ;
  - `markFallback(sourceID:) throws`.
- **Modify :**
  - `MemoryStore` : `saveVoiceNote(audioPath:duration:transcript:languages:engine:) throws -> Memory` (source vocale + souvenir interim, une transaction), `sourcesAwaitingAnalysis() throws -> [UUID]`, `saveTextNote(_:)`, qui reprend la note texte P1 ;
  - `MemoryStore.memoriesStream(kinds:statuses:)`, pour la liste « À faire ».
- **Tests (`ThoughtFilerTests`) :**
  - remplace l'interim par N souvenirs analysés, catégorisés et tagués ;
  - un interim modifié à la main est conservé et reçoit seulement la catégorie ;
  - la source passe à `done` ;
  - le repli conserve l'interim et marque `done` ;
  - un lien rejeté n'est pas recréé ;
  - la note vocale enregistre l'audio et la transcription ;
  - le flux « À faire » ne contient que les tâches et rendez-vous actifs.

### Task 4 — Orchestration (EngramPipeline)
- **Create :** cible `EngramPipeline` (dépend de Core et Store), avec `actor ThoughtProcessor(memories:categories:filer:analyzer:)` :
  - `process(sourceID:) async -> ProcessingOutcome` (`filed(FilingSummary)`, `waiting(reason)`, `fallback`) ;
  - `processPending() async -> [ProcessingOutcome]`.

  Un `invalidOutput` ou un `busy` déclenche un seul nouvel essai.
- **Tests (`ThoughtProcessorTests`, avec `FakeAnalyzer`) :**
  - succès, avec l'IA qui reçoit les chemins existants ;
  - indisponible : la source reste `waiting` et l'interim est intact ;
  - invalide deux fois : repli ;
  - invalide puis valide : classé ;
  - `processPending` traite toutes les sources en attente ;
  - une note sans texte (transcription vide) passe en repli.

### Task 5 — Analyseur Apple (EngramIntelligence)
- **Create :** cible `EngramIntelligence`, avec :
  - `AppleThoughtAnalyzer: MemoryAnalyzer` (`@Generable` GeneratedThoughts, GeneratedThought, GeneratedKind ; consignes `AnalysisPrompt.v1` ; découpage au-delà de 2 500 caractères ; correspondance des erreurs selon la spec §6.2) ;
  - `AppleThoughtAnalyzer.availabilityDescription` ;
  - `EvaluationSet` (40 phrases fictives FR/EN, avec les racines de catégorie acceptées).
- **Tests :** `EvaluationSetTests` (40 cas, chacun avec au moins une catégorie acceptée, et aucune donnée réelle). L'analyseur lui-même est vérifié par la compilation en CI et par l'écran Évaluation sur l'iPhone.

### Task 6 — Enregistrement et transcription (EngramCapture)
- **Create :** cible `EngramCapture`, avec :
  - `VoiceRecorder` (`@MainActor @Observable` : state, elapsed, level ; `start()`, `stop() -> RecordingResult?`, `cancel()` ; 5 min maximum ; gestion des interruptions) ;
  - `FileTranscriber` (`transcribe(url:) async throws -> Transcript { text, locale }`, avec installation des ressources de la langue) ;
  - `AudioFiles` (création du chemin `audio/<uuid>.caf`).
- **Tests :** `AudioFilesTests` (chemin relatif, dossier créé). Le reste est vérifié par la compilation et sur l'iPhone.

### Task 7 — Interface « Enregistrer »
- **Create :**
  - `App/Sources/Record/RecordView.swift` (cercle, chrono, onde, Annuler, clavier, états) ;
  - `RecordModel.swift` (enregistrement, puis sauvegarde de l'interim, transcription, mise à jour de la source et traitement, avec reprise en cas d'échec) ;
  - `FiledResultCard.swift` ;
  - `TextCaptureSheet.swift`.
- **Modify :**
  - `AppModel`, qui crée `ThoughtProcessor`, `AppleThoughtAnalyzer`, `FileTranscriber` et lance `processPending()` au lancement et au retour au premier plan ;
  - `project.yml`, avec les nouveaux produits et `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` en français.

### Task 8 — Interface « Notes », Réglages et Évaluation
- **Create :**
  - `App/Sources/Notes/NotesView.swift` (recherche, À faire, arbre des catégories, À classer, Archives, Corbeille, Réglages) ;
  - `Settings/EvaluationView.swift`.
- **Modify :** `RootView`, qui passe à deux onglets avec le style monochrome (`.tint(.primary)`). Les anciennes vues Home, Library et Search sont retirées ou réutilisées.

### Task 9 — Vérification et documents
- CI verte.
- Récupérer le `.ipa` et donner au propriétaire la liste de contrôle :
  - parler une pensée ;
  - parler plusieurs pensées ;
  - les exemples Lexus, portefeuille et congé ;
  - correction d'une catégorie ;
  - mode avion ;
  - interruption ;
  - Évaluation.
- Mettre à jour `IMPLEMENTATION_PROGRESS.md` et `ROADMAP.md`, ainsi que la PR.
