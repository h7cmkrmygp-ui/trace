import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// Corrections issues de la relecture finale P2 + P3 (orchestration).
struct ReviewFixesPipelineTests {
    static let text = "Rappeler d'acheter des wipers pour ma Corolla"
    static let analysis = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Wipers", summary: nil, excerpt: "acheter des wipers pour ma Corolla", kind: .task,
                        tags: [], mentionedDates: [], category: "Automobile", subcategory: "Corolla"),
    ])

    func make(_ responses: [Result<ThoughtAnalysis, AnalyzerError>]) throws -> (MemoryStore, FakeAnalyzer, ThoughtProcessor) {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let analyzer = FakeAnalyzer(responses)
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        return (memories, analyzer, processor)
    }

    @Test func aBusyModelAfterTheRetryLeavesTheNoteWaiting() async throws {
        let (memories, analyzer, processor) = try make([.failure(.busy), .failure(.busy)])
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(Self.text) else { throw CancellationError() }
        guard case .waiting = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("un modèle occupé doit laisser la note en attente")
            return
        }
        #expect(analyzer.callCount == 2)
        #expect(try memories.sourcesAwaitingAnalysis() == [interim.sourceID])
    }

    @Test func processingTheSameSourceTwiceAtOnceFilesItOnce() async throws {
        let (memories, _, processor) = try make([.success(Self.analysis)])
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(Self.text) else { throw CancellationError() }
        async let first = processor.process(sourceID: interim.sourceID)
        async let second = processor.process(sourceID: interim.sourceID)
        _ = await (first, second)
        #expect(try memories.memories(statuses: [.active, .unsorted]).count == 1)
    }
}
