import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramIntelligence

/// P31 — les catégories viennent du sens de chaque note : aucune liste toute faite dans les consignes, une catégorie
/// existante seulement si le sujet y appartient vraiment, sinon une nouvelle ; une fête n'est jamais une mesure de santé.
struct CategoryPromptTests {
    static let toronto = TimeZone(identifier: "America/Toronto")!

    @Test func theInstructionsGiveNoReadyMadeCategories() {
        let system = CloudPrompt.system
        #expect(!system.contains("Santé › Poids"))
        #expect(!system.contains("Finance › Assurances"))
        #expect(!system.contains("such as Santé, Travail"))
        #expect(system.localizedCaseInsensitiveContains("create a new category"))
        #expect(system.localizedCaseInsensitiveContains("birthday"))
        #expect(CloudPrompt.version == "p32-cloud-v1")
    }

    @Test func whatEngramRecognizedIsGivenWithTheNote() {
        let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200), timeZone: Self.toronto,
                                   facts: ["la fête d'Inès, le 13 octobre (une date pour une personne, pas une mesure de santé)"])
        let prompt = CloudPrompt.user(text: "Retiens l'anniversaire de Inès c'est le 13 octobre", categories: ["Santé › Poids"],
                                      context: context)
        #expect(prompt.contains("Engram a déjà reconnu"))
        #expect(prompt.contains("la fête d'Inès, le 13 octobre"))
        let plain = CloudPrompt.user(text: "Acheter du lait", categories: [], context: CloudContext(now: Date(), timeZone: Self.toronto))
        #expect(!plain.contains("Engram a déjà reconnu"))
    }

    @Test func onlyCategoriesCloseInMeaningAreSuggested() {
        let embedder = FakeEmbedder(vectors: [
            "Retiens l'anniversaire de Inès": [1, 0, 0],
            "Famille": [0.9, 0.1, 0],
            "Santé › Poids": [0.1, 1, 0],
            "Finance": [0, 0, 1],
        ])
        #expect(CategoryHints.likely(text: "Retiens l'anniversaire de Inès", categories: ["Finance", "Santé › Poids", "Famille"],
                                     embedder: embedder) == ["Famille"])
        // Sans le sens, aucune suggestion : l'ordre alphabétique des dossiers n'est pas un indice.
        #expect(CategoryHints.likely(text: "x", categories: ["Finance", "Famille"], embedder: FakeEmbedder(vectors: [:])).isEmpty)
    }

    @Test func theFactsTravelToTheOnlineService() async throws {
        let thought = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                            category: "Épicerie", subcategory: nil),
        ])
        let gemini = FakeCloud(.success(thought))
        let router = RoutedAnalyzer(local: FakeAnalyzer([.success(thought)]), judge: FakeJudge(verdict: .neutral),
                                    neutral: CloudProvider(name: "gemini", analyzer: gemini), personal: nil,
                                    quota: CloudQuota(defaults: nil))
        _ = try await router.analyze(text: "Acheter du lait", existingCategories: [],
                                     context: AnalysisContext(capturedAt: Date(), facts: ["un ajout à la liste d'épicerie"]))
        #expect(gemini.receivedContexts.first?.facts == ["un ajout à la liste d'épicerie"])
    }

    #if canImport(FoundationModels)
    @Test func theAppleInstructionsGiveNoReadyMadeCategoriesEither() {
        #expect(AnalysisPrompt.version == "p32-v1")
        #expect(!AnalysisPrompt.instructions.contains("belongs to Santé"))
        #expect(AnalysisPrompt.instructions.localizedCaseInsensitiveContains("create a new category"))
        #expect(AnalysisPrompt.instructions.localizedCaseInsensitiveContains("birthday"))
        #expect(AnalysisPrompt.prompt(text: "x", categories: [], likely: [], facts: ["une mesure de poids"])
            .contains("une mesure de poids"))
    }
    #endif
}
