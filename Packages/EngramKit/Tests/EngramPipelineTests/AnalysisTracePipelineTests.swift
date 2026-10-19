import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// F29 — chaque tentative de classement laisse une trace locale (version lue de la source, fournisseur et modèle
/// exacts, versions du contrat et des consignes, confidentialité, propositions, refus, opérations, issue) : le parcours
/// d'une note mal classée se reconstruit entièrement, et l'export de diagnostic, expurgé par défaut, ne montre ni la note
/// ni ses dossiers.
struct AnalysisTracePipelineTests {
    static let text = "Faut que j'appelle le garage pour les pneus d'hiver"
    static let route = AnalysisRoute(level: .neutral, provider: "gemini", reason: "Neutre.", needsCloudRetry: false,
                                     basis: .judged, model: "gemini-2.5-flash", promptVersion: "p50-cloud-v1")

    @Test func thePathOfAMisfiledNoteCanBeRebuiltWithoutRevealingIt() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let invented = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Pneus", summary: nil, excerpt: "Call the garage about winter tires", kind: .task,
                            tags: [], mentionedDates: [], category: "Automobile", subcategory: nil, intent: .obligation),
        ], route: Self.route)
        let good = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Appeler le garage", summary: nil, excerpt: Self.text, kind: .task, tags: [],
                            mentionedDates: [], category: "Automobile", subcategory: nil, intent: .obligation),
        ], route: Self.route)
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates),
                                         analyzer: FakeAnalyzer([.success(invented), .success(good)]))
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(Self.text) else {
            throw CancellationError()
        }
        guard case .filed = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée au second essai")
            return
        }
        let runs = try memories.analysisRuns(sourceID: interim.sourceID)
        #expect(runs.map(\.outcome) == [.refused, .filed])
        #expect(runs.map(\.attempt) == [1, 2])
        #expect(runs.first?.problems.count == 1)
        #expect(runs.allSatisfy { $0.revision == 1 && !$0.textHash.isEmpty })
        let last = try #require(runs.last)
        #expect(last.provider == "gemini")
        #expect(last.model == "gemini-2.5-flash")
        #expect(last.promptVersion == "p50-cloud-v1")
        #expect(last.contractVersion == AnalysisContract.version)
        #expect(last.privacyLevel == "neutral")
        #expect(last.proposals.map(\.intent) == ["obligation"])
        #expect(!last.operations.isEmpty)

        let report = try memories.diagnosticReport(sourceID: interim.sourceID)
        for expected in ["gemini-2.5-flash", "p50-cloud-v1", AnalysisContract.version, "refusée", "classée"] {
            #expect(report.contains(expected), "\(expected)")
        }
        for hidden in ["garage", "pneus", "Pneus", "Automobile", "Call the"] {
            #expect(!report.contains(hidden), "\(hidden)")
        }
        #expect(try memories.diagnosticReport(sourceID: interim.sourceID, redacted: false).contains("Automobile"))
    }
}
