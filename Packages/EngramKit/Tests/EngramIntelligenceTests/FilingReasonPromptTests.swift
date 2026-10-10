import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramIntelligence

/// P32 — l'IA lit ce que contient chaque catégorie, explique son choix avant de le faire, et seules des descriptions sans
/// rien de sensible quittent l'iPhone (jamais vers Gemini).
struct FilingReasonPromptTests {
    static let toronto = TimeZone(identifier: "America/Toronto")!
    static let thought = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                        category: "Épicerie", subcategory: nil),
    ])

    @Test func theAIExplainsItsChoiceBeforeMakingIt() throws {
        let schema = CloudSchema.response(.gemini)
        let properties = try #require(schema["properties"] as? [String: Any])
        let notes = try #require(properties["notes"] as? [String: Any])
        let note = try #require(notes["items"] as? [String: Any])
        let order = try #require(note["propertyOrdering"] as? [String])
        let reason = try #require(order.firstIndex(of: "categoryReason"))
        let category = try #require(order.firstIndex(of: "category"))
        #expect(reason < category)
        #expect(CloudPrompt.system.contains("categoryReason"))
        #expect(CloudPrompt.version == "p33-cloud-v1")
    }

    @Test func theReasonIsReadFromTheAnswer() throws {
        let answer = #"{"notes":[{"title":"Fête de Léa","excerpt":"la fête à Léa","kind":"info","categoryReason":"Une date à retenir pour Léa.","category":"Famille"}]}"#
        #expect(try CloudDecoder.decode(answer).thoughts.first?.categoryReason == "Une date à retenir pour Léa.")
        let older = #"{"notes":[{"title":"Idée","excerpt":"une idée"}]}"#
        #expect(try CloudDecoder.decode(older).thoughts.first?.categoryReason == nil)
    }

    @Test func theAISeesWhatEachCategoryContains() {
        let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200), timeZone: Self.toronto,
                                   categoryDescriptions: ["Automobile": "Entretien et réparations de la voiture"])
        let prompt = CloudPrompt.user(text: "Réévaluer l'assurance de la maison", categories: ["Automobile", "Automobile › Pièces"],
                                      context: context)
        #expect(prompt.contains("Automobile : Entretien et réparations de la voiture"))
        #expect(prompt.contains("Automobile › Pièces"))
    }

    func router(gemini: FakeCloud, groq: FakeCloud) -> RoutedAnalyzer {
        RoutedAnalyzer(local: FakeAnalyzer([.success(Self.thought)]), judge: FakeJudge(verdict: .neutral),
                       neutral: CloudProvider(name: "gemini", analyzer: gemini),
                       personal: CloudProvider(name: "groq", analyzer: groq), quota: CloudQuota(defaults: nil))
    }

    static let categories = ["Finance", "Maison", "Maison › Chalet"]
    static let descriptions = ["Maison": "Entretien de la maison", "Maison › Chalet": "Tout sur le chalet",
                               "Finance": "Budget de 450 $ par mois"]

    @Test func geminiNeverReceivesTheDescriptions() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(
            text: "Acheter du lait", existingCategories: Self.categories,
            context: AnalysisContext(capturedAt: Date(), categoryDescriptions: Self.descriptions))
        #expect(gemini.callCount == 1)
        #expect(gemini.receivedContexts.first?.categoryDescriptions.isEmpty == true)
    }

    @Test func groqReceivesOnlyHarmlessDescriptions() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(
            text: "Je pèse 75 kg ce matin", existingCategories: Self.categories,
            context: AnalysisContext(capturedAt: Date(), categoryDescriptions: Self.descriptions))
        #expect(groq.callCount == 1)
        // Un montant ne part pas.
        #expect(groq.receivedContexts.first?.categoryDescriptions
            == ["Maison": "Entretien de la maison", "Maison › Chalet": "Tout sur le chalet"])
    }

    @Test func theEvaluationChecksBirthdays() {
        #expect(EvaluationSet.cases.contains { item in
            item.sentence.localizedCaseInsensitiveContains("fête à") && item.accepts(categoryPath: ["Anniversaires"])
                && !item.accepts(categoryPath: ["Santé"])
        })
    }

    #if canImport(FoundationModels)
    @Test func theAppleModelExplainsAndReadsTheDescriptionsToo() {
        #expect(AnalysisPrompt.version == "p33-v1")
        #expect(AnalysisPrompt.instructions.contains("categoryReason"))
        #expect(AnalysisPrompt.prompt(text: "x", categories: ["Automobile"], likely: [],
                                      descriptions: ["Automobile": "Entretien de la voiture"])
            .contains("Automobile : Entretien de la voiture"))
    }
    #endif
}
