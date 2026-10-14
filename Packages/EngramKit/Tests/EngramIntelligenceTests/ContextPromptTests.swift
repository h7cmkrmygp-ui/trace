import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramIntelligence

/// P42 — l'IA sait ce qui vient d'être dit (la dictée précédente) pour comprendre « elle », « cette liste », « ce projet » ;
/// Gemini (palier gratuit) n'en reçoit jamais un nom de personne.
struct ContextPromptTests {
    static let toronto = TimeZone(identifier: "America/Toronto")!
    static let recent = RecentContext(people: ["Julie"], lists: ["épicerie", "cadeaux pour Julie"],
                                      folders: ["Projets › Chalet", "Famille › Julie"], minutesAgo: 5)
    static let thought = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                        category: "Épicerie", subcategory: nil),
    ])

    @Test func theAIKnowsWhatWasJustSaid() {
        let system = CloudPrompt.system
        #expect(system.contains("Note précédente"))
        #expect(system.contains("cette liste"))
        #expect(CloudPrompt.version == "p42-cloud-v1")
        let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200), timeZone: Self.toronto,
                                   recent: RecentContext(people: ["Julie"], lists: ["souhaits d'anniversaire"],
                                                         folders: ["Projets › Chalet"], minutesAgo: 5))
        let prompt = CloudPrompt.user(text: "Elle adore aussi le chocolat", categories: [], context: context)
        #expect(prompt.contains(
            "Note précédente (il y a 5 min) : personnes : Julie ; listes : souhaits d'anniversaire ; dossiers : Projets › Chalet"))
        #expect(!CloudPrompt.user(text: "x", categories: [], context: CloudContext(now: Date(), timeZone: Self.toronto))
            .contains("Note précédente"))
    }

    func router(gemini: FakeCloud, groq: FakeCloud) -> RoutedAnalyzer {
        RoutedAnalyzer(local: FakeAnalyzer([.success(Self.thought)]), judge: FakeJudge(verdict: .neutral),
                       neutral: CloudProvider(name: "gemini", analyzer: gemini),
                       personal: CloudProvider(name: "groq", analyzer: groq), quota: CloudQuota(defaults: nil))
    }

    @Test func geminiNeverSeesWhoWasJustMentioned() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(
            text: "Acheter du lait", existingCategories: [],
            context: AnalysisContext(capturedAt: Date(), recent: Self.recent))
        let context = try #require(gemini.receivedContexts.first)
        #expect(context.recent == RecentContext(people: [], lists: ["épicerie"], folders: ["Projets", "Famille"], minutesAgo: 5))
    }

    /// Le choix du propriétaire : seuls des noms de dossiers (et de listes) quittent l'iPhone, jamais les personnes d'une
    /// autre note. « Elle » est relié à la bonne personne sur l'iPhone.
    @Test func groqGetsTheListsAndFoldersButNobodysName() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(
            text: "Je pèse 75 kg ce matin", existingCategories: [],
            context: AnalysisContext(capturedAt: Date(), recent: Self.recent))
        let context = try #require(groq.receivedContexts.first)
        #expect(context.recent == RecentContext(people: [], lists: Self.recent.lists, folders: Self.recent.folders,
                                                minutesAgo: 5))
        #expect(!CloudPrompt.system.contains("that person, in people"))
    }

    #if canImport(FoundationModels)
    @Test func theAppleModelKnowsWhatWasJustSaidToo() {
        #expect(AnalysisPrompt.version == "p42-v1")
        #expect(AnalysisPrompt.instructions.contains("Previous note"))
        let prompt = AnalysisPrompt.prompt(text: "x", categories: [], likely: [],
                                           recent: RecentContext(people: ["Julie"], lists: [], folders: ["Projets › Chalet"],
                                                                 minutesAgo: 5))
        #expect(prompt.contains("Previous note (5 min ago): people: Julie; folders: Projets › Chalet"))
    }
    #endif
}
