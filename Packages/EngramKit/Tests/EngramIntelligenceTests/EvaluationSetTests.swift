import EngramCore
import Testing
@testable import EngramIntelligence

struct EvaluationSetTests {
    @Test func hasFortyFictionalCasesWithAcceptedCategories() {
        let cases = EvaluationSet.cases
        #expect(cases.count >= 40)
        #expect(Set(cases.map(\.sentence)).count == cases.count)
        for item in cases {
            #expect(!item.sentence.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!item.acceptedRoots.isEmpty, "aucune catégorie acceptée pour « \(item.sentence) »")
        }
    }

    @Test func scoresByNormalizedRootCategory() {
        let item = EvaluationCase(sentence: "Changer l'huile de la Civic", acceptedRoots: ["Automobile", "Auto"])
        #expect(item.accepts(categoryPath: ["automobiles", "Civic"]))
        #expect(item.accepts(categoryPath: ["Auto"]))
        #expect(!item.accepts(categoryPath: ["Maison"]))
        #expect(!item.accepts(categoryPath: []))
    }
}
