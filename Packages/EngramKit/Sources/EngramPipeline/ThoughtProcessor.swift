import EngramCore
import EngramStore
import Foundation

public enum ProcessingOutcome: Sendable, Equatable {
    case filed(FilingSummary)
    /// Le modèle ne peut pas répondre pour l'instant (raison lisible) : la note reste « À classer » et sera retraitée.
    case waiting(String)
    /// L'analyse a échoué : la note reste « À classer » avec son texte brut.
    case fallback
}

/// Texte → analyse → validation anti-invention → classement.
/// Une sortie invalide ou un modèle occupé déclenchent un seul nouvel essai ; tout autre échec mène au repli.
public actor ThoughtProcessor {
    /// Au-delà, la liste de catégories prendrait trop de place dans le contexte du modèle.
    static let maxCategoriesInPrompt = 150

    let memories: MemoryStore
    let categories: CategoryStore
    let filer: ThoughtFiler
    let analyzer: any MemoryAnalyzer

    public init(memories: MemoryStore, categories: CategoryStore, filer: ThoughtFiler, analyzer: any MemoryAnalyzer) {
        self.memories = memories
        self.categories = categories
        self.filer = filer
        self.analyzer = analyzer
    }

    /// Traitements en cours : un second appel pour la même source attend le premier au lieu de la classer deux fois.
    private var inFlight: [UUID: Task<ProcessingOutcome, Never>] = [:]

    public func process(sourceID: UUID) async -> ProcessingOutcome {
        if let running = inFlight[sourceID] { return await running.value }
        let task = Task { await self.run(sourceID: sourceID) }
        inFlight[sourceID] = task
        let outcome = await task.value
        inFlight[sourceID] = nil
        return outcome
    }

    private func run(sourceID: UUID) async -> ProcessingOutcome {
        do {
            guard let source = try memories.source(id: sourceID) else { return .fallback }
            // « Vérifie ta note » : rien n'est envoyé à une IA avant la confirmation du propriétaire.
            guard !source.needsReview else { return .waiting("La note attend ta vérification.") }
            let text = (source.referenceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                try filer.markFallback(sourceID: sourceID)
                return .fallback
            }
            let paths = Array(try categories.categoryPaths().prefix(Self.maxCategoriesInPrompt))
            // Ce qu'Engram reconnaît déjà (une fête, une mesure, une liste) est dit à l'IA avec la note (P31).
            // Ce que contient chaque catégorie, pour que l'IA juge par le sens et pas par le nom (P32).
            let descriptions = try categories.categoryDescriptions().filter { paths.contains($0.key) }
            let context = AnalysisContext(keepLocal: source.keepLocal, capturedAt: source.capturedAt,
                                          facts: NoteFacts.describe(text), categoryDescriptions: descriptions)
            var attempt = 0
            while true {
                attempt += 1
                do {
                    // Un simple « rappelle-moi ça demain » rejoint la note précédente au lieu d'en créer une deuxième,
                    // et deux pensées au même extrait n'en font qu'une.
                    let analysis = DuplicateThoughts.merge(ReminderMerger.merge(
                        try await analyzer.analyze(text: text, existingCategories: paths, context: context), in: text))
                    let valid = try AnalysisValidator.validate(analysis, against: text)
                    // Des pensées rejetées ou un texte mal couvert : la note complète reste aussi « À classer ».
                    let summary = try filer.file(valid, sourceID: sourceID, keepInterimIfUncovered: true,
                                                 forceKeepInterim: valid.count < analysis.thoughts.count)
                    if let route = analysis.route { try memories.recordRoute(sourceID: sourceID, route: route) }
                    return .filed(summary)
                } catch AnalyzerError.unavailable(let reason) {
                    return .waiting(reason)
                } catch AnalyzerError.invalidOutput where attempt < 2 {
                    continue
                } catch AnalyzerError.busy {
                    // Modèle occupé (souvent quand l'app passe en arrière-plan) : un nouvel essai, puis on réessaiera plus tard.
                    if attempt < 2 { continue }
                    return .waiting("Le modèle est occupé : la note sera classée au prochain retour dans l'app.")
                }
            }
        } catch {
            try? filer.markFallback(sourceID: sourceID)
            return .fallback
        }
    }

    /// Traite toutes les sources en attente, de la plus ancienne à la plus récente.
    /// S'arrête dès que le modèle est indisponible (inutile d'insister).
    public func processPending() async -> [ProcessingOutcome] {
        guard let ids = try? memories.sourcesAwaitingAnalysis() else { return [] }
        var outcomes: [ProcessingOutcome] = []
        for id in ids {
            let outcome = await process(sourceID: id)
            outcomes.append(outcome)
            if case .waiting = outcome { break }
        }
        return outcomes
    }
}
