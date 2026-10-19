import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// Lot C, de bout en bout avec le vrai ThoughtFiler : une proposition fausse du modèle ne devient pas une écriture (F03),
/// une négation, une condition ou une citation ne changent aucune liste (F04), et deux réponses refusées ne sont jamais
/// « sauvées » dans le dossier de la première (F07).
struct ActionContractPipelineTests {
    struct Env {
        let database: AppDatabase
        let memories: MemoryStore
        let categories: CategoryStore
        let analyzer: FakeAnalyzer
        let processor: ThoughtProcessor

        init(_ responses: [Result<ThoughtAnalysis, AnalyzerError>]) throws {
            database = try AppDatabase.inMemory()
            let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
            memories = MemoryStore(database: database, dates: dates)
            categories = CategoryStore(database: database, dates: dates)
            analyzer = FakeAnalyzer(responses)
            processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        }

        func save(_ text: String) throws -> Memory {
            guard case .saved(let memory) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
            return memory
        }

        var lists: [String] { (try? ListStore(database: database, dates: SystemDateProvider()).lists().map(\.title)) ?? [] }
    }

    @Test func aCleaningObligationProposedAsAPurchaseStaysATask() async throws {
        let text = "Lundi, je dois nettoyer ma douche"
        let env = try Env([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Nettoyer ma douche", summary: nil, excerpt: text, kind: .task, tags: [],
                            mentionedDates: ["Lundi"], category: "Achats", subcategory: nil, listName: "achats",
                            listItems: ["Nettoyer ma douche"], intent: .purchase),
        ]))])
        let interim = try env.save(text)
        guard case .filed(let summary) = await env.processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        #expect(env.lists.isEmpty)
        let task = try #require(summary.memories.first { $0.kind == .task })
        #expect(task.dueAt != nil)
        #expect(try env.categories.categories(for: task.id).map(\.name) != ["Achats"])
    }

    @Test func aNegatedHypotheticalOrQuotedCommandChangesNoList() async throws {
        for text in ["N'ajoute pas du lait à ma liste d'épicerie",
                     "Si je te dis ajoute du lait à ma liste d'épicerie, que feras-tu ?",
                     "Paul m'a dit : ajoute du lait à ta liste d'épicerie"] {
            let env = try Env([.success(ThoughtAnalysis(thoughts: [
                AnalyzedThought(title: "Lait", summary: nil, excerpt: text, kind: .other, tags: [], mentionedDates: [],
                                category: "Courses", subcategory: nil, listName: "épicerie", listItems: ["Lait"],
                                intent: .listAdd),
            ]))])
            let interim = try env.save(text)
            _ = await env.processor.process(sourceID: interim.sourceID)
            #expect(env.lists.isEmpty, "\(text)")
        }
        // Le modèle a bien compris une préférence : la forme « ajoute … à ma liste » n'autorise rien.
        let text = "Ajoute du lait à ma liste d'épicerie"
        let env = try Env([.success(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Lait", summary: nil, excerpt: text, kind: .preference, tags: [], mentionedDates: [],
                            category: "Goûts", subcategory: nil, intent: .preference),
        ]))])
        _ = await env.processor.process(sourceID: try env.save(text).sourceID)
        #expect(env.lists.isEmpty)
    }

    @Test func twoInventedAnswersFallBackWithTheirErrorsAndNoSalvage() async throws {
        let text = "Faut que j'appelle le garage pour les pneus d'hiver"
        let invented = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Pneus", summary: nil, excerpt: "Call the garage about winter tires", kind: .task,
                            tags: [], mentionedDates: [], category: "Automobile", subcategory: nil, listName: "achats",
                            listItems: ["Pneus d'hiver"], intent: .purchase),
        ])
        let env = try Env([.success(invented), .success(invented)])
        let interim = try env.save(text)
        #expect(await env.processor.process(sourceID: interim.sourceID) == .fallback)
        #expect(env.analyzer.callCount == 2)
        // Le second essai reçoit les erreurs précises du premier.
        #expect(env.analyzer.receivedContexts.first?.repairNotes.isEmpty == true)
        #expect(env.analyzer.receivedContexts.last?.repairNotes.isEmpty == false)
        // La dictée reste « À classer », sans dossier, sans liste.
        let kept = try #require(try env.memories.memory(id: interim.id))
        #expect(kept.status == .unsorted)
        #expect(try env.categories.categories(for: kept.id).isEmpty)
        #expect(env.lists.isEmpty)
    }
}
