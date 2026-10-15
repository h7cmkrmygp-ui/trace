import Foundation
import Testing
@testable import EngramCore

/// P35 — moins de « À classer » : seule la partie oubliée par l'IA devient une note (pas toute la dictée, et pas pour des
/// « euh ») ; si l'IA reformule au lieu de recopier, la dictée entière est classée comme une seule note.
struct UnsortedFixesTests {
    @Test func onlyTheForgottenPartRemains() {
        let text = "Acheter des wipers pour la Corolla. Penser à rappeler le notaire au sujet de la maison."
        #expect(AnalysisValidator.leftover(of: text, excerpts: ["Acheter des wipers pour la Corolla"])
            == "Penser à rappeler le notaire au sujet de la maison")
        #expect(AnalysisValidator.leftover(of: text, excerpts: [text]) == nil)
    }

    @Test func hesitationsAreNotForgottenWords() {
        let text = "Euh ok faut que je call le garage pour les pneus, genre demain"
        #expect(AnalysisValidator.leftover(of: text, excerpts: ["call le garage pour les pneus", "demain"]) == nil)
        // Un petit bout sans sujet (« Aussi, bon ») ne fait pas une note.
        #expect(AnalysisValidator.leftover(of: "Appeler le garage pour les pneus. Aussi, bon.",
                                           excerpts: ["Appeler le garage pour les pneus"]) == nil)
    }

    @Test func aRephrasedAnswerStillFilesTheWholeNote() throws {
        let text = "Faut que j'appelle le garage pour les pneus d'hiver"
        // L'IA a traduit au lieu de recopier : aucun extrait ne se retrouve dans la note.
        let analysis = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Appeler le garage", summary: "Pneus d'hiver", excerpt: "Call the garage about winter tires",
                            kind: .task, tags: ["Pneus"], mentionedDates: [], category: "Automobile", subcategory: nil,
                            categoryReason: "Un entretien de l'auto."),
        ])
        #expect(throws: AnalyzerError.invalidOutput) { try AnalysisValidator.validate(analysis, against: text) }
        let whole = try #require(AnalysisValidator.salvage(analysis, against: text))
        #expect(whole.excerpt == text)
        #expect(whole.title == "Appeler le garage")
        #expect(whole.categoryPath == ["Automobile"])
        #expect(whole.kind == .task)
        #expect(whole.categoryReason == "Un entretien de l'auto.")
        #expect(AnalysisValidator.salvage(ThoughtAnalysis(thoughts: []), against: text) == nil)
    }
}
