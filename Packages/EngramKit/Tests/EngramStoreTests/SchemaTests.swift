import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct SchemaTests {
    @Test func createsAllTables() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { (db: Database) throws in
            for table in ["source", "memory", "memory_version", "category", "memory_category", "tag",
                          "memory_tag", "embedding", "memory_fts", "processing_job", "change_log", "setting"] {
                #expect(try db.tableExists(table), "table manquante : \(table)")
            }
            #expect(try Schema.migrator.hasCompletedMigrations(db))
        }
    }

    @Test func migratingTwiceIsHarmless() throws {
        let database = try AppDatabase.inMemory()
        _ = try AppDatabase(database.writer)
    }

    @Test func memoryRequiresAnExistingSource() throws {
        let database = try AppDatabase.inMemory()
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try Fixtures.memory(sourceID: UUID()).insert(db) }
        }
    }

    @Test func rejectsUnknownStatus() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in try Fixtures.source().insert(db) }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE source SET processing_status = 'bogus'")
            }
        }
    }

    @Test func trashedMemoryMustHaveTrashedAt() throws {
        let database = try AppDatabase.inMemory()
        let source = Fixtures.source()
        try database.writer.write { db in try source.insert(db) }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try Fixtures.memory(sourceID: source.id, status: .trashed).insert(db)
            }
        }
    }

    @Test func fullTextIndexFollowsMemoryChanges() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            let source = Fixtures.source()
            try source.insert(db)
            var memory = Fixtures.memory(sourceID: source.id, title: "Réunion budget", content: "Préparer le budget")
            try memory.insert(db)
            let count = { (term: String) throws -> Int in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM memory_fts WHERE memory_fts MATCH ?", arguments: [term]) ?? -1
            }
            #expect(try count("reunion") == 1)
            memory.title = "Rendez-vous dentiste"
            try memory.update(db)
            #expect(try count("reunion") == 0)
            #expect(try count("dentiste") == 1)
            _ = try memory.delete(db)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM memory_fts") == 0)
        }
    }

    @Test func changeLogRecordsMutations() throws {
        let database = try AppDatabase.inMemory()
        let source = Fixtures.source()
        try database.writer.write { db in try source.insert(db) }
        let rows = try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT entity, op FROM change_log ORDER BY seq")
        }
        #expect(rows.count == 1)
        let entity: String? = rows.first?["entity"]
        let op: String? = rows.first?["op"]
        #expect(entity == "source")
        #expect(op == "insert")
    }

    @Test func embeddingsDisappearWithTheirMemory() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            let source = Fixtures.source()
            try source.insert(db)
            let memory = Fixtures.memory(sourceID: source.id)
            try memory.insert(db)
            try db.execute(sql: """
                INSERT INTO embedding(id, owner_kind, owner_id, model, dimensions, vector, input_hash, created_at)
                VALUES (?, 'memory', ?, 'test', 2, ?, 'h', ?)
                """, arguments: [UUID(), memory.id, Data(count: 8), Fixtures.date])
            _ = try memory.delete(db)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM embedding") == 0)
        }
    }

    @Test func activeSiblingCategoriesCannotShareANormalizedName() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try EngramCategory(name: "Voyages", parentID: nil, origin: .seed, now: Fixtures.date).insert(db)
        }
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in
                try EngramCategory(name: "voyage", parentID: nil, origin: .ai, now: Fixtures.date).insert(db)
            }
        }
        try database.writer.write { db in
            try EngramCategory(name: "voyage", parentID: nil, origin: .ai, status: .archived, now: Fixtures.date).insert(db)
        }
    }

    @Test func dataSurvivesReopeningTheFile() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("engram.sqlite").path
        do {
            let database = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
            try database.writer.write { db in try Fixtures.source().insert(db) }
        }
        let reopened = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
        #expect(try reopened.writer.read { db in try Source.fetchCount(db) } == 1)
    }
}
