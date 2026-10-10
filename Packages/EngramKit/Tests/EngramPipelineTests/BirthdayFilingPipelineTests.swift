import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// P31 — « Retiens l'anniversaire de Inès c'est le 13 octobre » classé dans Santé › Poids (signalé sur l'iPhone).
struct BirthdayFilingPipelineTests {
    static let text = "Retiens l'anniversaire de Inès c'est le 13 octobre"

    @Test func aBirthdayIsNeverFiledAsAWeight() async throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let categories = CategoryStore(database: database, dates: dates)
        // L'IA se trompe de dossier, et son extrait a perdu le début de la phrase.
        let analyzer = FakeAnalyzer([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Anniversaire d'Inès", summary: nil, excerpt: "Inès c'est le 13 octobre", kind: .info,
                            tags: [], mentionedDates: ["13 octobre"], category: "Santé", subcategory: "Poids",
                            people: ["Inès"]),
        ]))])
        let processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(Self.text) else { throw CancellationError() }
        guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        // Ce qu'Engram a déjà reconnu (une fête, pas une mesure) est dit à l'IA avec la note.
        #expect(analyzer.receivedContexts.first?.facts == NoteFacts.describe(Self.text))
        #expect(analyzer.receivedContexts.first?.facts.isEmpty == false)
        // Pas de dossier « Poids » : la note attend d'être classée plutôt que d'être mal rangée.
        #expect(summary.categoryPaths.isEmpty)
        #expect(try !categories.activeCategories().map(\.name).contains("Poids"))
        // La fête est sur la page d'Inès, même si l'extrait de l'IA était incomplet.
        let birthdays = try EntityStore(database: database, dates: dates).birthdays()
        #expect(birthdays.map(\.name) == ["Inès"])
        #expect(birthdays.first?.month == 10 && birthdays.first?.day == 13)
    }
}
