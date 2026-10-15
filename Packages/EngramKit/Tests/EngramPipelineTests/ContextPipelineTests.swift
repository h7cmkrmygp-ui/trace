import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// P42 — deux dictées à quelques minutes d'intervalle : « elle » renvoie à la personne de la première.
struct ContextPipelineTests {
    @Test func elleInTheNextDictationIsThePersonJustMentioned() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        let analyzer = FakeAnalyzer([
            .success(ThoughtAnalysis(thoughts: [
                AnalyzedThought(title: "Julie aime les parfums", summary: nil, excerpt: "Julie aime les parfums",
                                kind: .preference, tags: [], mentionedDates: [], category: "Famille", subcategory: nil,
                                people: ["Julie"]),
            ])),
            .success(ThoughtAnalysis(thoughts: [
                AnalyzedThought(title: "Elle adore le chocolat", summary: nil, excerpt: "Elle adore aussi le chocolat",
                                kind: .preference, tags: [], mentionedDates: [], category: "Famille", subcategory: nil),
            ])),
        ])
        let processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        guard case .saved(let first) = try memories.saveTextNoteWithoutAnalysis("Julie aime les parfums") else {
            throw CancellationError()
        }
        _ = await processor.process(sourceID: first.sourceID)
        dates.advance(by: 5 * 60)
        guard case .saved(let second) = try memories.saveTextNoteWithoutAnalysis("Elle adore aussi le chocolat") else {
            throw CancellationError()
        }
        guard case .filed(let summary) = await processor.process(sourceID: second.sourceID) else {
            Issue.record("la deuxième dictée devait être classée")
            return
        }
        // L'IA a reçu ce qui venait d'être dit.
        #expect(analyzer.receivedContexts.last?.recent?.people == ["Julie"])
        let chocolate = try #require(summary.memories.first)
        #expect(try EntityStore(database: database, dates: dates).entities(for: chocolate.id).map(\.name) == ["Julie"])
    }
}
