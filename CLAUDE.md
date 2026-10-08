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
