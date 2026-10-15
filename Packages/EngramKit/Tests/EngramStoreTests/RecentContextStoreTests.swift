import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// P42 — Engram se souvient de la dictée d'il y a quelques minutes : ses personnes, ses listes et ses dossiers.
struct RecentContextStoreTests {
    func fileFirstDictation(_ env: StoreTestEnvironment) throws {
        let text = "Julie aime les parfums. Pour le chalet il faut réparer le quai. J'aimerais recevoir des écouteurs."
        let first = try env.saveNote(text)
        _ = try env.filer.file([
            ValidThought(title: "Julie aime les parfums", summary: nil, excerpt: "Julie aime les parfums", spanStart: nil,
                         spanEnd: nil, kind: .preference, tags: [], categoryPath: ["Famille"], mentionedDates: [],
                         people: ["Julie"]),
            ValidThought(title: "Réparer le quai", summary: nil, excerpt: "Pour le chalet il faut réparer le quai",
                         spanStart: nil, spanEnd: nil, kind: .task, tags: [], categoryPath: ["Projets", "Chalet"],
                         mentionedDates: []),
            ValidThought(title: "Écouteurs", summary: nil, excerpt: "J'aimerais recevoir des écouteurs", spanStart: nil,
                         spanEnd: nil, kind: .other, tags: [], categoryPath: ["Listes"], mentionedDates: [],
                         listName: "souhaits d'anniversaire", listItems: ["Écouteurs"]),
        ], sourceID: first.sourceID)
    }

    @Test func theDictationJustBeforeIsRemembered() throws {
        let env = try StoreTestEnvironment()
        try fileFirstDictation(env)
        env.dates.advance(by: 10 * 60)
        let second = try env.saveNote("Elle adore aussi le chocolat")
        let recent = try #require(try env.memories.recentContext(before: second.sourceID))
        #expect(recent.people == ["Julie"])
        #expect(recent.lists == ["souhaits d'anniversaire"])
        // Le dossier de la liste n'est pas un projet : seulement ceux des notes.
        #expect(recent.folders.sorted() == ["Famille", "Projets › Chalet"])
        #expect(recent.minutesAgo == 10)
    }

    @Test func aDictationFromHoursAgoIsNoLongerContext() throws {
        let env = try StoreTestEnvironment()
        try fileFirstDictation(env)
        env.dates.advance(by: 2 * 60 * 60)
        let later = try env.saveNote("Elle adore aussi le chocolat")
        #expect(try env.memories.recentContext(before: later.sourceID) == nil)
    }
}
