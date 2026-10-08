import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// Plongements factices : un vecteur fixe par texte connu.
struct FakeEmbedder: SentenceEmbedder {
    let vectors: [String: [Double]]

    func vector(for text: String) -> [Double]? { vectors[text] }
}

/// Classement sur l'iPhone (notes secrètes et secours) : consignes revues, indices de catégories par le sens.
struct LocalClassificationTests {
    @Test func categoriesAreRankedByMeaning() {
        let embedder = FakeEmbedder(vectors: [
            "Je pèse 75 kg": [1, 0, 0],
            "Santé": [0.9, 0.1, 0],
            "Automobile": [0, 1, 0],
            "Finance": [0.2, 0, 0.9],
        ])
        let ranked = CategoryHints.rank(text: "Je pèse 75 kg", categories: ["Automobile", "Finance", "Santé"], embedder: embedder)
        #expect(ranked.first == "Santé")
        #expect(ranked.count == 3)
    }

    @Test func withoutEmbeddingsTheOrderIsKept() {
        let embedder = FakeEmbedder(vectors: [:])
        #expect(CategoryHints.rank(text: "x", categories: ["B", "A"], embedder: embedder) == ["B", "A"])
        #expect(CategoryHints.rank(text: "x", categories: [], embedder: embedder).isEmpty)
    }

    @Test func theEvaluationSetCoversTheProblemsTheOwnerReported() {
        let cases = EvaluationSet.cases
        #expect(cases.count >= 40)
        // Un rappel qui parle de la même chose reste une seule note.
        #expect(cases.contains { $0.expectedNotes == 1 && $0.sentence.localizedCaseInsensitiveContains("rappelle-moi ça demain") })
        // Un poids va en Santé.
        #expect(cases.contains { $0.sentence.contains("kg") && $0.accepts(categoryPath: ["Santé"]) })
        // Deux sujets sans rapport donnent deux notes.
        #expect(cases.contains { $0.expectedNotes == 2 })
    }

    #if canImport(FoundationModels)
    @Test func appleInstructionsNoLongerInviteSplittingSentences() {
        #expect(AnalysisPrompt.version == "p4-v1")
        #expect(!AnalysisPrompt.instructions.localizedCaseInsensitiveContains("A single sentence can contain several thoughts"))
        #expect(AnalysisPrompt.instructions.localizedCaseInsensitiveContains("never split"))
        #expect(AnalysisPrompt.prompt(text: "Je pèse 75 kg", categories: ["Santé"], likely: ["Santé"]).contains("Santé"))
    }

    @Test func theAppleJudgeNeverTurnsDoubtIntoNeutral() {
        #expect(ApplePrivacyJudge.verdict(.neutral) == .neutral)
        #expect(ApplePrivacyJudge.verdict(.unsure) == .unsure)
        #expect(ApplePrivacyJudge.verdict(.secret) == .secret)
        #expect(ApplePrivacyJudge.verdict(.personal) == .personal)
    }
    #endif
}

#if canImport(FoundationModels)
/// Descriptions des anciennes catégories, écrites sur l'iPhone.
struct CategoryDescriberTests {
    @Test func thePromptGivesTheNameAndExamples() {
        let prompt = AppleCategoryDescriber.prompt(name: "Maison", titles: ["Tailler la haie", "Réparer la porte"])
        #expect(prompt.contains("Maison"))
        #expect(prompt.contains("Tailler la haie"))
    }

    @Test func descriptionsAreTrimmedAndShort() {
        #expect(AppleCategoryDescriber.clean("  « Entretien de la maison »  ") == "Entretien de la maison")
        #expect(AppleCategoryDescriber.clean(String(repeating: "a", count: 300)).count == AppleCategoryDescriber.maxLength)
    }
}
#endif
