import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P21 — l'objectif d'une habitude par semaine : dit dans une note ou fixé à la main.
struct HabitGoalStoreTests {
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
        #expect(try env.database.writer.read { db in try db.tableExists("habit_goal") })
    }

    @Test func aGoalSaidInANoteIsKeptAndTheNewestWins() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Mon objectif : méditer 5 fois par semaine")
        #expect(try store(env).habitGoals() == [.meditation: 5])
        env.dates.advance(by: 86_400)
        try file(env, "Nouvel objectif : méditer 3 fois par semaine")
        #expect(try store(env).habitGoals()[.meditation] == 3)
    }

    @Test func theOwnerSetsOrRemovesAGoal() throws {
        let env = try StoreTestEnvironment()
        try store(env).setHabitGoal(.exercise, perWeek: 4)
        #expect(try store(env).habitGoals()[.exercise] == 4)
        #expect(throws: (any Error).self) { try store(env).setHabitGoal(.exercise, perWeek: 8) }
        try store(env).removeHabitGoal(.exercise)
        #expect(try store(env).habitGoals().isEmpty)
    }

    @Test func theExportContainsTheGoals() throws {
        let env = try StoreTestEnvironment()
        try store(env).setHabitGoal(.reading, perWeek: 7)
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"habit_goals\""))
    }
}
