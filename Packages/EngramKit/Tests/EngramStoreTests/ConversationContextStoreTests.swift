import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// F23 — le contexte récent suit la conversation : chaque élément (personnes, listes, dossiers) vient de la dernière
/// dictée qui en a dit un, dans la fenêtre de 30 minutes ; une dictée qui ne nomme rien n'interrompt pas la suite.
struct ConversationContextStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind, path: [String], people: [String] = [],
              intent: IntentType) throws -> UUID {
        let interim = try env.saveNote(text)
        _ = try env.filer.file([ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil,
                                             kind: kind, tags: [], categoryPath: path, mentionedDates: [], people: people,
                                             intent: intent)],
                               sourceID: interim.sourceID)
        env.dates.advance(by: 60)
        return interim.sourceID
    }

    @Test func aDictationWithoutNamesDoesNotBreakTheThread() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "Julie aime les parfums", kind: .preference, path: ["Famille"], people: ["Julie"],
                     intent: .preference)
        _ = try file(env, "Réparer le quai du chalet", kind: .task, path: ["Projets", "Chalet"], intent: .obligation)
        let third = try env.saveNote("Elle aimerait aussi un foulard")
        let recent = try #require(try env.memories.recentContext(before: third.sourceID))
        #expect(recent.people == ["Julie"])
        #expect(recent.folders == ["Projets › Chalet"])
        #expect(recent.minutesAgo == 1)
    }

    @Test func theLatestPersonWins() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "Julie aime les parfums", kind: .preference, path: ["Famille"], people: ["Julie"],
                     intent: .preference)
        _ = try file(env, "Marc déteste le café", kind: .preference, path: ["Famille"], people: ["Marc"],
                     intent: .preference)
        let third = try env.saveNote("Il aime le thé")
        #expect(try env.memories.recentContext(before: third.sourceID)?.people == ["Marc"])
    }

    @Test func nothingOlderThanTheWindowIsUsed() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "Julie aime les parfums", kind: .preference, path: ["Famille"], people: ["Julie"],
                     intent: .preference)
        env.dates.advance(by: RecentContext.window + 60)
        let later = try env.saveNote("Elle aimerait un foulard")
        #expect(try env.memories.recentContext(before: later.sourceID) == nil)
    }
}
