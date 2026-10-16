# Moteur fiable — suivi des constats F01 à F29

Branche de travail : `moteur-fiable` (issue de `p2-je-parle` au commit a45ba3d, le commit de l'audit du 16 octobre 2026).
Rapport : `Audit_Engram_Trace_2026-10-16.pdf` (fourni par le propriétaire, hors du dépôt).

Règles :
- chaque correction commence par un test qui échoue sur le défaut, poussé sur la CI (rouge), puis le code (vert) ;
- aucune migration publiée n'est modifiée ; aucune donnée existante n'est supprimée ou réanalysée sans choix explicite.

## Point de reprise

Dernière étape terminée : voir la colonne « État » ci-dessous et `git log --oneline moteur-fiable`.

## Tableau

| ID | Constat (audit) | État dans le code actuel | Correction | Fichiers | Tests | Résultat CI | Limites / reste |
|---|---|---|---|---|---|---|---|
| F01 | Liste agrégée sans la confidentialité de ses ajouts | Confirmé (ListStore.widgetSources lisait la seule première source) | Fait : masque des destinations interdites par liste (`memory_list.forbidden_mask`, jamais abaissé, migration v19 avec reprise des listes existantes) ; widget, rappels de lieu, Siri (`widgetSources`), Retrouver, export pour assistant et contexte envoyé suivent toutes les contributions | PrivacyPolicy.swift, ListStore.swift, ListActionStore.swift, Reminders.swift, PlaceReminders.swift, TextSearch.swift, AssistantExport.swift, Schema.swift | PrivacyPolicyTests, PrivacyBoundaryStoreTests | Vert (run 38914400687) | Provenance par élément : F09 |
| F02 | Contexte historique sans politique héritée | Confirmé (RoutedAnalyzer filtrait par mots, sans provenance) | Fait : `ContextProvenance` calculée sur l'iPhone (dossiers, listes, dictée précédente) ; enveloppe par destination ; sans provenance connue, aucun dérivé ne sort ; filtres de mots gardés en défense | RoutedAnalyzer.swift, OutboundProvenance.swift, ThoughtProcessor.swift | OutboundEnvelopeTests, OutboundProvenanceStoreTests, ProvenancePipelineTests | Vert (run 38914400687) | Descriptions neutres vérifiées : à mesurer |
| F03 | Contrat d'intention insuffisant | Confirmé (AnalyzedThought sans intention, polarité ni modalité) | À faire (lot C) | | | | |
| F04 | Parseurs de listes prioritaires sur le sens | Confirmé (`spoken ?? understood`, ListActionParser d'abord) | À faire (lot C) | | | | |
| F05 | Couverture par mots qui perd des intentions | Confirmé (`leftover` par ensemble de mots, ≥ 3 mots, « pas » ignoré) | Fait : couverture par positions exactes (`uncoveredPassages`, `EvidenceSpan` UTF-16) ; négations et commandes courtes gardées ; un passage par note à classer | AnalysisValidator.swift, EvidenceSpan.swift, ThoughtFiler.swift | PassageCoverageTests, PrivacyBoundaryStoreTests, PrivacyAndCoveragePipelineTests | Vert (run 38914400687) | Couverture par intention : lot C |
| F06 | Ancrage trop permissif | Confirmé (moitié des mots dans toute la dictée) | À faire (lot C) | | | | |
| F07 | Sauvetage d'une sortie invalide | Confirmé (`salvage` : toute la dictée, premier dossier) | À faire (lot C) | | | | |
| F08 | Deux ajouts à la même liste se neutralisent | Confirmé (clé source + liste) | À faire (lot B) | | | | |
| F09 | Listes sans provenance par élément | Confirmé (cases = lignes du résumé) | À faire (lot D) | | | | |
| F10 | Résultat appliqué à une révision obsolète | Confirmé (aucune révision vérifiée au commit) | À faire (lot B) | | | | |
| F11 | Retranscription pouvant dupliquer une note protégée | Confirmé (filer ne regarde que les notes provisoires) | À faire (lot B) | | | | |
| F12 | Reclassement destructif avant succès | Confirmé (`reopenForCloudRetry` supprime avant la réponse) | À faire (lot B) | | | | |
| F13 | Classement et route dans deux transactions | Confirmé (`recordRoute` après `file`) | Fait : route écrite en premier dans la transaction du classement ; `privacy_basis` ; politique inconnue = aucune sortie automatique ; reçus d'envoi écrits avant l'envoi (`transmission_receipt`) | ThoughtFiler.swift, ThoughtProcessor.swift, RoutedAnalyzer.swift, AppModel.swift | PrivacyBoundaryStoreTests, OutboundEnvelopeTests | Vert (run 38914400687) | |
| F14 | File d'attente fragile | Confirmé (`processPending` s'arrête au premier « waiting » ; `processing_job` inutilisée) | À faire (lot B) | | | | |
| F15 | Mesures sans sujet ni modalité | À relire au moment de la correction | À faire (lot D) | | | | |
| F16 | Rôles temporels perdus | À relire au moment de la correction | À faire (lot D) | | | | |
| F17 | Calendrier sans filtre de confidentialité | Confirmé (`syncAppointments` ne lisait pas la politique) | Fait : calendrier synchronisé = destination externe ; calendrier « Sur mon iPhone » reconnu ; décision ciblée « L'ajouter quand même » (`output_consent`) | CalendarData.swift, CalendarService.swift, AppModel.swift, MemoryDetailView.swift | OutboundProvenanceStoreTests | Vert (run 38914400687) | Paramètres EventKit réels : à vérifier sur l'iPhone |
| F18 | Événement créé sans reçu local | Confirmé (`try?` sur le lien après création) | À faire (lot F) | | | | |
| F19 | Boîte de partage vidée avant enregistrement | Confirmé (`drain` supprimait avant l'enregistrement) | Fait : lecture sans retrait, identifiant d'import stable (`source.import_id` unique), acquittement après enregistrement, quarantaine avec erreur ; `drain` retiré | SharedInbox.swift, ShareImport.swift, MemoryStore.swift, AppModel.swift | SharedImportTests, PrivacyBoundaryStoreTests | Vert (run 38914400687) | Arrêt réel de l'app : à vérifier sur l'iPhone |
| F20 | Évaluations non bloquantes | Confirmé (`eval.yml` manuel, rapport seulement) | Continu | | | | |
| F21 | Préférences sans remplacement | Confirmé (`PersonQuestion.tastes` additionne) | À faire (lot D) | | | | |
| F22 | Bonne note, mauvaise réponse | À relire au moment de la correction | À faire (lot E) | | | | |
| F23 | Contexte conversationnel pauvre | Confirmé (`projectFolder` prend le seul dossier) | À faire (lot D) | | | | |
| F24 | Voisinage qui renforce les erreurs | À relire au moment de la correction | À faire (lot E) | | | | |
| F25 | Budget de contexte alphabétique | Confirmé (`prefix(150)` après tri alphabétique) | À faire (lot E) | | | | |
| F26 | Qualité ASR perdue | À relire au moment de la correction | À faire (lot E) | | | | |
| F27 | Ressources non bornées | À relire au moment de la correction | À faire (lot E) | | | | |
| F28 | Restauration non atomique | À relire au moment de la correction | À faire (lot F) | | | | |
| F29 | Traçabilité insuffisante | Confirmé (`analysisVersion` p2-v1, pas de trace par tentative) | À faire (lot F) | | | | |
