import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

struct ThoughtProcessorTests {
    /// Le choix « Garder sur l'iPhone » est transmis à l'analyseur, et l'endroit du classement est enregistré.
    @Test func theOwnersChoiceReachesTheAnalyzerAndTheRouteIsRecorded() async throws {
        var routed = Self.corolla
        routed.route = AnalysisRoute(level: .secret, provider: "apple", reason: "Tu as choisi « Garder sur l'iPhone ».",
                                     needsCloudRetry: false)
        let env = try Env([.success(routed)])
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/k.caf", duration: 2)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: Self.text, languages: [],
                                              engine: nil, needsReview: true)
        _ = try env.memories.confirmReview(sourceID: recording.sourceID, text: Self.text, keepLocal: true)
        guard case .filed = await env.processor.process(sourceID: recording.sourceID) else {
            Issue.record("la note devait être classée")
            return
        }
        #expect(env.analyzer.receivedContexts.first?.keepLocal == true)
        let source = try #require(try env.memories.source(id: recording.sourceID))
        #expect(source.analysisProvider == "apple")
        #expect(source.privacyLevel == .secret)
    }

    /// Une note qui attend la vérification du propriétaire n'est jamais envoyée à l'IA.
    @Test func aNoteAwaitingReviewIsNotAnalyzed() async throws {
        let env = try Env([.success(Self.corolla)])
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/v.caf", duration: 2)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: Self.text, languages: [],
                                              engine: nil, needsReview: true)
        guard case .waiting = await env.processor.process(sourceID: recording.sourceID) else {
            Issue.record("la note à vérifier ne doit pas être classée")
            return
        }
        #expect(env.analyzer.callCount == 0)
    }

    struct Env {
        let memories: MemoryStore
        let categories: CategoryStore
        let analyzer: FakeAnalyzer
        let processor: ThoughtProcessor

        init(_ responses: [Result<ThoughtAnalysis, AnalyzerError>]) throws {
            let database = try AppDatabase.inMemory()
            let dates = TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
            memories = MemoryStore(database: database, dates: dates)
            categories = CategoryStore(database: database, dates: dates)
            analyzer = FakeAnalyzer(responses)
            processor = ThoughtProcessor(memories: memories, categories: categories,
                                         filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
        }

        func saveNote(_ text: String) throws -> Memory {
            guard case .saved(let memory) = try memories.saveTextNoteWithoutAnalysis(text) else {
                throw CancellationError()
            }
            return memory
        }
    }

    static let corolla = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Acheter des wipers", summary: nil, excerpt: "acheter des wipers pour ma Corolla",
                        kind: .task, tags: ["Achat"], mentionedDates: [], category: "Automobile", subcategory: "Corolla"),
    ])
    static let text = "Rappeler d'acheter des wipers pour ma Corolla"

    @Test func filesTheThoughtAndSendsTheExistingCategories() async throws {
        let env = try Env([.success(Self.corolla)])
        _ = try env.categories.resolvePath(["Travail"], origin: .ai)
        let interim = try env.saveNote(Self.text)
        guard case .filed(let summary) = await env.processor.process(sourceID: interim.sourceID) else {
            Issue.record("classement attendu")
            return
        }
        #expect(summary.categoryPaths == ["Automobile › Corolla"])
        #expect(env.analyzer.receivedCategories == [["Travail"]])
        #expect(try env.memories.memory(id: interim.id) == nil)
    }

    @Test func unavailableModelLeavesTheNoteWaiting() async throws {
        let env = try Env([.failure(.unavailable("Apple Intelligence désactivé"))])
        let interim = try env.saveNote(Self.text)
        #expect(await env.processor.process(sourceID: interim.sourceID) == .waiting("Apple Intelligence désactivé"))
        #expect(try env.memories.memory(id: interim.id)?.status == .unsorted)
        #expect(try env.memories.sourcesAwaitingAnalysis() == [interim.sourceID])
    }

    @Test func invalidOutputTwiceFallsBack() async throws {
        let env = try Env([.failure(.invalidOutput), .failure(.invalidOutput)])
        let interim = try env.saveNote(Self.text)
        #expect(await env.processor.process(sourceID: interim.sourceID) == .fallback)
        #expect(env.analyzer.callCount == 2)
        #expect(try env.memories.memory(id: interim.id)?.status == .unsorted)
        #expect(try env.memories.sourcesAwaitingAnalysis().isEmpty)
    }

    @Test func invalidThenValidIsFiled() async throws {
        let env = try Env([.failure(.invalidOutput), .success(Self.corolla)])
        let interim = try env.saveNote(Self.text)
        guard case .filed = await env.processor.process(sourceID: interim.sourceID) else {
            Issue.record("classement attendu au second essai")
            return
        }
        #expect(env.analyzer.callCount == 2)
    }

    @Test func anInventedExcerptFallsBackAfterOneRetry() async throws {
        let invented = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Pneus", summary: nil, excerpt: "changer les pneus d'hiver", kind: .task, tags: [],
                            mentionedDates: [], category: "Automobile", subcategory: nil),
        ])
        let env = try Env([.success(invented), .success(invented)])
        let interim = try env.saveNote(Self.text)
        #expect(await env.processor.process(sourceID: interim.sourceID) == .fallback)
        #expect(try env.memories.memory(id: interim.id) != nil)
    }

    @Test func aRefusalFallsBackWithoutRetrying() async throws {
        let env = try Env([.failure(.refused)])
        let interim = try env.saveNote(Self.text)
        #expect(await env.processor.process(sourceID: interim.sourceID) == .fallback)
        #expect(env.analyzer.callCount == 1)
    }

    @Test func anEmptyTranscriptFallsBackWithoutCallingTheModel() async throws {
        let env = try Env([.success(Self.corolla)])
        let memory = try env.memories.saveVoiceNote(audioPath: "audio/z.caf", duration: 2, transcript: "",
                                                    languages: [], engine: "apple-speech")
        #expect(await env.processor.process(sourceID: memory.sourceID) == .fallback)
        #expect(env.analyzer.callCount == 0)
    }

    @Test func processPendingHandlesEveryWaitingSource() async throws {
        let env = try Env([.success(Self.corolla)])
        _ = try env.saveNote(Self.text)
        _ = try env.saveNote("Rappeler d'acheter des wipers pour ma Corolla demain")
        let outcomes = await env.processor.processPending()
        #expect(outcomes.count == 2)
        #expect(try env.memories.sourcesAwaitingAnalysis().isEmpty)
    }
}
