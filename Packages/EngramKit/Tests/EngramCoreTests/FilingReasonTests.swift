import Foundation
import Testing
@testable import EngramCore

/// P32 — le choix de la catégorie vient de l'IA, qui l'explique en une phrase ; Engram ne fait que vérifier.
struct FilingReasonTests {
    static let text = "Retiens la fête à Léa, c'est le 13 mars"

    func validated(category: String, subcategory: String? = nil, reason: String?) throws -> ValidThought {
        let thought = AnalyzedThought(title: "Fête de Léa", summary: nil, excerpt: Self.text, kind: .info, tags: [],
                                      mentionedDates: [], category: category, subcategory: subcategory,
                                      categoryReason: reason)
        return try #require(try AnalysisValidator.validate(ThoughtAnalysis(thoughts: [thought]), against: Self.text).first)
    }

    @Test func theAIsReasonIsKeptWithItsChoice() throws {
        let valid = try validated(category: "Famille", reason: "  Une date à retenir pour Léa :\n elle va avec la famille.  ")
        #expect(valid.categoryPath == ["Famille"])
        #expect(valid.categoryReason == "Une date à retenir pour Léa : elle va avec la famille.")
        // Trop longue : coupée.
        let long = try validated(category: "Famille", reason: String(repeating: "a", count: 500))
        #expect(long.categoryReason?.count == AnalysisValidator.maxReasonLength)
        #expect(try validated(category: "Famille", reason: "   ").categoryReason == nil)
    }

    @Test func aRefusedChoiceLeavesNoReason() throws {
        // Engram refuse une fête dans un suivi de poids : la raison donnée pour ce dossier ne compte plus.
        let valid = try validated(category: "Santé", subcategory: "Poids", reason: "C'est une mesure.")
        #expect(valid.categoryPath.isEmpty)
        #expect(valid.categoryReason == nil)
    }
}
