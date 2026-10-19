import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// F14 — chaque analyse est un travail durable : un bail empêche deux traitements de la même note (reprise après un arrêt
/// quand il expire), chaque échec garde son type d'erreur et ses tentatives, et une note en échec ne bloque pas les suivantes.
struct QueuePipelineTests {
    static let thought = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                        category: "Épicerie", subcategory: nil),
    ])

    func make(_ responses: [Result<ThoughtAnalysis, AnalyzerError>])
        throws -> (MemoryStore, TestDateProvider, FakeAnalyzer, ThoughtProcessor) {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let analyzer = FakeAnalyzer(responses)
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        return (memories, dates, analyzer, processor)
    }

    @Test func aNoteHeldByAnotherProcessingWaitsForItsLease() async throws {
        let (memories, dates, analyzer, processor) = try make([.success(Self.thought)])
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis("Acheter du lait") else {
            throw CancellationError()
        }
        // Un autre traitement l'a prise (puis l'app s'est arrêtée).
        #expect(try memories.beginAnalysis(sourceID: interim.sourceID, revision: 1, lease: 600))
        guard case .deferred = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("une note déjà prise doit attendre")
            return
        }
        #expect(analyzer.callCount == 0)
        // Le bail expire : la note est reprise.
        dates.advance(by: 601)
        guard case .filed = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être reprise après le bail")
            return
        }
        #expect(try memories.analysisJob(sourceID: interim.sourceID)?.status == .succeeded)
    }

    @Test func aFailedNoteKeepsItsErrorAndDoesNotBlockTheNextOne() async throws {
        let (memories, dates, _, processor) = try make([.failure(.refused), .success(Self.thought)])
        guard case .saved(let first) = try memories.saveTextNoteWithoutAnalysis("Une note refusée") else {
            throw CancellationError()
        }
        dates.advance(by: 60)
        guard case .saved(let second) = try memories.saveTextNoteWithoutAnalysis("Acheter du lait") else {
            throw CancellationError()
        }
        let outcomes = await processor.processPending()
        #expect(outcomes.count == 2)
        guard case .filed? = outcomes.last else {
            Issue.record("la deuxième note devait être classée malgré l'échec de la première")
            return
        }
        let job = try #require(try memories.analysisJob(sourceID: first.sourceID))
        #expect(job.status == .failed)
        #expect(job.errorKind == .policy)
        #expect(job.attempts == 1)
        #expect(try memories.analysisJob(sourceID: second.sourceID)?.status == .succeeded)
    }
}
