import Foundation
import Testing
@testable import EngramCore

/// P36 — une recherche qui trouve : les petits mots ne bloquent plus, une faute de frappe passe, les notes qui ont le plus
/// de mots cherchés viennent d'abord, le mot en train d'être tapé compte comme un début de mot, et chaque résultat montre
/// le passage trouvé.
struct SearchTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func document(_ title: String, _ text: String, status: MemoryStatus = .active, categories: [String] = [],
                  tags: [String] = []) -> RecallDocument {
        RecallDocument(id: UUID(), title: title, text: text, kind: .info, status: status,
                       capturedAt: Self.now.addingTimeInterval(-86_400), dueAt: nil, categories: categories, tags: tags)
    }

    func ids(_ hits: [RecallHit]) -> [UUID] { hits.map(\.document.id) }

    @Test func smallWordsNoLongerBlockTheSearch() {
        let policy = document("Numéro de police d'assurance", "Le numéro de police de l'assurance auto est dans le coffre")
        let call = document("Appeler l'assurance", "Appeler l'assurance pour la maison")
        let other = document("Acheter du lait", "Acheter du lait")
        let hits = RecallRanker.search([other, call, policy], for: "c'est quoi déjà le numéro d'assurance", now: Self.now)
        #expect(ids(hits) == [policy.id, call.id])
    }

    @Test func aTypoStillFinds() {
        let policy = document("Assurance de l'auto", "Renouveler l'assurance de l'auto")
        #expect(ids(RecallRanker.search([policy], for: "assurence", now: Self.now)) == [policy.id])
        // Un prénom entendu à une lettre près.
        let party = document("Fête d'Amélie", "La fête d'Amélie samedi")
        #expect(ids(RecallRanker.search([party], for: "Amelia", now: Self.now)) == [party.id])
        // Les mots courts ne sont pas rapprochés : « pain » ne trouve pas « bain ».
        let bath = document("Nettoyer le bain", "Nettoyer le bain")
        #expect(RecallRanker.search([bath], for: "pain", now: Self.now).isEmpty)
    }

    @Test func theWordBeingTypedCountsAsABeginning() {
        let tires = document("Changer les pneus", "Changer les pneus de la Corolla")
        #expect(ids(RecallRanker.search([tires], for: "pneus coro", now: Self.now)) == [tires.id])
        #expect(ids(RecallRanker.search([tires], for: "Coro", now: Self.now)) == [tires.id])
    }

    @Test func foldersPeopleAndSynonymsCount() {
        let sister = document("Souper dimanche", "Souper chez ma sœur dimanche", tags: ["Julie"])
        let car = document("Laver l'auto", "Laver l'auto samedi", categories: ["Automobile"])
        #expect(ids(RecallRanker.search([sister, car], for: "Julie", now: Self.now)) == [sister.id])
        #expect(ids(RecallRanker.search([sister, car], for: "voiture", now: Self.now)) == [car.id])
    }

    @Test func finishedNotesComeAfter() {
        let done = document("Payer l'hydro", "Payer la facture d'hydro", status: .archived)
        let open = document("Payer l'hydro", "Payer la facture d'hydro")
        let trashed = document("Payer l'hydro", "Payer la facture d'hydro", status: .trashed)
        #expect(ids(RecallRanker.search([done, trashed, open], for: "hydro", now: Self.now)) == [open.id, done.id])
    }

    @Test func eachResultShowsWhereTheWordsAre() {
        let text = "Appeler le garage pour les pneus. Le numéro de police est dans la boîte à gants."
        #expect(SearchSnippet.make(text, query: "c'est quoi le numéro de police") == "Le numéro de police est dans la boîte à gants")
        #expect(SearchSnippet.make(text, query: "assurence") == nil)
        let snippet = "Le numéro de police est dans la boîte à gants"
        let words = SearchSnippet.highlights(in: snippet, query: "numero police").map { String(snippet[$0]) }
        #expect(words == ["numéro", "police"])
    }

    @Test func retrouverToleratesTyposToo() {
        let policy = document("Assurance de l'auto", "Renouveler l'assurance de l'auto")
        let query = RecallQuery.parse("C'était quand le renouvèlement de l'assurence?", now: Self.now, calendar: .current)
        #expect(ids(RecallRanker.rank([policy], for: query, now: Self.now)) == [policy.id])
    }
}
