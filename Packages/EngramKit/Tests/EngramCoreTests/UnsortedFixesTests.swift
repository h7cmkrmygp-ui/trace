import Foundation
import Testing
@testable import EngramCore

/// P35 — moins de « À classer » : seule la partie oubliée par l'IA devient une note (pas toute la dictée, et pas pour des
/// « euh ») ; F07 : si l'IA reformule au lieu de recopier, sa réponse est refusée avec une raison précise.
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

    /// F07 (remplace le sauvetage de P35) : une réponse reformulée est refusée, et la raison précise est écrite pour le
    /// nouvel essai (l'extrait fautif cité, la consigne de recopier les mots exacts) ; aucune note n'est déduite d'elle.
    @Test func aRephrasedAnswerIsRefusedWithItsPreciseError() throws {
        let text = "Faut que j'appelle le garage pour les pneus d'hiver"
        // L'IA a traduit au lieu de recopier : aucun extrait ne se retrouve dans la note.
        let analysis = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Appeler le garage", summary: "Pneus d'hiver", excerpt: "Call the garage about winter tires",
                            kind: .task, tags: ["Pneus"], mentionedDates: [], category: "Automobile", subcategory: nil,
                            categoryReason: "Un entretien de l'auto."),
        ])
        #expect(throws: AnalyzerError.invalidOutput) { try AnalysisValidator.validate(analysis, against: text) }
        let problems = AnalysisValidator.problems(in: analysis, against: text)
        #expect(problems.count == 1)
        #expect(problems.first?.contains("Call the garage about winter tires") == true)
        // Une réponse vide est aussi expliquée.
        #expect(!AnalysisValidator.problems(in: ThoughtAnalysis(thoughts: []), against: text).isEmpty)
    }
}
