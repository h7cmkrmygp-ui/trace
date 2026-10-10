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
- Une note qui demande un rappel (« rappelle-moi », « fais-moi penser », « remind me ») va dans « À faire », quelle que soit l'IA qui l'a classée (un rendez-vous reste un rendez-vous).
- L'heure d'un autre jour n'est plus collée à l'échéance (« réserver la salle le 24 novembre à 14 h, rappelle-moi ça demain » : demain, sans 14 h).
- Une heure seule déjà passée (« à 9 h » dit à 10 h) désigne le lendemain.
- Un rendez-vous d'aujourd'hui sans heure est ajouté au calendrier, même dicté l'après-midi.
- Une note modifiée à la main reçoit quand même son échéance.
- Les liens du calendrier sont dans l'export.
- Calendrier : plus de rendez-vous affichés en double, rechargement après un ajout, accès refusé expliqué avec un lien vers les Réglages, événements de plusieurs jours affichés chaque jour.

**Écrans**
- Cerveau vide : plus aucun point derrière « Ton cerveau est vide » (le point central n'est plus dessiné), message lisible par VoiceOver ; compteur « 1 note » au singulier.
- Cerveau lisible par VoiceOver (liste des catégories).
- Arrêt automatique à 5 min sans double fin.
- « Ajouté au calendrier » sur la carte de résultat.
- Bouton « + » dans les Notes.
- Boutons principaux et interrupteurs toujours lisibles en mode sombre.
- « Réécouter » sur la carte revient tout seul à la fin de la lecture, et la musique des autres apps reprend.

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
- Mémoire vide : le Cerveau affiche seulement « Ton cerveau est vide » (aucun point derrière, message lu par VoiceOver), et les Notes « Aucune note pour l'instant ».
- Défauts trouvés et corrigés : étiquette du Cerveau coupée, zones des jours trop petites, recherche cachée.

Ce n'est **pas** une vérification sur iPhone : la colonne « iPhone » reste ⏳.

Tests automatiques : **273** (Core 68, Store 117, Pipeline 12, Intelligence 57 dont 2 mesures du modèle d'Apple lancées à la main, Capture 19).

## P5 — « Je parle, c'est enregistré ; je demande, ça revient » (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-08-engram-p5-retrouver-design.md`

Retour du propriétaire sur l'iPhone (2026-10-08) : la note est bien enregistrée et classée, mais l'app se fermait en touchant le bouton de la carte « Vérifie ta note » ; le chat était introuvable (il n'existait pas dans le code).

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| BUG | Plus de fermeture à « Classer » | ✅ | n/a | ✅ | ✅ (parcours sur simulateur) | ⏳ | — | la carte avait un lien « forcé » vers la dictée : elle relisait une valeur déjà effacée ; feuille avec sa propre copie, boutons au-dessus du clavier |
| F1 | Enregistrement sans confirmation | ✅ | n/a | ✅ | ✅ | ⏳ | — | « Vérifier avant de classer » désactivé par défaut (option gardée) ; « Enregistré » + retour haptique |
| F1 | Arrêt automatique quand on se tait | n/a | ✅ | ✅ | ✅ (détecteur) | ⏳ | — | après 1 s de parole et 4 s de silence ; une pause pour réfléchir ne coupe pas ; réglage |
| F94 | Retrouver (et chat) | ✅ | ✅ | ✅ | ✅ (moteur, parcours) | ⏳ | — | question écrite ou dictée ; période, type, mots, mots proches, sens ; réponse de l'IA d'Apple à partir des seules notes ; tout sur l'iPhone |
| — | Notes liées | ✅ | ✅ | ✅ | ✅ | ⏳ | — | au plus 3, seulement au-dessus d'un seuil |
| — | Rappels (notifications) | ✅ | ✅ | ✅ | ✅ (calcul) | ⏳ | — | à l'heure dite, 1 h avant un rendez-vous, 9 h sans heure ; note secrète : « Rappel Engram » seulement |
| — | Siri, raccourcis, bouton Action | n/a | n/a | ✅ | compile | ⏳ | — | « Enregistrer une pensée », « Noter dans Engram », « Demander à Engram » (iPhone déverrouillé) |
| — | Détail d'une note | ✅ | n/a | ✅ | compile | ⏳ | — | type et échéance affichés, « Marquer comme fait » |

Tests automatiques : **304** (Core 88, Store 119, Pipeline 12, Intelligence 61 dont 2 mesures du modèle d'Apple lancées à la main, Capture 24).

Ajouts de P5 faits ensuite :
- « dans 10 minutes », « dans 2 heures » donnent une échéance précise (rappels relatifs).
- Retrouver comprend « récentes », « dernières », et affine par une question de suite (« Et la semaine passée ? », « de ce sujet »).
- Descriptions des dossiers lisibles en très grand texte ; transitions discrètes (désactivées avec « Réduire les animations »).

## P6 — Cerveau vivant, tâches qui avancent, widgets (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-08-engram-p6-cerveau-rappels-widgets-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| F25 | Cerveau vivant | ✅ | n/a | ✅ | ✅ (captures, mouvements) | ⏳ | — | neurones colorés qui respirent, notes en orbite, signaux sur les synapses, silhouette, poussière de lueurs, catégories à centrer ; immobile avec « Réduire les animations » |
| — | Couleurs de catégorie partout | ✅ | n/a | ✅ | ✅ (couleur stable) | ⏳ | — | Cerveau, Notes, Retrouver, détail d'une note |
| — | Sphère d'enregistrement | ✅ | n/a | ✅ | compile | ⏳ | — | verre, lumière qui tourne ; ondes rouges pendant l'enregistrement |
| — | Rappels « Fait », « Dans 1 h », « Demain » | n/a | ✅ | ✅ | ✅ (reports) | ⏳ | — | le report est gardé sur l'iPhone |
| — | Résumé du matin, pastille, résumé de la semaine | n/a | ✅ | ✅ | ✅ (calcul) | ⏳ | — | 8 h (jour et retards) ; dimanche 18 h ; jamais de titre secret |
| — | Widgets « Aujourd'hui » et « Enregistrer », Centre de contrôle | ✅ | n/a | ✅ | compile | ⏳ | — | titres masqués écran verrouillé ; recalcule « aujourd'hui » seul les jours suivants |
| — | Partager vers Engram | ✅ | ✅ | ✅ | ✅ (boîte de dépôt) | ⏳ | — | texte ou lien, classé à l'ouverture suivante |
| — | Conversation de Retrouver gardée | ✅ | n/a | ✅ | compile | ⏳ | — | 30 derniers échanges, effacée par « Nouvelle recherche » |
| INFRA | Deux IPA | n/a | n/a | ✅ | ✅ | ⏳ | — | `Engram.ipa` (extensions, droits en signature ad hoc) et `Engram-simple.ipa` (comme avant) |

Tests automatiques : **317** (Core 100, Store 120, Pipeline 12, Intelligence 61 dont 2 mesures du modèle d'Apple lancées à la main, Capture 24).

## P7 — Sauvegarde chiffrée et Face ID (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p7-sauvegarde-faceid-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| F89 | Sauvegarde chiffrée automatique | ✅ | ✅ | ✅ | ✅ (chiffrement, copie, restauration) | ⏳ | — | PBKDF2 600 000 tours + AES-GCM par blocs ; dossier choisi (iCloud Drive) ; chaque semaine ; 4 gardées |
| F90 | Restauration | ✅ | ✅ | ✅ | ✅ | ⏳ | — | vérifiée avant ; appliquée au lancement suivant ; anciennes données gardées dans « Avant-restauration » |
| PRIV | Verrouillage Face ID | ✅ | n/a | ✅ | compile | ⏳ | — | au retour dans l'app ; contenu masqué dans le sélecteur ; widgets et notifications sans titres |

Tests automatiques : **324** (Core 105, Store 122, Pipeline 12, Intelligence 61 dont 2 mesures du modèle d'Apple lancées à la main, Capture 24).

## P8 — Corrections finales : bruit, franglais, navigation, Cerveau, vraie note (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p8-corrections-finales-design.md` · Étude MCP : `docs/ASSISTANTS-MCP.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| BUG | Arrêt automatique malgré le bruit | n/a | ✅ | ✅ | ✅ (musique, ventilateur, voix au loin, coup à la porte, pauses) | ⏳ | — | seuil réglé sur ta voix (10 dB sous tes syllabes fortes) ; bruit bref isolé ignoré |
| BUG | Phrase d'exemple jetée | n/a | ✅ | ✅ | ✅ | ⏳ | — | c'était l'amorce de Whisper, prise pour un écho ; nouvelle amorce |
| — | « euh », « hum » retirés | n/a | ✅ | ✅ | ✅ | ⏳ | — | élision refaite (« de euh appeler » → « d'appeler ») ; l'audio reste entier |
| — | Deux sujets par phrase, titres en bon français | n/a | ✅ | ✅ (consignes p8) | ✅ (consignes, extraits presque mot pour mot) | ⏳ | — | « call » → « appeler », « shift » → « quart de travail » ; « pis après » hérite de la date |
| — | Vraie date dans les titres | n/a | ✅ | ✅ | ✅ | ⏳ | — | « aujourd'hui » → « le 9 octobre » ; tes mots exacts restent |
| — | Sous-catégories plus précises | n/a | n/a | ✅ (consignes) | ✅ (consignes) | ⏳ | — | Finance › Assurances, Travail › Horaire… ; anciennes notes non reclassées |
| BUG | Onglet qui garde la sous-page | n/a | n/a | ✅ | ✅ (test d'interface sur simulateur) | ⏳ | — | piles de navigation vidées en quittant l'onglet |
| — | Vraie note (titre, texte, cases à cocher) | ✅ | n/a | ✅ | ✅ (texte ↔ cases) | ⏳ | — | modifiée sur place, enregistrée en quittant un champ ; détails techniques dans « Détails » |
| — | Cerveau sobre et utile | ✅ | n/a | ✅ | ✅ (captures, recherche sur simulateur) | ⏳ | — | panneau des notes du neurone touché ou des résultats ; titres de près |
| — | Raccourci « Trouver dans Engram pour un assistant » | n/a | ✅ | ✅ | ✅ (notes privées exclues) | ⏳ | — | pour ChatGPT ou Claude, à ta demande ; MCP en ligne mis de côté (serveur et copie de la mémoire hors de l'iPhone) |
| — | « Demande à ton cerveau » | n/a | n/a | ✅ | ✅ (recherche sur simulateur) | ⏳ | — | la recherche du Cerveau passe par le moteur de Retrouver ; « Réponse complète dans Retrouver » |
| — | Visuel des dossiers des Notes | ✅ | n/a | ✅ | ✅ (disposition, cases à cocher) | ⏳ | — | petit réseau du dossier en haut ; icône du type et « 2/3 » dans les lignes |

Tests automatiques : **357** (Core 127, Store 124, Pipeline 12, Intelligence 62 dont 2 mesures du modèle d'Apple lancées à la main, Capture 32) ; après la P9 : **376** (Core 132, Store 136, Pipeline 13, Intelligence 63, Capture 32).

## P9 — Les personnes et les lieux de ta mémoire (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p9-personnes-lieux-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Noms reconnus au classement | n/a | ✅ | ✅ (consignes p9) | ✅ (décodage, schéma, anti-invention) | ⏳ | — | Gemini, Groq ou Apple ; 4 personnes et 4 lieux au plus par note ; jamais « je » ni « moi » |
| — | Doublons et décisions du propriétaire | n/a | ✅ | ✅ | ✅ (clés, alias, fusion, renommage, masquage, retrait) | ⏳ | — | « mon manager » = « le manager » ; un nom retiré ne revient pas |
| — | Pages Personnes et Lieux | ✅ | n/a | ✅ | compile + captures | ⏳ | — | à faire, notes par mois, renommer, fusionner, masquer |
| — | Pastilles dans une note | ✅ | n/a | ✅ | compile | ⏳ | — | toucher ouvre la page, appui long retire, « Ajouter » |
| — | Anciennes notes relues sur l'iPhone | n/a | ✅ | ✅ | ✅ (faux reconnaisseur) | ⏳ | — | NaturalLanguage d'Apple, rien n'est envoyé |
| — | Personnes dans le Cerveau | ✅ | n/a | ✅ | ✅ (liens) | ⏳ | — | nœuds neutres reliés à leurs notes par des pointillés |
| — | Retrouver et export | n/a | ✅ | ✅ | ✅ | ⏳ | — | les noms comptent comme mots forts ; export JSON complet |

## P10 — Les suivis (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p10-suivis-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Mesures reconnues sur l'iPhone | n/a | ✅ | ✅ | ✅ (une trentaine de phrases, pièges) | ⏳ | — | poids, sommeil, tension, pouls, pas, glycémie ; aucune IA, aucun envoi |
| — | Table des mesures (migration v6) | n/a | n/a | ✅ | ✅ (classement, hier, corbeille, suppression, relecture, export) | ⏳ | — | relevées au classement et au lancement |
| — | Suivis et graphiques | ✅ | n/a | ✅ | compile + captures | ⏳ | — | cartes, courbes, Mois/3 mois/Année/Tout, min/moy/max, livres ou kilos |
| — | Pastilles « Suivi » dans une note | ✅ | n/a | ✅ | compile | ⏳ | — | ouvrent le graphique |

Tests automatiques après la P10 : **393** (Core 142, Store 143, Pipeline 13, Intelligence 63, Capture 32). Relecture des mesures : seulement les notes nouvelles ou modifiées depuis la dernière fois.

## P11 — Épingler, journal, objectifs (branche `p2-je-parle`)

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Notes épinglées | ✅ | n/a | ✅ | ✅ (ordre, corbeille) | ⏳ | — | migration v7 ; carte « Épinglées » en haut des Notes |
| — | Journal jour par jour | ✅ | n/a | ✅ | ✅ (noms des jours, regroupement) | ⏳ | — | « Aujourd'hui », « Hier », « Mercredi 13 janvier », l'année si elle change |
| — | Objectifs des suivis | ✅ | ✅ | ✅ | ✅ (dits dans une note, le plus récent l'emporte, progression dans les deux sens) | ⏳ | — | ligne pointillée sur le graphique, barre de progression |

## P12 — Photo → note (branche `p2-je-parle`)

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Texte d'une photo, lu sur l'iPhone | ✅ | n/a | ✅ | ✅ (mise au propre : phrases recollées, césures, listes, bruit) | ⏳ | — | Vision d'Apple, français et anglais ; appareil photo ou photothèque ; vérifié avant le classement ; la photo n'est pas gardée |

## P13 — « Te souviens-tu ? » et résumé du dimanche (branche `p2-je-parle`)

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Te souviens-tu ? » à 19 h | ✅ | n/a | ✅ | ✅ (19 h, demain après 19 h, une différente chaque soir, jamais une tâche ni une note privée) | ⏳ | — | idées de plus de 30 jours ; toucher ouvre la note ; sans titre si Engram est verrouillé ; réglage dans Rappels |
| — | Résumé du dimanche plus riche | n/a | n/a | ✅ | ✅ (personnes, évolution des suivis) | ⏳ | — | « Avec Julie et Marc », « Poids −1,2 lb · Sommeil 7 h 10 en moyenne » ; aucun nom si Engram est verrouillé |

## P14 — Rappels de lieu (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p14-rappels-de-lieu-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Quand j'arrive chez… » reconnu | n/a | ✅ | ✅ | ✅ (arriver, partir, maison, anglais ; pièges « j'arrive à dormir », « à l'aise », « au bout ») | ⏳ | — | sur l'iPhone, sans IA ; le lieu est créé et relié à la note |
| — | Adresse d'un lieu (migration v8) | ✅ | n/a | ✅ | ✅ (personne refusée, fusion, export, effacée avec la note) | ⏳ | — | ma position actuelle ou recherche Plans d'Apple ; rayon 100, 200 ou 500 m ; petite carte |
| — | Notification en arrivant (ou en partant) | n/a | n/a | ✅ | ✅ (20 lieux au plus, notes privées discrètes) | ⏳ | — | `UNLocationNotificationTrigger` : iOS surveille seul ; « Fait » depuis la notification ; revient à chaque arrivée tant que ce n'est pas fait |
| — | Pastille « En arrivant · Costco » | ✅ | n/a | ✅ | compile + capture | ⏳ | — | menu : voir le lieu ou ajouter l'adresse, « en partant plutôt », retirer ; poser à la main depuis … |

## P15 — Listes (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p15-listes-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Ajoute … à ma liste d'épicerie » reconnu | n/a | ✅ | ✅ | ✅ (6 façons de le dire, anglais, pièges « ajoute une réunion à mon calendrier », « ma liste est longue ») | ⏳ | — | sur l'iPhone, sans IA |
| — | Une note par liste (migration v9) | ✅ | n/a | ✅ | ✅ (sans doublon, case cochée qui revient, jamais ajoutée deux fois, corbeille, dictée mêlée, export) | ⏳ | — | la dictée qui complète ne laisse pas de note |
| — | Notes › Listes, « Retirer les cases cochées » | ✅ | n/a | ✅ | compile + captures | ⏳ | — | carte en haut des Notes |

## P16 — Tâches qui reviennent (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p16-taches-qui-reviennent-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Rythme dicté reconnu | n/a | ✅ | ✅ | ✅ (jour, matin, jours de la semaine, en semaine, aux deux semaines, tous les 3 mois, le 1er du mois, chaque année ; pièges) | ⏳ | — | sur l'iPhone, sans IA ; seulement tâches et rendez-vous |
| — | La prochaine fois (migration v10) | n/a | ✅ | ✅ | ✅ (semaine, deux jours dans la semaine, aux deux semaines, 31 → 28 février, année) | ⏳ | — | sans date dite, la tâche prend la prochaine fois |
| — | « Fait » passe à la prochaine fois | ✅ | n/a | ✅ | ✅ (compte, version, « Jamais » qui archive de nouveau, export) | ⏳ | — | menu, glissement et notification ; les rappels suivent |
| — | Pastille « Tous les lundis », « Répéter… » | ✅ | n/a | ✅ | compile | ⏳ | — | Jamais, jour, semaine (jours), deux semaines, mois (jour précis), année |

## P17 — Habitudes (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p17-habitudes-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Habitudes reconnues | n/a | ✅ | ✅ | ✅ (7 habitudes, quantités, hier, anglais ; projets, refus et faux amis) | ⏳ | — | sur l'iPhone, sans IA |
| — | Séries, semaine, grille (migration v11) | ✅ | ✅ | ✅ | ✅ (série vivante jusqu'au lendemain, meilleure série, semaine, grille de 16 semaines, corbeille, anciennes notes, export) | ⏳ | — | une relecture complète des anciennes notes, une seule fois |
| — | Cartes « Habitudes » et page d'une habitude | ✅ | n/a | ✅ | compile + captures | ⏳ | — | dans Notes › Suivis |

## P18 — « Ta semaine » (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p18-ta-semaine-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Chiffres de la semaine | n/a | ✅ | ✅ | ✅ (notes, semaine d'avant, faites dont les tâches qui reviennent, à faire, jours, dossiers principaux, personnes, habitudes) | ⏳ | — | lus sur l'iPhone |
| — | Page « Ta semaine » | ✅ | n/a | ✅ | compile + capture | ⏳ | — | titre, comparaison, jour le plus actif, flèches pour remonter les semaines |
| — | Le résumé du dimanche ouvre « Ta semaine » | n/a | n/a | ✅ | compile | ⏳ | — | au lieu d'une question à Retrouver |

## P19 — Listes à la voix (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p19-listes-a-la-voix-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Coche le lait », « j'ai acheté le pain » | n/a | ✅ | ✅ | ✅ (cocher, retirer, anglais, pièges « enlève tes souliers ») | ⏳ | — | sans nouvelle note ; la liste qui contient la chose, l'épicerie d'abord |
| — | Cases retrouvées malgré la façon de les dire | n/a | ✅ | ✅ | ✅ (« Lait 2 % », pluriel, « œufs »/« oeufs », jamais « Laitue ») | ⏳ | — | |
| — | « J'ai acheté une tondeuse » reste une note | n/a | n/a | ✅ | ✅ | ⏳ | — | une demande claire sans case ne devient pas une note |
| — | Partager une note | ✅ | n/a | ✅ | compile | ⏳ | — | … › « Partager » |

## P20 — Fêtes (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p20-fetes-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Fête dictée reconnue | n/a | ✅ | ✅ | ✅ (6 façons de le dire, l'année, « ma mère », anglais ; Noël, mariage, 31 février) | ⏳ | — | sur l'iPhone, sans IA ; la personne est créée au besoin |
| — | Fête d'une personne (migration v12) | ✅ | n/a | ✅ | ✅ (posée, changée, retirée, lieu refusé, fusion, personne masquée, export) | ⏳ | — | section « Fête » et « Fêtes à venir » |
| — | Rappels la veille et le jour même | n/a | ✅ | ✅ | ✅ (âge, 29 février, sans nom si verrouillé, veille passée) | ⏳ | — | 60 prochains jours |

## P21 — Garde ta série (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p21-garde-ta-serie-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Objectif d'habitude par semaine (migration v13) | ✅ | ✅ | ✅ | ✅ (dit de 5 façons, pièges, le plus récent l'emporte, fixé ou retiré à la main, export) | ⏳ | — | « 3/5 cette semaine » sur la carte |
| — | « Garde ta série » à 20 h | n/a | ✅ | ✅ | ✅ (série vivante pas faite, déjà faite, trop tard, une journée, plusieurs habitudes) | ⏳ | — | réglage dans Rappels ; sans nom si verrouillé |

## P22 — Calendrier plus complet (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p22-calendrier-complet-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Prochaines fois des tâches qui reviennent | ✅ | ✅ | ✅ | ✅ (après l'échéance, jamais avant, mois suivant, tâche jetée) | ⏳ | — | dans le Calendrier |
| — | Fêtes dans le Calendrier | ✅ | ✅ | ✅ | ✅ (âge, 29 février) | ⏳ | — | toucher ouvre la personne |

## P23 — Doublons possibles (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p23-doublons-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | La même pensée dite deux fois est proposée | ✅ | ✅ | ✅ | ✅ (pas deux notes différentes, pas un autre genre, pas à 45 jours, pas un seul mot) | ⏳ | — | carte « Doublons possibles » |
| — | Réunir sans rien perdre (migration v14) | ✅ | n/a | ✅ | ✅ (texte, dossiers, personnes, doublon à la corbeille, plus proposé) | ⏳ | — | le doublon se récupère dans la corbeille |
| — | « Ce n'est pas un doublon » | ✅ | n/a | ✅ | ✅ | ⏳ | — | |

## P24 — « Ce jour-là » (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p24-ce-jour-la-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Notes du même jour, il y a un mois, six mois, un an… | ✅ | ✅ | ✅ | ✅ (moments, note privée, mois plus court, trois au plus) | ⏳ | — | carte dans les Notes |

## P25 — Widget « Liste » (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p25-widget-liste-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Ce qui reste sur la liste, sur l'écran d'accueil | ✅ | ✅ | ✅ | ✅ (épicerie d'abord, 4 listes, 8 choses, liste privée, Engram verrouillé) | ⏳ | — | installation complète seulement ; toucher ouvre la liste |

## P26 — Les listes avec Siri (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p26-listes-avec-siri-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Lis ma liste dans Engram » | n/a | ✅ | ✅ | ✅ (liste, tout coché, vide, longue, privée, liste nommée) | ⏳ | — | iPhone déverrouillé exigé |
| — | « Ajoute à ma liste dans Engram » | n/a | ✅ | ✅ | ✅ (la demande devient une vraie commande de liste) | ⏳ | — | classée comme une dictée |

## P27 — « Ma journée » avec Siri (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p27-ma-journee-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Ma journée dans Engram » | n/a | ✅ | ✅ | ✅ (heures d'abord, retards, fêtes, séries, journée vide, note privée, longue journée) | ⏳ | — | iPhone déverrouillé exigé |

## P28 — « Ton mois » (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p28-ton-mois-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Bilan d'un mois | ✅ | ✅ | ✅ | ✅ (titre, mois d'avant, jour le plus actif, mois jour par jour, la semaine inchangée) | ⏳ | — | Semaine | Mois dans « Ta semaine » |

## P29 — La liste t'attend au magasin (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p29-la-liste-t-attend-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | « Liste de Costco » prévient en arrivant chez Costco | n/a | ✅ | ✅ | ✅ (lieu avec adresse, tout coché, lieu inconnu, pas de double) | ⏳ | — | rien à régler |

## P30 — L'adresse des lieux, trouvée toute seule (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p30-lieux-trouves-tout-seuls-design.md`

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Adresse trouvée toute seule après la dictée | n/a | ✅ | ✅ | ✅ (3 plus proches à 40 km, noms qui correspondent, mot général, jamais un lieu à soi ni chez quelqu'un) | ⏳ | — | Plans d'Apple : le nom du lieu et la zone seulement |
| — | N'importe quelle succursale prévient (migration v15) | n/a | ✅ | ✅ | ✅ (une région par succursale, 20 au plus, choix du propriétaire qui l'emporte, recherche refaite après une semaine, export) | ⏳ | — | réglage dans Rappels |

## Icône de l'app (branche `p2-je-parle`)

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Icône « une pensée qui devient un souvenir » | ✅ | n/a | ✅ | construction de l'IPA | ⏳ | — | une onde de voix qui devient une constellation ; image 1024 × 1024 sans transparence, la même en mode sombre |

## P31 — Les fêtes bien retenues, des catégories qui viennent du sens (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p31-fetes-et-categories-design.md` — signalé sur l'iPhone (une fête classée dans Santé › Poids, « C'est quand la fête à Inès ? » sans réponse).

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | Plus de liste de catégories toute faite dans les consignes (Gemini, Groq, Apple) | n/a | ✅ | ✅ | ✅ (aucun exemple de catégorie, réutiliser seulement si le sujet y va vraiment, sinon en créer une, sous-catégorie facultative) | ⏳ | — | consignes `p31-cloud-v1`, `p31-v1` |
| — | Ce qu'Engram a reconnu est dit à l'IA (fête, mesure, liste) | n/a | ✅ | ✅ | ✅ (Gemini, Groq et l'iPhone le reçoivent) | ⏳ | — | rien de plus que la note ne part |
| — | Un suivi (Poids, Sommeil…) ne reçoit que sa mesure | n/a | ✅ | ✅ | ✅ (une fête ou une nuit de sommeil refusées dans Poids, « À classer » plutôt que mal rangée) | ⏳ | — | aussi pour les anciennes notes, une fois |
| — | Fêtes dites comme au Québec | n/a | ✅ | ✅ | ✅ (« la fête à », jour en lettres, « fête ses 30 ans » → année de naissance, extrait incomplet relu) | ⏳ | — | anciennes notes relues une fois |
| — | Retrouver et Siri répondent « C'est quand la fête à … ? » | n/a | ✅ | ✅ | ✅ (« fête » = « anniversaire », nom à une lettre près, date et âge) | ⏳ | — | depuis la page de la personne |

## P32 — Le choix de la catégorie : fait par l'IA, réfléchi et visible (branche `p2-je-parle`)

Spec : `docs/superpowers/specs/2026-10-09-engram-p32-choix-de-l-ia-reflechi-design.md` — demande : « assure-toi que c'est vraiment l'IA qui choisit, de façon intelligente ».

| ID | Fonctionnalité | Dessiné | Simulé | Implémenté | CI | iPhone | Prêt | Notes |
|---|---|---|---|---|---|---|---|---|
| — | L'IA lit ce que contient chaque catégorie | n/a | ✅ | ✅ | ✅ (Apple : toutes ; Groq : sans coordonnées, numéros ni montants ; Gemini : aucune) | ⏳ | — | descriptions des catégories |
| — | L'IA explique son choix avant de le faire (migration v16) | n/a | ✅ | ✅ | ✅ (raison avant la catégorie dans la réponse, gardée avec la note, effacée si le chemin est refusé ou retiré par le propriétaire) | ⏳ | — | note › Détails › « Pourquoi ce dossier » |
| — | Évaluation sur l'iPhone comme une vraie note | n/a | ✅ | ✅ | ✅ (49 phrases, dont deux fêtes et une assurance ; raison affichée) | ⏳ | — | Réglages › Intelligence |
