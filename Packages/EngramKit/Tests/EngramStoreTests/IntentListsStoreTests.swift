import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P41 — les choses à recevoir, à acheter ou à offrir vont dans leur liste (créée la première fois, retrouvée ensuite même
/// dite autrement), sans note à part ; le résumé dit ce qui a été ajouté.
struct IntentListsStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, list: String?, items: [String], path: [String] = ["Listes"],
              intent: IntentType = .wish)
        throws -> FilingSummary {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .other, tags: [],
                                   categoryPath: path, mentionedDates: [], listName: list, listItems: items,
                                   intent: intent)
        return try env.filer.file([thought], sourceID: interim.sourceID)
    }

    @Test func wishesGoInTheirListWithoutASeparateNote() throws {
        let env = try StoreTestEnvironment()
        let summary = try file(env, "J'aimerais recevoir une bouteille d'eau pour mon anniversaire",
                               list: "souhaits d'anniversaire", items: ["Bouteille d'eau"])
        let list = try #require(try ListStore(database: env.database, dates: env.dates).lists().first)
        #expect(list.title == "Liste de souhaits d'anniversaire")
        #expect(summary.memories.map(\.id) == [list.memoryID])
        #expect(summary.listAdditions[list.memoryID] == ["Bouteille d'eau"])
        #expect(try env.memories.memory(id: list.memoryID)?.summary == "☐ Bouteille d'eau")
    }

    @Test func threeDaysLaterTheSameListIsCompleted() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "J'aimerais recevoir une bouteille d'eau pour mon anniversaire",
                     list: "souhaits d'anniversaire", items: ["Bouteille d'eau"])
        // Dit autrement, par l'IA ou par la commande « ajoute … à ma liste d'anniversaire » : la même liste.
        _ = try file(env, "Des écouteurs aussi", list: "anniversaire", items: ["Écouteurs"])
        let command = try env.saveNote("Ajoute un livre à ma liste d'anniversaire")
        _ = try env.filer.file([ValidThought(title: "Livre", summary: nil, excerpt: "Ajoute un livre à ma liste d'anniversaire",
                                             spanStart: nil, spanEnd: nil, kind: .task, tags: [], categoryPath: [],
                                             mentionedDates: [], intent: .listAdd)], sourceID: command.sourceID)
        let lists = try ListStore(database: env.database, dates: env.dates).lists()
        try #require(lists.count == 1)
        #expect(try env.memories.memory(id: lists[0].memoryID)?.summary == "☐ Bouteille d'eau\n☐ Écouteurs\n☐ Livre")
    }
}
