import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// Lot A, de bout en bout : la route est écrite avec le classement (F13), et une intention oubliée par l'IA reste visible
/// à classer, même si elle partage ses mots avec une autre (F05).
struct PrivacyAndCoveragePipelineTests {
    func make(_ analysis: ThoughtAnalysis) throws -> (MemoryStore, ThoughtProcessor) {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates),
                                         analyzer: FakeAnalyzer([.success(analysis)]))
        return (memories, processor)
    }

    @Test func theRouteIsRecordedWithTheNotes() async throws {
        let route = AnalysisRoute(level: .personal, provider: "groq", reason: "Une personne nommée.", needsCloudRetry: false,
                                  basis: .judged)
        let (memories, processor) = try make(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Appeler Julie", summary: nil, excerpt: "Appeler Julie", kind: .task, tags: [],
                            mentionedDates: [], category: "Famille", subcategory: nil),
        ], route: route))
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis("Appeler Julie") else {
            throw CancellationError()
        }
        guard case .filed = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        let source = try #require(try memories.source(id: interim.sourceID))
        #expect(source.privacyLevel == .personal)
        #expect(source.privacyBasis == .judged)
        #expect(source.analysisProvider == "groq")
    }

    @Test func aForgottenCallStaysVisible() async throws {
        let text = "Je dois appeler Paul. Je dois appeler Marc."
        let (memories, processor) = try make(ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Appeler Paul", summary: nil, excerpt: "Je dois appeler Paul", kind: .task, tags: [],
                            mentionedDates: [], category: "Appels", subcategory: nil, people: ["Paul"]),
        ]))
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        guard case .filed(let summary) = await processor.process(sourceID: interim.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        #expect(summary.memories.map(\.content).contains("Je dois appeler Marc"))
        #expect(try memories.memories(statuses: [.unsorted]).map(\.content) == ["Je dois appeler Marc"])
    }
}
