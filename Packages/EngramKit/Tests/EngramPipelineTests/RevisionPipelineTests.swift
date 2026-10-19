import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// Une porte que l'on ouvre une fois ; ceux qui attendent repartent.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

/// Un analyseur qui s'arrête pendant sa première réponse, le temps que le test change la source.
final class GatedAnalyzer: MemoryAnalyzer, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [ThoughtAnalysis]
    private var contexts: [AnalysisContext] = []
    let entered = Gate()
    let release = Gate()

    init(_ responses: [ThoughtAnalysis]) {
        self.responses = responses
    }

    func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories, context: AnalysisContext())
    }

    func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        let index: Int = lock.withLock {
            contexts.append(context)
            return contexts.count - 1
        }
        if index == 0 {
            await entered.open()
            await release.wait()
        }
        return responses[min(index, responses.count - 1)]
    }

    var receivedContexts: [AnalysisContext] { lock.withLock { contexts } }
}

/// F10 — une analyse ne s'écrit que sur la version de la source qu'elle a lue : une retranscription ou un changement de
/// confidentialité pendant l'attente la rend obsolète, et la source est relue.
struct RevisionPipelineTests {
    static func task(_ text: String, category: String, route: AnalysisRoute? = nil) -> ThoughtAnalysis {
        ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .task, tags: [], mentionedDates: [],
                            category: category, subcategory: nil),
        ], route: route)
    }

    func make(_ analyzer: any MemoryAnalyzer) throws -> (MemoryStore, ThoughtProcessor) {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        return (memories, processor)
    }

    @Test func aRetranscriptionDuringTheAnalysisInvalidatesTheOldResult() async throws {
        let analyzer = GatedAnalyzer([Self.task("Appeler le garage", category: "Automobile"),
                                      Self.task("Appeler le dentiste", category: "Santé")])
        let (memories, processor) = try make(analyzer)
        let voice = try memories.saveVoiceNote(audioPath: "audio/a.caf", duration: 2, transcript: "Appeler le garage",
                                               languages: ["fr-CA"], engine: "apple-speech")
        let running = Task { await processor.process(sourceID: voice.sourceID) }
        await analyzer.entered.wait()
        try memories.retranscribe(sourceID: voice.sourceID, transcript: "Appeler le dentiste", languages: ["fr-CA"],
                                  engine: "whisperkit")
        await analyzer.release.open()
        guard case .filed(let summary) = await running.value else {
            Issue.record("la source devait être relue puis classée")
            return
        }
        #expect(summary.memories.map(\.excerpt) == ["Appeler le dentiste"])
        #expect(try memories.memories(statuses: [.active, .unsorted]).map(\.excerpt) == ["Appeler le dentiste"])
        #expect(analyzer.receivedContexts.count == 2)
        #expect(try memories.source(id: voice.sourceID)?.revision == 2)
    }

    @Test func keepingTheNoteLocalDuringTheAnalysisInvalidatesTheOldResult() async throws {
        let cloud = AnalysisRoute(level: .neutral, provider: "gemini", reason: "Neutre.", needsCloudRetry: false, basis: .judged)
        let local = AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.ownerKeepLocal, needsCloudRetry: false,
                                  basis: .ownerKeepLocal)
        let analyzer = GatedAnalyzer([Self.task("Acheter du lait", category: "Épicerie", route: cloud),
                                      Self.task("Acheter du lait", category: "Épicerie", route: local)])
        let (memories, processor) = try make(analyzer)
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis("Acheter du lait") else {
            throw CancellationError()
        }
        let running = Task { await processor.process(sourceID: interim.sourceID) }
        await analyzer.entered.wait()
        try memories.setKeepLocal(sourceID: interim.sourceID, keepLocal: true)
        await analyzer.release.open()
        guard case .filed = await running.value else {
            Issue.record("la source devait être relue puis classée")
            return
        }
        let source = try #require(try memories.source(id: interim.sourceID))
        #expect(source.keepLocal)
        #expect(source.policyVersion == 2)
        #expect(source.analysisProvider == "apple")
        #expect(source.privacyBasis == .ownerKeepLocal)
        #expect(analyzer.receivedContexts.last?.keepLocal == true)
    }

    @Test func aStaleResultIsRefusedByTheStore() throws {
        let database = try AppDatabase.inMemory()
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
        let memories = MemoryStore(database: database, dates: dates)
        let voice = try memories.saveVoiceNote(audioPath: "audio/b.caf", duration: 2, transcript: "Appeler le garage",
                                               languages: [], engine: nil)
        let read = try #require(try memories.source(id: voice.sourceID)).snapshot
        try memories.retranscribe(sourceID: voice.sourceID, transcript: "Appeler le dentiste", languages: [], engine: nil)
        let thought = ValidThought(title: "Garage", summary: nil, excerpt: "Appeler le garage", spanStart: 0, spanEnd: 17,
                                   kind: .task, tags: [], categoryPath: ["Automobile"], mentionedDates: [])
        #expect(throws: StoreError.staleRevision) {
            try ThoughtFiler(database: database, dates: dates).file([thought], sourceID: voice.sourceID, expected: read)
        }
        #expect(try memories.memories(statuses: [.active]).isEmpty)
    }
}
