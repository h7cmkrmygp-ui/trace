import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// Indices fixes, pour vérifier qu'ils arrivent jusqu'à l'IA.
struct FixedEvidence: FolderEvidenceSource {
    let evidence: [FolderEvidence]
    func evidence(for text: String) async -> [FolderEvidence] { evidence }
}

/// P34 — avant chaque classement, l'IA reçoit où sont rangées les notes semblables et la taille de chaque dossier.
struct FolderEvidencePipelineTests {
    @Test func theAIReceivesTheEvidenceAndTheFolderSizes() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        let filer = ThoughtFiler(database: database, dates: dates)
        // Une note déjà rangée dans Automobile.
        guard case .saved(let first) = try memories.saveTextNoteWithoutAnalysis("Laver l'auto") else { throw CancellationError() }
        _ = try filer.file([ValidThought(title: "Laver l'auto", summary: nil, excerpt: "Laver l'auto", spanStart: nil, spanEnd: nil,
                                         kind: .task, tags: [], categoryPath: ["Automobile"], mentionedDates: [])],
                           sourceID: first.sourceID)
        let text = "Changer les essuie-glaces"
        let analyzer = FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .task, tags: [], mentionedDates: [],
                            category: "Automobile", subcategory: nil),
        ]))])
        let evidence = [FolderEvidence(path: "Automobile", notes: 1, byOwner: 0)]
        let processor = ThoughtProcessor(memories: memories, categories: categories, filer: filer, analyzer: analyzer,
                                         evidence: FixedEvidence(evidence: evidence))
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        guard case .filed = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        let context = try #require(analyzer.receivedContexts.first)
        #expect(context.folderEvidence == evidence)
        #expect(context.categoryCounts == ["Automobile": 1])
    }
}
