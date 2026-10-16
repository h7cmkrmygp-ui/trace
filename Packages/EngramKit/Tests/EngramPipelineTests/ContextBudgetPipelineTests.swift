import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// F24, F25 — de bout en bout : un dossier pertinent au-delà des 150 premiers (ordre alphabétique) est donné au modèle ;
/// des notes semblables rangées seulement par l'IA n'imposent pas leur dossier à une note sans dossier.
struct ContextBudgetPipelineTests {
    @Test func aRelevantFolderBeyondTheFirst150IsGivenToTheModel() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        for index in 1...200 {
            _ = try categories.createCategory(name: String(format: "Dossier %03d", index), parentID: nil, origin: .user)
        }
        _ = try categories.createCategory(name: "Zoo vétérinaire", parentID: nil, origin: .user)
        let text = "Prendre rendez-vous chez le vétérinaire pour le chat"
        let analyzer = FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .task, tags: [], mentionedDates: [],
                            category: "Zoo vétérinaire", subcategory: nil, intent: .obligation),
        ]))])
        let processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        _ = await processor.process(sourceID: interim.sourceID)
        let sent = try #require(analyzer.receivedCategories.first)
        #expect(sent.count == 150)
        #expect(sent.contains("Zoo vétérinaire"))
    }

    @Test func notesFiledOnlyByTheAIDoNotFileANoteWithoutAFolder() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        let text = "Changer les essuie-glaces"
        let processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates),
                                         analyzer: FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
                                             AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .task,
                                                             tags: [], mentionedDates: [], category: "", subcategory: nil,
                                                             intent: .obligation),
                                         ]))]),
                                         evidence: FixedEvidence(evidence: [FolderEvidence(path: "Automobile", notes: 3,
                                                                                           byOwner: 0)]))
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        let memory = try #require(summary.memories.first)
        #expect(try categories.categories(for: memory.id).isEmpty)
    }
}
