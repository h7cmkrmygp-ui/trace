import Foundation
import Testing
@testable import EngramCore

/// F06 — chaque chose, personne, lieu et date d'une pensée doit venir de son propre passage : un mot présent ailleurs dans
/// la dictée ne suffit pas ; un titre ou un résumé ne peut pas ajouter un montant ou un nom absent.
struct EvidenceGroundingTests {
    func validate(_ text: String, _ thoughts: [AnalyzedThought]) throws -> [ValidThought] {
        try AnalysisValidator.validate(ThoughtAnalysis(thoughts: thoughts), against: text)
    }

    func thought(_ excerpt: String, title: String? = nil, summary: String? = nil, list: String? = nil, items: [String] = [],
                 people: [String] = [], dates: [String] = [], intent: IntentType? = .obligation) -> AnalyzedThought {
        AnalyzedThought(title: title ?? excerpt, summary: summary, excerpt: excerpt, kind: .task, tags: [],
                        mentionedDates: dates, category: "Maison", subcategory: nil, people: people, listName: list,
                        listItems: items, intent: intent)
    }

    @Test func aListItemMustBeSaidInItsOwnPassage() throws {
        // Un adjectif ajouté : « lait chocolaté » n'a pas été dit.
        let valid = try validate("Acheter du lait", [thought("Acheter du lait", list: "épicerie",
                                                             items: ["Lait chocolaté", "Lait"], intent: .purchase)])
        #expect(valid.first?.listItems == ["Lait"])
        // Le café appartient à l'autre pensée.
        let text = "Réparer la douche. Acheter du café."
        let mixed = try validate(text, [thought("Réparer la douche", list: "achats", items: ["Café"], intent: .purchase),
                                        thought("Acheter du café", list: "épicerie", items: ["Café"], intent: .purchase)])
        #expect(mixed.first?.listName == nil)
        #expect(mixed.last?.listItems == ["Café"])
    }

    @Test func peopleAndDatesBelongToTheirOwnAction() throws {
        let text = "Appeler Paul demain. Écrire à Marc lundi."
        let valid = try validate(text, [
            thought("Appeler Paul demain", people: ["Marc"], dates: ["lundi"]),
            thought("Écrire à Marc lundi", people: ["Marc"], dates: ["lundi"]),
        ])
        #expect(valid.first?.people.isEmpty == true)
        #expect(valid.first?.mentionedDates.isEmpty == true)
        #expect(valid.last?.people == ["Marc"])
        #expect(valid.last?.mentionedDates == ["lundi"])
    }

    @Test func aTitleOrSummaryCannotAddAnAmountOrAName() throws {
        let text = "Payer le plombier"
        let valid = try validate(text, [thought(text, title: "Payer 450 $ au plombier Tremblay",
                                                summary: "Payer 450 $ au plombier Tremblay avant vendredi")])
        let first = try #require(valid.first)
        #expect(first.summary == nil)
        #expect(!first.title.contains("450"))
        #expect(!first.title.contains("Tremblay"))
        // Ce qui est dit reste : un montant de la note peut figurer dans le résumé.
        let said = try validate("Payer 450 $ au plombier", [thought("Payer 450 $ au plombier", summary: "Payer 450 $ au plombier.")])
        #expect(said.first?.summary == "Payer 450 $ au plombier.")
    }

    @Test func theIntentAndItsArgumentsSurviveValidation() throws {
        var proposed = thought("Je ne dois pas appeler Marc", people: ["Marc"])
        proposed.polarity = .negative
        proposed.subject = "moi"
        proposed.action = "appeler"
        proposed.object = "Marc"
        proposed.temporal = [TemporalMention(role: .deadline, phrase: "demain")]
        let valid = try #require(try validate("Je ne dois pas appeler Marc", [proposed]).first)
        #expect(valid.intent == .obligation)
        #expect(valid.polarity == .negative)
        #expect(valid.action == "appeler")
        // « demain » n'est pas dans la note : la date est retirée.
        #expect(valid.temporal.isEmpty)
    }
}
