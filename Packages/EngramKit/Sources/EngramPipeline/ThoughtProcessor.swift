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

    /// F14 — bail d'un travail d'analyse : au-delà, un traitement interrompu (app arrêtée) est repris.
    static let analysisLease: TimeInterval = 10 * 60
    /// F10 — relectures au plus quand la source change pendant l'analyse.
    static let maxStaleReruns = 2

    /// Le résultat d'un essai : un résultat à rendre, une source changée pendant l'analyse (à relire), ou un échec typé.
    private enum Attempt {
        case done(ProcessingOutcome)
        case stale
        case failed(AnalysisJob.ErrorKind, String)
    }

    private func run(sourceID: UUID) async -> ProcessingOutcome {
        do {
            guard let source = try memories.source(id: sourceID) else { return .fallback }
            // « Vérifie ta note » : rien n'est envoyé à une IA avant la confirmation du propriétaire.
            guard !source.needsReview else { return .waiting("La note attend ta vérification.") }
            // F14 — le travail est pris pour un temps (bail) ; tenu par un autre traitement, la note attend son tour.
            guard try memories.beginAnalysis(sourceID: sourceID, revision: source.revision, lease: Self.analysisLease) else {
                return .deferred("La note est déjà en cours de classement.")
            }
        } catch {
            return .deferred("La note n'a pas pu être lue : Engram réessaiera.")
        }
        for _ in 0...Self.maxStaleReruns {
            switch await attempt(sourceID: sourceID) {
            case .done(let outcome):
                switch outcome {
                case .filed: finish(sourceID, .succeeded)
                case .waiting(let reason): finish(sourceID, .waiting, .providerWait, reason)
                case .deferred(let reason): finish(sourceID, .waiting, .stale, reason)
                case .fallback: finish(sourceID, .failed, .technical, nil)
                }
                return outcome
            case .stale:
                // F10 — la source a changé pendant l'analyse : l'ancien résultat n'est pas écrit, la source est relue.
                continue
            case .failed(let kind, let detail):
                do {
                    try filer.markFallback(sourceID: sourceID)
                } catch {
                    finish(sourceID, .failed, .technical, String(describing: error))
                    return .fallback
                }
                finish(sourceID, .failed, kind, detail)
                return .fallback
            }
        }
        finish(sourceID, .waiting, .stale, "La note a changé pendant l'analyse.")
        return .deferred("La note a changé pendant l'analyse : elle sera relue.")
    }

    /// F14 — l'état du travail est gardé (son échec, typé, ne passe jamais pour un succès).
    private func finish(_ sourceID: UUID, _ status: AnalysisJob.Status, _ kind: AnalysisJob.ErrorKind? = nil,
                        _ detail: String? = nil) {
        try? memories.finishAnalysis(sourceID: sourceID, status: status, errorKind: kind, detail: detail)
    }

    /// Un essai complet sur la version actuelle de la source (F10 : sa révision et sa politique sont relues ici, et vérifiées
    /// à l'écriture).
    private func attempt(sourceID: UUID) async -> Attempt {
        do {
            guard let source = try memories.source(id: sourceID) else { return .failed(.technical, "Source introuvable.") }
            guard !source.needsReview else { return .done(.waiting("La note attend ta vérification.")) }
            let snapshot = source.snapshot
            let text = (source.referenceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .failed(.quality, "Aucun texte à classer.") }
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
            var context = AnalysisContext(keepLocal: snapshot.keepLocal, capturedAt: source.capturedAt,
                                          facts: NoteFacts.describe(text), categoryDescriptions: descriptions,
                                          folderEvidence: similar, categoryCounts: counts, lists: lists,
                                          recent: recent, sourceID: sourceID, provenance: provenance)
            var tries = 0
            while true {
                tries += 1
                do {
                    // Un simple « rappelle-moi ça demain » rejoint la note précédente au lieu d'en créer une deuxième,
                    // et deux pensées au même extrait n'en font qu'une.
                    let analysis = DuplicateThoughts.merge(ReminderMerger.merge(
                        try await analyzer.analyze(text: text, existingCategories: paths, context: context), in: text))
                    var valid: [ValidThought]
                    do {
                        valid = try AnalysisValidator.validate(analysis, against: text, recent: recent)
                    } catch AnalyzerError.invalidOutput where tries < 2 {
                        // F07 — une réponse hors contrat n'obtient aucune confiance : un seul nouvel essai, qui reçoit les
                        // erreurs précises à corriger ; un deuxième refus laisse la dictée « À classer » (aucun sauvetage
                        // dans le dossier ou la liste de la réponse refusée).
                        context.repairNotes = AnalysisValidator.problems(in: analysis, against: text)
                        continue
                    }
                    valid = await withSimilarNotesFolder(valid)
                    // Des pensées rejetées ou un texte mal couvert : chaque passage oublié reste « À classer » (F05). La
                    // décision de confidentialité est écrite dans la même transaction que les notes (F13), seulement si
                    // la source est encore celle qui a été lue (F10).
                    let summary = try filer.file(valid, sourceID: sourceID, route: analysis.route, expected: snapshot,
                                                 keepInterimIfUncovered: true,
                                                 forceKeepInterim: valid.count < analysis.thoughts.count)
                    return .done(.filed(summary))
                } catch AnalyzerError.unavailable(let reason) {
                    return .done(.waiting(reason))
                } catch AnalyzerError.invalidOutput where tries < 2 {
                    // La réponse ne respectait pas le schéma (illisible) : le nouvel essai le sait.
                    context.repairNotes = [AnalysisValidator.unreadableAnswer]
                    continue
                } catch AnalyzerError.busy {
                    // Modèle occupé (souvent quand l'app passe en arrière-plan) : un nouvel essai, puis on réessaiera plus tard.
                    if tries < 2 { continue }
                    return .done(.waiting("Le modèle est occupé : la note sera classée au prochain retour dans l'app."))
                }
            }
        } catch StoreError.staleRevision {
            return .stale
        } catch AnalyzerError.refused {
            return .failed(.policy, "Le modèle a refusé de classer cette note.")
        } catch AnalyzerError.invalidOutput {
            return .failed(.quality, "La réponse de l'IA ne respectait pas le contrat.")
        } catch {
            return .failed(.technical, String(describing: error))
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
