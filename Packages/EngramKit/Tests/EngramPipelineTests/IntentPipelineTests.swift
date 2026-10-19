import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// P41 — une dictée mélangée devient plusieurs éléments au bon endroit : une liste de souhaits, une tâche, une fête.
struct IntentPipelineTests {
    static let text = "J'aimerais qu'on m'achète une bouteille d'eau et des élastiques pour les cheveux. Il faut aussi que j'appelle mon manager demain. Ah, et l'anniversaire de Léa est le 3 novembre."

    @Test func oneDictationFillsAListAddsATaskAndRemembersABirthday() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        let analyzer = FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Souhaits", summary: nil,
                            excerpt: "J'aimerais qu'on m'achète une bouteille d'eau et des élastiques pour les cheveux",
                            kind: .other, tags: [], mentionedDates: [], category: "Listes", subcategory: nil,
                            listName: "souhaits", listItems: ["Bouteille d'eau", "Élastiques pour les cheveux"],
                            intent: .wish),
            AnalyzedThought(title: "Appeler mon gestionnaire", summary: nil, excerpt: "Il faut aussi que j'appelle mon manager demain",
                            kind: .task, tags: [], mentionedDates: ["demain"], category: "Travail", subcategory: nil),
            AnalyzedThought(title: "Fête de Léa", summary: nil, excerpt: "l'anniversaire de Léa est le 3 novembre",
                            kind: .info, tags: [], mentionedDates: ["3 novembre"], category: "Famille", subcategory: nil,
                            people: ["Léa"]),
        ]))])
        let processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(Self.text) else { throw CancellationError() }
        guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la dictée devait être classée")
            return
        }
        let lists = try ListStore(database: database, dates: dates).lists()
        let wishes = try #require(lists.first { $0.title == "Liste de souhaits" })
        #expect(summary.listAdditions[wishes.memoryID] == ["Bouteille d'eau", "Élastiques pour les cheveux"])
        let task = try #require(summary.memories.first { $0.kind == .task })
        #expect(task.dueAt != nil)
        #expect(try categories.categories(for: task.id).map(\.name) == ["Travail"])
        let birthdays = try EntityStore(database: database, dates: dates).birthdays()
        #expect(birthdays.map(\.name) == ["Léa"])
        #expect(summary.pathByMemory.values.contains("Anniversaires"))
        // Aucune note à part pour les souhaits.
        #expect(!summary.memories.contains { $0.title == "Souhaits" })
    }
}
