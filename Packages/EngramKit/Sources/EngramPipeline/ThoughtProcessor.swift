import EngramCore
import EngramStore
import Foundation

public enum ProcessingOutcome: Sendable, Equatable {
    case filed(FilingSummary)
    /// Le modèle ne peut pas répondre pour l'instant (raison lisible) : la note reste « À classer » et sera retraitée.
    case waiting(String)
    /// F14 — cette note doit attendre (déjà prise ailleurs, ou changée pendant l'analyse) ; les suivantes continuent.
    case deferred(String)
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

    /// Où sont rangées les notes semblables (P34), calculé sur l'iPhone avant chaque classement.
    let evidence: (any FolderEvidenceSource)?

    public init(memories: MemoryStore, categories: CategoryStore, filer: ThoughtFiler, analyzer: any MemoryAnalyzer,
                evidence: (any FolderEvidenceSource)? = nil) {
        self.memories = memories
        self.categories = categories
        self.filer = filer
        self.analyzer = analyzer
        self.evidence = evidence
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
            // Où sont rangées les notes semblables, et la taille de chaque dossier : l'IA classe comme le propriétaire (P34).
            let similar = await evidence?.evidence(for: text) ?? []
            let counts = try categories.categoryCounts().filter { paths.contains($0.key) }
            // Les listes du propriétaire (leurs noms) : l'IA y ajoute au lieu d'en créer d'autres (P41).
            let lists = try ListStore(database: memories.database, dates: memories.dates).names()
            // Ce qui vient d'être dit (la dictée d'il y a quelques minutes) : « elle », « cette liste », « ce projet » (P42).
            let recent = try memories.recentContext(before: sourceID)
            // F02 — d'où vient chaque dossier, chaque liste et la dictée précédente : un dérivé d'une note locale (ou de
            // provenance inconnue) ne part vers aucun service.
            let provenance = ContextProvenance(
                categories: try categories.provenanceMasks(),
                lists: try ListStore(database: memories.database, dates: memories.dates).provenanceMasks(),
                recent: try memories.recentProvenance(before: sourceID))
            let context = AnalysisContext(keepLocal: source.keepLocal, capturedAt: source.capturedAt,
                                          facts: NoteFacts.describe(text), categoryDescriptions: descriptions,
                                          folderEvidence: similar, categoryCounts: counts, lists: lists,
                                          recent: recent, sourceID: sourceID, provenance: provenance)
            var attempt = 0
            while true {
                attempt += 1
                do {
                    // Un simple « rappelle-moi ça demain » rejoint la note précédente au lieu d'en créer une deuxième,
                    // et deux pensées au même extrait n'en font qu'une.
                    let analysis = DuplicateThoughts.merge(ReminderMerger.merge(
                        try await analyzer.analyze(text: text, existingCategories: paths, context: context), in: text))
                    var valid: [ValidThought]
                    do {
                        valid = try AnalysisValidator.validate(analysis, against: text, recent: recent)
                    } catch AnalyzerError.invalidOutput where attempt >= 2 {
                        // P35 : l'IA a reformulé au lieu de recopier, deux fois : la dictée entière devient une seule note,
                        // dans le dossier choisi par l'IA, plutôt que de rester « À classer ».
                        guard let whole = AnalysisValidator.salvage(analysis, against: text) else {
                            throw AnalyzerError.invalidOutput
                        }
                        valid = [whole]
                    }
                    valid = await withSimilarNotesFolder(valid)
                    // Des pensées rejetées ou un texte mal couvert : chaque passage oublié reste « À classer » (F05). La
                    // décision de confidentialité est écrite dans la même transaction que les notes (F13).
                    let summary = try filer.file(valid, sourceID: sourceID, route: analysis.route, keepInterimIfUncovered: true,
                                                 forceKeepInterim: valid.count < analysis.thoughts.count)
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

    /// P35 — une pensée sans dossier va là où sont rangées les notes qui lui ressemblent, quand elles sont d'accord (au moins
    /// 2 notes, ou une rangée par le propriétaire) et qu'un suivi ne la refuse pas.
    func withSimilarNotesFolder(_ thoughts: [ValidThought]) async -> [ValidThought] {
        guard let evidence else { return thoughts }
        var result = thoughts
        for index in result.indices where result[index].categoryPath.isEmpty {
            guard let top = await evidence.evidence(for: result[index].excerpt).first,
                  top.notes >= 2 || top.byOwner >= 1 else { continue }
            let path = top.path.components(separatedBy: CategoryPaths.separator)
            guard MeasurementFolders.accepts(path, text: result[index].excerpt) else { continue }
            result[index].categoryPath = path
            result[index].categoryReason = "Rangée comme tes notes semblables (\(top.path)) : l'IA n'avait pas trouvé de dossier sûr."
        }
        return result
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
