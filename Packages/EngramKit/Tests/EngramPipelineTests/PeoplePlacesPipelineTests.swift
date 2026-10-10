import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// P9 de bout en bout : l'IA nomme les personnes et les lieux, la règle anti-invention les vérifie, le classement les
/// relie à la note.
struct PeoplePlacesPipelineTests {
    @Test func theNamesFoundByTheAIEndUpOnTheirPages() async throws {
        let text = "Faut que j'appelle Julie avant d'aller au Costco"
        var thought = AnalyzedThought(title: "Appeler Julie", summary: nil, excerpt: text, kind: .task, tags: [],
                                      mentionedDates: [], category: "Famille", subcategory: nil)
        thought.people = ["Julie", "Pierre"]
        thought.places = ["au Costco"]
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates),
                                         analyzer: FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [thought]))]))
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID),
              let memory = summary.memories.first else {
            Issue.record("la note devait être classée")
            return
        }
        let entities = EntityStore(database: database, dates: dates)
        // « Pierre » n'est pas dans la note : il n'est pas créé.
        #expect(Set(try entities.entities(for: memory.id).map(\.name)) == ["Julie", "Costco"])
        #expect(try entities.summaries(kind: .person).map(\.entity.name) == ["Julie"])
        #expect(try entities.summaries(kind: .place).map(\.entity.name) == ["Costco"])
    }
}
