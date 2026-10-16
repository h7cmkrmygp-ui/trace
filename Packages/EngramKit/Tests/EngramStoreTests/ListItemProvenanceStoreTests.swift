import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// F09 — chaque chose d'une liste garde ses contributions (quelle dictée l'a ajoutée, cochée ou retirée, et si le
/// propriétaire y a touché) : un ajout erroné se retire seul, une nouvelle analyse retire ce qu'elle ne dit plus, une
/// modification automatique n'est jamais une modification du propriétaire, et une liste supprimée ne laisse aucune
/// dictée orpheline (texte et audio).
struct ListItemProvenanceStoreTests {
    func command(_ text: String, list: String = "épicerie", items: [String], people: [String] = []) -> ValidThought {
        ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .other, tags: [],
                     categoryPath: ["Listes"], mentionedDates: [], people: people, listName: list, listItems: items,
                     intent: .listAdd)
    }

    @discardableResult
    func add(_ env: StoreTestEnvironment, _ text: String, list: String = "épicerie", items: [String],
             people: [String] = []) throws -> (list: UUID, source: UUID) {
        let interim = try env.saveNote(text)
        let summary = try env.filer.file([command(text, list: list, items: items, people: people)], sourceID: interim.sourceID)
        env.dates.advance(by: 60)
        return (try #require(summary.memories.first).id, interim.sourceID)
    }

    func lists(_ env: StoreTestEnvironment) -> ListStore { ListStore(database: env.database, dates: env.dates) }

    @Test func anAutomaticAdditionIsNotAnOwnerEdit() throws {
        let env = try StoreTestEnvironment()
        let first = try add(env, "Ajoute du lait à ma liste d'épicerie", items: ["Lait"])
        #expect(try env.memories.memory(id: first.list)?.userEdited == false)
        #expect(try env.memories.versions(of: first.list).first?.changedBy == .ai)
        try add(env, "Ajoute du pain à ma liste d'épicerie", items: ["Pain"])
        #expect(try env.memories.memory(id: first.list)?.userEdited == false)
        #expect(try env.memories.versions(of: first.list).first?.changedBy == .ai)
    }

    @Test func eachItemKnowsTheDictationsThatAddedIt() throws {
        let env = try StoreTestEnvironment()
        let first = try add(env, "Ajoute du lait à ma liste d'épicerie", items: ["Lait"])
        let second = try add(env, "Ajoute du café et du lait à ma liste d'épicerie", items: ["Café", "Lait"])
        let items = try lists(env).items(of: first.list)
        #expect(items.map(\.text) == ["Lait", "Café"])
        #expect(items.first?.sources == [first.source, second.source])
        #expect(items.last?.sources == [second.source])
        #expect(items.allSatisfy { $0.provenanceKnown && !$0.touchedByOwner && !$0.done })
    }

    @Test func oneWrongAdditionCanBeRetractedAlone() throws {
        let env = try StoreTestEnvironment()
        let first = try add(env, "Ajoute du lait à ma liste d'épicerie", items: ["Lait"])
        let wrong = try add(env, "Ajoute du café et du lait à ma liste d'épicerie", items: ["Café", "Lait"])
        #expect(try lists(env).retract(sourceID: wrong.source) == ["Café"])
        // Le lait reste : une autre dictée l'avait demandé.
        #expect(try env.memories.memory(id: first.list)?.summary == "☐ Lait")
        #expect(try lists(env).items(of: first.list).map(\.text) == ["Lait"])
        // Le retrait est une action d'Engram, gardée dans l'historique de la note.
        #expect(try env.memories.versions(of: first.list).first?.changedBy == .system)
    }

    @Test func aRetractionNeverUndoesTheOwner() throws {
        let env = try StoreTestEnvironment()
        let first = try add(env, "Ajoute du lait à ma liste d'épicerie", items: ["Lait"])
        let second = try add(env, "Ajoute du café à ma liste d'épicerie", items: ["Café"])
        // Le propriétaire coche le café à la main : la case est à lui.
        _ = try env.memories.updateMemory(first.list, with: MemoryEdit(summary: "☐ Lait\n☑ Café"), actor: .user)
        #expect(try lists(env).retract(sourceID: second.source).isEmpty)
        #expect(try env.memories.memory(id: first.list)?.summary == "☐ Lait\n☑ Café")
        let coffee = try #require(try lists(env).items(of: first.list).last)
        #expect(coffee.touchedByOwner)
        #expect(coffee.done)
        // Une case écrite à la main a le propriétaire pour seule source connue.
        _ = try env.memories.updateMemory(first.list, with: MemoryEdit(summary: "☐ Lait\n☑ Café\n☐ Beurre"), actor: .user)
        let butter = try #require(try lists(env).items(of: first.list).last)
        #expect(butter.text == "Beurre")
        #expect(butter.touchedByOwner)
        #expect(butter.sources.isEmpty)
    }

    @Test func aNewAnalysisRemovesWhatItNoLongerSays() throws {
        let env = try StoreTestEnvironment()
        let other = try add(env, "Ajoute du beurre à ma liste d'épicerie", items: ["Beurre"])
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/l.caf", duration: 2,
                                                   transcript: "Ajoute du lait à ma liste d'épicerie", languages: [],
                                                   engine: nil)
        _ = try env.filer.file([command("Ajoute du lait à ma liste d'épicerie", items: ["Lait"])], sourceID: voice.sourceID)
        #expect(try env.memories.memory(id: other.list)?.summary == "☐ Beurre\n☐ Lait")
        // Whisper entend mieux : c'était du pain. Le lait, ajouté par cette seule dictée et jamais touché, part.
        try env.memories.retranscribe(sourceID: voice.sourceID, transcript: "Ajoute du pain à ma liste d'épicerie",
                                      languages: [], engine: "whisperkit")
        _ = try env.filer.file([command("Ajoute du pain à ma liste d'épicerie", items: ["Pain"])], sourceID: voice.sourceID)
        #expect(try env.memories.memory(id: other.list)?.summary == "☐ Beurre\n☐ Pain")
    }

    @Test func deletingAListOfSeveralDictationsLeavesNoOrphanDictation() throws {
        let env = try StoreTestEnvironment()
        let first = try add(env, "Ajoute du lait à ma liste d'épicerie", items: ["Lait"])
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/pain.caf", duration: 2,
                                                   transcript: "Ajoute du pain à ma liste d'épicerie", languages: [],
                                                   engine: nil)
        _ = try env.filer.file([command("Ajoute du pain à ma liste d'épicerie", items: ["Pain"])], sourceID: voice.sourceID)
        // Une dictée qui a aussi une autre note garde sa source.
        let mixed = try env.saveNote("Ajoute du café à ma liste d'épicerie. Appeler le garage.")
        _ = try env.filer.file([command("Ajoute du café à ma liste d'épicerie", items: ["Café"]),
                                ValidThought(title: "Appeler le garage", summary: nil, excerpt: "Appeler le garage",
                                             spanStart: nil, spanEnd: nil, kind: .task, tags: [], categoryPath: ["Auto"],
                                             mentionedDates: [], intent: .obligation)],
                               sourceID: mixed.sourceID)
        _ = try env.memories.setStatus(.trashed, for: first.list, actor: .user)
        let deletion = try env.memories.deletePermanently(first.list)
        #expect(deletion.deletedSourceID == first.source)
        #expect(deletion.orphanedSources == [voice.sourceID])
        #expect(deletion.orphanedAudioPaths == ["audio/pain.caf"])
        #expect(try env.memories.source(id: voice.sourceID) == nil)
        #expect(try env.memories.source(id: mixed.sourceID) != nil)
        // L'export ne contient plus la dictée du pain ; la note du garage reste.
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(!json.contains("Ajoute du pain"))
        #expect(json.contains("Appeler le garage"))
    }

    @Test func theRecentContextKnowsWhoTheLastAdditionWasFor() throws {
        let env = try StoreTestEnvironment()
        try add(env, "Ajoute un livre pour Julie à ma liste de cadeaux", list: "cadeaux", items: ["Livre"], people: ["Julie"])
        try add(env, "Ajoute une écharpe pour Marc à ma liste de cadeaux", list: "cadeaux", items: ["Écharpe"],
                people: ["Marc"])
        let next = try env.saveNote("Il aimerait aussi des gants")
        let recent = try #require(try env.memories.recentContext(before: next.sourceID))
        #expect(recent.people == ["Marc"])
        #expect(recent.lists == ["cadeaux"])
    }

    /// Les listes d'avant cette version : leurs cases deviennent des choses, de provenance inconnue (rien n'est inventé),
    /// sauf celles dont une opération notée (F08) dit la dictée.
    @Test func theMigrationKeepsExistingListsWithUnknownProvenance() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v20_revisions_operations_jobs")
        let sourceID = UUID()
        let listID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO source (id, kind, original_text, content_hash, captured_at, created_at, updated_at,
                                    processing_status)
                VALUES (?, 'text', 'Ajoute du lait et du pain à ma liste d''épicerie', 'empreinte', ?, ?, ?, 'done')
                """, arguments: [sourceID, now, now, now])
            try db.execute(sql: """
                INSERT INTO memory (id, source_id, excerpt, title, summary, content, kind, status, analysis_version,
                                    captured_at, created_at, updated_at)
                VALUES (?, ?, 'Ajoute du lait et du pain', 'Liste d''épicerie', ?, 'Ajoute du lait et du pain', 'other',
                        'active', 'p2-v1', ?, ?, ?)
                """, arguments: [listID, sourceID, "☐ Lait\n☑ Pain", now, now, now])
            try db.execute(sql: "INSERT INTO memory_list (normalized_name, name, memory_id, created_at) VALUES ('epicerie', 'épicerie', ?, ?)",
                           arguments: [listID, now])
            try db.execute(sql: """
                INSERT INTO list_operation (op_key, source_id, list_key, kind, item, applied_at)
                VALUES (?, ?, 'epicerie', 'add', 'Lait', ?)
                """, arguments: ["\(sourceID.uuidString)|add|epicerie|lait", sourceID, now])
        }
        try Schema.migrator.migrate(queue)
        let items = try queue.read { db in try ListStore.items(db, of: listID) }
        #expect(items.map(\.text) == ["Lait", "Pain"])
        #expect(items.map(\.done) == [false, true])
        #expect(items.first?.sources == [sourceID])
        #expect(items.first?.provenanceKnown == true)
        #expect(items.last?.provenanceKnown == false)
    }
}
