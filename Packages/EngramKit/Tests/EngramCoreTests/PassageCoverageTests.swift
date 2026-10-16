import Foundation
import Testing
@testable import EngramCore

/// F05 — ce qu'aucune pensée ne reprend se mesure par passages exacts, pas par mots partagés ailleurs : « appeler Marc »
/// n'est pas couvert par « appeler Paul », une négation ou une commande courte n'est jamais perdue.
struct PassageCoverageTests {
    func thought(_ excerpt: String, in text: String, dates: [String] = [], people: [String] = []) -> ValidThought {
        let range = (text as NSString).range(of: excerpt)
        return ValidThought(title: excerpt, summary: nil, excerpt: excerpt, spanStart: range.location,
                            spanEnd: range.location + range.length, kind: .task, tags: [], categoryPath: [],
                            mentionedDates: dates, people: people)
    }

    func uncovered(_ text: String, _ excerpts: [String]) -> [String] {
        AnalysisValidator.uncoveredPassages(of: text, thoughts: excerpts.map { thought($0, in: text) }).map(\.text)
    }

    @Test func anIntentionThatSharesWordsWithAnotherIsNotCovered() {
        #expect(uncovered("Je dois appeler Paul. Je dois appeler Marc.", ["Je dois appeler Paul"]) == ["Je dois appeler Marc"])
    }

    @Test func aNegationOrAShortCommandIsKept() {
        #expect(uncovered("Appeler Paul. Ne pas appeler Paul.", ["Appeler Paul"]) == ["Ne pas appeler Paul"])
        #expect(uncovered("Réparer la douche. Payer loyer.", ["Réparer la douche"]) == ["Payer loyer"])
        #expect(uncovered("Appeler Marc demain, pas Paul.", ["Appeler Marc demain"]) == ["pas Paul"])
    }

    @Test func hesitationsAndTheThoughtsOwnDetailsAreNotLeftOver() {
        let text = "Euh ok faut que je call le garage pour les pneus, genre demain"
        let call = thought("call le garage pour les pneus", in: text, dates: ["demain"])
        #expect(AnalysisValidator.uncoveredPassages(of: text, thoughts: [call]).isEmpty)
        #expect(uncovered("Appeler le garage pour les pneus. Aussi, bon.", ["Appeler le garage pour les pneus"]).isEmpty)
        #expect(uncovered("J'aimerais une gourde. Ah, et.", ["J'aimerais une gourde"]).isEmpty)
    }

    @Test func eachPassageKeepsItsExactPosition() throws {
        let text = "Réparer la douche. Payer loyer. Appeler Marc."
        let passages = AnalysisValidator.uncoveredPassages(of: text, thoughts: [thought("Réparer la douche", in: text)])
        #expect(passages.map(\.text) == ["Payer loyer", "Appeler Marc"])
        for passage in passages {
            #expect((text as NSString).substring(with: passage.range) == passage.text)
        }
    }

    @Test func theOldLeftoverEntryUsesTheSameRule() {
        #expect(AnalysisValidator.leftover(of: "Je dois appeler Paul. Je dois appeler Marc.", excerpts: ["Je dois appeler Paul"])
            == "Je dois appeler Marc")
    }
}
