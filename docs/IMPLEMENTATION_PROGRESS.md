# Engram — État réel du développement

Légende : ✅ fait · ⏳ en cours · — pas encore · n/a sans objet

Colonnes : **Dessiné** (l'écran existe) · **Simulé** (fonctionne avec de faux services) · **Implémenté** (vrai code) · **CI** (tests automatiques verts) · **iPhone** (vérifié par le propriétaire sur son iPhone) · **Prêt** (utilisable au quotidien)

## Phase 1

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| INFRA-1 | Compilation GitHub Actions et `.ipa` | n/a | n/a | ✅ | ✅ | n/a | ✅ | premier run vert le 2026-10-07 |
| INFRA-2 | Installation via AltStore | n/a | n/a | n/a | n/a | ✅ | ✅ | confirmé par le propriétaire le 2026-10-07 (build 1) |
| INFRA-3 | Relevé des API iOS 27 | n/a | n/a | ✅ | ✅ | n/a | ✅ | `docs/notes/2026-10-ios27-sdk.md` ; relevé ciblé complémentaire au début de P2 |
| F1 | Capture vocale | — | — | — | — | — | — | plan P3 |
| F2 | Transcription | — | — | — | — | — | — | plan P3 |
| F3 | Découpage d'un enregistrement | — | — | — | — | — | — | plan P2 |
| F4 | Capture textuelle | ✅ | n/a | ✅ | ✅ | ✅ | — | P1 sans IA (souvenir « À classer »), P2 avec IA |
| F7 | Conservation des originaux | ✅ | n/a | ✅ | ✅ | ✅ | — | texte d'origine affiché dans « Source » |
| F10 | Pipeline de transformation | n/a | — | — | — | — | — | plan P2 |
| F11 | Titres et résumés | ✅ | — | ✅ | ✅ | ✅ | — | P1 : titre de repli (première ligne, ≤ 80 caractères) |
| F12 | Catégories automatiques | — | — | — | — | — | — | plan P2 ; stockage anti-synonymes prêt (CI ✅) |
| F13 | Classement automatique | ✅ | — | — | — | — | — | P1 : classement manuel (« Choisir les catégories… ») |
| F14 | Classification multiple | ✅ | n/a | ✅ | ✅ | ✅ | — | |
| F15 | Tags | — | — | ✅ | ✅ | n/a | — | stockage + règle du propriétaire ; écran en P4 |
| F17 | Persistance locale | n/a | n/a | ✅ | ✅ | ✅ | — | SQLite protégé par la Data Protection d'iOS |
| F20 | Doublons (partiel) | ✅ | n/a | ✅ | ✅ | ✅ | — | P1 : doublons techniques (10 min) |
| F23 | Provenance | ✅ | n/a | ✅ | ✅ | ✅ | — | |
| F24 | Modification, versions, restauration | ✅ | n/a | ✅ | ✅ | ✅ | — | |
| F89 | Export ouvert | ✅ | n/a | ✅ | ✅ | ✅ | — | JSON + Markdown + audio + ZIP |
| F90 | Suppression contrôlée | ✅ | n/a | ✅ | ✅ | ⏳ | — | archive, corbeille, suppression définitive : OK ; correctif de navigation de la Corbeille (point 8) à revérifier |
| F94 | Recherche (partiel) | ✅ | n/a | ✅ | ✅ | ✅ | — | P1 : par mots, insensible aux accents, avec filtres |

Tests automatiques au dernier run : **75** (21 EngramCore + 54 EngramStore).

Vérification iPhone de P1 par le propriétaire le 2026-10-08 : points 1 à 7 et 9 à 11 ✅ ; point 8 ❌ (navigation Corbeille) → corrigé (commit bf…/LibraryRoute), à revérifier.
