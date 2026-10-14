import Foundation
import Testing
@testable import EngramCore

/// P41 — comprendre les intentions : une chose à recevoir, à acheter ou une idée de cadeau va dans la bonne liste (déjà là
/// ou nouvelle), même sans le mot « liste » ; une liste existante est reconnue même dite autrement ; rien d'inventé.
struct IntentListsTests {
    @Test func anExistingListIsRecognizedEvenWhenSaidDifferently() {
        #expect(ListResolver.resolve("anniversaire", existing: ["souhaits d'anniversaire", "épicerie"]) == "souhaits d'anniversaire")
        #expect(ListResolver.resolve("Liste d'anniversaire", existing: ["souhaits d'anniversaire"]) == "souhaits d'anniversaire")
        #expect(ListResolver.resolve("Épicerie", existing: ["épicerie"]) == "épicerie")
        #expect(ListResolver.resolve("courses", existing: ["épicerie"]) == "épicerie")
        #expect(ListResolver.resolve("wishlist", existing: ["souhaits"]) == "souhaits")
        #expect(ListResolver.resolve("Liste de souhaits", existing: []) == "souhaits")
    }

    @Test func aDifferentOrAmbiguousListIsNeverGuessed() {
        #expect(ListResolver.resolve("cadeaux pour Julie", existing: ["cadeaux pour Marc"]) == "cadeaux pour Julie")
        #expect(ListResolver.resolve("anniversaire", existing: ["idées de cadeaux pour l'anniversaire de Julie"]) == "anniversaire")
        #expect(ListResolver.resolve("cadeaux", existing: ["cadeaux pour Julie", "cadeaux pour Marc"]) == "cadeaux")
    }

    func validated(_ text: String, list: String?, items: [String]) throws -> ValidThought {
        let thought = AnalyzedThought(title: "Souhaits", summary: nil, excerpt: text, kind: .other, tags: [], mentionedDates: [],
                                      category: "Listes", subcategory: nil, listName: list, listItems: items)
        return try #require(try AnalysisValidator.validate(ThoughtAnalysis(thoughts: [thought]), against: text).first)
    }

    @Test func onlyThingsActuallySaidGoInTheList() throws {
        let text = "J'aimerais qu'on m'achète une bouteille d'eau et des élastiques pour les cheveux"
        let valid = try validated(text, list: "Liste de souhaits", items: ["Bouteille d'eau", "Élastiques pour les cheveux", "Parfum"])
        #expect(valid.listName == "souhaits")
        #expect(valid.listItems == ["Bouteille d'eau", "Élastiques pour les cheveux"])
        // Sans chose à ajouter, ce n'est pas une liste.
        #expect(try validated(text, list: "souhaits", items: []).listName == nil)
        #expect(try validated(text, list: "  ", items: ["Bouteille d'eau"]).listName == nil)
    }
}
