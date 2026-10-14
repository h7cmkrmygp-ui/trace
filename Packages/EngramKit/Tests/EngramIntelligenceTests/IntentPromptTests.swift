import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramIntelligence

/// P41 — l'IA comprend l'intention de chaque morceau (une chose à recevoir, à acheter, une idée de cadeau, une tâche, une
/// idée, une décision, une préférence) et connaît les listes existantes (leurs noms seulement).
struct IntentPromptTests {
    static let toronto = TimeZone(identifier: "America/Toronto")!

    @Test func theInstructionsTellIntentionsApart() {
        let system = CloudPrompt.system
        #expect(system.contains("listItems"))
        #expect(system.contains("j'aimerais qu'on m'achète"))
        #expect(system.contains("je dois acheter"))
        #expect(system.localizedCaseInsensitiveContains("gift idea"))
        #expect(system.localizedCaseInsensitiveContains("preference"))
        #expect(CloudPrompt.version == "p42-cloud-v1")
    }

    @Test func theAIKnowsTheExistingLists() {
        let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200), timeZone: Self.toronto,
                                   lists: ["épicerie", "souhaits d'anniversaire"])
        let prompt = CloudPrompt.user(text: "Ajoute des écouteurs à ma liste d'anniversaire", categories: [], context: context)
        #expect(prompt.contains("Listes existantes : épicerie ; souhaits d'anniversaire"))
        #expect(!CloudPrompt.user(text: "x", categories: [], context: CloudContext(now: Date(), timeZone: Self.toronto))
            .contains("Listes existantes"))
    }

    @Test func theAnswerCarriesTheListAndItsThings() throws {
        let answer = #"{"notes":[{"title":"Souhaits","excerpt":"qu'on m'achète une bouteille d'eau","kind":"other","category":"Listes","list":"souhaits","listItems":["Bouteille d'eau"]}]}"#
        let thought = try #require(try CloudDecoder.decode(answer).thoughts.first)
        #expect(thought.listName == "souhaits")
        #expect(thought.listItems == ["Bouteille d'eau"])
        let schema = CloudSchema.response(.gemini)
        let note = try #require(((schema["properties"] as? [String: Any])?["notes"] as? [String: Any])?["items"] as? [String: Any])
        let order = try #require(note["propertyOrdering"] as? [String])
        #expect(order.contains("list") && order.contains("listItems"))
    }

    @Test func geminiNeverSeesAListNamedAfterSomeone() async throws {
        let thought = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                            category: "Épicerie", subcategory: nil),
        ])
        let gemini = FakeCloud(.success(thought))
        let router = RoutedAnalyzer(local: FakeAnalyzer([.success(thought)]), judge: FakeJudge(verdict: .neutral),
                                    neutral: CloudProvider(name: "gemini", analyzer: gemini), personal: nil,
                                    quota: CloudQuota(defaults: nil))
        _ = try await router.analyze(text: "Acheter du lait", existingCategories: [],
                                     context: AnalysisContext(capturedAt: Date(), lists: ["épicerie", "cadeaux pour Julie"]))
        #expect(gemini.receivedContexts.first?.lists == ["épicerie"])
    }

    #if canImport(FoundationModels)
    @Test func theAppleModelKnowsTheListsToo() {
        #expect(AnalysisPrompt.version == "p42-v1")
        #expect(AnalysisPrompt.instructions.contains("listItems"))
        #expect(AnalysisPrompt.prompt(text: "x", categories: [], likely: [], lists: ["épicerie"]).contains("Existing lists: épicerie"))
    }
    #endif
}
