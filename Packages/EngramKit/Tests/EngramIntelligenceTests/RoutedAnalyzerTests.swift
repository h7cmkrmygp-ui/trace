import EngramCore
import EngramTesting
import Foundation
import Synchronization
import Testing
@testable import EngramIntelligence

/// Faux service en ligne : renvoie le résultat prévu et retient ce qu'il a reçu.
final class FakeCloud: CloudThoughtAnalyzing {
    private let state: Mutex<(result: Result<ThoughtAnalysis, CloudError>, calls: [[String]], contexts: [CloudContext])>

    init(_ result: Result<ThoughtAnalysis, CloudError>) {
        state = Mutex((result, [], []))
    }

    func analyze(text: String, existingCategories: [String], context: CloudContext) async throws -> ThoughtAnalysis {
        let result = state.withLock { state in
            state.calls.append(existingCategories)
            state.contexts.append(context)
            return state.result
        }
        return try result.get()
    }

    var callCount: Int { state.withLock { $0.calls.count } }
    var receivedCategories: [[String]] { state.withLock { $0.calls } }
    var receivedContexts: [CloudContext] { state.withLock { $0.contexts } }
}

/// Routage : neutre → Gemini, personnel → Groq, secret → iPhone ; repli sur l'iPhone si un service manque.
struct RoutedAnalyzerTests {
    static let thought = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Note", summary: nil, excerpt: "note", kind: .info, tags: [], mentionedDates: [],
                        category: "Divers", subcategory: nil),
    ])

    struct Env {
        let gemini: FakeCloud
        let groq: FakeCloud
        let local: FakeAnalyzer
        let router: RoutedAnalyzer

        init(gemini: Result<ThoughtAnalysis, CloudError> = .success(RoutedAnalyzerTests.thought),
             groq: Result<ThoughtAnalysis, CloudError> = .success(RoutedAnalyzerTests.thought),
             judge: PrivacyVerdict? = .neutral, withProviders: Bool = true) {
            self.gemini = FakeCloud(gemini)
            self.groq = FakeCloud(groq)
            local = FakeAnalyzer([.success(RoutedAnalyzerTests.thought)])
            router = RoutedAnalyzer(local: local, judge: FakeJudge(verdict: judge),
                                    neutral: withProviders ? CloudProvider(name: "gemini", analyzer: self.gemini) : nil,
                                    personal: withProviders ? CloudProvider(name: "groq", analyzer: self.groq) : nil,
                                    quota: CloudQuota(defaults: nil))
        }

        func route(_ text: String, categories: [String] = [], keepLocal: Bool = false) async throws -> AnalysisRoute? {
            try await router.analyze(text: text, existingCategories: categories,
                                     context: AnalysisContext(keepLocal: keepLocal, capturedAt: Date())).route
        }
    }

    @Test func aNeutralNoteGoesToGemini() async throws {
        let env = Env()
        let route = try #require(try await env.route("Acheter du lait"))
        #expect(route.provider == "gemini")
        #expect(route.level == .neutral)
        #expect(!route.needsCloudRetry)
        #expect(env.groq.callCount == 0)
        #expect(env.local.callCount == 0)
    }

    @Test func aPersonalNoteGoesToGroqAndNeverToGemini() async throws {
        let env = Env()
        let route = try #require(try await env.route("Je pèse 75 kg ce matin"))
        #expect(route.provider == "groq")
        #expect(route.level == .personal)
        #expect(env.gemini.callCount == 0)
    }

    @Test func aSecretNeverLeavesTheIPhone() async throws {
        let env = Env()
        let route = try #require(try await env.route("Mon NIP est 4821"))
        #expect(route.provider == "apple")
        #expect(route.level == .secret)
        #expect(!route.needsCloudRetry)
        #expect(env.gemini.callCount == 0 && env.groq.callCount == 0)
        let kept = try #require(try await env.route("Acheter du lait", keepLocal: true))
        #expect(kept.provider == "apple")
        #expect(env.gemini.callCount == 0 && env.groq.callCount == 0)
    }

    @Test func withoutTheAppleJudgementNothingIsSent() async throws {
        let env = Env(judge: nil)
        let route = try #require(try await env.route("Acheter du lait"))
        #expect(route.provider == "apple")
        #expect(env.gemini.callCount == 0 && env.groq.callCount == 0)
    }

    @Test func aGeminiQuotaFallsBackToGroqAndPausesGemini() async throws {
        let env = Env(gemini: .failure(.quotaExceeded(retryAfter: 3_600)))
        #expect(try await env.route("Acheter du lait")?.provider == "groq")
        #expect(try await env.route("Acheter du pain")?.provider == "groq")
        #expect(env.gemini.callCount == 1)
    }

    @Test func whenNoServiceAnswersTheNoteIsFiledLocallyAndRetriedLater() async throws {
        let env = Env(groq: .failure(.network))
        let route = try #require(try await env.route("Je pèse 75 kg"))
        #expect(route.provider == "apple")
        #expect(route.needsCloudRetry)
        #expect(env.local.callCount == 1)
    }

    @Test func withoutKeysEverythingStaysOnTheIPhoneWithoutRetry() async throws {
        let env = Env(withProviders: false)
        let route = try #require(try await env.route("Acheter du lait"))
        #expect(route.provider == "apple")
        #expect(!route.needsCloudRetry)
    }

    @Test func onlyShareableCategoryNamesAreSent() async throws {
        let env = Env()
        _ = try await env.route("Acheter du lait", categories: ["Achats", "Écrire à quelqu'un@example.com"])
        #expect(env.gemini.receivedCategories == [["Achats"]])
    }

    /// Gemini ne voit que les grandes catégories : une sous-catégorie peut porter un nom propre.
    @Test func geminiOnlySeesBroadCategoryNames() async throws {
        let env = Env()
        _ = try await env.route("Acheter du lait",
                                categories: ["Achats", "Famille › Julie", "Maison › Jardin", "Écrire à quelqu'un@example.com"])
        let sent = try #require(env.gemini.receivedCategories.first)
        #expect(!sent.contains { $0.contains("›") })
        #expect(!sent.contains { $0.contains("Julie") || $0.contains("@") })
        #expect(Set(sent).isSubset(of: ["Achats", "Famille", "Maison"]))
    }

    @Test func groqSeesTheFullCategoryPaths() async throws {
        let env = Env()
        _ = try await env.route("Je pèse 75 kg", categories: ["Santé", "Famille › Julie"])
        #expect(env.groq.receivedCategories.first == ["Santé", "Famille › Julie"])
    }

    /// Réglage global « Tout garder sur l'iPhone » : aucune note n'est envoyée, même avec des clés.
    @Test func keepEverythingLocalSendsNothing() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        let router = RoutedAnalyzer(local: FakeAnalyzer([.success(Self.thought)]), judge: FakeJudge(verdict: .neutral),
                                    providers: { (CloudProvider(name: "gemini", analyzer: gemini),
                                                  CloudProvider(name: "groq", analyzer: groq)) },
                                    keepEverythingLocal: { true }, quota: CloudQuota(defaults: nil))
        let analysis = try await router.analyze(text: "Acheter du lait", existingCategories: [],
                                                context: AnalysisContext(keepLocal: false, capturedAt: Date()))
        #expect(analysis.route?.provider == "apple")
        #expect(analysis.route?.level == .secret)
        #expect(gemini.callCount == 0 && groq.callCount == 0)
    }

    @Test func quotaPausesExpireAndUsageIsCountedPerPacificDay() {
        let quota = CloudQuota(defaults: nil)
        let now = Date(timeIntervalSince1970: 1_791_475_200)
        quota.pause("gemini", until: now.addingTimeInterval(60))
        #expect(quota.isPaused("gemini", now: now))
        #expect(!quota.isPaused("gemini", now: now.addingTimeInterval(61)))
        #expect(!quota.isPaused("groq", now: now))
        quota.recordUse("groq", now: now)
        quota.recordUse("groq", now: now)
        #expect(quota.usage("groq", now: now) == 2)
        #expect(quota.usage("groq", now: now.addingTimeInterval(86_400)) == 0)
    }
}
