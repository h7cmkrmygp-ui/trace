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

## P2 — « Je parle, c'est classé » (branche `p2-je-parle`)

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| F1 | Capture vocale (5 min, CAF) | ✅ | n/a | ✅ | compile | ⏳ | — | VoiceRecorder |
| F2 | Transcription sur l'iPhone (fr-CA) | n/a | n/a | ✅ | compile | ⏳ | — | après l'arrêt ; Whisper en P3 si besoin |
| F3/F10/F11 | Découpage, titres, résumés | ✅ | ✅ | ✅ | ✅ | ⏳ | — | AppleThoughtAnalyzer + validateur anti-invention |
| F12/F13/F14 | Catégories et sous-catégories automatiques | ✅ | ✅ | ✅ | ✅ | ⏳ | — | aucune catégorie de départ |
| F15 | Tags par l'IA | — | ✅ | ✅ | ✅ | ⏳ | — | |
| — | Liste « À faire » | ✅ | n/a | ✅ | ✅ | ⏳ | — | |
| — | Évaluation (40 phrases fictives) | ✅ | n/a | ✅ | ✅ | ⏳ | — | Réglages › Évaluer le classement |

Tests automatiques : **115** (Core 31, Store 69, Pipeline 8, Intelligence 5, Capture 2).

## P3 — « Cerveau et Calendrier » (branche `p2-je-parle`)

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| F25–F27 | Cerveau (nuage de points, zoom, ouverture) | ✅ | n/a | ✅ | ✅ (disposition) | ⏳ | — | |
| F49/F50 | Calendrier + rendez-vous ajoutés au calendrier de l'iPhone | ✅ | n/a | ✅ | ✅ (données) | ⏳ | — | Google via les comptes iOS |
| F51/F57 | Échéances calculées depuis les dates dites | ✅ | n/a | ✅ | ✅ | ⏳ | — | DateResolver déterministe |

Tests automatiques : **149** (Core 48, Store 83, Pipeline 10, Intelligence 5, Capture 3). Relecture indépendante P2+P3 faite ; 1 critique et 9 importants corrigés.
