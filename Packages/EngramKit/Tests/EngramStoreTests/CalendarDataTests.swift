import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct CalendarDataTests {
    func valid(_ title: String, kind: MemoryKind, dates: [String] = [], path: [String] = ["Santé"]) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: title, spanStart: nil, spanEnd: nil, kind: kind,
                     tags: [], categoryPath: path, mentionedDates: dates)
    }

    func file(_ env: StoreTestEnvironment, _ thoughts: [ValidThought]) throws -> [Memory] {
        let interim = try env.saveNote(thoughts.map(\.title).joined(separator: ". "))
        return try env.filer.file(thoughts, sourceID: interim.sourceID).memories
    }

    /// Fixtures.date = vendredi 15 janvier 2027, 3 h, à Toronto.
    static func toronto(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Fixtures.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func aV1DatabaseMigratesToV2WithoutLosingData() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("engram.sqlite").path
        let sourceID = UUID()
        let memoryID = UUID()
        do {
            let queue = try DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration())
            try Schema.migrator.migrate(queue, upTo: "v1_initial")
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO source (id, kind, original_text, languages, content_hash, captured_at, processing_status, created_at, updated_at)
                    VALUES (?, 'text', 'Acheter du lait', '[]', 'h', ?, 'waiting', ?, ?)
                    """, arguments: [sourceID, Fixtures.date, Fixtures.date, Fixtures.date])
                try db.execute(sql: """
                    INSERT INTO memory (id, source_id, excerpt, title, content, status, mentioned_dates, analysis_version, captured_at, created_at, updated_at)
                    VALUES (?, ?, 'Acheter du lait', 'Acheter du lait', 'Acheter du lait', 'unsorted', '[]', 'interim-none', ?, ?, ?)
                    """, arguments: [memoryID, sourceID, Fixtures.date, Fixtures.date, Fixtures.date])
            }
        }
        let database = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
        let memory = try #require(try database.writer.read { db in try Memory.fetchOne(db, key: memoryID) })
        #expect(memory.title == "Acheter du lait")
        #expect(memory.dueAt == nil)
        #expect(memory.dueHasTime == false)
        #expect(try database.writer.read { db in try db.tableExists("calendar_link") })
    }

    @Test func filingResolvesTheDueDateFromTheMentionedDates() throws {
        let env = try StoreTestEnvironment()
        let memories = try file(env, [
            valid("Dentiste demain à 14h", kind: .appointment, dates: ["demain à 14h"]),
            valid("Idée de jardin", kind: .idea, path: ["Maison"]),
            valid("Rapport vendredi", kind: .task, dates: ["vendredi"], path: ["Travail"]),
        ])
        #expect(memories[0].dueAt == Self.toronto(2027, 1, 16, 14, 0))
        #expect(memories[0].dueHasTime)
        #expect(memories[1].dueAt == nil)
        #expect(memories[2].dueAt == Self.toronto(2027, 1, 22))
        #expect(memories[2].dueHasTime == false)
    }

    @Test func streamsMemoriesDueWithinARange() async throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, [
            valid("Dentiste demain", kind: .appointment, dates: ["demain"]),
            valid("Rapport le 29 janvier", kind: .task, dates: ["29 janvier"], path: ["Travail"]),
        ])
        var iterator = env.memories.memoriesStream(dueFrom: Self.toronto(2027, 1, 16), to: Self.toronto(2027, 1, 17)).makeAsyncIterator()
        let due = try #require(try await iterator.next())
        #expect(due.map(\.title) == ["Dentiste le 16 janvier"])
    }

    @Test func settingsStoreStringsAndBooleansWithDefaults() throws {
        let env = try StoreTestEnvironment()
        let settings = SettingStore(database: env.database, dates: env.dates)
        #expect(try settings.bool(.calendarAutoAdd, default: true) == true)
        try settings.set(false, for: .calendarAutoAdd)
        #expect(try settings.bool(.calendarAutoAdd, default: true) == false)
        #expect(try settings.string(.calendarTarget) == nil)
        try settings.set("calendrier-1", for: .calendarTarget)
        #expect(try settings.string(.calendarTarget) == "calendrier-1")
        try settings.set(nil, for: .calendarTarget)
        #expect(try settings.string(.calendarTarget) == nil)
    }

    @Test func linksAMemoryOnceAndListsUnlinkedFutureAppointments() throws {
        let env = try StoreTestEnvironment()
        let memories = try file(env, [
            valid("Dentiste demain", kind: .appointment, dates: ["demain"]),
            valid("Garage le 29 janvier", kind: .appointment, dates: ["29 janvier"], path: ["Automobile"]),
            valid("Payer le loyer demain", kind: .task, dates: ["demain"], path: ["Finance"]),
            valid("Rendez-vous un jour", kind: .appointment),
        ])
        let links = CalendarLinkStore(database: env.database, dates: env.dates)
        #expect(Set(try links.unlinkedAppointments().map(\.title)) == ["Dentiste le 16 janvier", "Garage le 29 janvier"])
        try links.link(memoryID: memories[0].id, eventIdentifier: "evt-1", calendarIdentifier: "cal")
        #expect(try links.link(for: memories[0].id)?.eventIdentifier == "evt-1")
        #expect(try links.unlinkedAppointments().map(\.title) == ["Garage le 29 janvier"])
        try links.link(memoryID: memories[0].id, eventIdentifier: "evt-2", calendarIdentifier: "cal")
        #expect(try links.link(for: memories[0].id)?.eventIdentifier == "evt-1")
    }

    @Test func brainSnapshotUsesTheMostPreciseCategory() async throws {
        let env = try StoreTestEnvironment()
        let memories = try file(env, [
            valid("Wipers", kind: .task, path: ["Automobile", "Corolla"]),
            valid("Pensée floue", kind: .idea, path: []),
        ])
        let trashed = try env.saveNote("À jeter")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)
        var iterator = env.categories.brainSnapshotStream().makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(Set(snapshot.categories.map(\.name)) == ["Automobile", "Corolla"])
        let corolla = try #require(snapshot.categories.first { $0.name == "Corolla" })
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        #expect(byID[memories[0].id]?.categoryID == corolla.id)
        #expect(byID[memories[1].id]?.categoryID == nil)
        #expect(byID[trashed.id] == nil)
    }
}
