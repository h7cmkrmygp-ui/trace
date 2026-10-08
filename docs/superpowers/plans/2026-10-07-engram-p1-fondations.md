# Engram P1 — Fondations : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une app Engram installable sur l'iPhone via AltStore, qui enregistre réellement des pensées texte sur l'appareil, les liste, les classe à la main dans des catégories, les cherche par mots (sans tenir compte des accents), les versionne, les met à la corbeille ou les supprime définitivement, et exporte toute la mémoire dans un ZIP. Toute la chaîne compilation → tests → `.ipa` tourne sur GitHub Actions, sans Mac.

**Architecture:** Un paquet Swift local `EngramKit` (modules `EngramCore`, `EngramStore` et `EngramTesting`, ce dernier réservé aux tests) et une app SwiftUI fine décrite par XcodeGen. La base SQLite (GRDB) porte le schéma complet de la spec : sources, souvenirs, versions, catégories, tags, liens, embeddings, plein texte FTS5, file de traitement et journal des changements. Les tests du paquet tournent avec `swift test` sur un runner macOS ; l'app est archivée sans signature en `.ipa` à chaque envoi, et AltStore la signe sur l'iPhone.

**Tech Stack:** Swift 6 · SwiftUI · Swift Testing · GRDB 7.11.1 · XcodeGen 2.46.0 · GitHub Actions (runner `xcode-27`, Xcode 27.0) · gitleaks 8.30.1 · AltStore.

**Spec:** `docs/superpowers/specs/2026-10-07-engram-phase1-design.md`

## Découpage de la Phase 1

| Plan | Contenu | Rédigé |
|---|---|---|
| **P1 — Fondations** (ce document) | CI et `.ipa` sans Mac, vérification des API iOS 27, modèle de données complet, dépôts, recherche par mots, export, interface minimale (notes texte sans IA) | ✅ |
| P2 — Moteur de mémoire | File de traitement, analyse par le modèle Apple, validation anti-invention, découpage, classement et catégories automatiques, embeddings, recherche hybride, écran d'évaluation | après P1 |
| P3 — Capture vocale | Enregistrement robuste (CAF), transcription Apple et Whisper, correction de transcription | après P1 |
| P4 — Interface complète | Onboarding, bibliothèque complète, gestion des catégories, Face ID, réglages, icône, accessibilité, performance | après P2/P3 |

P2 et P3 seront rédigés **après** la tâche 3, car leur code dépend des signatures exactes des API d'iOS 27 (Foundation Models, Speech, NaturalLanguage) que cette tâche relève.

## Global Constraints

- Cible : **iOS 27.0** uniquement (`deploymentTarget iOS: "27.0"`) ; iPhone seulement (`TARGETED_DEVICE_FAMILY: "1"`).
- Swift : `swift-tools-version: 6.0`, `SWIFT_VERSION: "6.0"` (mode de langage Swift 6, concurrence stricte). Plateformes du paquet : `.iOS("27.0")`, `.macOS("26.0")` (macOS sert uniquement à `swift test` en CI).
- Dépendances épinglées : GRDB `exact: "7.11.1"` · XcodeGen `2.46.0` · gitleaks `8.30.1` · `actions/checkout@v7.0.1` · `actions/upload-artifact@v7.0.1`.
- Runner CI macOS : `runs-on: xcode-27` (Xcode 27.0 par défaut, simulateur « iPhone 17 » sous iOS 27.0).
- Identifiant de bundle : `io.github.h7cmkrmygpui.engram` · nom affiché : **Engram**.
- Interface **en français**, langage de design Apple strict : composants SwiftUI natifs, SF Symbols, couleurs système, accent `.indigo`.
- **Dépôt public** : aucune donnée personnelle ni aucun secret ; données de test fictives et neutres ; identité Git `h7cmkrmygp-ui <339358467+h7cmkrmygp-ui@users.noreply.github.com>`.
- Les faux services (`Test…`, `Fake…`) vivent uniquement dans `EngramTesting` et ne sont **jamais** liés à l'app.
- Aucune perte de données : pas de `fatalError`, pas de `try!` sur un chemin utilisateur ; toute écriture multi-tables dans une seule transaction.
- Titre d'un souvenir : 1 à **80 caractères** (graphèmes). Fenêtre de doublon technique : **10 minutes**. Catégories de départ : Travail, Études, Projets, Finances, Santé, Voyages, Personnel, Idées, Documents.
- Ne jamais déclarer une fonctionnalité « testée sur iPhone » sans confirmation du propriétaire ; suivre `docs/IMPLEMENTATION_PROGRESS.md`.

## Review Focus

1. **Note vide ou faite d'espaces et de retours à la ligne** : refus clair, rien n'est créé (test dans la tâche 6).
2. **Double toucher sur « Enregistrer »** : une seule note. Le même texte 11 minutes plus tard crée une nouvelle note (tâche 6).
3. **Recherche contenant des caractères spéciaux FTS5** (`"`, `*`, `-`, `(`, `:`, `AND`, `NEAR`) ou seulement de la ponctuation : jamais d'erreur (tâche 8).
4. **Noms de catégories qui ne diffèrent que par les accents, la casse, le pluriel ou les espaces** : une seule catégorie (tâche 7).
5. **Suppression définitive d'un souvenir dont la source sert à d'autres souvenirs** : la source est conservée. Après le dernier souvenir, la source est supprimée et le chemin audio renvoyé (tâche 6).

## Écarts assumés par rapport à la spec (à reporter dans la spec à la tâche 11)

- Les liens souvenir ↔ catégorie et souvenir ↔ tag ont une colonne `rejected` : un lien retiré par le propriétaire est conservé comme « rejeté », pour que l'IA ne le recrée jamais (exigence §6.3 « priorité au propriétaire »).
- Le `snapshot` d'une version contient titre, résumé, contenu, `kind` et statut, mais pas les catégories ni les tags (les liens ont leur propre historique dans `change_log`).
- Les passages automatiques `unsorted` ↔ `active` causés par l'ajout ou le retrait d'une catégorie ne créent pas de version (seulement une ligne `change_log`).
- Les types de domaine s'appellent `EngramCategory` et `EngramTag`, pour éviter les conflits avec `Testing.Tag` et le `Category` d'Objective-C.
- La suppression définitive n'est possible que depuis la corbeille.
- Le `.ipa` est produit à chaque envoi par `ci.yml`. Un workflow séparé en `workflow_dispatch` imposerait d'être d'abord sur `main`.
- En attendant P2, une note texte devient un souvenir « À classer » sans analyse (`analysis_version = "interim-none"`). P2 ré-analysera ces souvenirs s'ils n'ont pas été modifiés à la main.

## Mode opératoire sans Mac

- On travaille sur la branche `p1-fondations`. Chaque cycle « tester » = `bash scripts/ci.sh` **lancé en arrière-plan**. Le script pousse la branche, attend le run GitHub Actions du commit `HEAD` et affiche les journaux des étapes en échec.
- Une étape « vérifier l'échec » signifie : la CI doit échouer **pour la raison annoncée**. Pour un nouveau symbole Swift, c'est une erreur de compilation `cannot find '…' in scope`.
- `gh` peut être absent du `PATH` : utiliser `"/c/Program Files/GitHub CLI/gh.exe"` (le script le gère).
- Les commandes `bash` s'exécutent dans Git Bash, à la racine du dépôt.

## Structure des fichiers

```
Secondarybrain/
├── CLAUDE.md                                   consignes du projet pour Claude
├── README.md
├── project.yml                                 description XcodeGen de l'app
├── .github/
│   ├── actions/setup-xcodegen/action.yml       installe XcodeGen 2.46.0
│   └── workflows/
│       ├── ci.yml                              gitleaks + swift test + .ipa
│       └── sdk-check.yml                       relevé des API iOS 27
├── scripts/
│   ├── ci.sh                                   pousse et attend la CI
│   └── fetch-ipa.sh                            télécharge le dernier .ipa
├── docs/
│   ├── ROADMAP.md                              F1…F100 → phases
│   ├── IMPLEMENTATION_PROGRESS.md              état réel, par fonctionnalité
│   └── notes/2026-10-ios27-sdk.md              API relevées (tâche 3)
├── App/Sources/
│   ├── EngramApp.swift                         point d'entrée, ouverture de la base
│   ├── AppModel.swift                          services partagés + erreurs
│   ├── RootView.swift                          barre d'onglets
│   ├── Support/ErrorAlert.swift
│   ├── Home/HomeView.swift
│   ├── Library/LibraryView.swift
│   ├── Library/MemoryListView.swift
│   ├── Library/CategoryMemoriesView.swift
│   ├── Memory/MemoryRow.swift
│   ├── Memory/MemorySwipeActions.swift
│   ├── Memory/MemoryDetailView.swift
│   ├── Memory/MemoryEditor.swift
│   ├── Memory/CategoryPicker.swift
│   ├── Search/SearchView.swift
│   └── Settings/SettingsView.swift
└── Packages/EngramKit/
    ├── Package.swift
    ├── Sources/EngramCore/
    │   ├── EngramCore.swift                    constantes de module
    │   ├── Enums.swift                         statuts, types, origines
    │   ├── Models.swift                        Source, Memory, EngramCategory, EngramTag, liens, versions
    │   ├── MemoryValidation.swift              règles de validité d'un souvenir
    │   ├── TextNormalizer.swift                noms normalisés, forme de comparaison
    │   ├── TitleMaker.swift                    titre de repli ≤ 80 caractères
    │   ├── ContentHasher.swift                 SHA-256
    │   └── DateProvider.swift                  horloge injectable
    ├── Sources/EngramStore/
    │   ├── AppDatabase.swift                   ouverture, emplacement protégé, flux observés
    │   ├── Schema.swift                        migration v1 (SQL), déclencheurs
    │   ├── Records.swift                       conformités GRDB
    │   ├── StoreError.swift
    │   ├── SortingStatus.swift                 « À classer » ↔ actif
    │   ├── MemoryStore.swift                   sources, souvenirs, versions, suppression
    │   ├── AssignmentRules.swift               règle « le propriétaire décide »
    │   ├── CategoryStore.swift                 catégories, tags, liens, bibliothèque
    │   ├── TextSearch.swift                    recherche FTS5 + filtres
    │   └── Exporter.swift                      export JSON + Markdown + audio + ZIP
    ├── Sources/EngramTesting/
    │   ├── EngramTesting.swift
    │   ├── TestDateProvider.swift
    │   └── TemporaryDirectory.swift
    └── Tests/
        ├── EngramCoreTests/…
        └── EngramStoreTests/…
```

---

### Task 1: Squelette du projet, CI et dépôt GitHub

**Files:**
- Create: `Packages/EngramKit/Package.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/EngramCore.swift`
- Create: `Packages/EngramKit/Sources/EngramTesting/EngramTesting.swift`
- Create: `Packages/EngramKit/Tests/EngramCoreTests/SmokeTests.swift`
- Create: `project.yml`, `App/Sources/EngramApp.swift`, `App/Sources/RootView.swift`
- Create: `.github/actions/setup-xcodegen/action.yml`, `.github/workflows/ci.yml`
- Create: `scripts/ci.sh`
- Create: `CLAUDE.md`, `README.md`, `docs/ROADMAP.md`, `docs/IMPLEMENTATION_PROGRESS.md`
- Modify: `.gitignore` (ajout de `App/Info.plist`)

**Interfaces:**
- Consumes: rien.
- Produces: `EngramCore.exportFormatVersion: Int` (= 1) ; le paquet `EngramKit` avec les cibles `EngramCore`, `EngramTesting` et `EngramCoreTests` ; le workflow `ci.yml` (jobs `secrets-scan`, `package-tests`, `ipa`) ; l'artefact CI `Engram-ipa-<run_number>` contenant `Engram.ipa` ; le script `scripts/ci.sh [workflow]`.

- [ ] **Step 1: Créer la branche de travail**

```bash
git switch -c p1-fondations
```

- [ ] **Step 2: Créer le paquet Swift**

`Packages/EngramKit/Package.swift` :

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngramKit",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "EngramCore", targets: ["EngramCore"]),
    ],
    targets: [
        .target(name: "EngramCore"),
        .target(name: "EngramTesting", dependencies: ["EngramCore"]),
        .testTarget(name: "EngramCoreTests", dependencies: ["EngramCore", "EngramTesting"]),
    ]
)
```

`Packages/EngramKit/Sources/EngramCore/EngramCore.swift` :

```swift
/// Constantes partagées du module.
public enum EngramCore {
    /// Version du format d'export (`engram.json`). À incrémenter à chaque changement incompatible.
    public static let exportFormatVersion = 1
}
```

`Packages/EngramKit/Sources/EngramTesting/EngramTesting.swift` :

```swift
/// Outils réservés aux tests (horloge contrôlable, dossiers temporaires…).
/// Ce module ne doit JAMAIS être lié à l'application.
public enum EngramTesting {}
```

`Packages/EngramKit/Tests/EngramCoreTests/SmokeTests.swift` :

```swift
import Testing
@testable import EngramCore

@Test func exportFormatVersionIsOne() {
    #expect(EngramCore.exportFormatVersion == 1)
}
```

- [ ] **Step 3: Créer l'app minimale et sa description XcodeGen**

`project.yml` :

```yaml
name: Engram
options:
  bundleIdPrefix: io.github.h7cmkrmygpui
  deploymentTarget:
    iOS: "27.0"
  createIntermediateGroups: true
  developmentLanguage: fr
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
packages:
  EngramKit:
    path: Packages/EngramKit
targets:
  Engram:
    type: application
    platform: iOS
    sources:
      - path: App/Sources
    dependencies:
      - package: EngramKit
        product: EngramCore
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Engram
        CFBundleName: $(PRODUCT_NAME)
        CFBundleIdentifier: $(PRODUCT_BUNDLE_IDENTIFIER)
        CFBundleExecutable: $(EXECUTABLE_NAME)
        CFBundlePackageType: $(PRODUCT_BUNDLE_PACKAGE_TYPE)
        CFBundleInfoDictionaryVersion: "6.0"
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleDevelopmentRegion: fr
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.github.h7cmkrmygpui.engram
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_STYLE: Manual
        DEVELOPMENT_TEAM: ""
        CODE_SIGN_IDENTITY: ""
```

`App/Sources/EngramApp.swift` :

```swift
import SwiftUI

@main
struct EngramApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.indigo)
        }
    }
}
```

`App/Sources/RootView.swift` :

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Engram",
            systemImage: "brain",
            description: Text("Les fondations sont en construction.")
        )
    }
}
```

Ajouter à la fin de `.gitignore` :

```gitignore

# Info.plist généré par XcodeGen
App/Info.plist
```

- [ ] **Step 4: Créer la CI**

`.github/actions/setup-xcodegen/action.yml` :

```yaml
name: Installer XcodeGen
description: Installe XcodeGen 2.46.0 (version épinglée) et l'ajoute au PATH.
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        curl -sSfL -o "$RUNNER_TEMP/xcodegen.zip" \
          https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
        unzip -q "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP"
        echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
    - shell: bash
      run: xcodegen --version
```

`.github/workflows/ci.yml` :

```yaml
name: CI
on:
  push:
  pull_request:
  workflow_dispatch:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
defaults:
  run:
    shell: bash
jobs:
  secrets-scan:
    name: Analyse des secrets (gitleaks)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7.0.1
        with:
          fetch-depth: 0
      - name: Installer gitleaks 8.30.1
        run: |
          curl -sSfL -o gitleaks.tar.gz \
            https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
          tar -xzf gitleaks.tar.gz gitleaks
      - name: Analyser tout l'historique
        run: ./gitleaks git --redact --verbose --exit-code 1 .

  package-tests:
    name: Tests EngramKit (swift test)
    runs-on: xcode-27
    steps:
      - uses: actions/checkout@v7.0.1
      - name: Versions
        run: xcodebuild -version && swift --version
      - name: swift test
        working-directory: Packages/EngramKit
        run: swift test

  ipa:
    name: Construire Engram.ipa (sans signature)
    runs-on: xcode-27
    needs: package-tests
    steps:
      - uses: actions/checkout@v7.0.1
      - uses: ./.github/actions/setup-xcodegen
      - name: Générer le projet Xcode
        run: xcodegen generate
      - name: Archiver sans signature
        run: |
          xcodebuild archive \
            -project Engram.xcodeproj -scheme Engram -configuration Release \
            -destination 'generic/platform=iOS' \
            -archivePath "$RUNNER_TEMP/Engram.xcarchive" \
            CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
      - name: Empaqueter le .ipa
        run: |
          mkdir -p "$RUNNER_TEMP/ipa/Payload"
          cp -R "$RUNNER_TEMP/Engram.xcarchive/Products/Applications/Engram.app" "$RUNNER_TEMP/ipa/Payload/"
          (cd "$RUNNER_TEMP/ipa" && zip -qry Engram.ipa Payload)
          ls -lh "$RUNNER_TEMP/ipa/Engram.ipa"
      - uses: actions/upload-artifact@v7.0.1
        with:
          name: Engram-ipa-${{ github.run_number }}
          path: ${{ runner.temp }}/ipa/Engram.ipa
          retention-days: 7
          if-no-files-found: error
```

`scripts/ci.sh` :

```bash
#!/usr/bin/env bash
# Usage : bash scripts/ci.sh [fichier-workflow]   (défaut : ci.yml)
# Pousse la branche courante, attend le run GitHub Actions du commit HEAD et affiche le résultat.
set -euo pipefail
WORKFLOW="${1:-ci.yml}"
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SHA="$(git rev-parse HEAD)"
git push -u origin "$BRANCH"
echo "En attente du run $WORKFLOW pour $SHA…"
RUN_ID=""
for _ in $(seq 1 40); do
  RUN_ID="$("$GH" run list --workflow "$WORKFLOW" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$RUN_ID" ] && break
  sleep 5
done
[ -n "$RUN_ID" ] || { echo "Aucun run $WORKFLOW trouvé pour $SHA"; exit 2; }
if "$GH" run watch "$RUN_ID" --exit-status --interval 20 >/dev/null; then
  echo "✅ CI verte (run $RUN_ID)"
else
  echo "❌ CI en échec (run $RUN_ID). Journaux des étapes en échec :"
  "$GH" run view "$RUN_ID" --log-failed | tail -n 200
  exit 1
fi
```

- [ ] **Step 5: Créer les documents du projet**

`CLAUDE.md` :

```markdown
# Engram — consignes pour Claude

## Le propriétaire
- Débutant en développement, francophone (Québec) : explications simples, en français.
- Usage strictement personnel. iPhone 17 sous iOS 27, AltStore avec Apple ID gratuit. PC Windows, **aucun Mac**.

## Règles absolues (dépôt PUBLIC)
1. Aucune donnée personnelle dans le dépôt (notes, enregistrements, exports, captures d'écran de vrais souvenirs). Données de test fictives et neutres uniquement.
2. Identité Git de ce dépôt : `h7cmkrmygp-ui <339358467+h7cmkrmygp-ui@users.noreply.github.com>` (configuration locale). Vérifier `git config user.email` avant de committer ; ne jamais utiliser le Gmail du propriétaire.
3. Aucun secret dans le code ni dans les journaux de CI.
4. Ne jamais déclarer une fonctionnalité « testée sur iPhone » sans confirmation du propriétaire. L'état réel est tenu dans `docs/IMPLEMENTATION_PROGRESS.md`.

## Travailler sans Mac
- Compilation, tests et `.ipa` : GitHub Actions (`.github/workflows/ci.yml`, runner `xcode-27`).
- Pousser et attendre la CI : `bash scripts/ci.sh` (à lancer en arrière-plan).
- Télécharger le dernier `.ipa` : `bash scripts/fetch-ipa.sh` → `build/ipa/Engram.ipa`.
- `gh` peut être absent du PATH : `"/c/Program Files/GitHub CLI/gh.exe"`.
- Le projet Xcode est généré par XcodeGen depuis `project.yml` : ne jamais committer `.xcodeproj`.

## Conventions
- Swift 6 (concurrence stricte) ; tests avec Swift Testing (`import Testing`).
- Interface en français ; langage de design Apple strict (composants natifs, SF Symbols, couleurs système, accent indigo).
- Code et identifiants en anglais, commentaires en français.
- Références : `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/ROADMAP.md`.
```

`README.md` :

```markdown
# Engram

Application iPhone personnelle de mémoire intelligente : capturer ses pensées, les laisser s'organiser seules, les retrouver.

Projet personnel, non distribué. Le code est public ; **aucune donnée personnelle n'est versionnée**.

- Vision et conception : [`docs/superpowers/specs/`](docs/superpowers/specs/)
- Plans d'implémentation : [`docs/superpowers/plans/`](docs/superpowers/plans/)
- Feuille de route : [`docs/ROADMAP.md`](docs/ROADMAP.md)
- État réel : [`docs/IMPLEMENTATION_PROGRESS.md`](docs/IMPLEMENTATION_PROGRESS.md)
```

`docs/ROADMAP.md` :

```markdown
# Engram — Feuille de route

Les identifiants F1…F100 sont ceux du master prompt « SECOND BRAIN ULTIMATE ». « S8.x » désigne les sous-sections non numérotées du module VI (Siri, App Intents, bouton Action). L'affectation des phases 2 à 6 sera confirmée au démarrage de chaque phase.

| Phase | Identifiants | Contenu |
|---|---|---|
| **1 — Fondation** | F1, F2, F3, F4, F7, F8, F10, F11, F12, F13, F14, F15, F17, F19 (partiel), F20 (partiel), F23, F24, F84, F85 (principe), F86 (partiel), F88, F89, F90, F92, F93 (partiel), F94 (partiel), F96, F97 | Capture texte et voix, transcription, souvenirs, catégories automatiques, bibliothèque, recherche, versions, suppression contrôlée, export |
| **2 — Mémoire avancée** | F5, F16, F18, F19, F20, F21, F22, F25–F31, F32–F38, F75, F87 | Import multimodal, types de mémoire, évolution, contradictions, incertitudes, Brain Graph, Ask Your Brain, personnes, compartiments |
| **3 — Intégrations IA** | F17 (serveur), F40–F48, F72, F73, F86 (serveur), F91 | Serveur, synchronisation, MCP (ChatGPT, Claude, Claude Code), permissions, journal d'accès, projets, décisions, défense contre l'injection d'instructions |
| **4 — Apple et organisation** | F6, S8.1–S8.5, F49, F50, F51, F52, F57, F58, F60, F65, F66, F71, F95 | Extension de partage, Siri et Raccourcis, bouton Action, widgets, calendrier, rappels, priorisation, briefing, notifications |
| **5 — Intelligence proactive** | F39, F53–F56, F59, F61–F64, F67–F70, F74, F82, F83, F98–F100 | Planification, automatisations, revues, anticipation, objectifs, habitudes, suggestions, clarifications, agent d'organisation |
| **6 — Expansion** | F9, F76–F81, S8.6 | Réunions, apprentissage, révision espacée, documents, finances, santé, voyages, Apple Watch, autres plateformes |
```

`docs/IMPLEMENTATION_PROGRESS.md` :

```markdown
# Engram — État réel du développement

Légende : ✅ fait · ⏳ en cours · — pas encore · n/a sans objet

Colonnes :
- **Dessiné** : l'écran existe.
- **Simulé** : fonctionne avec de faux services.
- **Implémenté** : le vrai code existe.
- **CI** : tests automatiques verts.
- **iPhone** : vérifié par le propriétaire sur son iPhone.
- **Prêt** : utilisable au quotidien.

## Phase 1

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| INFRA-1 | Compilation GitHub Actions et `.ipa` | n/a | n/a | — | — | n/a | — | |
| INFRA-2 | Installation via AltStore | n/a | n/a | n/a | n/a | — | — | |
| INFRA-3 | Relevé des API iOS 27 | n/a | n/a | — | — | n/a | — | |
| F1 | Capture vocale | — | — | — | — | — | — | plan P3 |
| F2 | Transcription | — | — | — | — | — | — | plan P3 |
| F3 | Découpage d'un enregistrement | — | — | — | — | — | — | plan P2 |
| F4 | Capture textuelle | — | n/a | — | — | — | — | P1 sans IA, P2 avec IA |
| F7 | Conservation des originaux | — | n/a | — | — | — | — | |
| F10 | Pipeline de transformation | n/a | — | — | — | — | — | plan P2 |
| F11 | Titres et résumés | — | — | — | — | — | — | P1 : titre de repli |
| F12 | Catégories automatiques | — | — | — | — | — | — | plan P2 |
| F13 | Classement automatique | — | — | — | — | — | — | P1 : manuel |
| F14 | Classification multiple | — | n/a | — | — | — | — | |
| F15 | Tags | — | — | — | — | — | — | P1 : stockage |
| F17 | Persistance locale | n/a | n/a | — | — | — | — | |
| F20 | Doublons (partiel) | — | n/a | — | — | — | — | P1 : doublons techniques |
| F23 | Provenance | — | n/a | — | — | — | — | |
| F24 | Modification, versions, restauration | — | n/a | — | — | — | — | |
| F89 | Export ouvert | — | n/a | — | — | — | — | |
| F90 | Suppression contrôlée | — | n/a | — | — | — | — | |
| F94 | Recherche (partiel) | — | n/a | — | — | — | — | P1 : par mots |
```

- [ ] **Step 6: Commit**

```bash
git add -A
git status --short
git commit -m "chore: squelette du projet, CI GitHub Actions et documents

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Avant le commit, vérifier dans `git status --short` qu'aucun fichier inattendu n'est ajouté (aucun `.xcodeproj`, `build/`, audio).

- [ ] **Step 7: ⚠️ Créer le dépôt public GitHub (accord explicite du propriétaire requis)**

Demander au propriétaire, dans la conversation : « Je crée le dépôt public `engram` sur ton compte h7cmkrmygp-ui et j'y envoie la spec et le squelette. OK ? » Ne continuer qu'après un « oui ».

```bash
GH="/c/Program Files/GitHub CLI/gh.exe"
git switch main
"$GH" repo create engram --public --source . --remote origin \
  --description "Engram — mémoire personnelle intelligente pour iPhone (projet personnel)"
git push -u origin main
"$GH" api -X PATCH repos/h7cmkrmygp-ui/engram \
  -f "security_and_analysis[secret_scanning][status]=enabled" \
  -f "security_and_analysis[secret_scanning_push_protection][status]=enabled"
"$GH" api repos/h7cmkrmygp-ui/engram --jq '.visibility, .security_and_analysis'
git switch p1-fondations
```

Expected : `public`, puis `secret_scanning` et `secret_scanning_push_protection` à `enabled`.

- [ ] **Step 8: Lancer la CI et vérifier qu'elle passe**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. Les 3 jobs (`secrets-scan`, `package-tests`, `ipa`) sont verts et l'artefact `Engram-ipa-<n>` existe.

Si `ipa` échoue, lire le journal :
- Une erreur Info.plist ou de signature : corriger `project.yml`.
- Une erreur `runs-on` : vérifier l'étiquette `xcode-27` sur le changelog GitHub.

- [ ] **Step 9: Mettre à jour l'avancement et committer**

Dans `docs/IMPLEMENTATION_PROGRESS.md`, ligne `INFRA-1` : `Implémenté ✅`, `CI ✅`.

```bash
git add docs/IMPLEMENTATION_PROGRESS.md
git commit -m "docs: CI et .ipa opérationnels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Premier `.ipa` sur l'iPhone

**Files:**
- Create: `scripts/fetch-ipa.sh`
- Modify: `docs/IMPLEMENTATION_PROGRESS.md`

**Interfaces:**
- Consumes: l'artefact `Engram-ipa-<n>` produit par `ci.yml` (tâche 1).
- Produces: `scripts/fetch-ipa.sh [branche]` → `build/ipa/Engram.ipa`.

- [ ] **Step 1: Écrire le script de téléchargement**

`scripts/fetch-ipa.sh` :

```bash
#!/usr/bin/env bash
# Usage : bash scripts/fetch-ipa.sh [branche]   (défaut : branche courante)
# Télécharge le .ipa du dernier run CI réussi dans build/ipa/Engram.ipa.
set -euo pipefail
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
RUN_ID="$("$GH" run list --workflow ci.yml --branch "$BRANCH" --status success --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
[ -n "$RUN_ID" ] || { echo "Aucun run CI réussi sur $BRANCH"; exit 2; }
rm -rf build/ipa
mkdir -p build/ipa
"$GH" run download "$RUN_ID" --pattern 'Engram-ipa-*' --dir build/ipa
IPA="$(find build/ipa -name 'Engram.ipa' -type f | head -1)"
[ -n "$IPA" ] || { echo "Engram.ipa introuvable dans l'artefact"; exit 3; }
[ "$IPA" = "build/ipa/Engram.ipa" ] || mv "$IPA" build/ipa/Engram.ipa
echo "✅ $(pwd)/build/ipa/Engram.ipa (run $RUN_ID)"
```

- [ ] **Step 2: Télécharger le `.ipa`**

Run : `bash scripts/fetch-ipa.sh`
Expected : `✅ …/build/ipa/Engram.ipa (run …)`. `build/` est ignoré par Git.

- [ ] **Step 3: Faire installer l'app par le propriétaire**

Donner au propriétaire ces instructions (deux méthodes, selon sa version d'AltServer et d'AltStore) :

1. **Depuis l'iPhone (la plus simple) :**
   1. Copier `build\ipa\Engram.ipa` sur l'iPhone (iCloud Drive, OneDrive ou AirDrop vers Fichiers).
   2. Dans AltStore, ouvrir **My Apps**, toucher **+**, puis choisir `Engram.ipa`.
2. **Depuis le PC :**
   1. Brancher l'iPhone (ou le laisser sur le même Wi-Fi).
   2. Dans le menu d'AltServer (icône de la barre des tâches), maintenir **Maj** puis cliquer pour faire apparaître **Sideload .ipa…**.
   3. Choisir l'iPhone, puis le fichier.

Expected (confirmé par le propriétaire) : l'icône Engram apparaît ; l'app s'ouvre sur l'écran « Engram — Les fondations sont en construction. » avec le symbole de cerveau. Les App IDs AltStore en utilisent 1 de plus.

- [ ] **Step 4: Consigner le résultat et committer**

Dans `docs/IMPLEMENTATION_PROGRESS.md`, ligne `INFRA-2` : `iPhone ✅` seulement après confirmation du propriétaire, avec la date en note.

```bash
git add scripts/fetch-ipa.sh docs/IMPLEMENTATION_PROGRESS.md
git commit -m "chore: script de téléchargement du .ipa, première installation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Relevé des API iOS 27 utilisées par Engram

**Files:**
- Create: `.github/workflows/sdk-check.yml`
- Create: `docs/notes/2026-10-ios27-sdk.md`
- Modify: `docs/IMPLEMENTATION_PROGRESS.md`

**Interfaces:**
- Consumes: le runner `xcode-27`.
- Produces: `docs/notes/2026-10-ios27-sdk.md`. P2 (Foundation Models, NaturalLanguage) et P3 (Speech) s'appuieront sur ce document pour écrire leur code.

- [ ] **Step 1: Écrire le workflow de relevé**

`.github/workflows/sdk-check.yml` :

```yaml
name: SDK check
on:
  push:
    paths: [".github/workflows/sdk-check.yml"]
  workflow_dispatch:
permissions:
  contents: read
defaults:
  run:
    shell: bash
jobs:
  inspect:
    runs-on: xcode-27
    steps:
      - name: Versions et simulateurs
        run: |
          xcodebuild -version
          swift --version
          echo "iOS SDK : $(xcrun --sdk iphoneos --show-sdk-version)"
          xcrun simctl list devices available | grep -E "iPhone" || true
      - name: API publiques utilisées par Engram
        run: |
          SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
          inspect() {
            local fw="$1" pattern="$2" file
            file="$(find "$SDK/System/Library/Frameworks/$fw.framework" -name '*.swiftinterface' -path '*arm64e-apple-ios*' | head -1)"
            [ -n "$file" ] || file="$(find "$SDK/System/Library/Frameworks/$fw.framework" -name '*.swiftinterface' | head -1)"
            echo "::group::$fw — ${file:-introuvable}"
            if [ -n "$file" ]; then grep -nE "$pattern" "$file" | head -200 || true; fi
            echo "::endgroup::"
          }
          inspect FoundationModels 'SystemLanguageModel|LanguageModelSession|availability|contextSize|supportedLanguages|supportsLocale|func respond|macro Generable|macro Guide|GenerationOptions|GenerationError|guardrailViolation|exceededContextWindowSize|tokenCount|Instructions'
          inspect Speech 'SpeechAnalyzer|SpeechTranscriber|DictationTranscriber|AssetInventory|supportedLocales|installedLocales|reserve|assetInstallationRequest|ReportingOption|TranscriptionOption|ResultAttributeOption'
          inspect NaturalLanguage 'NLContextualEmbedding|embeddingResult|dimension|maximumSequenceLength|requestAssets|hasAvailableAssets|NLLanguageRecognizer'
          inspect LocalAuthentication 'class LAContext|func evaluatePolicy|deviceOwnerAuthentication'
```

- [ ] **Step 2: Lancer le relevé**

```bash
git add .github/workflows/sdk-check.yml
git commit -m "ci: relevé des API iOS 27

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh sdk-check.yml`
Expected : `✅ CI verte`. Puis lire la sortie complète : `"/c/Program Files/GitHub CLI/gh.exe" run view <RUN_ID> --log`.

- [ ] **Step 3: Rédiger la note de synthèse**

Créer `docs/notes/2026-10-ios27-sdk.md`, rédigé avec nos propres mots, **sans copier de bloc de l'interface Apple** au-delà des noms de symboles. Remplir chaque rubrique à partir du journal :

```markdown
# API iOS 27 relevées pour Engram — <date du run>

Run : <lien du run> · Xcode <version> · SDK iOS <version> · Swift <version>
Simulateurs iPhone disponibles : <liste>

## Foundation Models (P2)
- Vérifier la disponibilité du modèle : <symbole exact et cas d'indisponibilité>
- Taille de contexte : <symbole ou « non exposé »>
- Langues : <symbole>
- Session et génération guidée : <noms exacts : LanguageModelSession, respond(to:generating:…), @Generable, @Guide>
- Erreurs à gérer : <cas exacts, ex. dépassement de contexte, garde-fous>
- Écarts avec iOS 26 : <liste ou « aucun constaté »>

## Speech (P3)
- Transcription sur l'appareil : <SpeechAnalyzer / SpeechTranscriber : initialiseurs et options>
- Langues et ressources : <supportedLocales, installedLocales, AssetInventory…>
- Résultats en direct : <options de rapport>

## NaturalLanguage (P2)
- NLContextualEmbedding : <création, dimension, longueur max, ressources>
- NLLanguageRecognizer : <confirmé>

## LocalAuthentication (P4)
- <LAContext.evaluatePolicy : confirmé>

## Conséquences pour les plans
- P2 : <ajustements>
- P3 : <ajustements>
```

- [ ] **Step 4: Committer la note**

Dans `docs/IMPLEMENTATION_PROGRESS.md`, ligne `INFRA-3` : `Implémenté ✅`, `CI ✅`.

```bash
git add docs/notes/2026-10-ios27-sdk.md docs/IMPLEMENTATION_PROGRESS.md
git commit -m "docs: synthèse des API iOS 27 (Foundation Models, Speech, NaturalLanguage)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Types du domaine (EngramCore)

**Files:**
- Create: `Packages/EngramKit/Sources/EngramCore/Enums.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/Models.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/MemoryValidation.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/TextNormalizer.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/TitleMaker.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/ContentHasher.swift`
- Create: `Packages/EngramKit/Sources/EngramCore/DateProvider.swift`
- Create: `Packages/EngramKit/Sources/EngramTesting/TestDateProvider.swift`
- Create: `Packages/EngramKit/Sources/EngramTesting/TemporaryDirectory.swift`
- Test: `Packages/EngramKit/Tests/EngramCoreTests/TextNormalizerTests.swift`
- Test: `Packages/EngramKit/Tests/EngramCoreTests/TitleMakerTests.swift`
- Test: `Packages/EngramKit/Tests/EngramCoreTests/ContentHasherTests.swift`
- Test: `Packages/EngramKit/Tests/EngramCoreTests/MemoryValidationTests.swift`

**Interfaces:**
- Consumes: `EngramCore.exportFormatVersion` (tâche 1).
- Produces (tous `public`) :
  - Enums `String`, `Codable`, `Sendable` : `SourceKind {voice,text}` · `ProcessingStatus {pending,transcribing,analyzing,classifying,indexing,done,waiting,failed}` · `MemoryStatus {active,unsorted,archived,trashed}` (`CaseIterable`) · `MemoryKind {idea,task,appointment,decision,preference,info,other}` · `TextVersion {original,corrected}` · `Origin {seed,ai,user}` · `AssignmentOrigin {ai,user}` · `ChangeActor {user,ai,system}` · `CategoryStatus {active,archived}`.
  - Structs `Codable`, `Sendable`, `Hashable` aux clés snake_case :
    - `Source` (+ `referenceText`)
    - `Memory` (+ `init(id:draft:capturedAt:now:)`, `snapshot`)
    - `MemoryDraft`
    - `MemoryEdit` (+ `apply(to:) -> Bool`)
    - `MemorySnapshot`
    - `MemoryVersion` (+ `init(memory:changedBy:reason:at:)`)
    - `EngramCategory` (+ `init(id:name:descriptionText:parentID:origin:status:now:)`)
    - `EngramTag` (+ `init(id:name:origin:now:)`)
    - `CategoryAssignment` et `TagAssignment` (+ `init(memoryID:categoryID|tagID:origin:confidence:confirmed:rejected:now:)`)
  - `MemoryValidation.validate(title:content:) throws`, `MemoryDraft.validate() throws`, `MemoryValidationError {emptyTitle,titleTooLong,emptyContent,emptyExcerpt,invalidStatus,invalidConfidence}`.
  - `TextNormalizer.normalizedName(_:) -> String`, `TextNormalizer.matchingForm(_:) -> String`.
  - `TitleMaker.maxLength = 80`, `TitleMaker.fallbackTitle(from:) -> String`.
  - `ContentHasher.sha256Hex(_: Data) -> String`, `ContentHasher.textHash(_: String) -> String`.
  - `protocol DateProvider: Sendable { func now() -> Date }`, `SystemDateProvider`.
  - EngramTesting : `TestDateProvider(_ start: Date)` avec `now()` et `advance(by:)`, `TemporaryDirectory()` avec `url` (supprimé à la désallocation).

- [ ] **Step 1: Écrire les tests (ils doivent échouer)**

`Tests/EngramCoreTests/TextNormalizerTests.swift` :

```swift
import Testing
@testable import EngramCore

struct TextNormalizerTests {
    @Test(arguments: [
        ("Voyages", "voyage"),
        ("voyage", "voyage"),
        ("VOYAGES", "voyage"),
        ("Études", "etude"),
        ("Santé", "sante"),
        ("Idées", "idee"),
        ("Finances", "finance"),
        ("  Course   à pied ", "course a pied"),
        ("Voyages d'été", "voyage d ete"),
        ("Business", "business"),
        ("Bus", "bus"),
        ("!!!", ""),
        ("", ""),
    ])
    func normalizedName(input: String, expected: String) {
        #expect(TextNormalizer.normalizedName(input) == expected)
    }

    @Test func equivalentCategoryNamesShareNormalizedForm() {
        let forms = Set(["Voyages", "voyage", "  VOYAGE ", "Voyagés"].map(TextNormalizer.normalizedName))
        #expect(forms == ["voyage"])
    }

    @Test(arguments: [
        ("Il faut, que je TERMINE !", "il faut que je termine"),
        ("Réunion à 14h30", "reunion a 14h30"),
        ("  plusieurs\n\nlignes\t ici ", "plusieurs lignes ici"),
    ])
    func matchingForm(input: String, expected: String) {
        #expect(TextNormalizer.matchingForm(input) == expected)
    }
}
```

`Tests/EngramCoreTests/TitleMakerTests.swift` :

```swift
import Testing
@testable import EngramCore

struct TitleMakerTests {
    @Test func keepsShortFirstLine() {
        #expect(TitleMaker.fallbackTitle(from: "Acheter du lait") == "Acheter du lait")
    }

    @Test func usesFirstNonBlankLineCollapsed() {
        #expect(TitleMaker.fallbackTitle(from: "\n   \n  Première   ligne  \nDeuxième") == "Première ligne")
    }

    @Test func blankTextGetsPlaceholderTitle() {
        #expect(TitleMaker.fallbackTitle(from: "  \n\t ") == "Note sans titre")
    }

    @Test func longSingleWordIsCutWithEllipsis() {
        let title = TitleMaker.fallbackTitle(from: String(repeating: "a", count: 200))
        #expect(title.count == 80)
        #expect(title.hasSuffix("…"))
    }

    @Test func longSentenceIsCutAtAWordBoundary() {
        let text = Array(repeating: "mot", count: 60).joined(separator: " ")
        let title = TitleMaker.fallbackTitle(from: text)
        #expect(title.count <= 80)
        #expect(title.hasSuffix("mot…"))
    }

    @Test func neverBreaksEmojiGraphemes() {
        let family = "👨‍👩‍👧"
        let title = TitleMaker.fallbackTitle(from: Array(repeating: family, count: 50).joined(separator: " "))
        #expect(title.count <= 80)
        #expect(title.allSatisfy { $0 == Character(family) || $0 == " " || $0 == "…" })
    }
}
```

`Tests/EngramCoreTests/ContentHasherTests.swift` :

```swift
import Testing
import Foundation
@testable import EngramCore

struct ContentHasherTests {
    @Test func sha256OfKnownVector() {
        #expect(ContentHasher.sha256Hex(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func textHashIgnoresWhitespaceDifferences() {
        #expect(ContentHasher.textHash("  a   b \n") == ContentHasher.textHash("a b"))
    }

    @Test func textHashKeepsCase() {
        #expect(ContentHasher.textHash("A b") != ContentHasher.textHash("a b"))
    }
}
```

`Tests/EngramCoreTests/MemoryValidationTests.swift` :

```swift
import Testing
import Foundation
@testable import EngramCore

struct MemoryValidationTests {
    let sourceID = UUID()

    func draft(title: String = "Titre", content: String = "Contenu", excerpt: String = "Contenu",
               status: MemoryStatus = .unsorted, confidence: Double? = nil) -> MemoryDraft {
        MemoryDraft(sourceID: sourceID, excerpt: excerpt, title: title, content: content,
                    status: status, confidence: confidence, analysisVersion: "test")
    }

    @Test func validDraftPasses() throws {
        try draft().validate()
    }

    @Test func rejectsBlankTitle() {
        #expect(throws: MemoryValidationError.emptyTitle) { try draft(title: "   ").validate() }
    }

    @Test func rejectsTitleOver80Characters() {
        #expect(throws: MemoryValidationError.titleTooLong) {
            try draft(title: String(repeating: "x", count: 81)).validate()
        }
    }

    @Test func rejectsBlankContentAndExcerpt() {
        #expect(throws: MemoryValidationError.emptyContent) { try draft(content: " \n").validate() }
        #expect(throws: MemoryValidationError.emptyExcerpt) { try draft(excerpt: "").validate() }
    }

    @Test func draftCannotStartArchivedOrTrashed() {
        #expect(throws: MemoryValidationError.invalidStatus) { try draft(status: .archived).validate() }
        #expect(throws: MemoryValidationError.invalidStatus) { try draft(status: .trashed).validate() }
    }

    @Test func rejectsConfidenceOutsideZeroOne() {
        #expect(throws: MemoryValidationError.invalidConfidence) { try draft(confidence: 1.5).validate() }
    }

    @Test func memoryFromDraftStartsAtVersionOne() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let memory = Memory(draft: draft(title: "  Titre  "), capturedAt: now, now: now)
        #expect(memory.version == 1)
        #expect(memory.title == "Titre")
        #expect(memory.userEdited == false)
        #expect(memory.trashedAt == nil)
    }

    @Test func editReportsWhetherSomethingChanged() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var memory = Memory(draft: draft(), capturedAt: now, now: now)
        #expect(MemoryEdit(title: "Titre").apply(to: &memory) == false)
        #expect(MemoryEdit(title: " Nouveau ").apply(to: &memory) == true)
        #expect(memory.title == "Nouveau")
        #expect(MemoryEdit(summary: "Résumé").apply(to: &memory) == true)
        #expect(MemoryEdit(summary: "").apply(to: &memory) == true)
        #expect(memory.summary == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

```bash
git add Packages/EngramKit/Tests/EngramCoreTests
git commit -m "test: types du domaine (échec attendu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : FAIL au job `package-tests`, avec `cannot find 'TextNormalizer' in scope` (et des erreurs similaires pour `TitleMaker`, `ContentHasher`, `MemoryDraft`).

- [ ] **Step 3: Écrire l'implémentation**

`Sources/EngramCore/Enums.swift` :

```swift
import Foundation

/// Type d'une capture.
public enum SourceKind: String, Codable, Sendable, CaseIterable { case voice, text }

/// Avancement du traitement d'une source.
public enum ProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending, transcribing, analyzing, classifying, indexing, done, waiting, failed
}

/// État d'un souvenir. « À classer » = `unsorted`.
public enum MemoryStatus: String, Codable, Sendable, CaseIterable {
    case active, unsorted, archived, trashed
}

/// Nature de l'information extraite.
public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case idea, task, appointment, decision, preference, info, other
}

/// Texte de référence d'un extrait : transcription originale ou corrigée.
public enum TextVersion: String, Codable, Sendable { case original, corrected }

/// Qui a créé une catégorie ou un tag.
public enum Origin: String, Codable, Sendable { case seed, ai, user }

/// Qui a posé un lien souvenir ↔ catégorie ou tag.
public enum AssignmentOrigin: String, Codable, Sendable { case ai, user }

/// Qui a modifié un souvenir.
public enum ChangeActor: String, Codable, Sendable { case user, ai, system }

/// État d'une catégorie.
public enum CategoryStatus: String, Codable, Sendable { case active, archived }
```

`Sources/EngramCore/Models.swift` :

```swift
import Foundation

/// L'original d'une capture. Le texte original n'est jamais réécrit.
public struct Source: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: SourceKind
    public var audioPath: String?
    public var audioDuration: Double?
    public var originalText: String?
    public var correctedText: String?
    public var languages: [String]
    public var transcriptionEngine: String?
    public var contentHash: String
    public var capturedAt: Date
    public var processingStatus: ProcessingStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), kind: SourceKind, audioPath: String? = nil, audioDuration: Double? = nil,
        originalText: String? = nil, correctedText: String? = nil, languages: [String] = [],
        transcriptionEngine: String? = nil, contentHash: String, capturedAt: Date,
        processingStatus: ProcessingStatus = .pending, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.audioPath = audioPath
        self.audioDuration = audioDuration
        self.originalText = originalText
        self.correctedText = correctedText
        self.languages = languages
        self.transcriptionEngine = transcriptionEngine
        self.contentHash = contentHash
        self.capturedAt = capturedAt
        self.processingStatus = processingStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Texte à analyser : la correction du propriétaire si elle existe, sinon l'original.
    public var referenceText: String? { correctedText ?? originalText }

    enum CodingKeys: String, CodingKey {
        case id, kind, languages
        case audioPath = "audio_path"
        case audioDuration = "audio_duration"
        case originalText = "original_text"
        case correctedText = "corrected_text"
        case transcriptionEngine = "transcription_engine"
        case contentHash = "content_hash"
        case capturedAt = "captured_at"
        case processingStatus = "processing_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Données nécessaires pour créer un souvenir.
public struct MemoryDraft: Sendable, Hashable {
    public var sourceID: UUID
    public var excerpt: String
    public var spanStart: Int?
    public var spanEnd: Int?
    public var spanTextVersion: TextVersion
    public var title: String
    public var summary: String?
    public var content: String
    public var kind: MemoryKind?
    public var status: MemoryStatus
    public var confidence: Double?
    public var suggestedTopic: String?
    public var mentionedDates: [String]
    public var analysisVersion: String

    public init(
        sourceID: UUID, excerpt: String, spanStart: Int? = nil, spanEnd: Int? = nil,
        spanTextVersion: TextVersion = .original, title: String, summary: String? = nil,
        content: String, kind: MemoryKind? = nil, status: MemoryStatus = .unsorted,
        confidence: Double? = nil, suggestedTopic: String? = nil, mentionedDates: [String] = [],
        analysisVersion: String
    ) {
        self.sourceID = sourceID
        self.excerpt = excerpt
        self.spanStart = spanStart
        self.spanEnd = spanEnd
        self.spanTextVersion = spanTextVersion
        self.title = title
        self.summary = summary
        self.content = content
        self.kind = kind
        self.status = status
        self.confidence = confidence
        self.suggestedTopic = suggestedTopic
        self.mentionedDates = mentionedDates
        self.analysisVersion = analysisVersion
    }
}

/// Un souvenir.
public struct Memory: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sourceID: UUID
    public var excerpt: String
    public var spanStart: Int?
    public var spanEnd: Int?
    public var spanTextVersion: TextVersion
    public var title: String
    public var summary: String?
    public var content: String
    public var kind: MemoryKind?
    public var memoryType: String?
    public var status: MemoryStatus
    public var confidence: Double?
    public var suggestedTopic: String?
    public var mentionedDates: [String]
    public var userEdited: Bool
    public var possibleDuplicateOf: UUID?
    public var analysisVersion: String
    public var capturedAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?
    public var version: Int

    public init(id: UUID = UUID(), draft: MemoryDraft, capturedAt: Date, now: Date) {
        self.id = id
        self.sourceID = draft.sourceID
        self.excerpt = draft.excerpt
        self.spanStart = draft.spanStart
        self.spanEnd = draft.spanEnd
        self.spanTextVersion = draft.spanTextVersion
        self.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = draft.summary
        self.content = draft.content
        self.kind = draft.kind
        self.memoryType = nil
        self.status = draft.status
        self.confidence = draft.confidence
        self.suggestedTopic = draft.suggestedTopic
        self.mentionedDates = draft.mentionedDates
        self.userEdited = false
        self.possibleDuplicateOf = nil
        self.analysisVersion = draft.analysisVersion
        self.capturedAt = capturedAt
        self.createdAt = now
        self.updatedAt = now
        self.trashedAt = nil
        self.version = 1
    }

    /// Ce qui est conservé dans l'historique des versions.
    public var snapshot: MemorySnapshot {
        MemorySnapshot(title: title, summary: summary, content: content, kind: kind, status: status)
    }

    enum CodingKeys: String, CodingKey {
        case id, excerpt, title, summary, content, kind, status, confidence, version
        case sourceID = "source_id"
        case spanStart = "span_start"
        case spanEnd = "span_end"
        case spanTextVersion = "span_text_version"
        case memoryType = "memory_type"
        case suggestedTopic = "suggested_topic"
        case mentionedDates = "mentioned_dates"
        case userEdited = "user_edited"
        case possibleDuplicateOf = "possible_duplicate_of"
        case analysisVersion = "analysis_version"
        case capturedAt = "captured_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case trashedAt = "trashed_at"
    }
}

/// Une modification demandée sur un souvenir. `nil` = ne pas toucher ; `summary: ""` efface le résumé.
public struct MemoryEdit: Sendable, Hashable {
    public var title: String?
    public var summary: String?
    public var content: String?
    public var kind: MemoryKind?

    public init(title: String? = nil, summary: String? = nil, content: String? = nil, kind: MemoryKind? = nil) {
        self.title = title
        self.summary = summary
        self.content = content
        self.kind = kind
    }

    /// Applique la modification. Renvoie `true` si quelque chose a changé.
    public func apply(to memory: inout Memory) -> Bool {
        var changed = false
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != memory.title { memory.title = trimmed; changed = true }
        }
        if let summary {
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue: String? = trimmed.isEmpty ? nil : trimmed
            if newValue != memory.summary { memory.summary = newValue; changed = true }
        }
        if let content, content != memory.content {
            memory.content = content
            changed = true
        }
        if let kind, kind != memory.kind {
            memory.kind = kind
            changed = true
        }
        return changed
    }
}

/// Copie des champs d'un souvenir à un instant donné.
public struct MemorySnapshot: Codable, Sendable, Hashable {
    public var title: String
    public var summary: String?
    public var content: String
    public var kind: MemoryKind?
    public var status: MemoryStatus

    public init(title: String, summary: String?, content: String, kind: MemoryKind?, status: MemoryStatus) {
        self.title = title
        self.summary = summary
        self.content = content
        self.kind = kind
        self.status = status
    }
}

/// Une version de l'historique d'un souvenir.
public struct MemoryVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var memoryID: UUID
    public var version: Int
    public var snapshot: MemorySnapshot
    public var changedBy: ChangeActor
    public var changeReason: String?
    public var createdAt: Date

    public init(memory: Memory, changedBy: ChangeActor, reason: String?, at date: Date) {
        self.id = UUID()
        self.memoryID = memory.id
        self.version = memory.version
        self.snapshot = memory.snapshot
        self.changedBy = changedBy
        self.changeReason = reason
        self.createdAt = date
    }

    enum CodingKeys: String, CodingKey {
        case id, version, snapshot
        case memoryID = "memory_id"
        case changedBy = "changed_by"
        case changeReason = "change_reason"
        case createdAt = "created_at"
    }
}

/// Une catégorie (dossier). « À classer » n'en est pas une : c'est le statut `unsorted` d'un souvenir.
public struct EngramCategory: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var normalizedName: String
    public var descriptionText: String?
    public var parentID: UUID?
    public var origin: Origin
    public var status: CategoryStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, descriptionText: String? = nil, parentID: UUID?,
                origin: Origin, status: CategoryStatus = .active, now: Date) {
        self.id = id
        self.name = name
        self.normalizedName = TextNormalizer.normalizedName(name)
        self.descriptionText = descriptionText
        self.parentID = parentID
        self.origin = origin
        self.status = status
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, name, origin, status
        case normalizedName = "normalized_name"
        case descriptionText = "description"
        case parentID = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Une étiquette (idée, décision, facture…).
public struct EngramTag: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var normalizedName: String
    public var origin: Origin
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, origin: Origin, now: Date) {
        self.id = id
        self.name = name
        self.normalizedName = TextNormalizer.normalizedName(name)
        self.origin = origin
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, name, origin
        case normalizedName = "normalized_name"
        case createdAt = "created_at"
    }
}

/// Lien souvenir ↔ catégorie. `rejected` = retiré par le propriétaire (l'IA ne le recréera jamais).
public struct CategoryAssignment: Codable, Sendable, Hashable {
    public var memoryID: UUID
    public var categoryID: UUID
    public var origin: AssignmentOrigin
    public var confidence: Double?
    public var confirmed: Bool
    public var rejected: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(memoryID: UUID, categoryID: UUID, origin: AssignmentOrigin, confidence: Double? = nil,
                confirmed: Bool, rejected: Bool = false, now: Date) {
        self.memoryID = memoryID
        self.categoryID = categoryID
        self.origin = origin
        self.confidence = confidence
        self.confirmed = confirmed
        self.rejected = rejected
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case origin, confidence, confirmed, rejected
        case memoryID = "memory_id"
        case categoryID = "category_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Lien souvenir ↔ tag. Mêmes règles que `CategoryAssignment`.
public struct TagAssignment: Codable, Sendable, Hashable {
    public var memoryID: UUID
    public var tagID: UUID
    public var origin: AssignmentOrigin
    public var confidence: Double?
    public var confirmed: Bool
    public var rejected: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(memoryID: UUID, tagID: UUID, origin: AssignmentOrigin, confidence: Double? = nil,
                confirmed: Bool, rejected: Bool = false, now: Date) {
        self.memoryID = memoryID
        self.tagID = tagID
        self.origin = origin
        self.confidence = confidence
        self.confirmed = confirmed
        self.rejected = rejected
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case origin, confidence, confirmed, rejected
        case memoryID = "memory_id"
        case tagID = "tag_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

`Sources/EngramCore/MemoryValidation.swift` :

```swift
import Foundation

public enum MemoryValidationError: Error, Equatable, Sendable {
    case emptyTitle, titleTooLong, emptyContent, emptyExcerpt, invalidStatus, invalidConfidence
}

public enum MemoryValidation {
    /// Vérifie les champs communs à toute écriture d'un souvenir.
    public static func validate(title: String, content: String) throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MemoryValidationError.emptyTitle }
        if title.count > TitleMaker.maxLength { throw MemoryValidationError.titleTooLong }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MemoryValidationError.emptyContent }
    }
}

extension MemoryDraft {
    public func validate() throws {
        try MemoryValidation.validate(title: title.trimmingCharacters(in: .whitespacesAndNewlines), content: content)
        if excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MemoryValidationError.emptyExcerpt }
        guard status == .active || status == .unsorted else { throw MemoryValidationError.invalidStatus }
        if let confidence, !(0...1).contains(confidence) { throw MemoryValidationError.invalidConfidence }
    }
}
```

`Sources/EngramCore/TextNormalizer.swift` :

```swift
import Foundation

/// Formes normalisées du texte, indépendantes de la casse, des accents et de la ponctuation.
public enum TextNormalizer {
    /// Forme canonique d'un nom de catégorie ou de tag : « Voyages d'été » → « voyage d ete ».
    /// Pluriel simple : un « s » final est retiré des mots de plus de 3 lettres (sauf « ss »).
    public static func normalizedName(_ raw: String) -> String {
        words(of: raw).map(singularize).joined(separator: " ")
    }

    /// Forme de comparaison d'un texte : minuscules, sans accents, sans ponctuation, espaces simples.
    public static func matchingForm(_ raw: String) -> String {
        words(of: raw).joined(separator: " ")
    }

    static func words(of raw: String) -> [String] {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    static func singularize(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }
}
```

`Sources/EngramCore/TitleMaker.swift` :

```swift
import Foundation

/// Titre de repli quand aucune analyse n'est disponible.
public enum TitleMaker {
    public static let maxLength = 80

    /// Première ligne non vide, espaces réduits, coupée proprement à 80 caractères (graphèmes).
    public static func fallbackTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) }
            .map(String.init) ?? ""
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return "Note sans titre" }
        guard collapsed.count > maxLength else { return collapsed }
        let cut = collapsed.prefix(maxLength - 1)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= 40 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
```

`Sources/EngramCore/ContentHasher.swift` :

```swift
import CryptoKit
import Foundation

/// Empreintes SHA-256, pour détecter les doublons techniques.
public enum ContentHasher {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Empreinte d'un texte, insensible aux différences d'espaces (mais pas à la casse).
    public static func textHash(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return sha256Hex(Data(collapsed.utf8))
    }
}
```

`Sources/EngramCore/DateProvider.swift` :

```swift
import Foundation

/// Horloge injectable, pour pouvoir tester les règles liées au temps.
public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}
```

`Sources/EngramTesting/TestDateProvider.swift` :

```swift
import EngramCore
import Foundation
import Synchronization

/// Horloge contrôlable pour les tests. Ne jamais utiliser dans l'app.
public final class TestDateProvider: DateProvider {
    private let current: Mutex<Date>

    public init(_ start: Date) {
        current = Mutex(start)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(by interval: TimeInterval) {
        current.withLock { $0 += interval }
    }
}
```

`Sources/EngramTesting/TemporaryDirectory.swift` :

```swift
import Foundation

/// Dossier temporaire unique, supprimé automatiquement à la fin du test.
public final class TemporaryDirectory: Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engram-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Packages/EngramKit
git commit -m "feat(core): types du domaine, normalisation, titres de repli, empreintes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Vérifier que les tests passent**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. `package-tests` exécute `TextNormalizerTests`, `TitleMakerTests`, `ContentHasherTests` et `MemoryValidationTests`, tous au vert. En cas d'échec : corriger, committer (`fix(core): …`) et relancer.

---

### Task 5: Base de données et schéma v1 (EngramStore)

**Files:**
- Modify: `Packages/EngramKit/Package.swift`
- Create: `Packages/EngramKit/Sources/EngramStore/AppDatabase.swift`
- Create: `Packages/EngramKit/Sources/EngramStore/Schema.swift`
- Create: `Packages/EngramKit/Sources/EngramStore/Records.swift`
- Test: `Packages/EngramKit/Tests/EngramStoreTests/Fixtures.swift`
- Test: `Packages/EngramKit/Tests/EngramStoreTests/SchemaTests.swift`

**Interfaces:**
- Consumes: les types de la tâche 4.
- Produces :
  - `public struct AppDatabase: Sendable`, avec :
    - `writer: any DatabaseWriter` et `init(_ writer: any DatabaseWriter) throws` (applique les migrations) ;
    - `static makeConfiguration() -> Configuration`, `static openOnDisk(fileManager:) throws -> AppDatabase` et `static inMemory() throws -> AppDatabase` ;
    - `stream<Value: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> Value) -> AsyncThrowingStream<Value, any Error>`.
  - `enum Schema` avec `migrator: DatabaseMigrator` (migration `v1_initial`).
  - Conformités GRDB (`FetchableRecord`, `PersistableRecord`) de `Source` (table `source`), `Memory` (`memory`), `MemoryVersion` (`memory_version`), `EngramCategory` (`category`), `EngramTag` (`tag`), `CategoryAssignment` (`memory_category`) et `TagAssignment` (`memory_tag`).
  - Conformité `DatabaseValueConvertible` de tous les enums de la tâche 4.
  - Les identifiants (UUID) sont stockés en BLOB de 16 octets (stratégie GRDB par défaut). Les dates sont au format texte UTC `yyyy-MM-dd HH:mm:ss.SSS`.

- [ ] **Step 1: Déclarer le module Store dans le paquet**

Remplacer tout le contenu de `Packages/EngramKit/Package.swift` par :

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngramKit",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "EngramCore", targets: ["EngramCore"]),
        .library(name: "EngramStore", targets: ["EngramStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "EngramCore"),
        .target(
            name: "EngramStore",
            dependencies: ["EngramCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "EngramTesting", dependencies: ["EngramCore"]),
        .testTarget(name: "EngramCoreTests", dependencies: ["EngramCore", "EngramTesting"]),
        .testTarget(
            name: "EngramStoreTests",
            dependencies: ["EngramStore", "EngramCore", "EngramTesting", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
```

- [ ] **Step 2: Écrire les tests du schéma (échec attendu)**

`Tests/EngramStoreTests/Fixtures.swift` :

```swift
import EngramCore
import Foundation

/// Données de test fictives et neutres.
enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func source(text: String = "Acheter du lait", at date: Date = Fixtures.date) -> Source {
        Source(kind: .text, originalText: text, contentHash: ContentHasher.textHash(text),
               capturedAt: date, createdAt: date, updatedAt: date)
    }

    static func memory(sourceID: UUID, title: String = "Acheter du lait", content: String = "Acheter du lait",
                       status: MemoryStatus = .unsorted, at date: Date = Fixtures.date) -> Memory {
        Memory(draft: MemoryDraft(sourceID: sourceID, excerpt: content, title: title, content: content,
                                  status: status, analysisVersion: "test"),
               capturedAt: date, now: date)
    }
}
```

`Tests/EngramStoreTests/SchemaTests.swift` :

```swift
import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct SchemaTests {
    @Test func createsAllTables() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            for table in ["source", "memory", "memory_version", "category", "memory_category", "tag",
                          "memory_tag", "embedding", "memory_fts", "processing_job", "change_log", "setting"] {
                #expect(try db.tableExists(table), "table manquante : \(table)")
            }
            #expect(try Schema.migrator.hasCompletedMigrations(db))
        }
    }

    @Test func migratingTwiceIsHarmless() throws {
        let database = try AppDatabase.inMemory()
        _ = try AppDatabase(database.writer)
    }

    @Test func memoryRequiresAnExistingSource() throws {
        let database = try AppDatabase.inMemory()
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try Fixtures.memory(sourceID: UUID()).insert(db) }
        }
    }

    @Test func rejectsUnknownStatus() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in try Fixtures.source().insert(db) }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE source SET processing_status = 'bogus'")
            }
        }
    }

    @Test func trashedMemoryMustHaveTrashedAt() throws {
        let database = try AppDatabase.inMemory()
        let source = Fixtures.source()
        try database.writer.write { db in try source.insert(db) }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try Fixtures.memory(sourceID: source.id, status: .trashed).insert(db)
            }
        }
    }

    @Test func fullTextIndexFollowsMemoryChanges() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            let source = Fixtures.source()
            try source.insert(db)
            var memory = Fixtures.memory(sourceID: source.id, title: "Réunion budget", content: "Préparer le budget")
            try memory.insert(db)
            let count = { (term: String) throws -> Int in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM memory_fts WHERE memory_fts MATCH ?", arguments: [term]) ?? -1
            }
            #expect(try count("reunion") == 1)
            memory.title = "Rendez-vous dentiste"
            try memory.update(db)
            #expect(try count("reunion") == 0)
            #expect(try count("dentiste") == 1)
            _ = try memory.delete(db)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM memory_fts") == 0)
        }
    }

    @Test func changeLogRecordsMutations() throws {
        let database = try AppDatabase.inMemory()
        let source = Fixtures.source()
        try database.writer.write { db in try source.insert(db) }
        let rows = try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT entity, op FROM change_log ORDER BY seq")
        }
        #expect(rows.count == 1)
        let entity: String? = rows.first?["entity"]
        let op: String? = rows.first?["op"]
        #expect(entity == "source")
        #expect(op == "insert")
    }

    @Test func embeddingsDisappearWithTheirMemory() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            let source = Fixtures.source()
            try source.insert(db)
            let memory = Fixtures.memory(sourceID: source.id)
            try memory.insert(db)
            try db.execute(sql: """
                INSERT INTO embedding(id, owner_kind, owner_id, model, dimensions, vector, input_hash, created_at)
                VALUES (?, 'memory', ?, 'test', 2, ?, 'h', ?)
                """, arguments: [UUID(), memory.id, Data(count: 8), Fixtures.date])
            _ = try memory.delete(db)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM embedding") == 0)
        }
    }

    @Test func activeSiblingCategoriesCannotShareANormalizedName() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try EngramCategory(name: "Voyages", parentID: nil, origin: .seed, now: Fixtures.date).insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try EngramCategory(name: "voyage", parentID: nil, origin: .ai, now: Fixtures.date).insert(db)
            }
        }
        try database.writer.write { db in
            try EngramCategory(name: "voyage", parentID: nil, origin: .ai, status: .archived, now: Fixtures.date).insert(db)
        }
    }

    @Test func dataSurvivesReopeningTheFile() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("engram.sqlite").path
        do {
            let database = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
            try database.writer.write { db in try Fixtures.source().insert(db) }
        }
        let reopened = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
        #expect(try reopened.writer.read { db in try Source.fetchCount(db) } == 1)
    }
}
```

- [ ] **Step 3: Vérifier l'échec**

```bash
git add Packages/EngramKit
git commit -m "test(store): schéma v1 (échec attendu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : FAIL dans `package-tests` avec `cannot find 'AppDatabase' in scope`. Le module `EngramStore` n'a pas encore de sources : SwiftPM peut aussi signaler une cible sans fichiers, ce qui est un échec attendu pour la même raison.

- [ ] **Step 4: Écrire l'implémentation**

`Sources/EngramStore/AppDatabase.swift` :

```swift
import EngramCore
import Foundation
import GRDB

/// Accès à la base SQLite d'Engram.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    /// Ouvre la base et applique les migrations manquantes. Ne supprime jamais de données.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Schema.migrator.migrate(writer)
    }

    public static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "Engram"
        return configuration
    }

    /// Base de l'app, dans Application Support/Engram, protégée par la Data Protection d'iOS.
    public static func openOnDisk(fileManager: FileManager = .default) throws -> AppDatabase {
        let directory = try StorageLocation.engramDirectory(fileManager: fileManager)
        let url = directory.appendingPathComponent("engram.sqlite")
        return try AppDatabase(DatabasePool(path: url.path, configuration: makeConfiguration()))
    }

    /// Base en mémoire, pour les tests.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    /// Flux de valeurs recalculées à chaque modification des tables lues par `fetch`.
    public func stream<Value: Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, any Error> {
        let writer = self.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in ValueObservation.tracking(fetch).values(in: writer) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum StorageLocation {
    /// Dossier Application Support/Engram. Sur iOS, les fichiers créés dedans héritent de la protection
    /// « jusqu'à la première authentification » (lisibles en arrière-plan une fois l'iPhone déverrouillé).
    static func engramDirectory(fileManager: FileManager) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Engram", isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        if fileManager.fileExists(atPath: directory.path) {
            if !attributes.isEmpty { try fileManager.setAttributes(attributes, ofItemAtPath: directory.path) }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        }
        return directory
    }
}
```

`Sources/EngramStore/Schema.swift` :

```swift
import GRDB

/// Schéma de la base. Une migration publiée n'est JAMAIS modifiée : on en ajoute une nouvelle.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: v1Tables)
            try db.execute(sql: v1FullText)
            try createChangeLogTriggers(db)
        }
        return migrator
    }

    /// Tables suivies par le journal des changements, avec la colonne qui identifie l'entité.
    static let trackedTables: [(table: String, idColumn: String)] = [
        ("source", "id"), ("memory", "id"), ("category", "id"), ("tag", "id"),
        ("memory_category", "memory_id"), ("memory_tag", "memory_id"),
    ]

    static func createChangeLogTriggers(_ db: Database) throws {
        for (table, idColumn) in trackedTables {
            for (op, row) in [("insert", "new"), ("update", "new"), ("delete", "old")] {
                try db.execute(sql: """
                    CREATE TRIGGER \(table)_log_\(op) AFTER \(op.uppercased()) ON \(table) BEGIN
                      INSERT INTO change_log(entity, entity_id, op, changed_at)
                      VALUES ('\(table)', \(row).\(idColumn), '\(op)', strftime('%Y-%m-%d %H:%M:%f', 'now'));
                    END;
                    """)
            }
        }
    }

    static let v1Tables = """
        CREATE TABLE source (
          id BLOB PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL CHECK (kind IN ('voice','text')),
          audio_path TEXT,
          audio_duration REAL,
          original_text TEXT,
          corrected_text TEXT,
          languages TEXT NOT NULL DEFAULT '[]',
          transcription_engine TEXT,
          content_hash TEXT NOT NULL,
          captured_at DATETIME NOT NULL,
          processing_status TEXT NOT NULL CHECK (processing_status IN
            ('pending','transcribing','analyzing','classifying','indexing','done','waiting','failed')),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        );
        CREATE INDEX source_content_hash ON source(content_hash);
        CREATE INDEX source_captured_at ON source(captured_at);

        CREATE TABLE memory (
          id BLOB PRIMARY KEY NOT NULL,
          source_id BLOB NOT NULL REFERENCES source(id) ON DELETE RESTRICT,
          excerpt TEXT NOT NULL,
          span_start INTEGER,
          span_end INTEGER,
          span_text_version TEXT NOT NULL DEFAULT 'original' CHECK (span_text_version IN ('original','corrected')),
          title TEXT NOT NULL CHECK (length(trim(title)) > 0),
          summary TEXT,
          content TEXT NOT NULL,
          kind TEXT CHECK (kind IN ('idea','task','appointment','decision','preference','info','other')),
          memory_type TEXT,
          status TEXT NOT NULL CHECK (status IN ('active','unsorted','archived','trashed')),
          confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
          suggested_topic TEXT,
          mentioned_dates TEXT NOT NULL DEFAULT '[]',
          user_edited INTEGER NOT NULL DEFAULT 0 CHECK (user_edited IN (0,1)),
          possible_duplicate_of BLOB REFERENCES memory(id) ON DELETE SET NULL,
          analysis_version TEXT NOT NULL,
          captured_at DATETIME NOT NULL,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          trashed_at DATETIME,
          version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
          CHECK ((status = 'trashed') = (trashed_at IS NOT NULL))
        );
        CREATE INDEX memory_status ON memory(status);
        CREATE INDEX memory_source ON memory(source_id);
        CREATE INDEX memory_captured_at ON memory(captured_at);

        CREATE TABLE memory_version (
          id BLOB PRIMARY KEY NOT NULL,
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          version INTEGER NOT NULL,
          snapshot TEXT NOT NULL,
          changed_by TEXT NOT NULL CHECK (changed_by IN ('user','ai','system')),
          change_reason TEXT,
          created_at DATETIME NOT NULL,
          UNIQUE (memory_id, version)
        );

        CREATE TABLE category (
          id BLOB PRIMARY KEY NOT NULL,
          name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          normalized_name TEXT NOT NULL CHECK (length(normalized_name) > 0),
          description TEXT,
          parent_id BLOB REFERENCES category(id) ON DELETE RESTRICT,
          origin TEXT NOT NULL CHECK (origin IN ('seed','ai','user')),
          status TEXT NOT NULL CHECK (status IN ('active','archived')),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        );
        CREATE UNIQUE INDEX category_unique_active_name
          ON category(ifnull(parent_id, x''), normalized_name) WHERE status = 'active';
        CREATE INDEX category_parent ON category(parent_id);

        CREATE TABLE memory_category (
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          category_id BLOB NOT NULL REFERENCES category(id) ON DELETE CASCADE,
          origin TEXT NOT NULL CHECK (origin IN ('ai','user')),
          confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
          confirmed INTEGER NOT NULL DEFAULT 0 CHECK (confirmed IN (0,1)),
          rejected INTEGER NOT NULL DEFAULT 0 CHECK (rejected IN (0,1)),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (memory_id, category_id),
          CHECK (NOT (confirmed = 1 AND rejected = 1))
        );
        CREATE INDEX memory_category_category ON memory_category(category_id);

        CREATE TABLE tag (
          id BLOB PRIMARY KEY NOT NULL,
          name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          normalized_name TEXT NOT NULL UNIQUE CHECK (length(normalized_name) > 0),
          origin TEXT NOT NULL CHECK (origin IN ('seed','ai','user')),
          created_at DATETIME NOT NULL
        );

        CREATE TABLE memory_tag (
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          tag_id BLOB NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
          origin TEXT NOT NULL CHECK (origin IN ('ai','user')),
          confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
          confirmed INTEGER NOT NULL DEFAULT 0 CHECK (confirmed IN (0,1)),
          rejected INTEGER NOT NULL DEFAULT 0 CHECK (rejected IN (0,1)),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (memory_id, tag_id),
          CHECK (NOT (confirmed = 1 AND rejected = 1))
        );
        CREATE INDEX memory_tag_tag ON memory_tag(tag_id);

        CREATE TABLE embedding (
          id BLOB PRIMARY KEY NOT NULL,
          owner_kind TEXT NOT NULL CHECK (owner_kind IN ('memory','category')),
          owner_id BLOB NOT NULL,
          model TEXT NOT NULL,
          dimensions INTEGER NOT NULL CHECK (dimensions > 0),
          vector BLOB NOT NULL,
          input_hash TEXT NOT NULL,
          created_at DATETIME NOT NULL,
          UNIQUE (owner_kind, owner_id, model)
        );
        CREATE TRIGGER memory_embedding_cleanup AFTER DELETE ON memory BEGIN
          DELETE FROM embedding WHERE owner_kind = 'memory' AND owner_id = old.id;
        END;
        CREATE TRIGGER category_embedding_cleanup AFTER DELETE ON category BEGIN
          DELETE FROM embedding WHERE owner_kind = 'category' AND owner_id = old.id;
        END;

        CREATE TABLE processing_job (
          id BLOB PRIMARY KEY NOT NULL,
          source_id BLOB NOT NULL REFERENCES source(id) ON DELETE CASCADE,
          step TEXT NOT NULL CHECK (step IN ('transcribe','analyze','classify','index')),
          status TEXT NOT NULL CHECK (status IN ('queued','running','succeeded','waiting','failed')),
          attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
          max_attempts INTEGER NOT NULL DEFAULT 3 CHECK (max_attempts >= 1),
          next_attempt_at DATETIME,
          last_error TEXT,
          idempotency_key TEXT NOT NULL UNIQUE,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        );
        CREATE INDEX processing_job_status ON processing_job(status, next_attempt_at);

        CREATE TABLE change_log (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          entity TEXT NOT NULL,
          entity_id BLOB NOT NULL,
          op TEXT NOT NULL CHECK (op IN ('insert','update','delete')),
          changed_at DATETIME NOT NULL
        );

        CREATE TABLE setting (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL,
          updated_at DATETIME NOT NULL
        );
        """

    /// Index plein texte : sa propre copie du texte, identifiée par `memory_id`,
    /// pour ne pas dépendre du rowid (qu'un VACUUM peut changer).
    static let v1FullText = """
        CREATE VIRTUAL TABLE memory_fts USING fts5(
          memory_id UNINDEXED, title, summary, content, excerpt,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER memory_fts_insert AFTER INSERT ON memory BEGIN
          INSERT INTO memory_fts(memory_id, title, summary, content, excerpt)
          VALUES (new.id, new.title, ifnull(new.summary, ''), new.content, new.excerpt);
        END;
        CREATE TRIGGER memory_fts_delete AFTER DELETE ON memory BEGIN
          DELETE FROM memory_fts WHERE memory_id = old.id;
        END;
        CREATE TRIGGER memory_fts_update AFTER UPDATE OF title, summary, content, excerpt ON memory BEGIN
          DELETE FROM memory_fts WHERE memory_id = old.id;
          INSERT INTO memory_fts(memory_id, title, summary, content, excerpt)
          VALUES (new.id, new.title, ifnull(new.summary, ''), new.content, new.excerpt);
        END;
        """
}
```

`Sources/EngramStore/Records.swift` :

```swift
import EngramCore
import GRDB

// Persistance GRDB des types du domaine (encodage Codable, clés snake_case définies dans EngramCore).

extension Source: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "source" }
}

extension Memory: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory" }
}

extension MemoryVersion: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory_version" }
}

extension EngramCategory: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "category" }
}

extension EngramTag: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "tag" }
}

extension CategoryAssignment: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory_category" }
}

extension TagAssignment: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory_tag" }
}

extension SourceKind: @retroactive DatabaseValueConvertible {}
extension ProcessingStatus: @retroactive DatabaseValueConvertible {}
extension MemoryStatus: @retroactive DatabaseValueConvertible {}
extension MemoryKind: @retroactive DatabaseValueConvertible {}
extension TextVersion: @retroactive DatabaseValueConvertible {}
extension Origin: @retroactive DatabaseValueConvertible {}
extension AssignmentOrigin: @retroactive DatabaseValueConvertible {}
extension ChangeActor: @retroactive DatabaseValueConvertible {}
extension CategoryStatus: @retroactive DatabaseValueConvertible {}
```

- [ ] **Step 5: Commit**

```bash
git add Packages/EngramKit
git commit -m "feat(store): base SQLite, schéma v1, plein texte, journal des changements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Vérifier que les tests passent**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. Les 10 tests de `SchemaTests` passent. Le job `ipa` reste vert : l'app ne dépend pas encore de `EngramStore`.

---

### Task 6: Sources, souvenirs, versions et suppression (MemoryStore)

**Files:**
- Create: `Packages/EngramKit/Sources/EngramStore/StoreError.swift`
- Create: `Packages/EngramKit/Sources/EngramStore/SortingStatus.swift`
- Create: `Packages/EngramKit/Sources/EngramStore/MemoryStore.swift`
- Test: `Packages/EngramKit/Tests/EngramStoreTests/StoreTestEnvironment.swift`
- Test: `Packages/EngramKit/Tests/EngramStoreTests/MemoryStoreTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, les records et les types de la tâche 4.
- Produces :
  - `public enum StoreError: Error, Equatable, Sendable { case emptyContent, notFound, protectedByUser, nameConflict, invalidName, invalidOperation(String) }`
  - `enum SortingStatus` avec `static func hasValidCategory(_ db: Database, memoryID: UUID) throws -> Bool` et `static func refresh(_ db: Database, memoryID: UUID, now: Date) throws`.
  - `public struct MemoryStore: Sendable` — `init(database: AppDatabase, dates: any DateProvider = SystemDateProvider())`, `database`, `dates`.
    - Constantes : `static technicalDuplicateWindow = 600`, `static interimAnalysisVersion = "interim-none"`.
    - Types : `enum SourceInsertion { created(Source), duplicate(of: Source) }` · `enum TextNoteSave { saved(Memory), duplicate(of: Source) }` · `struct PermanentDeletion { memoryID, deletedSourceID: UUID?, audioPathToRemove: String? }`.
    - Écriture :
      - `insertTextSource(_:) throws -> SourceInsertion`
      - `saveTextNoteWithoutAnalysis(_:) throws -> TextNoteSave`
      - `createMemory(_:actor:) throws -> Memory`
      - `updateMemory(_:with:actor:reason:) throws -> Memory`
      - `setStatus(_:for:actor:) throws -> Memory`
      - `restore(_:actor:) throws -> Memory`
      - `restoreVersion(_:of:) throws -> Memory`
      - `deletePermanently(_:) throws -> PermanentDeletion`
    - Lecture :
      - `source(id:) throws -> Source?`
      - `memory(id:) throws -> Memory?`
      - `memories(statuses:limit:) throws -> [Memory]`
      - `memories(ids:) throws -> [Memory]` (dans l'ordre des ids)
      - `versions(of:) throws -> [MemoryVersion]` (la plus récente d'abord)
      - `memoriesStream(statuses:limit:) -> AsyncThrowingStream<[Memory], any Error>`
    - Variantes internes `insertTextSource(_ db:text:now:)` et `createMemory(_ db:draft:actor:now:)`.
  - Tests : `StoreTestEnvironment` (`database`, `dates: TestDateProvider`, `memories: MemoryStore`, `saveNote(_:) -> Memory`).

- [ ] **Step 1: Écrire les tests (échec attendu)**

`Tests/EngramStoreTests/StoreTestEnvironment.swift` :

```swift
import EngramCore
import EngramTesting
import Foundation
@testable import EngramStore

/// Base en mémoire + services, avec une horloge contrôlable.
struct StoreTestEnvironment {
    let database: AppDatabase
    let dates: TestDateProvider
    let memories: MemoryStore

    init() throws {
        database = try AppDatabase.inMemory()
        dates = TestDateProvider(Fixtures.date)
        memories = MemoryStore(database: database, dates: dates)
    }

    @discardableResult
    func saveNote(_ text: String) throws -> Memory {
        guard case .saved(let memory) = try memories.saveTextNoteWithoutAnalysis(text) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        return memory
    }
}

enum StoreTestFailure: Error { case unexpectedDuplicate }
```

`Tests/EngramStoreTests/MemoryStoreTests.swift` :

```swift
import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct MemoryStoreTests {
    @Test func savesTextNoteAsUnsortedMemory() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("  Acheter du lait\net du pain  ")
        #expect(memory.title == "Acheter du lait")
        #expect(memory.content == "Acheter du lait\net du pain")
        #expect(memory.excerpt == memory.content)
        #expect(memory.status == .unsorted)
        #expect(memory.version == 1)
        #expect(memory.analysisVersion == MemoryStore.interimAnalysisVersion)
        let source = try #require(try env.memories.source(id: memory.sourceID))
        #expect(source.kind == .text)
        #expect(source.originalText == "Acheter du lait\net du pain")
        #expect(source.processingStatus == .waiting)
        #expect(try env.memories.versions(of: memory.id).map(\.version) == [1])
    }

    @Test(arguments: ["", "   ", "\n\n\t "])
    func rejectsEmptyNotes(text: String) throws {
        let env = try StoreTestEnvironment()
        #expect(throws: StoreError.emptyContent) { try env.memories.saveTextNoteWithoutAnalysis(text) }
        #expect(try env.memories.memories(statuses: Set(MemoryStatus.allCases)).isEmpty)
        #expect(try env.database.writer.read { db in try Source.fetchCount(db) } == 0)
    }

    @Test func sameTextWithinTenMinutesIsATechnicalDuplicate() throws {
        let env = try StoreTestEnvironment()
        let first = try env.saveNote("Appeler le garage")
        env.dates.advance(by: 9 * 60)
        guard case .duplicate(let existing) = try env.memories.saveTextNoteWithoutAnalysis("Appeler   le garage ") else {
            Issue.record("un doublon technique était attendu")
            return
        }
        #expect(existing.id == first.sourceID)
        env.dates.advance(by: 2 * 60)
        guard case .saved = try env.memories.saveTextNoteWithoutAnalysis("Appeler le garage") else {
            Issue.record("après 11 minutes, une nouvelle note était attendue")
            return
        }
        #expect(try env.memories.memories(statuses: [.unsorted]).count == 2)
    }

    @Test func userEditCreatesAVersionAndProtectsFromAI() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Idée app")
        env.dates.advance(by: 60)
        let edited = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Idée : app de mémoire"), actor: .user)
        #expect(edited.version == 2)
        #expect(edited.userEdited)
        #expect(try env.memories.versions(of: memory.id).map(\.version) == [2, 1])
        #expect(throws: StoreError.protectedByUser) {
            try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Titre proposé par l'IA"), actor: .ai)
        }
    }

    @Test func editWithoutChangeKeepsTheVersion() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Rien ne change")
        let same = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Rien ne change"), actor: .user)
        #expect(same.version == 1)
        #expect(try env.memories.versions(of: memory.id).count == 1)
    }

    @Test func invalidEditIsRolledBack() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Titre valide")
        #expect(throws: MemoryValidationError.emptyTitle) {
            try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "   "), actor: .user)
        }
        let stored = try #require(try env.memories.memory(id: memory.id))
        #expect(stored.title == "Titre valide")
        #expect(stored.version == 1)
    }

    @Test func trashThenRestoreReturnsToUnsorted() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Note à jeter")
        let trashed = try env.memories.setStatus(.trashed, for: memory.id, actor: .user)
        #expect(trashed.status == .trashed)
        #expect(trashed.trashedAt == env.dates.now())
        let restored = try env.memories.restore(memory.id)
        #expect(restored.status == .unsorted)
        #expect(restored.trashedAt == nil)
        #expect(try env.memories.versions(of: memory.id).count == 3)
    }

    @Test func restoringAnOldVersionCreatesANewOne() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Version un")
        _ = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Version deux", content: "Version deux"), actor: .user)
        let restored = try env.memories.restoreVersion(1, of: memory.id)
        #expect(restored.title == "Version un")
        #expect(restored.content == "Version un")
        #expect(restored.version == 3)
    }

    @Test func permanentDeletionRequiresTheTrash() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("À garder")
        #expect(throws: StoreError.self) { try env.memories.deletePermanently(memory.id) }
        #expect(try env.memories.memory(id: memory.id) != nil)
    }

    @Test func sharedSourceSurvivesUntilItsLastMemoryIsDeleted() throws {
        let env = try StoreTestEnvironment()
        let first = try env.saveNote("Rendez-vous vendredi, acheter un ordinateur")
        let second = try env.memories.createMemory(
            MemoryDraft(sourceID: first.sourceID, excerpt: "acheter un ordinateur", title: "Acheter un ordinateur",
                        content: "Acheter un ordinateur", analysisVersion: "test"),
            actor: .ai)
        try env.database.writer.write { db in
            try db.execute(sql: "UPDATE source SET audio_path = ? WHERE id = ?", arguments: ["note.caf", first.sourceID])
        }
        _ = try env.memories.setStatus(.trashed, for: first.id, actor: .user)
        let firstDeletion = try env.memories.deletePermanently(first.id)
        #expect(firstDeletion.deletedSourceID == nil)
        #expect(firstDeletion.audioPathToRemove == nil)
        #expect(try env.memories.source(id: first.sourceID) != nil)

        _ = try env.memories.setStatus(.trashed, for: second.id, actor: .user)
        let secondDeletion = try env.memories.deletePermanently(second.id)
        #expect(secondDeletion.deletedSourceID == first.sourceID)
        #expect(secondDeletion.audioPathToRemove == "note.caf")
        #expect(try env.memories.source(id: first.sourceID) == nil)
        #expect(try env.memories.versions(of: second.id).isEmpty)
    }

    @Test func memoriesByIDsKeepTheRequestedOrder() throws {
        let env = try StoreTestEnvironment()
        let a = try env.saveNote("Alpha")
        let b = try env.saveNote("Bravo")
        let c = try env.saveNote("Charlie")
        #expect(try env.memories.memories(ids: [c.id, a.id, b.id]).map(\.id) == [c.id, a.id, b.id])
    }

    @Test func streamEmitsAfterEachChange() async throws {
        let env = try StoreTestEnvironment()
        var iterator = env.memories.memoriesStream(statuses: [.unsorted]).makeAsyncIterator()
        #expect(try await iterator.next()?.count == 0)
        try env.saveNote("Première pensée")
        #expect(try await iterator.next()?.count == 1)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

```bash
git add Packages/EngramKit/Tests
git commit -m "test(store): MemoryStore (échec attendu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : FAIL dans `package-tests` avec `cannot find 'MemoryStore' in scope` et `cannot find 'StoreError' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/EngramStore/StoreError.swift` :

```swift
/// Erreurs métier du stockage (les erreurs SQLite restent des `DatabaseError`).
public enum StoreError: Error, Equatable, Sendable {
    /// Le texte est vide ou ne contient que des espaces.
    case emptyContent
    /// L'élément demandé n'existe pas (ou plus).
    case notFound
    /// L'IA a tenté de modifier ce que le propriétaire a décidé à la main.
    case protectedByUser
    /// Un élément actif porte déjà ce nom au même endroit.
    case nameConflict
    /// Le nom est vide ou trop long.
    case invalidName
    /// L'opération n'est pas permise dans l'état actuel.
    case invalidOperation(String)
}
```

`Sources/EngramStore/SortingStatus.swift` :

```swift
import EngramCore
import Foundation
import GRDB

/// Règle « À classer » : un souvenir actif sans catégorie valable repasse « À classer »,
/// un souvenir « À classer » qui reçoit une catégorie devient actif.
/// Ces passages automatiques ne créent pas de version (ils restent tracés dans `change_log`).
enum SortingStatus {
    static func hasValidCategory(_ db: Database, memoryID: UUID) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS(
              SELECT 1 FROM memory_category mc JOIN category c ON c.id = mc.category_id
              WHERE mc.memory_id = ? AND mc.rejected = 0 AND c.status = 'active')
            """, arguments: [memoryID]) ?? false
    }

    static func refresh(_ db: Database, memoryID: UUID, now: Date) throws {
        let target: MemoryStatus = try hasValidCategory(db, memoryID: memoryID) ? .active : .unsorted
        try db.execute(sql: """
            UPDATE memory SET status = ?, updated_at = ?
            WHERE id = ? AND status IN ('active','unsorted') AND status <> ?
            """, arguments: [target, now, memoryID, target])
    }
}
```

`Sources/EngramStore/MemoryStore.swift` :

```swift
import EngramCore
import Foundation
import GRDB

/// Sources et souvenirs : création, modification versionnée, statuts, suppression contrôlée.
public struct MemoryStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider

    /// Deux captures identiques à moins de 10 minutes d'écart sont un doublon technique.
    public static let technicalDuplicateWindow: TimeInterval = 10 * 60
    /// Version d'analyse des souvenirs créés avant le moteur IA (plan P2), qui les ré-analysera.
    public static let interimAnalysisVersion = "interim-none"

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    public enum SourceInsertion: Sendable, Equatable {
        case created(Source)
        case duplicate(of: Source)
    }

    public enum TextNoteSave: Sendable, Equatable {
        case saved(Memory)
        case duplicate(of: Source)
    }

    public struct PermanentDeletion: Sendable, Equatable {
        public let memoryID: UUID
        /// Renseigné si la source n'avait plus d'autre souvenir et a été supprimée.
        public let deletedSourceID: UUID?
        /// Fichier audio à effacer du disque (chemin relatif au dossier audio), le cas échéant.
        public let audioPathToRemove: String?
    }

    // MARK: - Sources

    public func insertTextSource(_ text: String) throws -> SourceInsertion {
        let now = dates.now()
        return try database.writer.write { db in try insertTextSource(db, text: text, now: now) }
    }

    func insertTextSource(_ db: Database, text: String, now: Date) throws -> SourceInsertion {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyContent }
        let hash = ContentHasher.textHash(trimmed)
        let windowStart = now.addingTimeInterval(-Self.technicalDuplicateWindow)
        if let existing = try Source
            .filter(Column("content_hash") == hash && Column("captured_at") >= windowStart)
            .order(Column("captured_at").desc)
            .fetchOne(db) {
            return .duplicate(of: existing)
        }
        let source = Source(kind: .text, originalText: trimmed, contentHash: hash,
                            capturedAt: now, createdAt: now, updatedAt: now)
        try source.insert(db)
        return .created(source)
    }

    public func source(id: UUID) throws -> Source? {
        try database.writer.read { db in try Source.fetchOne(db, key: id) }
    }

    // MARK: - Note texte sans analyse (en attendant le moteur IA du plan P2)

    /// Enregistre une note texte comme un souvenir « À classer », en une seule transaction.
    public func saveTextNoteWithoutAnalysis(_ text: String) throws -> TextNoteSave {
        let now = dates.now()
        return try database.writer.write { db in
            switch try insertTextSource(db, text: text, now: now) {
            case .duplicate(let existing):
                return .duplicate(of: existing)
            case .created(var source):
                let body = source.originalText ?? ""
                let draft = MemoryDraft(
                    sourceID: source.id, excerpt: body, spanStart: 0, spanEnd: body.utf16.count,
                    title: TitleMaker.fallbackTitle(from: body), content: body,
                    status: .unsorted, analysisVersion: Self.interimAnalysisVersion)
                let memory = try createMemory(db, draft: draft, actor: .system, now: now)
                source.processingStatus = .waiting
                source.updatedAt = now
                try source.update(db)
                return .saved(memory)
            }
        }
    }

    // MARK: - Souvenirs

    public func createMemory(_ draft: MemoryDraft, actor: ChangeActor) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in try createMemory(db, draft: draft, actor: actor, now: now) }
    }

    func createMemory(_ db: Database, draft: MemoryDraft, actor: ChangeActor, now: Date) throws -> Memory {
        try draft.validate()
        guard let source = try Source.fetchOne(db, key: draft.sourceID) else { throw StoreError.notFound }
        let memory = Memory(draft: draft, capturedAt: source.capturedAt, now: now)
        try memory.insert(db)
        try MemoryVersion(memory: memory, changedBy: actor, reason: "création", at: now).insert(db)
        return memory
    }

    /// Modifie un souvenir et crée une version. L'IA ne peut pas modifier un souvenir édité à la main.
    public func updateMemory(_ id: UUID, with edit: MemoryEdit, actor: ChangeActor, reason: String? = nil) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            if actor == .ai && memory.userEdited { throw StoreError.protectedByUser }
            guard edit.apply(to: &memory) else { return memory }
            try MemoryValidation.validate(title: memory.title, content: memory.content)
            if actor == .user { memory.userEdited = true }
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: actor, reason: reason ?? "modification", at: now).insert(db)
            return memory
        }
    }

    /// Archive, met à la corbeille ou change le statut d'un souvenir. Chaque changement crée une version.
    public func setStatus(_ status: MemoryStatus, for id: UUID, actor: ChangeActor) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            guard memory.status != status else { return memory }
            memory.status = status
            memory.trashedAt = status == .trashed ? now : nil
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: actor, reason: "statut : \(status.rawValue)", at: now).insert(db)
            return memory
        }
    }

    /// Sort un souvenir de la corbeille ou des archives : actif s'il a une catégorie, sinon « À classer ».
    public func restore(_ id: UUID, actor: ChangeActor = .user) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            guard memory.status == .trashed || memory.status == .archived else { return memory }
            memory.status = try SortingStatus.hasValidCategory(db, memoryID: id) ? .active : .unsorted
            memory.trashedAt = nil
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: actor, reason: "restauration", at: now).insert(db)
            return memory
        }
    }

    /// Restaure le texte d'une ancienne version (nouvelle version créée, souvenir marqué « modifié à la main »).
    public func restoreVersion(_ version: Int, of id: UUID) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id),
                  let old = try MemoryVersion
                    .filter(Column("memory_id") == id && Column("version") == version)
                    .fetchOne(db)
            else { throw StoreError.notFound }
            memory.title = old.snapshot.title
            memory.summary = old.snapshot.summary
            memory.content = old.snapshot.content
            memory.kind = old.snapshot.kind
            memory.userEdited = true
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: .user, reason: "restauration de la version \(version)", at: now).insert(db)
            return memory
        }
    }

    /// Supprime définitivement un souvenir **qui est à la corbeille**, avec ses versions, liens, index et embedding.
    /// La source est supprimée si plus aucun souvenir ne l'utilise.
    public func deletePermanently(_ id: UUID) throws -> PermanentDeletion {
        try database.writer.write { db in
            guard let memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            guard memory.status == .trashed else {
                throw StoreError.invalidOperation("mettre le souvenir à la corbeille avant de le supprimer définitivement")
            }
            _ = try memory.delete(db)
            let remaining = try Memory.filter(Column("source_id") == memory.sourceID).fetchCount(db)
            guard remaining == 0, let source = try Source.fetchOne(db, key: memory.sourceID) else {
                return PermanentDeletion(memoryID: id, deletedSourceID: nil, audioPathToRemove: nil)
            }
            _ = try source.delete(db)
            return PermanentDeletion(memoryID: id, deletedSourceID: source.id, audioPathToRemove: source.audioPath)
        }
    }

    // MARK: - Lecture

    public func memory(id: UUID) throws -> Memory? {
        try database.writer.read { db in try Memory.fetchOne(db, key: id) }
    }

    public func memories(statuses: Set<MemoryStatus>, limit: Int = 500) throws -> [Memory] {
        try database.writer.read { db in
            try Memory.filter(statuses.contains(Column("status")))
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Souvenirs correspondant aux identifiants, dans le même ordre (les absents sont ignorés).
    public func memories(ids: [UUID]) throws -> [Memory] {
        guard !ids.isEmpty else { return [] }
        let found = try database.writer.read { db in
            try Memory.filter(ids.contains(Column("id"))).fetchAll(db)
        }
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func versions(of id: UUID) throws -> [MemoryVersion] {
        try database.writer.read { db in
            try MemoryVersion.filter(Column("memory_id") == id).order(Column("version").desc).fetchAll(db)
        }
    }

    /// Liste observée : une nouvelle valeur à chaque modification.
    public func memoriesStream(statuses: Set<MemoryStatus>, limit: Int = 500) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in
            try Memory.filter(statuses.contains(Column("status")))
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Packages/EngramKit
git commit -m "feat(store): sources, souvenirs versionnés, corbeille et suppression définitive

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Vérifier que les tests passent**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. Les 14 cas de `MemoryStoreTests` passent (le test paramétré compte 3 cas), ainsi que tous les précédents.

---

### Task 7: Catégories, tags et règle « le propriétaire décide » (CategoryStore)

**Files:**
- Create: `Packages/EngramKit/Sources/EngramStore/AssignmentRules.swift`
- Create: `Packages/EngramKit/Sources/EngramStore/CategoryStore.swift`
- Modify: `Packages/EngramKit/Tests/EngramStoreTests/StoreTestEnvironment.swift` (ajout de `categories`)
- Test: `Packages/EngramKit/Tests/EngramStoreTests/CategoryStoreTests.swift`

**Interfaces:**
- Consumes: `MemoryStore`, `SortingStatus`, `StoreError` et les records (tâches 5-6).
- Produces :
  - `public enum AssignmentOutcome: Sendable, Equatable { case assigned, alreadyAssigned, skippedRejectedByUser }`
  - `protocol AssignmentRow` (conformé par `CategoryAssignment` et `TagAssignment`) et `enum AssignmentRules` avec `assign`, `remove` et `confirm`.
  - `public struct CategoryStore: Sendable` — `init(database:dates:)`.
    - Constantes : `static defaultRootNames: [String]`, `static maxNameLength = 40`, `static maxTagLength = 30`.
    - Types : `enum Creation { created(EngramCategory), existing(EngramCategory); var category }` · `struct CategorySummary { category, depth, memoryCount; id }` · `struct LibrarySummary { categories, unsortedCount, archivedCount, trashedCount }`.
    - Catégories :
      - `seedDefaultsIfNeeded() throws`
      - `createCategory(name:parentID:origin:description:) throws -> Creation`
      - `rename(_:to:) throws -> EngramCategory`
      - `archiveCategory(_:) throws`
      - `merge(_:into:) throws`
      - `activeCategories() throws -> [EngramCategory]`
      - `categories(for:) throws -> [EngramCategory]`
      - `descendantIDs(of:) throws -> [UUID]` (inclut l'id lui-même)
    - Liens avec les catégories :
      - `assign(memoryID:categoryID:origin:confidence:) throws -> AssignmentOutcome`
      - `confirm(memoryID:categoryID:) throws`
      - `removeAssignment(memoryID:categoryID:by:) throws`
    - Tags :
      - `upsertTag(name:origin:) throws -> EngramTag`
      - `tag(memoryID:tagID:origin:confidence:) throws -> AssignmentOutcome`
      - `untag(memoryID:tagID:by:) throws`
      - `tags(for:) throws -> [EngramTag]`
    - Bibliothèque :
      - `librarySummaryStream() -> AsyncThrowingStream<LibrarySummary, any Error>`
      - `memoriesStream(inCategory:) -> AsyncThrowingStream<[Memory], any Error>`

- [ ] **Step 1: Mettre à jour l'environnement de test**

Remplacer tout le contenu de `Tests/EngramStoreTests/StoreTestEnvironment.swift` par :

```swift
import EngramCore
import EngramTesting
import Foundation
@testable import EngramStore

/// Base en mémoire + services, avec une horloge contrôlable.
struct StoreTestEnvironment {
    let database: AppDatabase
    let dates: TestDateProvider
    let memories: MemoryStore
    let categories: CategoryStore

    init() throws {
        database = try AppDatabase.inMemory()
        dates = TestDateProvider(Fixtures.date)
        memories = MemoryStore(database: database, dates: dates)
        categories = CategoryStore(database: database, dates: dates)
    }

    @discardableResult
    func saveNote(_ text: String) throws -> Memory {
        guard case .saved(let memory) = try memories.saveTextNoteWithoutAnalysis(text) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        return memory
    }

    func status(of memory: Memory) throws -> MemoryStatus? {
        try memories.memory(id: memory.id)?.status
    }
}

enum StoreTestFailure: Error { case unexpectedDuplicate }
```

- [ ] **Step 2: Écrire les tests (échec attendu)**

`Tests/EngramStoreTests/CategoryStoreTests.swift` :

```swift
import EngramCore
import Foundation
import Testing
@testable import EngramStore

struct CategoryStoreTests {
    @Test func seedsDefaultRootsOnlyOnce() throws {
        let env = try StoreTestEnvironment()
        try env.categories.seedDefaultsIfNeeded()
        try env.categories.seedDefaultsIfNeeded()
        let names = try env.categories.activeCategories().map(\.name)
        #expect(Set(names) == Set(CategoryStore.defaultRootNames))
        #expect(names.count == 9)
    }

    @Test func archivedSeedIsNotRecreated() throws {
        let env = try StoreTestEnvironment()
        try env.categories.seedDefaultsIfNeeded()
        let voyages = try #require(try env.categories.activeCategories().first { $0.name == "Voyages" })
        try env.categories.archiveCategory(voyages.id)
        try env.categories.seedDefaultsIfNeeded()
        #expect(try env.categories.activeCategories().contains { $0.name == "Voyages" } == false)
    }

    @Test(arguments: ["voyage", "VOYAGES", "  Voyagés ", "voyages"])
    func equivalentNamesReuseTheExistingCategory(name: String) throws {
        let env = try StoreTestEnvironment()
        let original = try env.categories.createCategory(name: "Voyages", parentID: nil, origin: .user).category
        guard case .existing(let reused) = try env.categories.createCategory(name: name, parentID: nil, origin: .ai) else {
            Issue.record("« \(name) » aurait dû réutiliser « Voyages »")
            return
        }
        #expect(reused.id == original.id)
    }

    @Test func sameNameIsAllowedUnderDifferentParents() throws {
        let env = try StoreTestEnvironment()
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .user).category
        let child = try env.categories.createCategory(name: "Course à pied", parentID: sante.id, origin: .ai)
        let root = try env.categories.createCategory(name: "Course à pied", parentID: nil, origin: .user)
        guard case .created = child, case .created = root else {
            Issue.record("deux catégories distinctes étaient attendues")
            return
        }
        #expect(try env.categories.descendantIDs(of: sante.id).count == 2)
    }

    @Test func rejectsBlankOrTooLongNames() throws {
        let env = try StoreTestEnvironment()
        #expect(throws: StoreError.invalidName) { try env.categories.createCategory(name: "  !! ", parentID: nil, origin: .user) }
        #expect(throws: StoreError.invalidName) {
            try env.categories.createCategory(name: String(repeating: "x", count: 41), parentID: nil, origin: .user)
        }
    }

    @Test func renameRefusesASiblingName() throws {
        let env = try StoreTestEnvironment()
        _ = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .user)
        let perso = try env.categories.createCategory(name: "Perso", parentID: nil, origin: .user).category
        #expect(throws: StoreError.nameConflict) { try env.categories.rename(perso.id, to: "travail") }
        #expect(try env.categories.rename(perso.id, to: "Personnel").name == "Personnel")
    }

    @Test func aiAssignmentActivatesAnUnsortedMemory() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Préparer la réunion budget")
        let travail = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .seed).category
        #expect(try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .ai, confidence: 0.8) == .assigned)
        #expect(try env.status(of: memory) == .active)
        #expect(try env.categories.categories(for: memory.id).map(\.id) == [travail.id])
    }

    @Test func userRemovalIsRememberedAndBlocksTheAI() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Préparer la réunion budget")
        let travail = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .seed).category
        _ = try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .ai)
        try env.categories.removeAssignment(memoryID: memory.id, categoryID: travail.id, by: .user)
        #expect(try env.status(of: memory) == .unsorted)
        #expect(try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .ai) == .skippedRejectedByUser)
        #expect(try env.categories.categories(for: memory.id).isEmpty)
        #expect(try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .user) == .assigned)
        #expect(try env.status(of: memory) == .active)
    }

    @Test func aiCannotRemoveAConfirmedAssignment() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Facture garage")
        let finances = try env.categories.createCategory(name: "Finances", parentID: nil, origin: .seed).category
        _ = try env.categories.assign(memoryID: memory.id, categoryID: finances.id, origin: .ai)
        try env.categories.confirm(memoryID: memory.id, categoryID: finances.id)
        #expect(throws: StoreError.protectedByUser) {
            try env.categories.removeAssignment(memoryID: memory.id, categoryID: finances.id, by: .ai)
        }
    }

    @Test func archivingACategoryMovesChildrenUpAndUnsortsOrphans() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Plan de course")
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .seed).category
        let sport = try env.categories.createCategory(name: "Sport", parentID: sante.id, origin: .ai).category
        _ = try env.categories.assign(memoryID: memory.id, categoryID: sante.id, origin: .user)
        try env.categories.archiveCategory(sante.id)
        #expect(try env.status(of: memory) == .unsorted)
        let movedSport = try #require(try env.categories.activeCategories().first { $0.id == sport.id })
        #expect(movedSport.parentID == nil)
    }

    @Test func mergeMovesAssignmentsAndKeepsTheStrongestDecision() throws {
        let env = try StoreTestEnvironment()
        let both = try env.saveNote("Réservation hôtel")
        let onlyOld = try env.saveNote("Billet de train")
        let voyagesPerso = try env.categories.createCategory(name: "Voyages perso", parentID: nil, origin: .ai).category
        let voyages = try env.categories.createCategory(name: "Voyages", parentID: nil, origin: .seed).category
        _ = try env.categories.assign(memoryID: both.id, categoryID: voyagesPerso.id, origin: .user)
        _ = try env.categories.assign(memoryID: both.id, categoryID: voyages.id, origin: .ai)
        _ = try env.categories.assign(memoryID: onlyOld.id, categoryID: voyagesPerso.id, origin: .ai)
        try env.categories.merge(voyagesPerso.id, into: voyages.id)
        #expect(try env.categories.activeCategories().contains { $0.id == voyagesPerso.id } == false)
        #expect(try env.categories.categories(for: both.id).map(\.id) == [voyages.id])
        #expect(try env.categories.categories(for: onlyOld.id).map(\.id) == [voyages.id])
        #expect(throws: StoreError.protectedByUser) {
            try env.categories.removeAssignment(memoryID: both.id, categoryID: voyages.id, by: .ai)
        }
    }

    @Test func cannotMergeIntoOwnDescendant() throws {
        let env = try StoreTestEnvironment()
        let parent = try env.categories.createCategory(name: "Projets", parentID: nil, origin: .seed).category
        let child = try env.categories.createCategory(name: "Engram", parentID: parent.id, origin: .user).category
        #expect(throws: StoreError.self) { try env.categories.merge(parent.id, into: child.id) }
    }

    @Test func tagsAreDeduplicatedAndRespectUserRemoval() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Idée de widget")
        let tag = try env.categories.upsertTag(name: "Idée", origin: .ai)
        #expect(try env.categories.upsertTag(name: "idee", origin: .user).id == tag.id)
        #expect(try env.categories.tag(memoryID: memory.id, tagID: tag.id, origin: .ai) == .assigned)
        try env.categories.untag(memoryID: memory.id, tagID: tag.id, by: .user)
        #expect(try env.categories.tag(memoryID: memory.id, tagID: tag.id, origin: .ai) == .skippedRejectedByUser)
        #expect(try env.categories.tags(for: memory.id).isEmpty)
    }

    @Test func librarySummaryCountsByCategoryAndStatus() async throws {
        let env = try StoreTestEnvironment()
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .seed).category
        _ = try env.categories.createCategory(name: "Sport", parentID: sante.id, origin: .ai)
        let classed = try env.saveNote("Rendez-vous médecin")
        _ = try env.categories.assign(memoryID: classed.id, categoryID: sante.id, origin: .user)
        try env.saveNote("Pensée en vrac")
        let trashed = try env.saveNote("À jeter")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)

        var iterator = env.categories.librarySummaryStream().makeAsyncIterator()
        let summary = try #require(try await iterator.next())
        #expect(summary.unsortedCount == 1)
        #expect(summary.trashedCount == 1)
        #expect(summary.archivedCount == 0)
        #expect(summary.categories.map(\.category.name) == ["Santé", "Sport"])
        #expect(summary.categories.map(\.depth) == [0, 1])
        #expect(summary.categories.first?.memoryCount == 1)
    }
}
```

- [ ] **Step 3: Vérifier l'échec**

```bash
git add Packages/EngramKit/Tests
git commit -m "test(store): catégories, tags et règle du propriétaire (échec attendu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : FAIL dans `package-tests` avec `cannot find type 'CategoryStore' in scope`.

- [ ] **Step 4: Écrire l'implémentation**

`Sources/EngramStore/AssignmentRules.swift` :

```swift
import EngramCore
import Foundation
import GRDB

public enum AssignmentOutcome: Sendable, Equatable {
    case assigned
    case alreadyAssigned
    /// Le propriétaire avait retiré ce lien : l'IA ne le recrée pas.
    case skippedRejectedByUser
}

/// Un lien souvenir ↔ catégorie ou tag.
protocol AssignmentRow: FetchableRecord, PersistableRecord {
    var origin: AssignmentOrigin { get set }
    var confirmed: Bool { get set }
    var rejected: Bool { get set }
    var updatedAt: Date { get set }
}

extension CategoryAssignment: AssignmentRow {}
extension TagAssignment: AssignmentRow {}

/// Règle « le propriétaire décide » : l'IA n'écrase jamais un choix du propriétaire.
enum AssignmentRules {
    static func assign<Row: AssignmentRow>(
        _ db: Database, existing: Row?, makeNew: () -> Row, origin: AssignmentOrigin, now: Date
    ) throws -> AssignmentOutcome {
        guard var row = existing else {
            try makeNew().insert(db)
            return .assigned
        }
        switch origin {
        case .ai:
            return row.rejected ? .skippedRejectedByUser : .alreadyAssigned
        case .user:
            if row.origin == .user && row.confirmed { return .alreadyAssigned }
            row.origin = .user
            row.confirmed = true
            row.rejected = false
            row.updatedAt = now
            try row.update(db)
            return .assigned
        }
    }

    /// Retrait par le propriétaire : le lien est gardé comme « rejeté ». Retrait par l'IA : seulement ses propres liens non confirmés.
    static func remove<Row: AssignmentRow>(_ db: Database, row: Row, by origin: AssignmentOrigin, now: Date) throws {
        var row = row
        switch origin {
        case .user:
            row.origin = .user
            row.confirmed = false
            row.rejected = true
            row.updatedAt = now
            try row.update(db)
        case .ai:
            guard row.origin == .ai, !row.confirmed, !row.rejected else { throw StoreError.protectedByUser }
            _ = try row.delete(db)
        }
    }

    static func confirm<Row: AssignmentRow>(_ db: Database, row: Row, now: Date) throws {
        var row = row
        row.origin = .user
        row.confirmed = true
        row.rejected = false
        row.updatedAt = now
        try row.update(db)
    }
}
```

`Sources/EngramStore/CategoryStore.swift` :

```swift
import EngramCore
import Foundation
import GRDB

/// Catégories, tags et liens avec les souvenirs.
public struct CategoryStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider

    public static let defaultRootNames = [
        "Travail", "Études", "Projets", "Finances", "Santé", "Voyages", "Personnel", "Idées", "Documents",
    ]
    public static let maxNameLength = 40
    public static let maxTagLength = 30
    static let seededSettingKey = "categories.seeded.v1"

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    public enum Creation: Sendable, Equatable {
        case created(EngramCategory)
        case existing(EngramCategory)

        public var category: EngramCategory {
            switch self {
            case .created(let category), .existing(let category): category
            }
        }
    }

    public struct CategorySummary: Sendable, Hashable, Identifiable {
        public let category: EngramCategory
        public let depth: Int
        /// Souvenirs actifs ou « À classer » liés directement à cette catégorie.
        public let memoryCount: Int
        public var id: UUID { category.id }
    }

    public struct LibrarySummary: Sendable, Equatable {
        /// Catégories actives, en arbre aplati (parent puis enfants, par ordre alphabétique).
        public let categories: [CategorySummary]
        public let unsortedCount: Int
        public let archivedCount: Int
        public let trashedCount: Int
    }

    // MARK: - Catégories

    /// Crée les catégories de départ une seule fois dans la vie de la base (même si on les supprime ensuite).
    public func seedDefaultsIfNeeded() throws {
        let now = dates.now()
        try database.writer.write { db in
            let seeded = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM setting WHERE key = ?)",
                                           arguments: [Self.seededSettingKey]) ?? false
            guard !seeded else { return }
            for name in Self.defaultRootNames {
                _ = try createCategory(db, name: name, parentID: nil, origin: .seed, description: nil, now: now)
            }
            try db.execute(sql: "INSERT INTO setting(key, value, updated_at) VALUES (?, '1', ?)",
                           arguments: [Self.seededSettingKey, now])
        }
    }

    /// Crée une catégorie, ou renvoie celle qui porte déjà ce nom (accents, casse, pluriel et espaces ignorés) au même endroit.
    public func createCategory(name: String, parentID: UUID?, origin: Origin, description: String? = nil) throws -> Creation {
        let now = dates.now()
        return try database.writer.write { db in
            try createCategory(db, name: name, parentID: parentID, origin: origin, description: description, now: now)
        }
    }

    func createCategory(_ db: Database, name: String, parentID: UUID?, origin: Origin,
                        description: String?, now: Date) throws -> Creation {
        let cleaned = try Self.cleanName(name, maxLength: Self.maxNameLength)
        let normalized = TextNormalizer.normalizedName(cleaned)
        if let existing = try activeSibling(db, normalizedName: normalized, parentID: parentID) {
            return .existing(existing)
        }
        if let parentID {
            guard let parent = try EngramCategory.fetchOne(db, key: parentID), parent.status == .active else {
                throw StoreError.notFound
            }
        }
        let category = EngramCategory(name: cleaned, descriptionText: description, parentID: parentID, origin: origin, now: now)
        try category.insert(db)
        return .created(category)
    }

    public func rename(_ id: UUID, to newName: String) throws -> EngramCategory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var category = try EngramCategory.fetchOne(db, key: id), category.status == .active else {
                throw StoreError.notFound
            }
            let cleaned = try Self.cleanName(newName, maxLength: Self.maxNameLength)
            let normalized = TextNormalizer.normalizedName(cleaned)
            if try activeSibling(db, normalizedName: normalized, parentID: category.parentID, excluding: id) != nil {
                throw StoreError.nameConflict
            }
            category.name = cleaned
            category.normalizedName = normalized
            category.updatedAt = now
            try category.update(db)
            return category
        }
    }

    /// « Supprimer » une catégorie : elle est archivée, ses sous-catégories remontent d'un niveau,
    /// ses liens sont retirés, et les souvenirs qui n'ont plus de catégorie repassent « À classer ».
    public func archiveCategory(_ id: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var category = try EngramCategory.fetchOne(db, key: id), category.status == .active else {
                throw StoreError.notFound
            }
            try reparentChildren(db, of: id, to: category.parentID, now: now)
            let affected = try UUID.fetchAll(db, sql: "SELECT memory_id FROM memory_category WHERE category_id = ?",
                                             arguments: [id])
            try CategoryAssignment.filter(Column("category_id") == id).deleteAll(db)
            category.status = .archived
            category.updatedAt = now
            try category.update(db)
            for memoryID in affected { try SortingStatus.refresh(db, memoryID: memoryID, now: now) }
        }
    }

    /// Fusionne `sourceID` dans `targetID` : liens et sous-catégories déplacés, `sourceID` archivée.
    public func merge(_ sourceID: UUID, into targetID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in try merge(db, from: sourceID, into: targetID, now: now) }
    }

    func merge(_ db: Database, from sourceID: UUID, into targetID: UUID, now: Date) throws {
        guard sourceID != targetID else {
            throw StoreError.invalidOperation("une catégorie ne peut pas fusionner avec elle-même")
        }
        guard var source = try EngramCategory.fetchOne(db, key: sourceID), source.status == .active,
              let target = try EngramCategory.fetchOne(db, key: targetID), target.status == .active
        else { throw StoreError.notFound }
        if try descendantIDs(db, of: sourceID).contains(targetID) {
            throw StoreError.invalidOperation("impossible de fusionner une catégorie dans une de ses sous-catégories")
        }
        for assignment in try CategoryAssignment.filter(Column("category_id") == sourceID).fetchAll(db) {
            var moved = assignment
            moved.categoryID = targetID
            moved.updatedAt = now
            _ = try assignment.delete(db)
            if let existing = try CategoryAssignment.fetchOne(db, key: ["memory_id": assignment.memoryID, "category_id": targetID]) {
                if Self.priority(moved) > Self.priority(existing) {
                    moved.createdAt = existing.createdAt
                    try moved.update(db)
                }
            } else {
                try moved.insert(db)
            }
        }
        try reparentChildren(db, of: sourceID, to: target.id, now: now)
        source.status = .archived
        source.updatedAt = now
        try source.update(db)
    }

    public func activeCategories() throws -> [EngramCategory] {
        try database.writer.read { db in
            try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Catégories actives d'un souvenir (liens non rejetés).
    public func categories(for memoryID: UUID) throws -> [EngramCategory] {
        try database.writer.read { db in
            try EngramCategory.fetchAll(db, sql: """
                SELECT c.* FROM category c JOIN memory_category mc ON mc.category_id = c.id
                WHERE mc.memory_id = ? AND mc.rejected = 0 AND c.status = 'active'
                ORDER BY c.name
                """, arguments: [memoryID])
        }
    }

    /// L'identifiant lui-même suivi de tous ceux de ses sous-catégories actives.
    public func descendantIDs(of id: UUID) throws -> [UUID] {
        try database.writer.read { db in try descendantIDs(db, of: id) }
    }

    func descendantIDs(_ db: Database, of id: UUID) throws -> [UUID] {
        try UUID.fetchAll(db, sql: """
            WITH RECURSIVE tree(id) AS (
              SELECT ? UNION ALL
              SELECT c.id FROM category c JOIN tree ON c.parent_id = tree.id WHERE c.status = 'active'
            ) SELECT id FROM tree
            """, arguments: [id])
    }

    // MARK: - Liens souvenir ↔ catégorie

    public func assign(memoryID: UUID, categoryID: UUID, origin: AssignmentOrigin, confidence: Double? = nil) throws -> AssignmentOutcome {
        let now = dates.now()
        return try database.writer.write { db in
            guard try Memory.exists(db, key: memoryID) else { throw StoreError.notFound }
            guard let category = try EngramCategory.fetchOne(db, key: categoryID), category.status == .active else {
                throw StoreError.notFound
            }
            let existing = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": category.id])
            let outcome = try AssignmentRules.assign(
                db, existing: existing,
                makeNew: { CategoryAssignment(memoryID: memoryID, categoryID: category.id, origin: origin,
                                              confidence: confidence, confirmed: origin == .user, now: now) },
                origin: origin, now: now)
            try SortingStatus.refresh(db, memoryID: memoryID, now: now)
            return outcome
        }
    }

    public func confirm(memoryID: UUID, categoryID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": categoryID]) else {
                throw StoreError.notFound
            }
            try AssignmentRules.confirm(db, row: row, now: now)
            try SortingStatus.refresh(db, memoryID: memoryID, now: now)
        }
    }

    public func removeAssignment(memoryID: UUID, categoryID: UUID, by origin: AssignmentOrigin) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": categoryID]) else {
                throw StoreError.notFound
            }
            try AssignmentRules.remove(db, row: row, by: origin, now: now)
            try SortingStatus.refresh(db, memoryID: memoryID, now: now)
        }
    }

    // MARK: - Tags

    public func upsertTag(name: String, origin: Origin) throws -> EngramTag {
        let now = dates.now()
        return try database.writer.write { db in
            let cleaned = try Self.cleanName(name, maxLength: Self.maxTagLength)
            let normalized = TextNormalizer.normalizedName(cleaned)
            if let existing = try EngramTag.filter(Column("normalized_name") == normalized).fetchOne(db) {
                return existing
            }
            let tag = EngramTag(name: cleaned, origin: origin, now: now)
            try tag.insert(db)
            return tag
        }
    }

    public func tag(memoryID: UUID, tagID: UUID, origin: AssignmentOrigin, confidence: Double? = nil) throws -> AssignmentOutcome {
        let now = dates.now()
        return try database.writer.write { db in
            guard try Memory.exists(db, key: memoryID), try EngramTag.exists(db, key: tagID) else {
                throw StoreError.notFound
            }
            let existing = try TagAssignment.fetchOne(db, key: ["memory_id": memoryID, "tag_id": tagID])
            return try AssignmentRules.assign(
                db, existing: existing,
                makeNew: { TagAssignment(memoryID: memoryID, tagID: tagID, origin: origin,
                                         confidence: confidence, confirmed: origin == .user, now: now) },
                origin: origin, now: now)
        }
    }

    public func untag(memoryID: UUID, tagID: UUID, by origin: AssignmentOrigin) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try TagAssignment.fetchOne(db, key: ["memory_id": memoryID, "tag_id": tagID]) else {
                throw StoreError.notFound
            }
            try AssignmentRules.remove(db, row: row, by: origin, now: now)
        }
    }

    public func tags(for memoryID: UUID) throws -> [EngramTag] {
        try database.writer.read { db in
            try EngramTag.fetchAll(db, sql: """
                SELECT t.* FROM tag t JOIN memory_tag mt ON mt.tag_id = t.id
                WHERE mt.memory_id = ? AND mt.rejected = 0
                ORDER BY t.name
                """, arguments: [memoryID])
        }
    }

    // MARK: - Bibliothèque

    public func librarySummaryStream() -> AsyncThrowingStream<LibrarySummary, any Error> {
        database.stream { db in try Self.librarySummary(db) }
    }

    public func memoriesStream(inCategory id: UUID) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in
            try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m JOIN memory_category mc ON mc.memory_id = m.id
                WHERE mc.category_id = ? AND mc.rejected = 0 AND m.status IN ('active','unsorted')
                ORDER BY m.captured_at DESC
                """, arguments: [id])
        }
    }

    static func librarySummary(_ db: Database) throws -> LibrarySummary {
        let categories = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
        var counts: [UUID: Int] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT mc.category_id AS category_id, count(*) AS n
            FROM memory_category mc JOIN memory m ON m.id = mc.memory_id
            WHERE mc.rejected = 0 AND m.status IN ('active','unsorted')
            GROUP BY mc.category_id
            """) {
            let id: UUID = row["category_id"]
            let n: Int = row["n"]
            counts[id] = n
        }
        let children = Dictionary(grouping: categories, by: \.parentID)
        var flat: [CategorySummary] = []
        func visit(_ parentID: UUID?, depth: Int) {
            let siblings = (children[parentID] ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            for category in siblings {
                flat.append(CategorySummary(category: category, depth: depth, memoryCount: counts[category.id] ?? 0))
                visit(category.id, depth: depth + 1)
            }
        }
        visit(nil, depth: 0)
        func count(_ status: MemoryStatus) throws -> Int {
            try Memory.filter(Column("status") == status).fetchCount(db)
        }
        return LibrarySummary(categories: flat, unsortedCount: try count(.unsorted),
                              archivedCount: try count(.archived), trashedCount: try count(.trashed))
    }

    // MARK: - Outils

    static func cleanName(_ raw: String, maxLength: Int) throws -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !TextNormalizer.normalizedName(collapsed).isEmpty, collapsed.count <= maxLength else {
            throw StoreError.invalidName
        }
        return collapsed
    }

    func activeSibling(_ db: Database, normalizedName: String, parentID: UUID?, excluding: UUID? = nil) throws -> EngramCategory? {
        var request = EngramCategory.filter(Column("normalized_name") == normalizedName && Column("status") == CategoryStatus.active)
        if let parentID {
            request = request.filter(Column("parent_id") == parentID)
        } else {
            request = request.filter(Column("parent_id") == nil)
        }
        if let excluding { request = request.filter(Column("id") != excluding) }
        return try request.fetchOne(db)
    }

    /// Déplace les sous-catégories actives sous `newParentID` ; en cas de nom identique à l'arrivée, elles fusionnent.
    func reparentChildren(_ db: Database, of parentID: UUID, to newParentID: UUID?, now: Date) throws {
        let children = try EngramCategory
            .filter(Column("parent_id") == parentID && Column("status") == CategoryStatus.active)
            .fetchAll(db)
        for var child in children {
            if let clash = try activeSibling(db, normalizedName: child.normalizedName, parentID: newParentID, excluding: child.id) {
                try merge(db, from: child.id, into: clash.id, now: now)
            } else {
                child.parentID = newParentID
                child.updatedAt = now
                try child.update(db)
            }
        }
    }

    /// Ordre de force d'une décision : confirmé > rejeté > posé par le propriétaire > proposé par l'IA.
    static func priority(_ assignment: CategoryAssignment) -> Int {
        if assignment.confirmed { return 3 }
        if assignment.rejected { return 2 }
        return assignment.origin == .user ? 1 : 0
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Packages/EngramKit
git commit -m "feat(store): catégories, tags, fusion, archivage et règle « le propriétaire décide »

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Vérifier que les tests passent**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. Les 17 cas de `CategoryStoreTests` passent (le test paramétré compte 4 cas), ainsi que tous les précédents.

---

### Task 8: Recherche par mots avec filtres (TextSearch)

**Files:**
- Create: `Packages/EngramKit/Sources/EngramStore/TextSearch.swift`
- Test: `Packages/EngramKit/Tests/EngramStoreTests/TextSearchTests.swift`

**Interfaces:**
- Consumes: `MemoryStore`, `CategoryStore` (dans les tests), la table `memory_fts` (tâche 5).
- Produces :
  - `public struct SearchFilters: Sendable, Equatable` — champs `categoryID: UUID?` (sous-catégories incluses), `tagID: UUID?`, `kinds: Set<MemoryKind>`, `includeArchived: Bool`, `capturedFrom: Date?`, `capturedTo: Date?` ; `init(categoryID:tagID:kinds:includeArchived:capturedFrom:capturedTo:)`, tous optionnels.
  - `public struct TextSearchHit: Sendable, Equatable { memoryID: UUID; rank: Double }` (plus `rank` est petit, meilleur est le résultat).
  - `public enum FTSQuery { static func make(from: String) -> String? }`.
  - `extension MemoryStore { func searchText(_ input: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) throws -> [TextSearchHit] }`.

- [ ] **Step 1: Écrire les tests (échec attendu)**

`Tests/EngramStoreTests/TextSearchTests.swift` :

```swift
import EngramCore
import Foundation
import Testing
@testable import EngramStore

struct TextSearchTests {
    @Test func ignoresAccentsAndCase() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Réunion budget avec l'équipe")
        #expect(try env.memories.searchText("REUNION").map(\.memoryID) == [memory.id])
        #expect(try env.memories.searchText("equipe").map(\.memoryID) == [memory.id])
    }

    @Test func matchesWordPrefixes() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Préparer le budget trimestriel")
        #expect(try env.memories.searchText("budg trim").map(\.memoryID) == [memory.id])
    }

    @Test func requiresEveryWord() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Acheter du lait")
        try env.saveNote("Acheter un ordinateur")
        #expect(try env.memories.searchText("acheter lait").count == 1)
    }

    @Test(arguments: ["\"", "*", "-lait", "(lait", "lait:", "AND", "NEAR(lait)", "lait OR", "\"lait", "^lait"])
    func specialCharactersNeverThrow(query: String) throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Acheter du lait")
        _ = try env.memories.searchText(query)
    }

    @Test(arguments: ["", "   ", "!!!", "--"])
    func punctuationOnlyFindsNothing(query: String) throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Acheter du lait")
        #expect(try env.memories.searchText(query).isEmpty)
    }

    @Test func singleLettersAreIgnoredWhenOtherWordsExist() {
        #expect(FTSQuery.make(from: "l'été") == "\"été\"*")
        #expect(FTSQuery.make(from: "a") == "\"a\"*")
        #expect(FTSQuery.make(from: "?!") == nil)
    }

    @Test func excludesTrashAndOptionallyIncludesArchives() throws {
        let env = try StoreTestEnvironment()
        let trashed = try env.saveNote("Lait à jeter")
        let archived = try env.saveNote("Lait archivé")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)
        _ = try env.memories.setStatus(.archived, for: archived.id, actor: .user)
        #expect(try env.memories.searchText("lait").isEmpty)
        #expect(try env.memories.searchText("lait", filters: SearchFilters(includeArchived: true)).map(\.memoryID) == [archived.id])
    }

    @Test func filtersByCategoryIncludingSubcategories() throws {
        let env = try StoreTestEnvironment()
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .seed).category
        let sport = try env.categories.createCategory(name: "Sport", parentID: sante.id, origin: .ai).category
        let inSport = try env.saveNote("Plan de course du mardi")
        let inSante = try env.saveNote("Course chez le pharmacien")
        try env.saveNote("Course de taxi")
        let rejected = try env.saveNote("Course annulée")
        _ = try env.categories.assign(memoryID: inSport.id, categoryID: sport.id, origin: .ai)
        _ = try env.categories.assign(memoryID: inSante.id, categoryID: sante.id, origin: .user)
        _ = try env.categories.assign(memoryID: rejected.id, categoryID: sante.id, origin: .ai)
        try env.categories.removeAssignment(memoryID: rejected.id, categoryID: sante.id, by: .user)
        let ids = Set(try env.memories.searchText("course", filters: SearchFilters(categoryID: sante.id)).map(\.memoryID))
        #expect(ids == [inSport.id, inSante.id])
    }

    @Test func filtersByTagKindAndDate() throws {
        let env = try StoreTestEnvironment()
        let early = try env.saveNote("Idée de jardin")
        env.dates.advance(by: 24 * 3600)
        let late = try env.saveNote("Idée de cuisine")
        let tag = try env.categories.upsertTag(name: "Idée", origin: .ai)
        _ = try env.categories.tag(memoryID: late.id, tagID: tag.id, origin: .ai)
        _ = try env.memories.updateMemory(early.id, with: MemoryEdit(kind: .idea), actor: .user)
        #expect(try env.memories.searchText("idee", filters: SearchFilters(tagID: tag.id)).map(\.memoryID) == [late.id])
        #expect(try env.memories.searchText("idee", filters: SearchFilters(kinds: [.idea])).map(\.memoryID) == [early.id])
        let from = Fixtures.date.addingTimeInterval(3600)
        #expect(try env.memories.searchText("idee", filters: SearchFilters(capturedFrom: from)).map(\.memoryID) == [late.id])
    }

    @Test func titleMatchesRankAboveContentMatches() throws {
        let env = try StoreTestEnvironment()
        let inContent = try env.saveNote("Notes diverses\nil faudra revoir le budget")
        let inTitle = try env.saveNote("Budget\nà revoir")
        #expect(try env.memories.searchText("budget").map(\.memoryID) == [inTitle.id, inContent.id])
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

```bash
git add Packages/EngramKit/Tests
git commit -m "test(store): recherche par mots (échec attendu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : FAIL dans `package-tests` avec `value of type 'MemoryStore' has no member 'searchText'` et `cannot find 'SearchFilters' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/EngramStore/TextSearch.swift` :

```swift
import EngramCore
import Foundation
import GRDB

public struct SearchFilters: Sendable, Equatable {
    /// Catégorie, sous-catégories comprises.
    public var categoryID: UUID?
    public var tagID: UUID?
    public var kinds: Set<MemoryKind>
    public var includeArchived: Bool
    public var capturedFrom: Date?
    public var capturedTo: Date?

    public init(categoryID: UUID? = nil, tagID: UUID? = nil, kinds: Set<MemoryKind> = [],
                includeArchived: Bool = false, capturedFrom: Date? = nil, capturedTo: Date? = nil) {
        self.categoryID = categoryID
        self.tagID = tagID
        self.kinds = kinds
        self.includeArchived = includeArchived
        self.capturedFrom = capturedFrom
        self.capturedTo = capturedTo
    }
}

public struct TextSearchHit: Sendable, Equatable {
    public let memoryID: UUID
    /// Score bm25 : plus il est petit (négatif), plus le résultat est pertinent.
    public let rank: Double
}

/// Transforme une saisie libre en requête FTS5 sûre.
public enum FTSQuery {
    /// Chaque mot devient un préfixe entre guillemets (jamais un opérateur), et tous les mots sont requis.
    /// Les mots d'une seule lettre (« l' », « a ») sont ignorés s'il y a d'autres mots.
    public static func make(from userInput: String) -> String? {
        let words = userInput
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let meaningful = words.filter { $0.count >= 2 }
        let kept = meaningful.isEmpty ? words : meaningful
        guard !kept.isEmpty else { return nil }
        return kept.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}

extension MemoryStore {
    /// Recherche par mots dans les souvenirs actifs et « À classer » (et archivés sur demande). La corbeille est exclue.
    public func searchText(_ input: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) throws -> [TextSearchHit] {
        guard let match = FTSQuery.make(from: input) else { return [] }
        var statuses: [MemoryStatus] = [.active, .unsorted]
        if filters.includeArchived { statuses.append(.archived) }

        var sql = """
            SELECT m.id AS memory_id, bm25(memory_fts, 0.0, 10.0, 4.0, 1.0, 2.0) AS rank
            FROM memory_fts
            JOIN memory m ON m.id = memory_fts.memory_id
            WHERE memory_fts MATCH ?
              AND m.status IN (\(Self.placeholders(statuses.count)))
            """
        var values: [(any DatabaseValueConvertible)?] = [match]
        values += statuses.map { $0 as (any DatabaseValueConvertible)? }

        if !filters.kinds.isEmpty {
            let kinds = filters.kinds.sorted { $0.rawValue < $1.rawValue }
            sql += "\n  AND m.kind IN (\(Self.placeholders(kinds.count)))"
            values += kinds.map { $0 as (any DatabaseValueConvertible)? }
        }
        if let from = filters.capturedFrom {
            sql += "\n  AND m.captured_at >= ?"
            values.append(from)
        }
        if let to = filters.capturedTo {
            sql += "\n  AND m.captured_at <= ?"
            values.append(to)
        }
        if let categoryID = filters.categoryID {
            sql += """

                  AND m.id IN (
                    SELECT mc.memory_id FROM memory_category mc
                    WHERE mc.rejected = 0 AND mc.category_id IN (
                      WITH RECURSIVE tree(id) AS (
                        SELECT ? UNION ALL
                        SELECT c.id FROM category c JOIN tree ON c.parent_id = tree.id WHERE c.status = 'active'
                      ) SELECT id FROM tree))
                """
            values.append(categoryID)
        }
        if let tagID = filters.tagID {
            sql += "\n  AND m.id IN (SELECT memory_id FROM memory_tag WHERE rejected = 0 AND tag_id = ?)"
            values.append(tagID)
        }
        sql += "\nORDER BY rank LIMIT ?"
        values.append(limit)

        let arguments = StatementArguments(values)
        return try database.writer.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                TextSearchHit(memoryID: row["memory_id"], rank: row["rank"])
            }
        }
    }

    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Packages/EngramKit
git commit -m "feat(store): recherche par mots insensible aux accents, avec filtres

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Vérifier que les tests passent**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. Les 22 cas de `TextSearchTests` passent.

---

### Task 9: Export complet (JSON + Markdown + audio + ZIP)

**Files:**
- Create: `Packages/EngramKit/Sources/EngramStore/Exporter.swift`
- Test: `Packages/EngramKit/Tests/EngramStoreTests/ExporterTests.swift`

**Interfaces:**
- Consumes: tous les records (tâches 5 à 7), `EngramCore.exportFormatVersion`.
- Produces :
  - `public struct ExportDocument: Codable, Sendable`, avec les champs :
    - `formatVersion`, `app`, `exportedAt` ;
    - `sources`, `memories`, `memoryVersions` ;
    - `categories`, `tags`, `categoryAssignments`, `tagAssignments`.

    Les clés JSON sont en snake_case et les dates au format ISO 8601.
  - `public struct ExportResult: Sendable, Equatable { folderURL: URL; archiveURL: URL; memoryCount: Int }`.
  - `public struct Exporter: Sendable` avec `init(database:audioDirectory:dates:)` et `export(into parentDirectory: URL) throws -> ExportResult`. Le dossier produit s'appelle `Engram-Export-<aaaaMMjj-HHmmss>/` et contient `engram.json`, `markdown/…`, `audio/…` et `LISEZMOI.txt`. Il s'accompagne d'un fichier `.zip` du même nom.

- [ ] **Step 1: Écrire les tests (échec attendu)**

`Tests/EngramStoreTests/ExporterTests.swift` :

```swift
import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct ExporterTests {
    @Test func exportsJSONMarkdownAndArchive() throws {
        let env = try StoreTestEnvironment()
        let classed = try env.saveNote("Préparer la réunion budget\nAvec les chiffres de mars")
        let trashed = try env.saveNote("Idée : une app de mémoire")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)
        let travail = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .user).category
        _ = try env.categories.assign(memoryID: classed.id, categoryID: travail.id, origin: .user)

        let out = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: out.url)
        #expect(result.memoryCount == 2)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: result.folderURL.appendingPathComponent("engram.json"))
        let document = try decoder.decode(ExportDocument.self, from: data)
        #expect(document.formatVersion == EngramCore.exportFormatVersion)
        #expect(Set(document.memories.map(\.id)) == [classed.id, trashed.id])
        #expect(document.categoryAssignments.count == 1)
        #expect(document.memoryVersions.count == 3)

        let markdown = result.folderURL.appendingPathComponent("markdown")
        #expect(try FileManager.default.contentsOfDirectory(atPath: markdown.appendingPathComponent("Travail").path).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: markdown.appendingPathComponent("Corbeille").path).count == 1)
        #expect(FileManager.default.fileExists(atPath: result.folderURL.appendingPathComponent("LISEZMOI.txt").path))

        let archive = try Data(contentsOf: result.archiveURL)
        #expect(archive.prefix(2) == Data("PK".utf8))
    }

    @Test func copiesAudioFilesWhenPresent() throws {
        let env = try StoreTestEnvironment()
        let audio = try TemporaryDirectory()
        try Data("audio-de-test".utf8).write(to: audio.url.appendingPathComponent("capture-1.caf"))
        try env.database.writer.write { db in
            try Source(kind: .voice, audioPath: "capture-1.caf", contentHash: "h", capturedAt: Fixtures.date,
                       createdAt: Fixtures.date, updatedAt: Fixtures.date).insert(db)
        }
        let out = try TemporaryDirectory()
        let result = try Exporter(database: env.database, audioDirectory: audio.url, dates: env.dates).export(into: out.url)
        #expect(FileManager.default.fileExists(atPath: result.folderURL.appendingPathComponent("audio/capture-1.caf").path))
    }

    @Test func unsafeTitlesBecomeSafeFileNamesAndQuotedFrontMatter() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Achats/Ventes : \"Q3\" <final>?")
        let out = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: out.url)
        let unsorted = result.folderURL.appendingPathComponent("markdown").appendingPathComponent("À classer")
        let files = try FileManager.default.contentsOfDirectory(atPath: unsorted.path)
        let name = try #require(files.first)
        #expect(files.count == 1)
        for forbidden in ["/", "\"", "<", ">", "?", ":"] { #expect(!name.contains(forbidden)) }
        let text = try String(contentsOf: unsorted.appendingPathComponent(name), encoding: .utf8)
        #expect(text.contains("titre: \"Achats/Ventes : \\\"Q3\\\" <final>?\""))
    }

    @Test func exportingTwiceReplacesThePreviousArchive() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Une pensée")
        let out = try TemporaryDirectory()
        let exporter = Exporter(database: env.database, dates: env.dates)
        let first = try exporter.export(into: out.url)
        let second = try exporter.export(into: out.url)
        #expect(first.archiveURL == second.archiveURL)
        #expect(FileManager.default.fileExists(atPath: second.archiveURL.path))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

```bash
git add Packages/EngramKit/Tests
git commit -m "test(store): export (échec attendu)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : FAIL dans `package-tests` avec `cannot find 'Exporter' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

`Sources/EngramStore/Exporter.swift` :

```swift
import EngramCore
import Foundation
import GRDB

/// Contenu de `engram.json`. Les embeddings (recalculables) et les données internes ne sont pas exportés.
public struct ExportDocument: Codable, Sendable {
    public var formatVersion: Int
    public var app: String
    public var exportedAt: Date
    public var sources: [Source]
    public var memories: [Memory]
    public var memoryVersions: [MemoryVersion]
    public var categories: [EngramCategory]
    public var tags: [EngramTag]
    public var categoryAssignments: [CategoryAssignment]
    public var tagAssignments: [TagAssignment]

    enum CodingKeys: String, CodingKey {
        case app, sources, memories, categories, tags
        case formatVersion = "format_version"
        case exportedAt = "exported_at"
        case memoryVersions = "memory_versions"
        case categoryAssignments = "category_assignments"
        case tagAssignments = "tag_assignments"
    }
}

public struct ExportResult: Sendable, Equatable {
    public let folderURL: URL
    public let archiveURL: URL
    public let memoryCount: Int
}

/// Export ouvert de toute la mémoire (F89). L'export n'est PAS chiffré.
public struct Exporter: Sendable {
    public let database: AppDatabase
    /// Dossier où se trouvent les fichiers audio (les `audio_path` lui sont relatifs).
    public let audioDirectory: URL?
    public let dates: any DateProvider

    public init(database: AppDatabase, audioDirectory: URL? = nil, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.audioDirectory = audioDirectory
        self.dates = dates
    }

    public func export(into parentDirectory: URL) throws -> ExportResult {
        let exportedAt = dates.now()
        let document = try database.writer.read { db in
            ExportDocument(
                formatVersion: EngramCore.exportFormatVersion,
                app: "Engram",
                exportedAt: exportedAt,
                sources: try Source.order(Column("captured_at")).fetchAll(db),
                memories: try Memory.order(Column("captured_at")).fetchAll(db),
                memoryVersions: try MemoryVersion.order(Column("created_at"), Column("version")).fetchAll(db),
                categories: try EngramCategory.order(Column("name")).fetchAll(db),
                tags: try EngramTag.order(Column("name")).fetchAll(db),
                categoryAssignments: try CategoryAssignment.fetchAll(db),
                tagAssignments: try TagAssignment.fetchAll(db))
        }
        let fileManager = FileManager.default
        let folder = parentDirectory.appendingPathComponent("Engram-Export-\(Self.stamp(exportedAt))", isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        try Self.writeJSON(document, to: folder.appendingPathComponent("engram.json"))
        try Self.writeMarkdown(document, to: folder.appendingPathComponent("markdown", isDirectory: true))
        try copyAudio(of: document.sources, to: folder.appendingPathComponent("audio", isDirectory: true))
        try Self.readme.write(to: folder.appendingPathComponent("LISEZMOI.txt"), atomically: true, encoding: .utf8)

        let archive = parentDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
        try Self.zip(folder, to: archive)
        return ExportResult(folderURL: folder, archiveURL: archive, memoryCount: document.memories.count)
    }

    // MARK: - JSON

    static func writeJSON(_ document: ExportDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    // MARK: - Markdown

    static func writeMarkdown(_ document: ExportDocument, to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let categoriesByID = Dictionary(uniqueKeysWithValues: document.categories.map { ($0.id, $0) })
        let tagsByID = Dictionary(uniqueKeysWithValues: document.tags.map { ($0.id, $0) })
        let sourcesByID = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.id, $0) })
        let categoryLinks = Dictionary(grouping: document.categoryAssignments.filter { !$0.rejected }, by: \.memoryID)
        let tagLinks = Dictionary(grouping: document.tagAssignments.filter { !$0.rejected }, by: \.memoryID)

        for memory in document.memories {
            let paths = (categoryLinks[memory.id] ?? [])
                .compactMap { categoriesByID[$0.categoryID] }
                .filter { $0.status == .active }
                .map { pathComponents(of: $0, in: categoriesByID) }
                .sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
            let tagNames = (tagLinks[memory.id] ?? []).compactMap { tagsByID[$0.tagID]?.name }.sorted()

            let folderComponents: [String] = switch memory.status {
            case .trashed: ["Corbeille"]
            case .archived: ["Archives"]
            case .unsorted: ["À classer"]
            case .active: paths.first ?? ["À classer"]
            }
            let directory = folderComponents.reduce(root) { $0.appendingPathComponent(safeFileName($1), isDirectory: true) }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileName = "\(safeFileName(memory.title))-\(memory.id.uuidString.prefix(8).lowercased()).md"
            let text = markdown(for: memory, categoryPaths: paths.map { $0.joined(separator: " / ") },
                                tags: tagNames, source: sourcesByID[memory.sourceID])
            try text.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }
    }

    static func markdown(for memory: Memory, categoryPaths: [String], tags: [String], source: Source?) -> String {
        var lines = ["---"]
        lines.append("id: \(yaml(memory.id.uuidString.lowercased()))")
        lines.append("titre: \(yaml(memory.title))")
        lines.append("statut: \(memory.status.rawValue)")
        if let kind = memory.kind { lines.append("type: \(kind.rawValue)") }
        lines.append("categories: [\(categoryPaths.map(yaml).joined(separator: ", "))]")
        lines.append("tags: [\(tags.map(yaml).joined(separator: ", "))]")
        lines.append("capture: \(yaml(memory.capturedAt.formatted(.iso8601)))")
        lines.append("version: \(memory.version)")
        if let source { lines.append("source: \(source.kind.rawValue)") }
        lines.append("---")
        lines.append("")
        lines.append("# \(memory.title)")
        if let summary = memory.summary { lines += ["", "_\(summary)_"] }
        lines += ["", memory.content]
        if memory.excerpt != memory.content {
            lines += ["", "> Extrait de la source : " + memory.excerpt.replacingOccurrences(of: "\n", with: "\n> ")]
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Chaîne YAML entre guillemets (une chaîne JSON est une chaîne YAML valide).
    static func yaml(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    static func pathComponents(of category: EngramCategory, in all: [UUID: EngramCategory]) -> [String] {
        var components = [category.name]
        var current = category
        var depth = 0
        while let parentID = current.parentID, let parent = all[parentID], depth < 32 {
            components.insert(parent.name, at: 0)
            current = parent
            depth += 1
        }
        return components
    }

    static func safeFileName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let replaced = String(String.UnicodeScalarView(raw.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        let trimmed = replaced.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        let limited = String(trimmed.prefix(60))
        return limited.isEmpty ? "sans-titre" : limited
    }

    // MARK: - Audio

    func copyAudio(of sources: [Source], to directory: URL) throws {
        guard let audioDirectory else { return }
        let fileManager = FileManager.default
        let paths = sources.compactMap(\.audioPath)
        guard !paths.isEmpty else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for path in paths {
            let from = audioDirectory.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            let to = directory.appendingPathComponent(from.lastPathComponent)
            if fileManager.fileExists(atPath: to.path) { try fileManager.removeItem(at: to) }
            try fileManager.copyItem(at: from, to: to)
        }
    }

    // MARK: - ZIP

    /// Compresse un dossier avec le service système (NSFileCoordinator `.forUploading`).
    static func zip(_ folder: URL, to archive: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: archive.path) { try fileManager.removeItem(at: archive) }
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: archive) } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    static func stamp(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static let readme = """
        Export Engram
        =============

        engram.json  : toute ta mémoire (sources, souvenirs, versions, catégories, tags, liens), format JSON.
        markdown/    : un fichier lisible par souvenir, rangé par catégorie (« À classer », « Archives », « Corbeille »).
        audio/       : les enregistrements d'origine, s'il y en a.

        Attention : cet export N'EST PAS chiffré. Garde-le dans un endroit sûr.
        """
}
```

- [ ] **Step 4: Commit**

```bash
git add Packages/EngramKit
git commit -m "feat(store): export complet JSON, Markdown, audio et ZIP

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Vérifier que les tests passent**

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`. Les 4 tests de `ExporterTests` passent. Si `zip` échoue sur le runner macOS (`NSFileCoordinator` sans résultat), relever l'erreur exacte et passer par `superpowers:systematic-debugging`. Ne pas contourner en désactivant le test.

---

### Task 10: Interface minimale (notes texte sans IA)

**Files:**
- Modify: `project.yml` (dépendance `EngramStore`)
- Modify: `App/Sources/EngramApp.swift`, `App/Sources/RootView.swift`
- Create: `App/Sources/AppModel.swift`, `App/Sources/Support/ErrorAlert.swift`
- Create: `App/Sources/Home/HomeView.swift`
- Create: `App/Sources/Library/LibraryView.swift`, `App/Sources/Library/MemoryListView.swift`, `App/Sources/Library/CategoryMemoriesView.swift`
- Create: `App/Sources/Memory/MemoryRow.swift`, `App/Sources/Memory/MemorySwipeActions.swift`, `App/Sources/Memory/MemoryDetailView.swift`, `App/Sources/Memory/MemoryEditor.swift`, `App/Sources/Memory/CategoryPicker.swift`
- Create: `App/Sources/Search/SearchView.swift`
- Create: `App/Sources/Settings/SettingsView.swift`
- Modify: `docs/IMPLEMENTATION_PROGRESS.md`

**Interfaces:**
- Consumes :
  - `MemoryStore` : `saveTextNoteWithoutAnalysis`, `memoriesStream`, `memory(id:)`, `memories(ids:)`, `source(id:)`, `versions(of:)`, `updateMemory`, `setStatus`, `restore`, `restoreVersion`, `deletePermanently`, `searchText`.
  - `CategoryStore` : `seedDefaultsIfNeeded`, `librarySummaryStream`, `memoriesStream(inCategory:)`, `activeCategories`, `categories(for:)`, `assign`, `removeAssignment`, `createCategory`.
  - `Exporter`.
- Produces : l'app SwiftUI à 4 onglets (Accueil, Bibliothèque, Recherche, Réglages). Pas d'API pour d'autres tâches.

La logique est entièrement testée dans `EngramStore` (tâches 6 à 9). Cette tâche ne contient que de l'assemblage d'interface. Sa vérification, c'est la compilation pour l'appareil en CI, puis la liste de contrôle sur l'iPhone (Step 5).

- [ ] **Step 1: Lier EngramStore à l'app**

Dans `project.yml`, remplacer le bloc `dependencies:` de la cible `Engram` par :

```yaml
    dependencies:
      - package: EngramKit
        product: EngramCore
      - package: EngramKit
        product: EngramStore
```

- [ ] **Step 2: Écrire le socle de l'app**

`App/Sources/EngramApp.swift` (remplace le contenu) :

```swift
import SwiftUI

@main
@MainActor
struct EngramApp: App {
    @State private var launch = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .success(let model):
                RootView()
                    .environment(model)
                    .tint(.indigo)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Impossible d'ouvrir ta mémoire", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Tes données n'ont pas été modifiées.\n\(AppModel.describe(error))")
                }
            }
        }
    }
}
```

`App/Sources/AppModel.swift` :

```swift
import EngramCore
import EngramStore
import Foundation
import Observation

/// Services partagés par tous les écrans, et dernière erreur à afficher.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let memories: MemoryStore
    let categories: CategoryStore
    var errorMessage: String?

    init(database: AppDatabase) {
        self.database = database
        memories = MemoryStore(database: database)
        categories = CategoryStore(database: database)
    }

    /// Ouvre la base sur l'appareil et crée les catégories de départ si besoin.
    static func launch() -> Result<AppModel, any Error> {
        Result {
            let model = AppModel(database: try AppDatabase.openOnDisk())
            try model.categories.seedDefaultsIfNeeded()
            return model
        }
    }

    /// Exécute une action ; en cas d'erreur, l'affiche dans une alerte.
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = Self.describe(error) }
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? StoreError {
            switch error {
            case .emptyContent: return "Le contenu est vide."
            case .notFound: return "Cet élément n'existe plus."
            case .protectedByUser: return "Ce souvenir a été modifié à la main : il est protégé."
            case .nameConflict: return "Une catégorie porte déjà ce nom à cet endroit."
            case .invalidName: return "Ce nom n'est pas valide (vide ou trop long)."
            case .invalidOperation(let reason): return "Opération impossible : \(reason)."
            }
        }
        if let error = error as? MemoryValidationError {
            switch error {
            case .emptyTitle: return "Le titre ne peut pas être vide."
            case .titleTooLong: return "Le titre dépasse 80 caractères."
            case .emptyContent: return "Le contenu ne peut pas être vide."
            case .emptyExcerpt, .invalidStatus, .invalidConfidence: return "Données de souvenir invalides."
            }
        }
        return error.localizedDescription
    }
}
```

`App/Sources/Support/ErrorAlert.swift` :

```swift
import SwiftUI

extension View {
    /// Affiche `message` dans une alerte tant qu'il n'est pas `nil`.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Une erreur est survenue",
            isPresented: Binding(get: { message.wrappedValue != nil },
                                 set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
```

`App/Sources/RootView.swift` (remplace le contenu) :

```swift
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("Accueil", systemImage: "house") { HomeView() }
            Tab("Bibliothèque", systemImage: "books.vertical") { LibraryView() }
            Tab("Recherche", systemImage: "magnifyingglass", role: .search) { SearchView() }
            Tab("Réglages", systemImage: "gearshape") { SettingsView() }
        }
        .errorAlert($model.errorMessage)
    }
}
```

- [ ] **Step 3: Écrire les écrans**

`App/Sources/Memory/MemoryRow.swift` :

```swift
import EngramCore
import SwiftUI

struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(memory.title)
                .lineLimit(2)
            HStack(spacing: 6) {
                if memory.status == .unsorted {
                    Label("À classer", systemImage: "tray")
                }
                Text(memory.capturedAt, format: .relative(presentation: .named))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
```

`App/Sources/Memory/MemorySwipeActions.swift` :

```swift
import EngramCore
import SwiftUI

/// Actions de balayage, selon l'état du souvenir.
struct MemorySwipeActions: View {
    @Environment(AppModel.self) private var model
    let memory: Memory

    var body: some View {
        switch memory.status {
        case .trashed:
            Button("Restaurer", systemImage: "arrow.uturn.backward") {
                model.perform { _ = try model.memories.restore(memory.id) }
            }
            .tint(.indigo)
        case .archived:
            Button("Corbeille", systemImage: "trash", role: .destructive) {
                model.perform { _ = try model.memories.setStatus(.trashed, for: memory.id, actor: .user) }
            }
            Button("Désarchiver", systemImage: "arrow.uturn.backward") {
                model.perform { _ = try model.memories.restore(memory.id) }
            }
            .tint(.indigo)
        case .active, .unsorted:
            Button("Corbeille", systemImage: "trash", role: .destructive) {
                model.perform { _ = try model.memories.setStatus(.trashed, for: memory.id, actor: .user) }
            }
            Button("Archiver", systemImage: "archivebox") {
                model.perform { _ = try model.memories.setStatus(.archived, for: memory.id, actor: .user) }
            }
            .tint(.indigo)
        }
    }
}
```

`App/Sources/Home/HomeView.swift` :

```swift
import EngramCore
import EngramStore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var recent: [Memory] = []
    @State private var feedback: String?
    @FocusState private var editorFocused: Bool

    private var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Écrire une pensée…", text: $draft, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($editorFocused)
                    Button("Enregistrer", systemImage: "square.and.arrow.down", action: save)
                        .disabled(!canSave)
                } footer: {
                    if let feedback { Text(feedback) }
                }
                Section("Récents") {
                    if recent.isEmpty {
                        ContentUnavailableView("Aucune pensée pour l'instant", systemImage: "brain",
                                               description: Text("Écris ta première pensée ci-dessus."))
                    }
                    ForEach(recent) { memory in
                        NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                            .swipeActions { MemorySwipeActions(memory: memory) }
                    }
                }
            }
            .navigationTitle("Engram")
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .task {
                do {
                    for try await list in model.memories.memoriesStream(statuses: [.active, .unsorted], limit: 30) {
                        recent = list
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
        }
    }

    private func save() {
        do {
            switch try model.memories.saveTextNoteWithoutAnalysis(draft) {
            case .saved: feedback = "Pensée enregistrée."
            case .duplicate: feedback = "Cette pensée vient déjà d'être enregistrée."
            }
            draft = ""
            editorFocused = false
        } catch {
            feedback = AppModel.describe(error)
        }
    }
}
```

`App/Sources/Library/LibraryView.swift` :

```swift
import EngramCore
import EngramStore
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CategoryStore.LibrarySummary?

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    Section {
                        NavigationLink {
                            MemoryListView(title: "À classer", statuses: [.unsorted])
                        } label: {
                            LabeledContent { Text("\(summary.unsortedCount)") } label: { Label("À classer", systemImage: "tray") }
                        }
                        NavigationLink {
                            MemoryListView(title: "Toutes les pensées", statuses: [.active, .unsorted])
                        } label: {
                            Label("Toutes les pensées", systemImage: "square.stack")
                        }
                    }
                    Section("Catégories") {
                        ForEach(summary.categories) { item in
                            NavigationLink {
                                CategoryMemoriesView(category: item.category)
                            } label: {
                                LabeledContent { Text("\(item.memoryCount)") } label: {
                                    Label(item.category.name, systemImage: "folder")
                                }
                            }
                            .padding(.leading, CGFloat(item.depth) * 16)
                        }
                    }
                    Section {
                        NavigationLink {
                            MemoryListView(title: "Archives", statuses: [.archived])
                        } label: {
                            LabeledContent { Text("\(summary.archivedCount)") } label: { Label("Archives", systemImage: "archivebox") }
                        }
                        NavigationLink {
                            MemoryListView(title: "Corbeille", statuses: [.trashed])
                        } label: {
                            LabeledContent { Text("\(summary.trashedCount)") } label: { Label("Corbeille", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Bibliothèque")
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .task {
                do {
                    for try await value in model.categories.librarySummaryStream() { summary = value }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
        }
    }
}
```

`App/Sources/Library/MemoryListView.swift` :

```swift
import EngramCore
import SwiftUI

struct MemoryListView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let statuses: Set<MemoryStatus>
    @State private var memories: [Memory] = []

    var body: some View {
        List(memories) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                .swipeActions { MemorySwipeActions(memory: memory) }
        }
        .overlay {
            if memories.isEmpty { ContentUnavailableView("Rien ici", systemImage: "tray") }
        }
        .navigationTitle(title)
        .task {
            do {
                for try await list in model.memories.memoriesStream(statuses: statuses) { memories = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
```

`App/Sources/Library/CategoryMemoriesView.swift` :

```swift
import EngramCore
import SwiftUI

struct CategoryMemoriesView: View {
    @Environment(AppModel.self) private var model
    let category: EngramCategory
    @State private var memories: [Memory] = []

    var body: some View {
        List(memories) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                .swipeActions { MemorySwipeActions(memory: memory) }
        }
        .overlay {
            if memories.isEmpty {
                ContentUnavailableView("Aucune pensée dans « \(category.name) »", systemImage: "folder")
            }
        }
        .navigationTitle(category.name)
        .task {
            do {
                for try await list in model.categories.memoriesStream(inCategory: category.id) { memories = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
```

`App/Sources/Memory/MemoryDetailView.swift` :

```swift
import EngramCore
import SwiftUI

struct MemoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID

    @State private var memory: Memory?
    @State private var source: Source?
    @State private var versions: [MemoryVersion] = []
    @State private var assigned: [EngramCategory] = []
    @State private var isEditing = false
    @State private var isPickingCategories = false
    @State private var isConfirmingDeletion = false

    var body: some View {
        Group {
            if let memory {
                content(memory)
            } else {
                ContentUnavailableView("Souvenir introuvable", systemImage: "questionmark.folder")
            }
        }
        .task { reload() }
    }

    private func content(_ memory: Memory) -> some View {
        List {
            Section {
                Text(memory.content)
                    .textSelection(.enabled)
            } header: {
                Text(memory.capturedAt, format: .dateTime.day().month(.wide).year().hour().minute())
            }
            Section("Catégories") {
                if assigned.isEmpty {
                    Text("À classer").foregroundStyle(.secondary)
                }
                ForEach(assigned) { Label($0.name, systemImage: "folder") }
                Button("Choisir les catégories…", systemImage: "folder.badge.plus") { isPickingCategories = true }
            }
            if let original = source?.originalText {
                Section("Source") {
                    Text(original)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section("Historique") {
                ForEach(versions) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(version.version)")
                            Text("\(version.changeReason ?? "") · \(version.createdAt.formatted(.relative(presentation: .named)))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if version.version != memory.version {
                            Button("Restaurer") {
                                model.perform { _ = try model.memories.restoreVersion(version.version, of: memoryID) }
                                reload()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle(memory.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { isEditing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                actionsMenu(memory)
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: reload) { MemoryEditor(memory: memory) }
        .sheet(isPresented: $isPickingCategories, onDismiss: reload) { CategoryPicker(memoryID: memoryID) }
        .confirmationDialog("Supprimer définitivement ce souvenir ?", isPresented: $isConfirmingDeletion,
                            titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                model.perform {
                    _ = try model.memories.deletePermanently(memoryID)
                    dismiss()
                }
            }
        } message: {
            Text("Cette action est irréversible.")
        }
    }

    private func actionsMenu(_ memory: Memory) -> some View {
        Menu("Actions", systemImage: "ellipsis.circle") {
            switch memory.status {
            case .trashed:
                Button("Restaurer", systemImage: "arrow.uturn.backward") { run { _ = try model.memories.restore(memoryID) } }
                Button("Supprimer définitivement", systemImage: "trash.slash", role: .destructive) { isConfirmingDeletion = true }
            case .archived:
                Button("Désarchiver", systemImage: "arrow.uturn.backward") { run { _ = try model.memories.restore(memoryID) } }
                Button("Mettre à la corbeille", systemImage: "trash", role: .destructive) {
                    run { _ = try model.memories.setStatus(.trashed, for: memoryID, actor: .user) }
                }
            case .active, .unsorted:
                Button("Archiver", systemImage: "archivebox") {
                    run { _ = try model.memories.setStatus(.archived, for: memoryID, actor: .user) }
                }
                Button("Mettre à la corbeille", systemImage: "trash", role: .destructive) {
                    run { _ = try model.memories.setStatus(.trashed, for: memoryID, actor: .user) }
                }
            }
        }
    }

    private func run(_ action: () throws -> Void) {
        model.perform(action)
        reload()
    }

    private func reload() {
        model.perform {
            memory = try model.memories.memory(id: memoryID)
            guard let memory else { return }
            source = try model.memories.source(id: memory.sourceID)
            versions = try model.memories.versions(of: memoryID)
            assigned = try model.categories.categories(for: memoryID)
        }
    }
}
```

`App/Sources/Memory/MemoryEditor.swift` :

```swift
import EngramCore
import SwiftUI

struct MemoryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memory: Memory
    @State private var title: String
    @State private var content: String
    @State private var errorText: String?

    init(memory: Memory) {
        self.memory = memory
        _title = State(initialValue: memory.title)
        _content = State(initialValue: memory.content)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") { TextField("Titre", text: $title) }
                Section("Contenu") {
                    TextEditor(text: $content).frame(minHeight: 220)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", action: save)
                }
            }
        }
    }

    private func save() {
        do {
            _ = try model.memories.updateMemory(memory.id, with: MemoryEdit(title: title, content: content), actor: .user)
            dismiss()
        } catch {
            errorText = AppModel.describe(error)
        }
    }
}
```

`App/Sources/Memory/CategoryPicker.swift` :

```swift
import EngramCore
import SwiftUI

/// Choix manuel des catégories d'un souvenir (en P1, l'IA ne classe pas encore).
struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    @State private var all: [EngramCategory] = []
    @State private var selected: Set<UUID> = []
    @State private var newName = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(all) { category in
                        Button { toggle(category) } label: {
                            HStack {
                                Label(category.name, systemImage: "folder")
                                Spacer()
                                if selected.contains(category.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Nouvelle catégorie") {
                    TextField("Nom", text: $newName)
                        .onSubmit(create)
                    Button("Créer et ajouter", systemImage: "plus", action: create)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Catégories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } }
            }
            .task { load() }
        }
    }

    private func load() {
        do {
            all = try model.categories.activeCategories()
            selected = Set(try model.categories.categories(for: memoryID).map(\.id))
        } catch {
            errorText = AppModel.describe(error)
        }
    }

    private func toggle(_ category: EngramCategory) {
        do {
            if selected.contains(category.id) {
                try model.categories.removeAssignment(memoryID: memoryID, categoryID: category.id, by: .user)
            } else {
                _ = try model.categories.assign(memoryID: memoryID, categoryID: category.id, origin: .user)
            }
            load()
        } catch {
            errorText = AppModel.describe(error)
        }
    }

    private func create() {
        do {
            let category = try model.categories.createCategory(name: newName, parentID: nil, origin: .user).category
            _ = try model.categories.assign(memoryID: memoryID, categoryID: category.id, origin: .user)
            newName = ""
            load()
        } catch {
            errorText = AppModel.describe(error)
        }
    }
}
```

`App/Sources/Search/SearchView.swift` :

```swift
import EngramCore
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [Memory] = []

    var body: some View {
        NavigationStack {
            List(results) { memory in
                NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Cherche dans ta mémoire", systemImage: "magnifyingglass",
                                           description: Text("Par mots, sans te soucier des accents."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Recherche")
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .searchable(text: $query, prompt: "Mots, idées, décisions…")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                model.perform {
                    let hits = try model.memories.searchText(query)
                    results = try model.memories.memories(ids: hits.map(\.memoryID))
                }
            }
        }
    }
}
```

`App/Sources/Settings/SettingsView.swift` :

```swift
import EngramStore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await export() }
                    } label: {
                        HStack {
                            Label("Exporter toute ma mémoire", systemImage: "square.and.arrow.up")
                            if isExporting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Partager ou enregistrer l'export", systemImage: "doc.zipper")
                        }
                    }
                } header: {
                    Text("Mes données")
                } footer: {
                    Text("L'export (JSON, Markdown et audio, dans un fichier ZIP) n'est pas chiffré. Garde-le en lieu sûr.")
                }
                Section("À propos") {
                    LabeledContent("Version", value: Self.versionString)
                    LabeledContent("Analyse IA", value: "Bientôt")
                }
            }
            .navigationTitle("Réglages")
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        let exporter = Exporter(database: model.database)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let result = try await Task.detached(priority: .userInitiated) {
                try exporter.export(into: destination)
            }.value
            exportURL = result.archiveURL
        } catch {
            model.errorMessage = AppModel.describe(error)
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
```

- [ ] **Step 4: Commit et compilation**

```bash
git add project.yml App
git commit -m "feat(app): interface minimale — notes texte, bibliothèque, recherche, détail, export

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Run (en arrière-plan) : `bash scripts/ci.sh`
Expected : `✅ CI verte`, avec le job `ipa` vert et un nouvel artefact `Engram-ipa-<n>`. En cas d'erreur de compilation Swift 6 (concurrence, API SwiftUI) : lire le message exact, corriger, committer `fix(app): …`, relancer.

- [ ] **Step 5: Vérification sur l'iPhone par le propriétaire**

Run : `bash scripts/fetch-ipa.sh`, puis faire installer `build/ipa/Engram.ipa` (même méthode qu'à la tâche 2). L'installation remplace la version précédente.

Liste de contrôle à donner au propriétaire. Il note ✅ ou ❌ pour chaque point. Il peut utiliser de vraies notes, qui restent sur son iPhone : ne jamais envoyer de capture d'écran de vrais souvenirs dans le dépôt.

1. L'app s'ouvre avec 4 onglets : Accueil, Bibliothèque, Recherche, Réglages.
2. Bibliothèque : les 9 catégories de départ sont listées, et « À classer » affiche 0.
3. Accueil : écrire « Test : acheter du lait », puis toucher Enregistrer. Le message « Pensée enregistrée. » apparaît et la note figure dans Récents avec « À classer ».
4. Toucher de nouveau Enregistrer avec le même texte : « Cette pensée vient déjà d'être enregistrée. »
5. Ouvrir la note et toucher Modifier pour changer le titre. L'Historique montre 2 versions ; toucher Restaurer sur la version 1 fait revenir l'ancien titre.
6. « Choisir les catégories… » : cocher Personnel. La note n'est plus « À classer », et Bibliothèque › Personnel affiche 1.
7. Recherche : « LAIT », « lait » et « acheter lait » trouvent la note.
8. Balayer la note vers la gauche et choisir Corbeille. Dans Bibliothèque › Corbeille (1), ouvrir la note, puis Actions › Supprimer définitivement, et confirmer. La note a disparu partout.
9. Réglages › Exporter toute ma mémoire, puis « Partager ou enregistrer l'export » › Enregistrer dans Fichiers. Dans l'app Fichiers, le ZIP s'ouvre et contient `engram.json`, `markdown/` et `LISEZMOI.txt`.
10. Fermer l'app depuis le sélecteur d'apps, puis la rouvrir : les notes sont toujours là.
11. Passer en mode sombre : tout reste lisible.

- [ ] **Step 6: Consigner le résultat et committer**

Mettre à jour `docs/IMPLEMENTATION_PROGRESS.md` :
- F4, F7, F14, F17, F20, F23, F24, F89, F90 et F94 : `Dessiné ✅`, `Implémenté ✅`, `CI ✅`.
- `iPhone ✅` seulement pour les points confirmés par le propriétaire, avec la date.
- Tout point ❌ : noter le symptôme exact dans la colonne Notes, puis ouvrir une correction avec `superpowers:systematic-debugging` avant de passer à la tâche 11.

```bash
git add docs/IMPLEMENTATION_PROGRESS.md
git commit -m "docs: vérification de P1 sur l'iPhone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Clôture de P1

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-engram-phase1-design.md`
- Modify: `docs/IMPLEMENTATION_PROGRESS.md`

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: une spec à jour avec les écarts assumés ; la branche `p1-fondations` intégrée à `main`.

- [ ] **Step 1: Reporter les écarts dans la spec**

Dans `docs/superpowers/specs/2026-10-07-engram-phase1-design.md` :
1. §5.1, table **`memory_category`** : remplacer la ligne de description par
   `` `memory_id` · `category_id` · `origin` (`ai` \| `user`) · `confidence` · `confirmed` · `rejected` (lien retiré par le propriétaire, conservé pour que l'IA ne le recrée pas) · `created_at` · `updated_at`. PK (`memory_id`, `category_id`). ``
   Et ajouter « Même structure, avec `rejected`. » à la ligne `memory_tag`.
2. §5.1, table **`memory_version`** : remplacer « `snapshot` (JSON : titre, résumé, contenu, kind, statut, catégories, tags) » par « `snapshot` (JSON : titre, résumé, contenu, kind, statut ; les liens ont leur propre historique dans `change_log`) ».
3. §5.3, ligne « Supprimer définitivement » : ajouter « Uniquement depuis la corbeille. »
4. §12.2 : remplacer la puce « Build `.ipa` (`build-ipa.yml`) » par « **`.ipa`** : produit à chaque envoi par le job `ipa` de `ci.yml` (archive Release sans signature → `Payload/Engram.app` → `Engram.ipa`, artefact conservé 7 jours). »
5. §4.2 : sous le tableau, ajouter « Les types de catégorie et de tag s'appellent `EngramCategory` et `EngramTag` (évite les conflits avec `Testing.Tag` et le `Category` d'Objective-C). »

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-10-07-engram-phase1-design.md docs/IMPLEMENTATION_PROGRESS.md
git commit -m "docs: spec alignée sur les choix faits pendant P1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Intégrer la branche**

REQUIRED SUB-SKILL : `superpowers:finishing-a-development-branch`. La CI doit être verte sur le dernier commit (`bash scripts/ci.sh`) avant toute intégration. Proposer au propriétaire une pull request vers `main`, puis la fusion.

- [ ] **Step 4: Préparer la suite**

Rédiger le plan **P2 — Moteur de mémoire** avec `superpowers:writing-plans`, à partir de la spec (§6 et §7) et de `docs/notes/2026-10-ios27-sdk.md`.
