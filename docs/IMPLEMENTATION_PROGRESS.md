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

## P4 — « Vraie IA » (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-08-engram-p4-vraie-ia-design.md` · Plan : `docs/superpowers/plans/2026-10-08-engram-p4-vraie-ia.md` · Vérification : `docs/VERIFICATION-IPHONE.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| BUG | Notes en dossiers, sans catégorie vide | ✅ | n/a | ✅ | ✅ | ⏳ | — | cartes « À vérifier », « À faire », « À classer », dossiers ; menu Archives, Corbeille, Réglages |
| BUG | Corbeille : supprimer d'un geste, « Tout supprimer », boutons colorés | ✅ | n/a | ✅ | ✅ | ⏳ | — | confirmation avant toute suppression définitive |
| BUG | Cerveau vide sans points fantômes | ✅ | n/a | ✅ | ✅ | ⏳ | — | seules les catégories qui contiennent une note (et leurs parents) |
| F2 | Whisper bilingue sur l'iPhone (Large V3 Turbo par défaut, Large V3) | ✅ | n/a | ✅ | ✅ (logique) | ⏳ | — | WhisperKit 1.1.0 ; langue par morceau, double décodage si mélange, jamais de traduction ; repli Apple |
| F2 | « Vérifie ta note » avant classement | ✅ | n/a | ✅ | ✅ | ⏳ | — | original toujours gardé ; « À vérifier » survit à une fermeture |
| F2 | Retranscription des anciennes notes | ✅ | n/a | ✅ | ✅ | ⏳ | — | jamais sur une note corrigée ou modifiée à la main |
| F2 | Banc d'essai Turbo / Large V3 | ✅ | n/a | ✅ | ✅ (mesures, règle) | ⏳ | — | 40 phrases fictives ; aucune bascule sans validation |
| PRIV | Contrôleur de confidentialité (neutre, personnel, secret) | n/a | ✅ | ✅ | ✅ | ⏳ | — | détecteurs, lexique, jugement d'Apple ; le doute reste sur l'iPhone |
| F10–F13 | Classement par Gemini (neutre) et Groq (personnel) | ✅ | ✅ | ✅ | ✅ | ⏳ | — | clés dans le trousseau ; quotas, reclassement ; Gemini ne voit que les grandes catégories |
| F10–F13 | IA d'Apple améliorée et fusion des rappels | n/a | ✅ | ✅ | ✅ | ⏳ | — | consignes p4-v1, descriptions de catégories, indices par le sens |
| DÉPÔT | Exemples fictifs à la place des exemples réels | n/a | n/a | ✅ | ✅ | n/a | ✅ | historique Git non réécrit (choix du propriétaire) |

Tests automatiques : **243** (Core 63, Store 110, Pipeline 12, Intelligence 42, Capture 16). Auto-relecture finale : 3 points importants corrigés (catégories envoyées à Gemini, corrections du propriétaire distinguées des retranscriptions, préparation de Whisper).

### Corrections faites ensuite (en autonomie, propriétaire absent)

**Réglage ajouté (prévu par la spec)**
- « Tout garder sur l'iPhone ».

**Confidentialité et transcription**
- Un code suivi de chiffres est toujours secret.
- Whisper ne traduit jamais : un test le garantit.

**Notes et « Vérifie ta note »**
- « À vérifier » n'apparaît plus aussi dans « À classer », ni dans la recherche ou le Cerveau avant d'être classée.
- La carte « Vérifie ta note » affiche la transcription la plus récente.
- Pas de retranscription d'une note corrigée à la main.
- Deux pensées au même extrait n'en font qu'une.

**Dates et calendrier**
- Un rendez-vous suivi d'un rappel (« dentiste mardi à 10 h, rappelle-moi ça lundi ») va au calendrier à sa propre date, pas à celle du rappel.
- Un rappel ajouté à une idée ou à une info en fait une chose « À faire ».
- L'heure d'un autre jour n'est plus collée à l'échéance (« réserver la salle le 24 novembre à 14 h, rappelle-moi ça demain » : demain, sans 14 h).
- Une heure seule déjà passée (« à 9 h » dit à 10 h) désigne le lendemain.
- Un rendez-vous d'aujourd'hui sans heure est ajouté au calendrier, même dicté l'après-midi.
- Une note modifiée à la main reçoit quand même son échéance.
- Les liens du calendrier sont dans l'export.
- Calendrier : plus de rendez-vous affichés en double, rechargement après un ajout, accès refusé expliqué avec un lien vers les Réglages, événements de plusieurs jours affichés chaque jour.

**Écrans**
- Cerveau lisible par VoiceOver (liste des catégories).
- Arrêt automatique à 5 min sans double fin.
- « Ajouté au calendrier » sur la carte de résultat.
- Bouton « + » dans les Notes.
- Boutons principaux et interrupteurs toujours lisibles en mode sombre.

Laissé tel quel (choix de design, non demandé) : « Fait » par balayage plutôt qu'en case à cocher.

**Ajouts suivants**
- Pas de jugement de confidentialité inutile quand aucun service n'est configuré.
- Table officielle des modèles Whisper par puce : signalée dans les Réglages, prise en compte par le banc d'essai.
- Descriptions des anciennes catégories, écrites sur l'iPhone.
- Bouton « + » dans les Notes, recherche toujours visible.
- Cerveau ajusté à l'écran, jours du calendrier plus faciles à toucher.

### Vérification visuelle sans iPhone (simulateur)

Workflow « UI screenshots » : l'app tourne sur un iPhone simulé, avec une base en mémoire remplie de notes **inventées**. Ce mode n'existe qu'en développement, jamais dans l'IPA installée.

**Contrôles**
- Captures de chaque écran, en mode clair et en mode sombre.
- Audit d'accessibilité d'iOS : contraste, libellés, zones touchables, texte coupé.

**Constats**
- Notes, Corbeille (Restaurer et Supprimer visibles, « Tout supprimer » avec confirmation), « Vérifie ta note », Réglages, Cerveau et Calendrier s'affichent correctement dans les deux modes.
- Le test agit aussi, comme toi : il confirme une dictée (« Classer », elle quitte « À vérifier »), balaie une note de la corbeille (Restaurer et Supprimer présents) et vide la corbeille pour de vrai (« Corbeille vide »).
- Défauts trouvés et corrigés : étiquette du Cerveau coupée, zones des jours trop petites, recherche cachée.

Ce n'est **pas** une vérification sur iPhone : la colonne « iPhone » reste ⏳.

Tests automatiques : **271** (Core 67, Store 117, Pipeline 12, Intelligence 56 dont 2 mesures du modèle d'Apple lancées à la main, Capture 19).
