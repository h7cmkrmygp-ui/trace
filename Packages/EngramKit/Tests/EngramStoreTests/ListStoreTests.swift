import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P15 — une liste par nom : chaque « ajoute … à ma liste d'épicerie » la complète, au lieu d'une nouvelle note.
struct ListStoreTests {
    func thought(_ text: String, kind: MemoryKind = .task) -> ValidThought {
        ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                     categoryPath: ["Achats"], mentionedDates: [])
    }

    func dictate(_ env: StoreTestEnvironment, _ texts: String...) throws -> (sourceID: UUID, filed: [Memory]) {
        let interim = try env.saveNote(texts.joined(separator: " "))
        let filed = try env.filer.file(texts.map { thought($0) }, sourceID: interim.sourceID).memories
        return (interim.sourceID, filed)
    }

    func lists(_ env: StoreTestEnvironment) -> ListStore { ListStore(database: env.database, dates: env.dates) }

    /// Comme une nouvelle transcription ou le retour du service en ligne : la dictée est à classer de nouveau.
    func reopen(_ env: StoreTestEnvironment, _ sourceID: UUID) throws {
        try env.database.writer.write { db in
            var source = try #require(try Source.fetchOne(db, key: sourceID))
            source.processingStatus = .waiting
            try source.update(db)
        }
    }

    @Test func theMigrationCreatesTheTables() throws {
        let env = try StoreTestEnvironment()
        let tables = try env.database.writer.read { db in
            try ["memory_list", "memory_list_addition"].map { try db.tableExists($0) }
        }
        #expect(tables == [true, true])
    }

    @Test func theFirstAdditionCreatesTheListAndTheNextOnesCompleteIt() throws {
        let env = try StoreTestEnvironment()
        let first = try dictate(env, "Ajoute du lait et des œufs à ma liste d'épicerie")
        let list = try #require(first.filed.first)
        #expect(first.filed.count == 1)
        #expect(list.title == "Liste d'épicerie")
        #expect(list.summary == "☐ Lait\n☐ Œufs")
        #expect(list.status == .active)
        env.dates.advance(by: 60)
        let second = try dictate(env, "Mets du pain sur la liste d'épicerie")
        #expect(second.filed.map(\.id) == [list.id])
        #expect(try env.memories.memory(id: list.id)?.summary == "☐ Lait\n☐ Œufs\n☐ Pain")
        // La dictée qui complète la liste ne laisse pas de note à elle.
        let left = try env.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory WHERE source_id = ?", arguments: [second.sourceID])
        }
        #expect(left == 0)
        let summary = try #require(try lists(env).lists().first)
        #expect(summary.memoryID == list.id)
        #expect(summary.name == "Épicerie")
        #expect(summary.open == 3)
        #expect(summary.done == 0)
    }

    @Test func aCheckedItemComesBackWhenItIsNeededAgain() throws {
        let env = try StoreTestEnvironment()
        let list = try #require(try dictate(env, "Ajoute du lait à ma liste d'épicerie").filed.first)
        _ = try env.memories.updateMemory(list.id, with: MemoryEdit(summary: "☑ Lait"), actor: .user)
        _ = try dictate(env, "Ajoute du lait et du café à la liste d'épicerie")
        #expect(try env.memories.memory(id: list.id)?.summary == "☐ Lait\n☐ Café")
    }

    @Test func theSameDictationIsNeverAddedTwice() throws {
        let env = try StoreTestEnvironment()
        let first = try dictate(env, "Ajoute du lait à ma liste d'épicerie")
        let list = try #require(first.filed.first)
        let second = try dictate(env, "Ajoute du café à ma liste d'épicerie")
        _ = try env.memories.updateMemory(list.id, with: MemoryEdit(summary: "☐ Lait\n☑ Café"), actor: .user)
        // Reclassée (service en ligne revenu, nouvelle transcription) : le café coché le reste.
        try reopen(env, second.sourceID)
        _ = try env.filer.file([thought("Ajoute du café à ma liste d'épicerie")], sourceID: second.sourceID)
        #expect(try env.memories.memory(id: list.id)?.summary == "☐ Lait\n☑ Café")
        // La liste elle-même n'est jamais remplacée quand sa première dictée est reclassée.
        try reopen(env, first.sourceID)
        _ = try env.filer.file([thought("Ajoute du lait à ma liste d'épicerie")], sourceID: first.sourceID)
        #expect(try env.memories.memory(id: list.id)?.status == .active)
        #expect(try lists(env).lists().count == 1)
    }

    @Test func aListThrownAwayStartsOver() throws {
        let env = try StoreTestEnvironment()
        let old = try #require(try dictate(env, "Ajoute du lait à ma liste d'épicerie").filed.first)
        _ = try env.memories.setStatus(.trashed, for: old.id, actor: .user)
        let fresh = try #require(try dictate(env, "Ajoute du café à ma liste d'épicerie").filed.first)
        #expect(fresh.id != old.id)
        #expect(fresh.summary == "☐ Café")
        #expect(try lists(env).lists().map(\.memoryID) == [fresh.id])
    }

    @Test func aDictationCanMixAListAndANote() throws {
        let env = try StoreTestEnvironment()
        let filed = try dictate(env, "Ajoute du lait à ma liste d'épicerie", "Appeler le garage").filed
        #expect(Set(filed.map(\.title)) == ["Liste d'épicerie", "Appeler le garage"])
    }

    @Test func theExportContainsTheLists() throws {
        let env = try StoreTestEnvironment()
        _ = try dictate(env, "Ajoute du lait à ma liste d'épicerie")
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"lists\""))
        #expect(json.contains("\"list_additions\""))
    }

    @Test func listsAreNamedAndCounted() throws {
        let env = try StoreTestEnvironment()
        _ = try dictate(env, "Ajoute un livre à ma liste de cadeaux")
        env.dates.advance(by: 60)
        let grocery = try #require(try dictate(env, "Ajoute du lait et du pain à ma liste d'épicerie").filed.first)
        _ = try env.memories.updateMemory(grocery.id, with: MemoryEdit(summary: "☑ Lait\n☐ Pain"), actor: .user)
        let all = try lists(env).lists()
        #expect(all.map(\.name) == ["Épicerie", "Cadeaux"])
        #expect(all.first?.open == 1)
        #expect(all.first?.done == 1)
    }
}
