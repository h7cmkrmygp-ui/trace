import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P17 — les habitudes relevées dans les notes, sur l'iPhone : séries, semaine, anciennes notes.
struct HabitStoreTests {
    func store(_ env: StoreTestEnvironment) -> MeasurementStore {
        MeasurementStore(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
    }

    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .info,
                                   tags: [], categoryPath: ["Santé"], mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func theMigrationCreatesTheTable() throws {
        let env = try StoreTestEnvironment()
        #expect(try env.database.writer.read { db in try db.tableExists("habit_entry") })
    }

    @Test func aDoneHabitIsKeptWithItsDay() throws {
        let env = try StoreTestEnvironment()
        try file(env, "J'ai médité 10 minutes")
        env.dates.advance(by: 60)
        try file(env, "Hier j'ai couru 5 km")
        let entries = try store(env).habitEntries(for: .running)
        #expect(entries.count == 1)
        #expect(entries.first?.quantity == 5)
        #expect(entries.first?.unit == "km")
        let yesterday = try #require(Fixtures.calendar.date(byAdding: .day, value: -1, to: Fixtures.date))
        #expect(Fixtures.calendar.isDate(try #require(entries.first?.doneAt), inSameDayAs: yesterday))
        let summaries = try store(env).habitSummaries(today: Fixtures.date)
        #expect(Set(summaries.map(\.habit)) == [.meditation, .running])
        let meditation = try #require(summaries.first { $0.habit == .meditation })
        #expect(meditation.total == 1)
        #expect(meditation.streak == 1)
        #expect(meditation.thisWeek == 1)
    }

    @Test func aNoteInTheTrashNoLongerCounts() throws {
        let env = try StoreTestEnvironment()
        let note = try file(env, "J'ai pris mes vitamines")
        _ = try env.memories.setStatus(.trashed, for: note.id, actor: .user)
        #expect(try store(env).habitSummaries(today: Fixtures.date).isEmpty)
    }

    @Test func oldNotesAreReadAgain() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("J'ai fait mon workout")
        #expect(try store(env).habitEntries(for: .exercise).isEmpty)
        _ = try store(env).backfill()
        #expect(try store(env).habitEntries(for: .exercise).count == 1)
        // Relue une deuxième fois : pas de doublon.
        _ = try store(env).backfill()
        #expect(try store(env).habitEntries(for: .exercise).count == 1)
    }

    @Test func theExportContainsTheHabits() throws {
        let env = try StoreTestEnvironment()
        try file(env, "J'ai médité")
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"habit_entries\""))
    }
}
