# Engram — Spécification de conception · Phase 1 (Fondation)

- **Date :** 2026-10-07
- **Statut :** en attente de relecture par le propriétaire
- **Référence de vision :** master prompt « SECOND BRAIN ULTIMATE » (sections 0 à 29), fourni le 2026-10-07. Les identifiants `F1`…`F100` de ce document renvoient aux fonctionnalités numérotées de ce prompt.

---

## 0. Résumé

Engram est une application iPhone **personnelle** de mémoire intelligente. L'utilisateur capture ses pensées (voix ou texte) ; l'app les transcrit, les découpe en souvenirs distincts, leur donne un titre et un résumé, les classe automatiquement dans des catégories qu'elle crée elle-même, et les rend retrouvables par mots et par sens.

La Phase 1 livre une application **réellement utilisable au quotidien**, fonctionnant **entièrement sur l'iPhone**, **sans coût** et **hors ligne**. Elle est conçue pour accueillir sans réécriture les phases suivantes (graphe, Ask Your Brain, serveur et MCP, intégrations Apple, intelligence proactive).

---

## 1. Intention et contexte

### 1.1 Ce que le propriétaire a demandé
- Un « deuxième cerveau » qui comprend, organise, relie et rend réutilisable ce qu'on lui confie (master prompt).
- **Usage strictement personnel** (un seul utilisateur, pas de distribution).
- Une **vraie app native iPhone**, installée par **AltServer/AltStore** avec un **Apple ID gratuit** ; renouvellement tous les 7 jours assumé par le propriétaire.
- Utilisation **loin du PC** : l'app ne doit pas dépendre de l'ordinateur pour fonctionner.
- **Budget : 0 $.**
- L'IA doit simplement **faire ce qui est demandé de façon fiable**, pas besoin d'un modèle de pointe.
- L'IA doit comprendre le **mélange français/anglais** dans une même note.
- Design **strictement dans le langage d'Apple** : l'app doit pouvoir être confondue avec une app Apple d'origine.
- Dépôt GitHub **public** acceptable, à condition que **rien de privé** n'y soit jamais exposé.
- Nom choisi : **Engram** (trace physique d'un souvenir dans le cerveau).

### 1.2 Faits vérifiés
| Fait | Source |
|---|---|
| AltStore fonctionne déjà sur l'iPhone du propriétaire (iOS 27) | propriétaire |
| Apple Intelligence est activé (langue système : anglais) | propriétaire |
| iPhone 17, iOS 27 | propriétaire |
| PC Windows 11, aucun Mac | propriétaire + environnement |
| Compte GitHub `h7cmkrmygp-ui` connecté via `gh` | vérifié le 2026-10-07 |
| Le modèle on-device d'Apple (Foundation Models) couvre les langues d'Apple Intelligence, dont l'anglais et le français ; la langue système doit être une langue supportée | forums développeurs Apple, WWDC25 Group Lab |
| GitHub propose une image de runner `xcode-27` (aperçu public depuis juillet 2026, hôte macOS 27 depuis septembre 2026) | GitHub Changelog |
| AltStore (Apple ID gratuit) : 3 apps actives maximum, 10 App IDs à la fois, chaque App ID expire après 7 jours, chaque extension d'app consomme un App ID | FAQ AltStore |

### 1.3 Écarts assumés par rapport au master prompt
| Exigence du master prompt | Décision pour Engram | Raison |
|---|---|---|
| Backend TypeScript + PostgreSQL dès le départ | Phase 1 **local-first** (SQLite sur l'iPhone). Serveur ajouté en Phase 3. | App plus simple et plus vite utilisable ; le serveur n'est indispensable que pour le MCP. Le modèle de données est prêt pour la synchronisation (UUID, journal des changements). |
| Authentification (Sign in with Apple, Google, courriel) | Aucune en Phase 1 (un seul utilisateur, données locales). Verrouillage optionnel par Face ID. | Usage personnel ; Sign in with Apple indisponible avec un Apple ID gratuit. L'authentification revient en Phase 3 pour le serveur et le MCP. |
| Identité visuelle originale | **Langage de design Apple strict** (Human Interface Guidelines), sans logo Apple. | Choix explicite du propriétaire le 2026-10-07. |
| Modèles IA cloud avec adaptateurs | **Modèle on-device d'Apple** (gratuit, privé, hors ligne). L'adaptateur permet d'ajouter une API plus tard. | Budget 0 $ ; confidentialité. |
| Multi-utilisateurs (`owner_id` partout) | Mono-utilisateur, pas de `owner_id` en local. | Usage personnel. Le serveur de la Phase 3 pourra l'ajouter si nécessaire. |
| Notifications push | Notifications **locales** uniquement (phases ultérieures). | Indisponibles avec un Apple ID gratuit. |
| 18 documents livrables d'un coup | Produits **progressivement**, chacun quand sa phase démarre. Phase 1 : cette spec, le plan d'implémentation, `IMPLEMENTATION_PROGRESS.md`, `ROADMAP.md`. | Séquencement, pas suppression : aucune capacité n'est abandonnée. |

---

## 2. Contraintes

1. **Pas de Mac.** Aucun Xcode ni simulateur local. Toute compilation et tout test automatique passent par **GitHub Actions** (runners macOS, image `xcode-27`). Boucle d'itération : envoi du code → compilation et tests (≈10–15 min, estimation) → téléchargement du `.ipa` → installation via AltStore → retour du propriétaire (captures d'écran, description).
2. **Apple ID gratuit via AltStore.** Re-signature tous les 7 jours ; 3 apps actives ; 10 App IDs. La Phase 1 n'utilise **aucune extension** (donc 1 seul App ID) et **aucune capacité réservée** aux comptes payants.
3. **iOS 27 uniquement** (cible de déploiement minimale : iOS 27.0).
4. **Budget 0 $** : aucune API payante, aucun service payant.
5. **Dépôt public** : règles de confidentialité strictes (§11).
6. **Dossier du projet dans OneDrive** : risque de conflits de synchronisation avec `.git` (§15).

---

## 3. Périmètre de la Phase 1

### 3.1 Inclus
| ID | Fonctionnalité | Portée en Phase 1 |
|---|---|---|
| F1 | Capture vocale instantanée | Dans l'app : démarrer, pause/reprise, annuler, terminer, sauvegarde continue. (Bouton Action et Siri : Phase 4.) |
| F2 | Transcription intelligente | FR/EN, détection de langue par segment, transcription originale conservée, correction possible ; une correction déclenche une ré-analyse **proposée**. |
| F3 | Décomposition d'un enregistrement | Une source → un ou plusieurs souvenirs, chacun lié à son extrait exact. |
| F4 | Capture textuelle rapide | Éditeur minimal, sans titre ni catégorie obligatoires. |
| F7 | Conservation des originaux | Audio et texte d'origine toujours conservés, sauf suppression définitive choisie. |
| F8 | Capture hors ligne | Natif : tout est local. La file attend si l'IA est indisponible. |
| F10 | Pipeline de transformation | Étapes A–F, H et J du §16 du master prompt (graphe G et actions I : phases ultérieures). |
| F11 | Titres et résumés automatiques | Titres précis ; résumés conservant dates, montants, conditions, incertitudes. |
| F12 | Création automatique de catégories | Catégories et sous-catégories créées quand plusieurs notes partagent un nouveau sujet ; anti-synonymes. |
| F13 | Classement automatique | Avec statut « À classer » quand l'IA hésite. |
| F14 | Classification multiple | Un souvenir dans plusieurs catégories sans duplication. |
| F15 | Tags intelligents | Proposés par l'IA, modifiables et supprimables. |
| F17 | Mémoire persistante | Locale + export complet. (Sauvegarde serveur : Phase 3.) |
| F19 | Historique temporel (partiel) | Date de capture, création, modification ; dates mentionnées conservées en texte brut. (Fenêtres de validité : Phase 2.) |
| F20 | Détection des doublons (partiel) | Doublons techniques ignorés ; quasi-doublons **signalés**. (Fusion intelligente : Phase 2.) |
| F23 | Sources et provenance | Chaque souvenir pointe vers sa source et son extrait. |
| F24 | Modification, archivage, restauration | Versions conservées et restaurables. |
| F84 | Propriété des données | Consulter, corriger, exporter, supprimer. |
| F86 | Chiffrement (partiel) | Chiffrement au repos par la Data Protection d'iOS. |
| F89 | Exportation ouverte | JSON + Markdown + fichiers audio dans un ZIP. |
| F90 | Suppression contrôlée | Archive, corbeille (restaurable), suppression définitive confirmée. |
| F92 | Design | Langage Apple strict (§9). |
| F93 | Accueil (partiel) | Capture, récents, « À classer », statut de traitement. |
| F94 | Recherche universelle (partiel) | Sur les souvenirs (tâches, événements, documents : phases ultérieures). |
| F96 | Accessibilité | VoiceOver, Dynamic Type, contrastes, Réduire les animations. |
| F97 | Performance | Objectifs mesurables (§14). |

### 3.2 Exclus de la Phase 1 (planifiés)
F5–F6 (import multimodal, extension de partage), F9 (réunions), F16 (types de mémoire), F18 et F21–F22 (évolution, contradictions, incertitudes complètes), F25–F31 (Brain Graph), F32–F39 (Ask Your Brain), F40–F48 (MCP), section 8 (Siri, App Intents, bouton Action, widgets), F49–F64 (calendrier et organisation), F65–F71 (briefings), F72–F83 (espaces et projets), F85, F87–F88 et F91 (complets), F98–F100. Voir §16.

---

## 4. Architecture

### 4.1 Vue d'ensemble

```
┌──────────────────────────────── App « Engram » (SwiftUI) ────────────────────────────────┐
│  Écrans · composants · view models                                                       │
└──────────────────────────────────────────┬───────────────────────────────────────────────┘
                                           │
                               ┌───────────▼───────────┐
                               │     EngramPipeline    │  file de traitement persistante
                               └──┬─────────┬────────┬─┘
                ┌─────────────────┘         │        └──────────────────┐
     ┌──────────▼─────────┐   ┌─────────────▼──────────┐   ┌────────────▼──────────┐
     │ EngramTranscription│   │   EngramIntelligence   │   │     EngramSearch      │
     │ Apple · Whisper    │   │  Modèle Apple on-device│   │ Plein texte · Sens    │
     └──────────┬─────────┘   └─────────────┬──────────┘   └────────────┬──────────┘
                │      ┌───────────────┐    │                           │
                │      │ EngramCapture │    │                           │
                │      │ (audio)       │    │                           │
                │      └───────┬───────┘    │                           │
                └──────────────┴────────────┼───────────────────────────┘
                                ┌───────────▼───────────┐
                                │      EngramStore      │  SQLite (GRDB) · migrations · journal
                                └───────────┬───────────┘
                                ┌───────────▼───────────┐
                                │      EngramCore       │  modèles · identifiants · protocoles
                                └───────────────────────┘
```

### 4.2 Modules
Un paquet Swift local `EngramKit` contient les modules ; l'app ne contient que l'interface.

| Module | Responsabilité | Dépend de |
|---|---|---|
| `EngramCore` | Types du domaine (Source, Memory, Category, Tag…), identifiants, erreurs, **protocoles** des services (`Transcriber`, `MemoryAnalyzer`, `Embedder`, `Clock`). Aucune dépendance système lourde. | — |
| `EngramStore` | Base SQLite via GRDB : schéma, migrations versionnées, dépôts (repositories), index plein texte, versions, journal des changements, suppression contrôlée, export. | Core |
| `EngramCapture` | Enregistrement audio robuste aux interruptions, gestion de la session audio et des autorisations. | Core |
| `EngramTranscription` | `AppleSpeechTranscriber` (SpeechAnalyzer/SpeechTranscriber), `WhisperTranscriber` (WhisperKit), détection de langue par segment. | Core |
| `EngramIntelligence` | `AppleFoundationModelAnalyzer` : extraction structurée, validation anti-invention, consignes versionnées, découpage des longs textes ; décisions de classement assistées par le modèle. | Core |
| `EngramSearch` | `Embedder` (Apple, plan B Core ML), recherche hybride et fusion des résultats. | Core, Store |
| `EngramPipeline` | Orchestration des étapes, file persistante, reprises, idempotence, règles de classement et de création de catégories. | tous les modules ci-dessus |
| `EngramTesting` | **Faux** services pour les tests (`FakeTranscriber`, `FakeAnalyzer`, `FakeEmbedder`), données de test **fictives**. **Jamais lié à l'app.** | Core |

Chaque service passe par un protocole : on peut remplacer le moteur de transcription, le modèle d'IA ou le moteur d'embeddings sans toucher au reste.

### 4.3 Choix techniques justifiés
| Choix | Pourquoi | Alternative écartée |
|---|---|---|
| **SwiftUI**, cible iOS 27 | Interface native, composants Apple à jour (effet « verre »), une seule version d'iOS à supporter. | UIKit (plus verbeux), Expo/React Native (les intégrations iOS exigeraient du Swift de toute façon). |
| **GRDB (SQLite)** | Recherche plein texte FTS5, migrations explicites, contraintes d'intégrité et clés étrangères, contrôle total du SQL, performances. | SwiftData : pas de recherche plein texte, migrations moins contrôlables. |
| **XcodeGen** (`project.yml`) | Projet décrit dans un fichier texte lisible et éditable sans Mac ; le `.xcodeproj` est généré sur le serveur de compilation et n'est pas versionné. | Éditer un `.xcodeproj` à la main : fragile et illisible. |
| **Swift 6, concurrence stricte** | Détecte les accès concurrents dangereux dès la compilation ; le pipeline est un `actor`. | — |
| Dépendances tierces minimales, **versions épinglées** | GRDB, WhisperKit (moteur optionnel), XcodeGen (outil de build), gitleaks (CI). | — |

---

## 5. Modèle de données

Conventions : identifiants **UUID** générés sur l'appareil ; dates en **UTC** ; clés étrangères activées ; toute écriture multi-tables se fait dans **une transaction** ; chaque mutation ajoute une ligne au journal `change_log`.

### 5.1 Tables

**`source`** : l'original d'une capture, jamais réécrit.
| Colonne | Type | Contraintes / notes |
|---|---|---|
| `id` | UUID | PK |
| `kind` | TEXT | `voice` \| `text` |
| `audio_path` | TEXT? | chemin relatif dans le conteneur de l'app |
| `audio_duration` | REAL? | secondes |
| `original_text` | TEXT? | transcription originale ou texte saisi, **immuable** une fois écrit |
| `corrected_text` | TEXT? | transcription corrigée par le propriétaire |
| `languages` | TEXT | JSON, ex. `["fr","en"]` |
| `transcription_engine` | TEXT? | ex. `apple-speech@<version>`, `whisperkit@<modèle>` |
| `content_hash` | TEXT | SHA-256 de l'audio ou du texte normalisé ; indexé |
| `captured_at` | DATETIME | |
| `processing_status` | TEXT | `pending` \| `transcribing` \| `analyzing` \| `classifying` \| `indexing` \| `done` \| `waiting` \| `failed` |
| `created_at`, `updated_at` | DATETIME | |

**`memory`** : un souvenir extrait.
| Colonne | Type | Contraintes / notes |
|---|---|---|
| `id` | UUID | PK |
| `source_id` | UUID | FK → `source`, NOT NULL |
| `excerpt` | TEXT | extrait **verbatim** du texte source |
| `span_start`, `span_end` | INTEGER? | position de l'extrait dans le texte de référence, en unités UTF-16 (compatibles `NSString`/`NSRange`) ; `excerpt` fait foi si les positions deviennent invalides |
| `span_text_version` | TEXT | `original` \| `corrected` |
| `title` | TEXT | NOT NULL, ≤ 80 caractères |
| `summary` | TEXT? | |
| `content` | TEXT | NOT NULL |
| `kind` | TEXT? | `idea` \| `task` \| `appointment` \| `decision` \| `preference` \| `info` \| `other` |
| `memory_type` | TEXT? | réservé à la Phase 2 (F16), NULL en Phase 1 |
| `status` | TEXT | `active` \| `unsorted` \| `archived` \| `trashed` |
| `confidence` | REAL? | 0…1, voir §6.3 |
| `suggested_topic` | TEXT? | sujet proposé quand le souvenir est « À classer » |
| `mentioned_dates` | TEXT | JSON, expressions brutes (« vendredi », « avant dimanche ») |
| `user_edited` | BOOLEAN | vrai dès qu'une modification manuelle a eu lieu ; protège contre l'écrasement par l'IA |
| `possible_duplicate_of` | UUID? | FK → `memory` |
| `analysis_version` | TEXT | version des consignes + identifiant du modèle |
| `captured_at`, `created_at`, `updated_at` | DATETIME | |
| `trashed_at` | DATETIME? | |
| `version` | INTEGER | NOT NULL, commence à 1, incrémenté à chaque modification |

Index : `status`, `source_id`, `captured_at`, `trashed_at`.

**`memory_version`** : historique restaurable (F24).
`id` PK · `memory_id` FK (cascade à la suppression définitive) · `version` · `snapshot` (JSON : titre, résumé, contenu, kind, statut, catégories, tags) · `changed_by` (`user` \| `ai` \| `system`) · `change_reason` · `created_at`. Unicité : (`memory_id`, `version`).

**`category`** : dossiers et sous-dossiers.
`id` PK · `name` · `normalized_name` (minuscules, sans accents, singulier simple) · `description` · `parent_id` FK → `category` (NULL = racine) · `origin` (`seed` \| `ai` \| `user`) · `status` (`active` \| `archived`) · `created_at` · `updated_at`. Unicité : (`parent_id` ou racine, `normalized_name`).
« À classer » **n'est pas une catégorie** : c'est le statut `unsorted` d'un souvenir.

**`memory_category`** : `memory_id` · `category_id` · `origin` (`ai` \| `user`) · `confidence` · `confirmed` (booléen) · `created_at`. PK (`memory_id`, `category_id`).

**`tag`** : `id` · `name` · `normalized_name` (unique) · `origin` · `created_at`.
**`memory_tag`** : même structure que `memory_category`.

**`embedding`** : `id` · `owner_kind` (`memory` \| `category`) · `owner_id` · `model` · `dimensions` · `vector` (BLOB, Float32, normalisé) · `input_hash` (pour détecter un embedding périmé) · `created_at`. Unicité : (`owner_kind`, `owner_id`, `model`).

**`memory_fts`** : table virtuelle FTS5 synchronisée avec `memory` (`title`, `summary`, `content`, `excerpt`), tokenizer `unicode61 remove_diacritics 2` (« décision » trouve « decision »).

**`processing_job`** : `id` · `source_id` FK · `step` (`transcribe` \| `analyze` \| `classify` \| `index`) · `status` (`queued` \| `running` \| `succeeded` \| `waiting` \| `failed`) · `attempts` · `max_attempts` · `next_attempt_at` · `last_error` (code d'erreur, **jamais de contenu personnel**) · `idempotency_key` (unique : source + étape + version d'entrée) · `created_at` · `updated_at`.

**`change_log`** : `seq` (entier auto-incrémenté) · `entity` · `entity_id` · `op` (`insert` \| `update` \| `delete`) · `changed_at`. Base de la synchronisation en Phase 3.

**`setting`** : paires clé/valeur (moteur de transcription, langue principale, verrouillage Face ID…).

### 5.2 Migrations
Migrations GRDB nommées (`v1_initial`, `v2_…`), **jamais modifiées après publication**. Un test vérifie la migration depuis chaque schéma précédent. Un échec de migration n'efface jamais de données : l'app affiche un écran de récupération qui propose l'export.

### 5.3 Suppression contrôlée (F90)
| Action | Effet | Réversible |
|---|---|---|
| Archiver | `status = archived`, hors des vues par défaut, toujours trouvable via un filtre | oui |
| Mettre à la corbeille | `status = trashed`, `trashed_at` renseigné | oui (restaurer) |
| Supprimer définitivement | Lignes supprimées (souvenir, versions, liens, embedding, entrée FTS). La source et son audio sont supprimés s'ils ne sont plus référencés par aucun souvenir. Confirmation obligatoire. | **non** |

La corbeille ne se vide **jamais automatiquement** en Phase 1.

---

## 6. Moteur de mémoire

### 6.1 Parcours d'une capture
| Étape (§16 du prompt) | Ce qui se passe | Écrit dans |
|---|---|---|
| A. Ingestion | Sauvegarde **immédiate** de l'audio ou du texte, calcul de l'empreinte. Doublon technique (même empreinte dans les 10 minutes) : ignoré, l'utilisateur est informé. Création des tâches de traitement. | `source`, `processing_job` |
| B. Prétraitement | Transcription (voix) ; détection de la langue par segment ; texte original conservé. | `source.original_text`, `languages` |
| C. Analyse sémantique | Découpage en informations distinctes et extraction structurée (§6.2). | (en mémoire, puis validé) |
| D. Comparaison avec la mémoire | Recherche de quasi-doublons (§6.4). | `memory.possible_duplicate_of` |
| E. Décision de stockage | Création des souvenirs (mises à jour et fusions : Phase 2). | `memory`, `memory_version` |
| F. Classement | Catégories et tags (§6.3). | `memory_category`, `memory_tag`, `category` |
| H. Indexation | Plein texte (automatique) + embedding. | `memory_fts`, `embedding` |
| J. Retour à l'utilisateur | « 3 souvenirs enregistrés : 2 classés, 1 à classer », avec correction rapide. | — |

**Idempotence.** Chaque étape écrit ses résultats **et** marque sa tâche comme réussie dans **la même transaction**. Si l'app est tuée en cours d'étape, l'étape est rejouée au prochain lancement et ses résultats précédents (identifiés par source + version d'analyse) sont remplacés, jamais dupliqués.

**Reprises.** Erreur temporaire : nouvel essai avec délai croissant (3 essais maximum). IA indisponible : statut `waiting`, avec une nouvelle vérification au retour de l'app au premier plan et à chaque changement de disponibilité du modèle.

**Arrière-plan.** Le traitement s'exécute quand l'app est ouverte. Quand l'app passe en arrière-plan, elle demande à iOS un court délai pour terminer l'étape en cours ; le reste reprend à la réouverture. **Aucune promesse de traitement continu en arrière-plan** : les règles exactes d'iOS 27 seront vérifiées avant l'implémentation.

### 6.2 Transcription et analyse

**Transcription (F2)**
- **Moteur Apple** (par défaut au départ) : SpeechAnalyzer/SpeechTranscriber, sur l'appareil. Langue principale réglable (`fr-CA` ou `fr-FR`). Limite connue : une langue par transcripteur, donc les mots anglais au milieu d'une phrase française peuvent être mal reconnus.
- **Moteur Whisper** (optionnel) : WhisperKit avec un modèle multilingue, détection automatique de la langue par fenêtre. Le modèle est téléchargé **à la demande** depuis Réglages ; sa taille est affichée avant le téléchargement.
- **Protocole de choix :** le propriétaire enregistre une dizaine de notes réelles mélangeant français et anglais, et l'app les transcrit avec les deux moteurs. Le meilleur devient le moteur par défaut. **Ces enregistrements restent sur l'iPhone et ne sont jamais envoyés au dépôt.**
- La transcription originale est immuable ; une correction remplit `corrected_text` et déclenche une **proposition** de ré-analyse : les souvenirs modifiés à la main (`user_edited`) ne sont jamais écrasés, les changements proposés sont affichés avant validation.

**Analyse (F3, F10, F11, F15)**
- Modèle : Foundation Models d'Apple (`SystemLanguageModel`), disponibilité vérifiée au lancement et avant chaque analyse.
- **Génération guidée** (sortie structurée typée) : pour chaque information extraite :
  - `title` : titre précis, dans la langue de la note ;
  - `summary` : résumé conservant dates, montants, conditions et incertitudes ;
  - `excerpt` : citation verbatim du texte source ;
  - `kind` : idée, tâche, rendez-vous, décision, préférence, information ou autre ;
  - `tags` : 5 au maximum ;
  - `topic` : sujet court ;
  - `mentionedDates` : expressions de date brutes.
- Consignes rédigées **en anglais** (recommandation d'Apple), texte de l'utilisateur transmis tel quel ; consigne explicite : « garder la langue d'origine de chaque information, y compris le mélange ».
- **Consignes versionnées** dans le code (`AnalysisPrompt.v1`…) ; la version est enregistrée dans `memory.analysis_version`.
- **Longs textes :** la fenêtre de contexte du modèle est limitée (4 096 tokens sous iOS 26, à revérifier pour iOS 27). Le texte est découpé aux frontières de phrases en morceaux qui laissent la place à la réponse, puis les résultats sont réunis.

**Validation anti-invention (règle non négociable)**
1. Chaque `excerpt` doit se retrouver dans le texte source, à la casse, aux espaces et à la ponctuation près.
2. Le titre n'est pas vide et fait au plus 80 caractères ; les tags sont au plus 5, de 30 caractères chacun au maximum ; `kind` appartient à la liste.
3. Il y a au moins une information extraite.
4. En cas d'échec : **un** nouvel essai avec le motif du rejet. Si l'échec persiste ou si le modèle refuse (filtres de sécurité) : **repli**, c'est-à-dire un seul souvenir contenant le texte entier, avec un titre formé des premiers mots, le statut `unsorted` et l'étiquette « à revoir ». **Aucune perte.**

### 6.3 Classement et catégories automatiques (F12, F13, F14)

**Catégories de départ** (`origin = seed`, renommables et supprimables) : Travail, Études, Projets, Finances, Santé, Voyages, Personnel, Idées, Documents.

**Algorithme pour chaque nouveau souvenir**
1. Calculer l'embedding du souvenir (titre + résumé + contenu).
2. Sélectionner les **5 catégories candidates** les plus proches. Le profil d'une catégorie combine son nom, sa description et le centre des souvenirs **confirmés** qu'elle contient : les corrections du propriétaire améliorent ainsi le classement suivant.
3. Le modèle choisit **0, 1 ou 2** catégories parmi les candidates (jamais en dehors de la liste), ou répond « aucune » en proposant un sujet.
4. Décision :
   - choix du modèle **et** similarité ≥ `T_assign` → catégorie attribuée (`origin = ai`, non confirmée), statut `active` ;
   - sinon → statut `unsorted` et `suggested_topic` renseigné.
5. Le niveau de confiance affiché combine la similarité et l'accord du modèle. La confiance « auto-déclarée » par le modèle n'est **pas** utilisée seule.

**Création automatique d'une catégorie**
- Déclencheur : au moins `N_min = 2` souvenirs `unsorted` dont les sujets ont une similarité deux à deux ≥ `T_cluster`.
- **Contrôle anti-synonymes**, dans l'ordre :
  1. nom normalisé identique à une catégorie existante → réutiliser celle-ci ;
  2. similarité ≥ `T_synonym` avec une catégorie existante → réutiliser ;
  3. zone grise (entre `T_gray` et `T_synonym`) → le modèle tranche (« même sujet ? »).
- Si aucune catégorie équivalente n'existe : le modèle propose un nom court et un parent (une catégorie racine existante, ou la racine). La catégorie est créée (`origin = ai`) et les souvenirs y sont rangés. Le retour à l'utilisateur l'indique : « Nouvelle catégorie : *Course à pied* (dans Santé) ».

**Valeurs initiales** (constantes nommées, à **calibrer** sur le jeu d'évaluation, §13) : `T_assign = 0.55`, `T_cluster = 0.75`, `T_synonym = 0.85`, `T_gray = 0.70`.

**Priorité au propriétaire.** Une catégorie ou un tag confirmé, corrigé ou supprimé par le propriétaire n'est **jamais** modifié automatiquement ensuite.

### 6.4 Doublons (F20, partiel)
- **Doublon technique :** même empreinte dans les 10 minutes → ignoré.
- **Quasi-doublon :** similarité ≥ 0.92 avec un souvenir actif **et** même `kind` → `possible_duplicate_of` renseigné et badge affiché. Le propriétaire choisit « Garder les deux » ou « Mettre celui-ci à la corbeille ». **Pas de fusion automatique** (Phase 2).

---

## 7. Recherche (F94, partiel)
- **Par mots :** FTS5 (classement bm25), recherche par préfixe, insensible aux accents.
- **Par sens :** embedding de la requête comparé à ceux des souvenirs, par un calcul vectoriel accéléré (Accelerate), adapté jusqu'à plusieurs dizaines de milliers de souvenirs.
- **Fusion :** Reciprocal Rank Fusion (k = 60).
- **Filtres :** catégorie (sous-catégories incluses), tag, `kind`, statut, période de capture. Corbeille exclue ; archives sur option.
- **Explication :** chaque résultat indique pourquoi il remonte (mots surlignés, ou « proche par le sens »).

**Embeddings**
- Principal : `NLContextualEmbedding` d'Apple (modèle multilingue pour l'alphabet latin), moyenné et normalisé. Les ressources du modèle peuvent devoir être téléchargées par iOS au premier usage (à vérifier).
- **Plan B :** un petit modèle d'embedding multilingue converti en Core ML et intégré à l'app, si la qualité du principal est insuffisante sur le jeu d'évaluation bilingue.
- L'identifiant du modèle est stocké ; un changement de modèle déclenche le recalcul des embeddings en tâche de fond.

---

## 8. Capture audio (F1)
- Enregistrement dans un format **résistant aux interruptions** (CAF), écrit en continu sur le disque. Si l'app est tuée, l'enregistrement partiel est récupéré au lancement suivant et proposé au propriétaire.
- Interruptions (appel, Siri, autre app audio) : passage automatique en pause, avec reprise possible.
- Micro actif signalé clairement : indicateur rouge, onde, chrono, retour haptique au démarrage et à l'arrêt.
- Autorisation micro ou reconnaissance vocale refusée : explication et lien vers Réglages ; la capture texte reste disponible.

---

## 9. Écrans et design

### 9.1 Principes (langage Apple strict, F92)
- Composants SwiftUI **natifs uniquement** : `TabView`, `NavigationStack`, `List`, feuilles, menus, `ContentUnavailableView`, recherche système, effet « verre » des composants standards.
- **SF Symbols** pour toutes les icônes ; police système (SF Pro) via les **styles de texte** (Dynamic Type) ; **couleurs système** uniquement ; une couleur d'accent : **indigo système**.
- Gestes et comportements standards : balayage pour archiver ou supprimer, menus contextuels à l'appui long, tirer pour actualiser si pertinent.
- Modèles : Dictaphone pour la capture, Notes et Fichiers pour la bibliothèque, Notes pour le détail.
- Mode clair et sombre ; respect de « Réduire les animations » et « Augmenter le contraste ».
- Écrans vides soignés et **aucune donnée fictive** dans l'app.
- Pas de logo Apple ; l'icône d'Engram est dessinée dans le style Apple.

### 9.2 Navigation
Barre d'onglets : **Accueil** · **Bibliothèque** · **Recherche** (rôle « recherche » natif) · **Réglages**. Bouton de capture vocale accessible depuis tous les onglets (accessoire de la barre d'onglets si l'API d'iOS 27 le permet, sinon bouton de barre d'outils).

### 9.3 Écrans
| Écran | Contenu |
|---|---|
| Premier lancement | Explication du concept (3 pages maximum), autorisations micro et reconnaissance vocale expliquées, vérification d'Apple Intelligence avec message clair si indisponible, choix de la langue principale, premier souvenir. |
| Accueil | Bouton de capture vocale, champ « Écrire une pensée… », souvenirs récents, carte « À classer (n) », statut des traitements en cours. |
| Capture vocale | Plein écran : onde, chrono, Pause/Reprendre, Annuler, Terminer ; texte en direct (moteur Apple) ; puis cartes des souvenirs extraits, corrigeables d'un toucher. |
| Note texte | Éditeur plein écran minimal, bouton Terminé. |
| Bibliothèque | Arborescence des catégories (avec compteurs), section « À classer », tags, Archives, Corbeille ; tri et filtres. |
| Liste d'une catégorie | Souvenirs triés par date, sous-catégories en tête. |
| Détail d'un souvenir | Titre, contenu, résumé ; **source** (lecture audio, transcription originale avec l'extrait surligné, transcription corrigée) ; catégories et tags (style distinct pour ceux proposés par l'IA, avec Confirmer et Corriger) ; badge doublon possible ; historique des versions avec restauration ; Modifier, Déplacer, Archiver, Supprimer. |
| « À classer » | Liste avec le sujet suggéré et des actions rapides (choisir une catégorie, accepter la suggestion). |
| Recherche | Barre unique, suggestions, filtres, résultats expliqués. |
| Réglages | Langue principale, moteur de transcription (et téléchargement du modèle Whisper), état de l'IA, verrouillage Face ID, stockage utilisé, **export**, catégories (renommer, fusionner, supprimer), mode développeur (écran d'évaluation, §13), à propos. |

---

## 10. Erreurs et fiabilité
| Situation | Comportement |
|---|---|
| App tuée pendant un enregistrement | Enregistrement partiel récupéré au lancement et proposé. |
| App tuée pendant un traitement | Étape rejouée sans doublon (§6.1). |
| IA indisponible (désactivée, en téléchargement, langue non supportée) | Captures sauvegardées, statut `waiting` visible, message explicatif. |
| Refus ou sortie invalide du modèle | Repli sur un souvenir unique « à revoir » (§6.2). |
| Échec de transcription | Audio conservé ; Réessayer, changer de moteur ou saisir le texte à la main. |
| Espace disque insuffisant | Alerte avant l'enregistrement ; aucune écriture partielle silencieuse. |
| Échec de migration | Aucune donnée effacée ; écran de récupération avec export. |

**Journalisation :** `os.Logger`, catégories par module ; tout contenu personnel est marqué privé (masqué dans les journaux). Le texte des notes n'est jamais journalisé ; l'identifiant de la source sert d'identifiant de corrélation.

---

## 11. Confidentialité et sécurité

### 11.1 Données sur l'iPhone
- **Aucune donnée personnelle ne quitte l'iPhone en Phase 1.** Seuls téléchargements réseau : le modèle Whisper (sur demande explicite) et les ressources de modèles gérées par iOS.
- Fichiers et base protégés par la **Data Protection d'iOS** (classe « jusqu'à la première authentification », pour permettre le traitement quand l'écran se verrouille). Une classe plus stricte pour les compartiments sensibles sera étudiée avec F87.
- **Verrouillage optionnel par Face ID** (LocalAuthentication) à l'ouverture et au retour au premier plan.
- **Export** : ZIP enregistré à l'emplacement choisi par le propriétaire (Fichiers), avec un avertissement que l'export n'est pas chiffré.

### 11.2 Dépôt public : règles absolues
1. **Aucune donnée personnelle** dans le dépôt : pas de notes, d'enregistrements, d'exports ni de captures d'écran contenant des souvenirs réels. Les données de test sont **fictives et neutres**.
2. **Identité Git anonyme** : commits signés de l'adresse `339358467+h7cmkrmygp-ui@users.noreply.github.com` (configurée localement pour ce dépôt).
3. **Aucun secret** dans le code. Les secrets futurs (serveur, MCP) vivront dans les coffres de GitHub et de l'hébergeur.
4. **Protection active :** *push protection* et analyse des secrets de GitHub activées sur le dépôt, plus **gitleaks** dans la CI à chaque envoi.
5. `.gitignore` strict : audio, exports, dossiers `private/` et `secrets/`, fichiers de signature, projet Xcode généré.
6. Les journaux de CI n'affichent aucun secret ni aucune donnée personnelle.
7. Le `.ipa` produit ne contient aucune donnée personnelle.

---

## 12. Compilation et distribution

### 12.1 Organisation du dépôt
```
Secondarybrain/
├── project.yml                  # description du projet (XcodeGen)
├── App/                         # cible SwiftUI « Engram »
│   ├── Sources/
│   └── Resources/               # Assets, icône, Info.plist (généré)
├── Packages/EngramKit/          # paquet Swift local (modules §4.2)
│   ├── Package.swift
│   ├── Sources/<Module>/
│   └── Tests/<Module>Tests/
├── .github/workflows/
│   ├── ci.yml                   # tests + gitleaks à chaque envoi
│   └── build-ipa.yml            # production du .ipa (manuel ou sur tag)
└── docs/
```

### 12.2 Chaîne de compilation
- **CI (`ci.yml`)**, à chaque envoi :
  1. génération du projet par XcodeGen ;
  2. tests du paquet et de l'app sur le simulateur iOS 27 ;
  3. analyse gitleaks.
- **Build `.ipa` (`build-ipa.yml`)** : archive Release **sans signature** (`CODE_SIGNING_ALLOWED=NO`) → dossier `Payload/Engram.app` compressé en `Engram.ipa` → publié comme artefact de la compilation (conservé 7 jours). Le propriétaire le télécharge et l'installe avec **AltStore, qui le signe avec son Apple ID**.
- Numéro de build = numéro d'exécution de la compilation.
- Runner : image `xcode-27` (aperçu public). Le libellé et la version de Xcode sont épinglés dans le workflow.

---

## 13. Tests et qualité

### 13.1 Tests automatiques (CI, simulateur)
- **Store :** migrations, contraintes, versions, trois niveaux de suppression, journal des changements, export (format et complétude).
- **Pipeline :** idempotence, reprise après interruption simulée, reprises sur erreur, statut `waiting`.
- **Intelligence :** validation anti-invention (sorties fausses injectées par `FakeAnalyzer`), découpage des longs textes, repli.
- **Classement :** attribution, « À classer », création automatique, anti-synonymes, priorité au propriétaire, avec des embeddings fictifs déterministes.
- **Recherche :** fusion des résultats, filtres, accents.
- Les faux services sont nommés `Fake…`, vivent dans `EngramTesting` et **ne sont jamais liés à l'app**.

### 13.2 Jeu d'évaluation fictif
Une quarantaine de notes **inventées**, bilingues et mélangées, avec le découpage et les catégories attendus. Il sert :
- aux tests automatiques (avec les faux services) ;
- à un **écran d'évaluation** dans l'app (mode développeur des Réglages), qui exécute le **vrai** modèle sur l'iPhone et affiche les scores. C'est notre moyen de mesurer l'IA réelle sans Mac, et de calibrer les seuils du §6.3.

### 13.3 Tests sur l'iPhone (manuels, consignés)
Scénarios du master prompt applicables à la Phase 1 :
- **A** : dicter une idée ;
- **B** : plusieurs intentions dans un enregistrement ;
- **C** : nouvelle catégorie automatique ;
- **I** (partiel) : recherche d'une ancienne note ;
- **K** : mode avion.

S'y ajoutent : appel entrant pendant l'enregistrement, app tuée pendant le traitement, Face ID, export puis vérification du ZIP, comparaison des moteurs de transcription.

### 13.4 Suivi honnête de l'avancement
`IMPLEMENTATION_PROGRESS.md` suit **séparément**, pour chaque fonctionnalité : Dessiné · Simulé · Implémenté · Testé en CI · Testé sur iPhone · Prêt. Rien n'est déclaré « fonctionne » sans preuve.

---

## 14. Objectifs de performance (à mesurer sur l'iPhone 17)
| Mesure | Objectif |
|---|---|
| Lancement à froid → interface utilisable | < 1 s |
| Toucher « capture » → micro actif | < 300 ms |
| Note texte sauvegardée et visible | < 100 ms |
| Analyse d'une note vocale d'une minute | < 15 s (estimation, à mesurer) |
| Recherche sur 10 000 souvenirs | < 150 ms |
| Défilement de la bibliothèque | fluide à 120 Hz |

---

## 15. Risques et points ouverts
| # | Risque | Mitigation |
|---|---|---|
| 1 | L'API Foundation Models ou ses limites ont pu changer avec iOS 27 (y compris le partenariat Apple–Google annoncé en janvier 2026). | Vérification dans le SDK Xcode 27 au début du plan ; l'adaptateur isole le reste de l'app. |
| 2 | Qualité de transcription inconnue pour le mélange FR/EN. | Deux moteurs, protocole de comparaison sur l'iPhone (§6.2). |
| 3 | Qualité inconnue de `NLContextualEmbedding` pour la recherche bilingue. | Jeu d'évaluation et plan B Core ML (§7). |
| 4 | Image `xcode-27` en aperçu public, susceptible de changer. | Libellé épinglé, surveillance du changelog GitHub. |
| 5 | Pas de compilation locale : les erreurs n'apparaissent qu'en CI. | Petits incréments, CI rapide, code fortement typé. |
| 6 | Une mise à jour d'iOS peut casser AltStore. | Hors de notre contrôle ; signalé au propriétaire. |
| 7 | Projet dans OneDrive : la synchronisation de `.git` peut créer des conflits ou des fichiers verrouillés. | Travailler depuis un seul PC ; envisager d'exclure le dossier de la synchronisation, puisque GitHub sert déjà de sauvegarde du code. |
| 8 | Supprimer l'app efface les données (avant la Phase 3). | Export complet ; rappel d'export optionnel dans les Réglages. |
| 9 | Disponibilité du modèle avec l'écran verrouillé, et règles d'exécution en arrière-plan sous iOS 27. | À tester sur l'iPhone ; aucune promesse avant vérification. |

---

## 16. Aperçu des phases suivantes
| Phase | Contenu principal | Adaptations déjà connues |
|---|---|---|
| 2 — Mémoire avancée | Types de mémoire, entités, faits atomiques, relations, temporalité, contradictions, incertitudes, fusion, **Ask Your Brain** (modèle on-device + recherche, citations obligatoires), **Brain Graph** 2D (3D en option). | Fenêtre de contexte limitée du modèle on-device : recherche ciblée indispensable. |
| 3 — Intégrations IA | Serveur gratuit (Cloudflare ou Supabase, choisi après vérification des offres), synchronisation via `change_log`, **serveur MCP** avec OAuth et permissions granulaires, journal des accès ; ChatGPT (mode développeur, à vérifier), Claude, Claude Code. | Données envoyées au serveur : chiffrement et compartiments à concevoir avant toute synchronisation. |
| 4 — Apple et organisation | App Intents, Raccourcis, bouton Action, widgets, calendrier (EventKit), rappels, notifications locales, briefing matinal. | Chaque extension consomme un App ID AltStore ; pas de push ; le « maintenir pour enregistrer » du bouton Action n'est a priori pas offert aux apps tierces (à vérifier). |
| 5 — Intelligence proactive | Planification, automatisations, clarifications, revues, suggestions. | — |
| 6 — Expansion | Modules spécialisés, autres plateformes, graphe avancé. | Selon les besoins réels du propriétaire. |
