import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// P32 — l'IA reçoit ce que contient chaque catégorie, et sa raison est gardée avec la note.
struct FilingReasonPipelineTests {
    @Test func theAIKnowsWhatEachCategoryContainsAndItsReasonIsKept() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        _ = try categories.createCategory(name: "Automobile", parentID: nil, origin: .ai,
                                          description: "Entretien et réparations de la voiture")
        let text = "Changer les essuie-glaces de la voiture"
        let analyzer = FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Changer les essuie-glaces", summary: nil, excerpt: text, kind: .task, tags: [],
                            mentionedDates: [], category: "Automobile", subcategory: nil,
                            categoryReason: "Un entretien de la voiture : il va dans Automobile."),
        ]))])
        let processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        #expect(analyzer.receivedContexts.first?.categoryDescriptions == ["Automobile": "Entretien et réparations de la voiture"])
        let memory = try #require(summary.memories.first)
        #expect(try categories.filingReasons(for: memory.id)
            == [FilingReason(path: "Automobile", reason: "Un entretien de la voiture : il va dans Automobile.")])
    }
}
