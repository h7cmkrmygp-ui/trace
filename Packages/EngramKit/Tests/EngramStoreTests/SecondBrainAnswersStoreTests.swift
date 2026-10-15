import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// P43 — les réponses viennent des listes, des notes reliées à la personne et de sa fête.
struct SecondBrainAnswersStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind = .preference, path: [String] = ["Famille"],
              people: [String] = ["Julie"], list: String? = nil, items: [String] = [], birthdayOf: String? = nil) throws {
        let interim = try env.saveNote(text)
        _ = try env.filer.file([ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind,
                                             tags: [], categoryPath: path, mentionedDates: [], people: people,
                                             birthdayOf: birthdayOf, listName: list, listItems: items)],
                               sourceID: interim.sourceID)
        env.dates.advance(by: 60 * 60)
    }

    @Test func theWishListAnswersWhatIWanted() throws {
        let env = try StoreTestEnvironment()
        try file(env, "J'aimerais recevoir des écouteurs pour mon anniversaire", kind: .other, path: ["Listes"], people: [],
                 list: "souhaits d'anniversaire", items: ["Écouteurs"])
        let lists = ListStore(database: env.database, dates: env.dates)
        #expect(try lists.listAnswer(to: "Qu'est-ce que je voulais pour mon anniversaire?")
            == "Dans ta liste de souhaits d'anniversaire : Écouteurs.")
        #expect(try lists.listAnswer(to: "C'est quoi le numéro du garage?") == nil)
    }

    @Test func whatJulieLikesHerGiftIdeasAndHerBirthday() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Julie aime les parfums")
        try file(env, "Un foulard ferait un beau cadeau pour Julie", kind: .idea, path: ["Listes"],
                 list: "cadeaux pour Julie", items: ["Foulard"])
        try file(env, "L'anniversaire de Julie est le 12 mars", kind: .info, path: ["Anniversaires"], birthdayOf: "Julie")
        let answer = try EntityStore(database: env.database, dates: env.dates)
            .personAnswer(to: "Qu'est-ce que Julie aime?", now: env.dates.now(), calendar: Fixtures.calendar)
        #expect(answer?.hasPrefix("D'après tes notes, Julie aime les parfums. Idées de cadeaux pour Julie : Foulard.") == true)
        #expect(answer?.contains("12 mars") == true)
    }
}
