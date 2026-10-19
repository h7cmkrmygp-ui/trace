import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// F23 — deux dictées qui se suivent : si la première est encore en cours de classement, la seconde attend son tour
/// au lieu d'être classée sans le contexte (« elle » = la personne de la première).
struct ConversationOrderPipelineTests {
    @Test func aLaterDictationWaitsForThePreviousOneStillBeingFiled() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let julie = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Julie aime les parfums", summary: nil, excerpt: "Julie aime les parfums", kind: .preference,
                            tags: [], mentionedDates: [], category: "Famille", subcategory: nil, people: ["Julie"],
                            intent: .preference),
        ])
        let scarf = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Un foulard", summary: nil, excerpt: "Elle aimerait aussi un foulard", kind: .preference,
                            tags: [], mentionedDates: [], category: "Famille", subcategory: nil, intent: .preference),
        ])
        let analyzer = GatedAnalyzer([julie, scarf])
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        guard case .saved(let first) = try memories.saveTextNoteWithoutAnalysis("Julie aime les parfums") else {
            throw CancellationError()
        }
        dates.advance(by: 60)
        guard case .saved(let second) = try memories.saveTextNoteWithoutAnalysis("Elle aimerait aussi un foulard") else {
            throw CancellationError()
        }
        let running = Task { await processor.process(sourceID: first.sourceID) }
        await analyzer.entered.wait()
        guard case .deferred = await processor.process(sourceID: second.sourceID) else {
            Issue.record("la seconde dictée devait attendre la première")
            return
        }
        #expect(analyzer.receivedContexts.count == 1)
        await analyzer.release.open()
        _ = await running.value
        let outcomes = await processor.processPending()
        guard case .filed(let summary)? = outcomes.first else {
            Issue.record("la seconde dictée devait être classée ensuite")
            return
        }
        #expect(analyzer.receivedContexts.last?.recent?.people == ["Julie"])
        let entities = EntityStore(database: database, dates: dates)
        let memory = try #require(summary.memories.first)
        #expect(try entities.entities(for: memory.id).map(\.name) == ["Julie"])
    }
}
