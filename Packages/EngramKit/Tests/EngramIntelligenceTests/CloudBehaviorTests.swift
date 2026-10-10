import EngramCore
import EngramTesting
import Foundation
import Synchronization
import Testing
@testable import EngramIntelligence

/// Faux transport HTTP : renvoie les réponses prévues dans l'ordre et retient les adresses appelées.
final class FakeTransport: HTTPTransport {
    private let state: Mutex<(responses: [(Int, Data)], urls: [String])>

    init(_ responses: [(Int, Data)]) {
        state = Mutex((responses, []))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, data) = state.withLock { state -> (Int, Data) in
            state.urls.append(request.url?.absoluteString ?? "")
            return state.responses.isEmpty ? (500, Data()) : state.responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    var urls: [String] { state.withLock { $0.urls } }
}

/// Juge qui compte ses appels (et répond « neutre »).
final class CountingJudge: PrivacyJudge {
    private let count = Mutex(0)

    func judge(_ text: String) async throws -> PrivacyJudgement {
        count.withLock { $0 += 1 }
        return PrivacyJudgement(verdict: .neutral, reason: "")
    }

    var calls: Int { count.withLock { $0 } }
}

struct CloudBehaviorTests {
    static let answer = #"{"notes":[{"title":"Lait","summary":"","excerpt":"acheter du lait","kind":"task","category":"Achats","categoryDescription":"","subcategory":"","tags":[],"dates":[]}]}"#

    static func geminiEnvelope() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["text": answer]]]]]])
    }

    @Test func geminiFallsBackToFlashLiteWhenFlashQuotaIsReached() async throws {
        let quota = Data(#"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"quota"}}"#.utf8)
        let transport = FakeTransport([(429, quota), (200, try Self.geminiEnvelope())])
        let analyzer = GeminiThoughtAnalyzer(client: GeminiClient(apiKey: "CLE-TEST", transport: transport),
                                             models: ["gemini-3.8-flash", "gemini-3.5-flash-lite"])
        let analysis = try await analyzer.analyze(text: "acheter du lait", existingCategories: [],
                                                  context: CloudContext(now: Date(), timeZone: .current))
        #expect(analysis.thoughts.first?.category == "Achats")
        #expect(transport.urls.count == 2)
        #expect(transport.urls[1].contains("gemini-3.5-flash-lite"))
        #expect(transport.urls.allSatisfy { !$0.contains("CLE-TEST") })
    }

    @Test func aRefusedGroqKeyIsReported() async {
        let transport = FakeTransport([(401, Data("{}".utf8))])
        await #expect(throws: CloudError.invalidKey) { try await GroqClient(apiKey: "mauvaise", transport: transport).checkKey() }
    }

    @Test func aGeminiKeyIsTestedWithTheModelList() async throws {
        let models = try JSONSerialization.data(withJSONObject: ["models": [
            ["name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-embedding-2", "supportedGenerationMethods": ["embedContent"]],
        ]])
        let transport = FakeTransport([(200, models)])
        let names = try await GeminiClient(apiKey: "CLE-TEST", transport: transport).listModels()
        #expect(names == ["models/gemini-3.8-flash"])
        #expect(!(transport.urls.first ?? "").contains("CLE-TEST"))
    }

    @Test func aMissingKeyNeverCallsTheNetwork() async {
        let transport = FakeTransport([])
        await #expect(throws: CloudError.missingKey) {
            try await GeminiClient(apiKey: "", transport: transport).generate(model: "m", system: "s", user: "u")
        }
        #expect(transport.urls.isEmpty)
    }

    @Test func whenGeminiRefusesANeutralNoteGroqClassifiesIt() async throws {
        let thought = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Lait", summary: nil, excerpt: "acheter du lait", kind: .task, tags: [], mentionedDates: [],
                            category: "Achats", subcategory: nil),
        ])
        let gemini = FakeCloud(.failure(.refused))
        let groq = FakeCloud(.success(thought))
        let router = RoutedAnalyzer(local: FakeAnalyzer([.success(thought)]), judge: FakeJudge(verdict: .neutral),
                                    neutral: CloudProvider(name: "gemini", analyzer: gemini),
                                    personal: CloudProvider(name: "groq", analyzer: groq), quota: CloudQuota(defaults: nil))
        let analysis = try await router.analyze(text: "acheter du lait", existingCategories: [],
                                                context: AnalysisContext(keepLocal: false, capturedAt: Date()))
        #expect(analysis.route?.provider == "groq")
        #expect(analysis.route?.needsCloudRetry == false)
    }

    /// Sans aucune clé, tout reste sur l'iPhone : inutile de faire juger la confidentialité (un appel au modèle en moins).
    @Test func withoutAnyServiceThePrivacyJudgeIsNotAsked() async throws {
        let judge = CountingJudge()
        let thought = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Lait", summary: nil, excerpt: "acheter du lait", kind: .task, tags: [], mentionedDates: [],
                            category: "Achats", subcategory: nil),
        ])
        let router = RoutedAnalyzer(local: FakeAnalyzer([.success(thought)]), judge: judge, neutral: nil, personal: nil,
                                    quota: CloudQuota(defaults: nil))
        let analysis = try await router.analyze(text: "acheter du lait", existingCategories: [],
                                                context: AnalysisContext(keepLocal: false, capturedAt: Date()))
        #expect(analysis.route?.provider == "apple")
        #expect(analysis.route?.needsCloudRetry == false)
        #expect(judge.calls == 0)
    }

    @Test func quotasSurviveARestartOfTheApp() throws {
        let suite = "engram-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let first = CloudQuota(defaults: defaults)
        first.pause("gemini", until: now.addingTimeInterval(3_600))
        first.recordUse("groq", now: now)
        let reopened = CloudQuota(defaults: defaults)
        #expect(reopened.isPaused("gemini", now: now))
        #expect(reopened.usage("groq", now: now) == 1)
    }
}
