import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// P35 — moins de « À classer » : une réponse reformulée classe quand même la dictée entière, et une pensée sans dossier
/// va là où sont rangées les notes semblables quand elles sont d'accord.
struct UnsortedFixesPipelineTests {
    struct Env {
        let memories: MemoryStore
        let categories: CategoryStore
        let processor: ThoughtProcessor

        init(_ analysis: ThoughtAnalysis, evidence: [FolderEvidence] = []) throws {
            let database = try AppDatabase.inMemory()
            let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
            memories = MemoryStore(database: database, dates: dates)
            categories = CategoryStore(database: database, dates: dates)
            processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates),
                                         analyzer: FakeAnalyzer([.success(analysis)]),
                                         evidence: FixedEvidence(evidence: evidence))
        }

        func process(_ text: String) async throws -> Memory {
            guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
            guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID) else {
                throw CancellationError()
            }
            return try #require(summary.memories.last)
        }
    }

    @Test func aRephrasedAnswerStillFilesTheNote() async throws {
        let text = "Faut que j'appelle le garage pour les pneus d'hiver"
        let env = try Env(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Appeler le garage", summary: nil, excerpt: "Call the garage about winter tires",
                            kind: .task, tags: [], mentionedDates: [], category: "Automobile", subcategory: nil),
        ]))
        let memory = try await env.process(text)
        #expect(memory.content == text)
        #expect(memory.status == .active)
        #expect(try env.categories.categories(for: memory.id).map(\.name) == ["Automobile"])
    }

    @Test func aThoughtWithoutAFolderGoesWhereSimilarNotesAre() async throws {
        let text = "Changer les essuie-glaces"
        let env = try Env(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .task, tags: [], mentionedDates: [],
                            category: "", subcategory: nil),
        ]), evidence: [FolderEvidence(path: "Automobile › Corolla", notes: 3, byOwner: 1)])
        let memory = try await env.process(text)
        #expect(try env.categories.categories(for: memory.id).map(\.name) == ["Corolla"])
        #expect(try env.categories.filingReasons(for: memory.id).first?.reason.contains("notes semblables") == true)
    }

    @Test func aSingleWeakHintIsNotEnough() async throws {
        let text = "Une idée floue"
        let env = try Env(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .idea, tags: [], mentionedDates: [],
                            category: "", subcategory: nil),
        ]), evidence: [FolderEvidence(path: "Projets", notes: 1, byOwner: 0)])
        let memory = try await env.process(text)
        #expect(memory.status == .unsorted)
    }
}
