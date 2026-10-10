import Foundation
import Testing
@testable import EngramCore

/// P32 — le choix de la catégorie vient de l'IA, qui l'explique en une phrase ; Engram ne fait que vérifier.
struct FilingReasonTests {
    static let text = "Changer les essuie-glaces de la voiture"

    func validated(category: String, subcategory: String? = nil, reason: String?) throws -> ValidThought {
        let thought = AnalyzedThought(title: "Changer les essuie-glaces", summary: nil, excerpt: Self.text, kind: .task, tags: [],
                                      mentionedDates: [], category: category, subcategory: subcategory,
                                      categoryReason: reason)
        return try #require(try AnalysisValidator.validate(ThoughtAnalysis(thoughts: [thought]), against: Self.text).first)
    }

    @Test func theAIsReasonIsKeptWithItsChoice() throws {
        let valid = try validated(category: "Automobile", reason: "  Un entretien de la voiture :\n il va dans Automobile.  ")
        #expect(valid.categoryPath == ["Automobile"])
        #expect(valid.categoryReason == "Un entretien de la voiture : il va dans Automobile.")
        // Trop longue : coupée.
        let long = try validated(category: "Automobile", reason: String(repeating: "a", count: 500))
        #expect(long.categoryReason?.count == AnalysisValidator.maxReasonLength)
        #expect(try validated(category: "Automobile", reason: "   ").categoryReason == nil)
    }

    @Test func aRefusedChoiceLeavesNoReason() throws {
        // Engram refuse une note sans mesure dans un suivi de poids : la raison donnée pour ce dossier ne compte plus.
        let valid = try validated(category: "Santé", subcategory: "Poids", reason: "Une mesure de la voiture.")
        #expect(valid.categoryPath.isEmpty)
        #expect(valid.categoryReason == nil)
    }
}
