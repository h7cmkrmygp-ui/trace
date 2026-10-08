# Engram — Spécification · P2 « Je parle, c'est classé »

- **Date :** 2026-10-08
- **Statut :** approuvée par le propriétaire (« oui », 2026-10-08)
- **Remplace en partie :** `2026-10-07-engram-phase1-design.md` (§6.3 catégories de départ et seuil de création, §9 style visuel). Le reste de la spec Phase 1 s'applique.

## 1. Intention

### 1.1 Ce que le propriétaire a demandé
- Une app **ultra minimaliste**, dans l'esprit des captures de l'app de référence : fond clair, noir et gris, un grand bouton central « toucher pour parler », un écran Cerveau, Aujourd'hui et Calendrier plus tard. On reprend la mise en page et le minimalisme, avec **nos propres visuels** : pas de logo ni d'écran copié.
- **Aucune catégorie de départ.** L'IA crée les catégories **dès la première pensée** sur un sujet, et en crée beaucoup au fil du temps.
  - « Rappeler d'acheter des low beams pour ma Lexus » → *Automobile*
  - « Appeler mon gestionnaire de portefeuille » → *Finance*
  - « Demander congé le 29 octobre » → *Travail*
- **Catégories et sous-catégories** créées seules quand c'est utile (choix B), par exemple *Automobile › Lexus* ou *Travail › Congés*.
- **Plus tard :** un calendrier pour les dates, relié à Google Agenda. Prévu en P3, par le Calendrier de l'iPhone (EventKit). Un compte Google ajouté dans les Réglages d'iOS suffit, sans API Google.

### 1.2 Contraintes confirmées
- L'IA tourne **sur l'iPhone** (Foundation Models).
- Le modèle Private Cloud Compute d'Apple n'est pas accessible avec un Apple ID gratuit : il exige le programme développeur payant et une autorisation spéciale du compte.

## 2. Périmètre
| ID | Fonctionnalité | Contenu en P2 |
|---|---|---|
| F1 | Capture vocale | Toucher pour démarrer et arrêter, chrono, onde, Annuler. 5 min maximum. Audio en CAF, PCM 16 kHz mono, écrit en continu. |
| F2 | Transcription | Sur l'iPhone, **après l'arrêt** de l'enregistrement : `SpeechAnalyzer` + `SpeechTranscriber` sur le fichier, en français (Canada). Les ressources de la langue sont téléchargées au besoin. |
| F3, F10, F11 | Découpage et analyse | Une dictée donne plusieurs pensées. Chacune reçoit un titre, un résumé, un type, des tags (3 au plus), les dates mentionnées et un chemin de catégorie. |
| F12, F13, F14 | Catégories automatiques | L'IA choisit une catégorie existante ou en crée une. Le chemin a 1 ou 2 niveaux. Pas de doublon. |
| F15 | Tags | Proposés par l'IA (origine `ai`). |
| — | « À faire » | Les pensées de type tâche ou rendez-vous sont listées. Un balayage « Fait » les archive. |
| — | Nouvelle interface | Barre **Enregistrer · Notes**, style monochrome, carte de résultat, saisie au clavier. |
| — | Évaluation | Écran caché dans les Réglages : 40 phrases **fictives** FR/EN passent dans la vraie IA, et l'écran affiche le taux de catégories attendues. |
| — | Nettoyage | Les catégories de départ inutilisées sont archivées. Les notes « interim-none » sont ré-analysées. |

Hors périmètre, prévu en P3 : Cerveau (graphe), Aujourd'hui, Calendrier et rappels, Whisper si la transcription du mélange FR/EN est insuffisante, transcription en direct, embeddings et recherche par le sens.

## 3. Écarts assumés
- **Catégorie créée dès la première pensée.** Ça remplace le seuil de 2 notes de la spec Phase 1 (§6.3). C'est la demande explicite du propriétaire.
- **Plus de catégories de départ.** `seedDefaultsIfNeeded` n'est plus appelé. Les catégories de départ sans aucun lien sont archivées une fois.
- **L'IA voit la liste complète des chemins de catégories existants** et choisit dedans, au lieu d'une pré-sélection par embeddings. C'est suffisant jusqu'à environ 150 catégories. Les embeddings viendront avec la recherche par le sens.
- **Transcription après l'arrêt, pas en direct.** C'est plus simple et plus fiable sans Mac pour tester, au prix de quelques secondes d'attente.
- **La table `processing_job` reste inutilisée.** La reprise s'appuie sur `source.processing_status` : les sources `waiting` ou `pending` sont retraitées au lancement et au retour au premier plan.
- **Style monochrome.** Il remplace l'accent indigo, avec des composants SwiftUI natifs dépouillés : liste en style simple, pas de couleur sauf le rouge de l'enregistrement.

## 4. Architecture
Nouveaux modules du paquet `EngramKit` :

| Module | Rôle | Testé en CI |
|---|---|---|
| `EngramCore` (ajouts) | `ThoughtAnalysis`, `AnalyzedThought`, protocole `MemoryAnalyzer`, `AnalyzerError`, `AnalysisValidator` (anti-invention) | oui |
| `EngramStore` (ajouts) | chemins de catégories (`resolvePath`, `categoryPaths`), nettoyage des catégories de départ, source vocale, `ThoughtFiler` (classement en une transaction), flux « À faire » | oui |
| `EngramPipeline` | `ThoughtProcessor` : texte → analyse → validation → classement, avec repli et reprise | oui (avec `FakeAnalyzer`) |
| `EngramIntelligence` | `AppleThoughtAnalyzer` (Foundation Models, génération guidée `@Generable`), jeu d'évaluation fictif | compilation seulement |
| `EngramCapture` | `VoiceRecorder` (AVAudioRecorder), `FileTranscriber` (SpeechAnalyzer) | compilation seulement |

## 5. Flux
1. **Capture** (voix ou texte). La source et un souvenir **interim** « À classer » contenant le texte brut sont sauvegardés **immédiatement**. La source passe au statut `waiting`. Rien ne peut se perdre.
2. **`ThoughtProcessor.process(sourceID:)`**, dans l'ordre :
   1. récupérer la liste des chemins de catégories ;
   2. appeler l'analyseur avec le texte de référence et la liste ;
   3. valider le résultat ;
   4. appeler `ThoughtFiler.file`.
3. **`ThoughtFiler.file`**, en **une transaction** :
   1. supprimer les souvenirs interim de la source, s'ils n'ont pas été modifiés à la main ;
   2. créer un souvenir par pensée, avec l'extrait, le titre, le résumé, le type, les dates et `analysis_version = "p2-v1"` ;
   3. résoudre le chemin de catégorie, en créant les niveaux manquants ;
   4. lier la catégorie et les tags (origine `ai`) ;
   5. marquer la source `done`.

   Renvoie un `FilingSummary` (souvenirs et chemins).
4. **Échecs :**
   - IA indisponible (`AnalyzerError.unavailable`) : la source reste `waiting`, et le souvenir interim reste visible dans « À classer ». Nouvel essai au prochain lancement ou retour au premier plan.
   - Sortie invalide après un nouvel essai, refus ou garde-fou : **repli**. Le souvenir interim est conservé « À classer » et la source passe `done`.
   - Souvenir interim modifié à la main : il n'est jamais écrasé. Il reçoit seulement la catégorie et les tags de la première pensée analysée.

## 6. Analyseur

### 6.1 Contrat et consignes
**Contrat :** `analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis`. Les chemins de catégories sont écrits « Parent › Enfant ».

**Consignes** (rédigées en anglais, recommandation d'Apple) :
- Découper le texte en pensées distinctes ; le texte mélange souvent français et anglais.
- Pour chaque pensée :
  - `title` : court et précis, dans la langue de l'utilisateur ;
  - `summary` : facultatif ;
  - `excerpt` : citation **mot pour mot** du texte ;
  - `kind` ;
  - `tags` : 3 au plus ;
  - `mentionedDates` : expressions brutes ;
  - `category` : domaine large **en français**, 1 à 3 mots (Automobile, Finance, Travail, Santé, Maison, Famille, Achats, Projets…) ;
  - `subcategory` : facultative, seulement pour une chose précise et nommée (marque, modèle, projet, personne, sujet récurrent).
- Réutiliser **exactement** l'orthographe d'une catégorie ou sous-catégorie existante quand elle convient.
- Ne jamais inventer.

### 6.2 Génération et erreurs
- **Génération guidée** :
  - `@Generable struct GeneratedThoughts { var thoughts: [GeneratedThought] }` ;
  - `@Generable enum GeneratedKind` ;
  - `@Guide(.maximumCount(3))` sur les tags.
- **Longs textes** : au-delà de 2 500 caractères, découpage aux frontières de phrases. En cas de `exceededContextWindowSize`, le morceau est coupé en deux et renvoyé.
- **Correspondance des erreurs :**
  - `unavailable` : `SystemLanguageModel.default.availability` vaut `.unavailable`, ou `GenerationError.assetsUnavailable` ;
  - `refused` : `guardrailViolation` ou `refusal` ;
  - `invalidOutput` : `decodingFailure` ;
  - `busy` : `rateLimited` ou `concurrentRequests`, avec un nouvel essai.

## 7. Validation anti-invention (`AnalysisValidator`)
1. L'`excerpt` doit apparaître dans le texte, comparé sous sa forme `TextNormalizer.matchingForm` aux **limites de mots**. Sinon la pensée est rejetée.
2. Le titre est découpé, puis réduit à 80 caractères par `TitleMaker` s'il est trop long. S'il est vide, on prend le titre de repli de l'extrait.
3. La catégorie, une fois nettoyée, doit avoir de 1 à 40 caractères. Une sous-catégorie vide ou identique à la catégorie est ignorée.
4. Les tags sont dédoublonnés, et seuls les 3 premiers de 30 caractères au plus sont gardés.
5. Au moins une pensée valide doit rester. Sinon `AnalyzerError.invalidOutput`, et le processeur fait un nouvel essai, puis le repli.

## 8. Résolution des catégories
- Chaque niveau est cherché parmi les catégories **actives** de même parent, par `normalized_name`. Si rien ne correspond, il est créé (origine `ai`). Le nom affiché est celui de la première création.
- Le lien est posé sur la catégorie la plus précise (sous-catégorie si elle existe), avec `origin = ai`. Un lien que le propriétaire a rejeté n'est jamais recréé.
- La liste envoyée à l'IA contient tous les chemins actifs, triés : « Automobile », « Automobile › Lexus », « Travail »…

## 9. Interface
- **Style.** Fond système, texte primaire et secondaire, SF Symbols en graisse légère. Couleur d'accent `.primary` (noir ou blanc selon le mode) ; seul le rouge signale l'enregistrement en cours.
- **Barre d'onglets :** Enregistrer (`waveform`) · Notes (`square.stack`).
- **Enregistrer.**
  - Au repos : un grand cercle (≈ 200 pt, trait fin) avec l'icône `mic`, et « Toucher pour parler » en petites capitales en dessous.
  - En cours : chrono « 0:21 / 5:00 », point rouge, onde de 24 barres alimentée par le niveau du micro ; toucher le cercle arrête, ✕ annule.
  - Ensuite : « Transcription… » puis « Classement… ».
  - Résultat : une carte par pensée (titre et chemin de catégorie). Toucher une carte ouvre le souvenir.
  - Icône clavier en bas à gauche : saisie texte, même traitement.
- **Notes.**
  - Recherche en haut.
  - Section « À faire » (tâches et rendez-vous actifs).
  - Catégories en arbre, avec compteurs.
  - « À classer » seulement s'il y a des pensées à classer.
  - En bas : Archives, Corbeille, Réglages.
  - Le détail d'un souvenir est celui de P1, épuré.
- **Réglages.** Export, état de l'IA (disponible ou raison), et **Évaluation** (mode développeur).

## 10. Tests
- **CI :**
  - validateur (extrait verbatim, limites de mots, titres, catégories, tags, rejet total) ;
  - résolution des chemins (réutilisation malgré accents, casse et pluriel ; création des deux niveaux ; aucune recréation d'un lien rejeté) ;
  - nettoyage des catégories de départ ;
  - `ThoughtFiler` (remplacement de l'interim, protection des souvenirs modifiés à la main, une transaction) ;
  - `ThoughtProcessor` avec `FakeAnalyzer` (succès, indisponible, sortie invalide puis repli, reprise des sources en attente) ;
  - flux « À faire ».
- **iPhone :** liste de contrôle à la voix, et écran Évaluation avec les phrases fictives.

## 11. Risques
- **Qualité du petit modèle sur les catégories.** Mesurée par l'écran Évaluation ; les consignes sont versionnées (`p2-v1`).
- **Transcription d'un texte qui mélange FR et EN.** Mesurée avec les vraies notes du propriétaire ; Whisper en P3 si nécessaire.
- **API d'iOS 27 utilisées sans Mac.** Signatures relevées le 2026-10-08 (run `SDK check` sur `p2-je-parle`). Les erreurs de compilation sont corrigées en CI.
