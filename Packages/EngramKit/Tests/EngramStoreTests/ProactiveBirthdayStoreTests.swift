import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// P44 — les idées de la veille d'une fête viennent des notes et des listes de la personne.
struct ProactiveBirthdayStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind = .preference, path: [String] = ["Famille"],
              people: [String], list: String? = nil, items: [String] = [], birthdayOf: String? = nil) throws {
        let interim = try env.saveNote(text)
        _ = try env.filer.file([ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind,
                                             tags: [], categoryPath: path, mentionedDates: [], people: people,
                                             birthdayOf: birthdayOf, listName: list, listItems: items)],
                               sourceID: interim.sourceID,
                               route: AnalysisRoute(level: .personal, provider: "groq", reason: "Une personne nommée.",
                                                    needsCloudRetry: false))
        env.dates.advance(by: 60 * 60)
    }

    @Test func onlyPeopleWithABirthdayGetIdeas() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Julie aime les parfums", people: ["Julie"])
        try file(env, "Un foulard ferait un beau cadeau pour Julie", kind: .idea, path: ["Listes"], people: ["Julie"],
                 list: "cadeaux pour Julie", items: ["Foulard"])
        try file(env, "L'anniversaire de Julie est le 12 mars", kind: .info, path: ["Anniversaires"], people: ["Julie"],
                 birthdayOf: "Julie")
        // Marc n'a pas de fête connue : aucune idée pour lui.
        try file(env, "Marc aime le café", people: ["Marc"])
        let store = EntityStore(database: env.database, dates: env.dates)
        let julie = try #require(try store.allEntities(kind: .person).first { $0.name == "Julie" })
        let ideas = try store.birthdayIdeas()
        #expect(ideas[julie.id] == "Idées de cadeaux : Foulard. Julie aime les parfums.")
        #expect(ideas.count == 1)
    }
}
