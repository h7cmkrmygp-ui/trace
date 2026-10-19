import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// F02 — avant chaque analyse, Engram dit d'où vient chaque dossier et chaque liste joints à la note, et quelle source est
/// analysée (pour revérifier sa politique juste avant l'envoi).
struct ProvenancePipelineTests {
    @Test func theAnalyzerLearnsWhereEachFolderComesFrom() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let filer = ThoughtFiler(database: database, dates: dates)
        func file(_ text: String, path: [String], keepLocal: Bool, route: AnalysisRoute) throws {
            guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) else {
                throw CancellationError()
            }
            _ = try filer.file([ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task,
                                             tags: [], categoryPath: path, mentionedDates: [])],
                               sourceID: interim.sourceID, route: route)
            dates.advance(by: 3600)
        }
        try file("Préparer la réunion", path: ["Travail"], keepLocal: false,
                 route: AnalysisRoute(level: .neutral, provider: "gemini", reason: "Neutre.", needsCloudRetry: false, basis: .judged))
        try file("Prendre les comprimés", path: ["Santé"], keepLocal: true,
                 route: AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.ownerKeepLocal,
                                      needsCloudRetry: false, basis: .ownerKeepLocal))
        let analyzer = FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                            category: "Épicerie", subcategory: nil),
        ]))])
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: filer, analyzer: analyzer)
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis("Acheter du lait") else {
            throw CancellationError()
        }
        _ = await processor.process(sourceID: interim.sourceID)
        let context = try #require(analyzer.receivedContexts.first)
        #expect(context.sourceID == interim.sourceID)
        let provenance = try #require(context.provenance)
        #expect(provenance.allowsCategory("Travail", .cloudNeutral))
        #expect(!provenance.allowsCategory("Santé", .cloudPersonal))
    }
}
