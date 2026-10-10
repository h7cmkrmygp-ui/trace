import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P11 — notes épinglées et objectifs des suivis.
struct PinsAndGoalsStoreTests {
    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .info,
                                   tags: [], categoryPath: ["Santé"], mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func theMigrationCreatesTheTables() throws {
        let env = try StoreTestEnvironment()
        let tables = try env.database.writer.read { db in try ["memory_pin", "tracker_goal"].map { try db.tableExists($0) } }
        #expect(tables == [true, true])
    }

    @Test func pinnedNotesComeFirstAndLeaveWithTheTrash() throws {
        let env = try StoreTestEnvironment()
        let first = try env.saveNote("Code de la porte du garage : demander à Marc")
        env.dates.advance(by: 60)
        let second = try env.saveNote("Idée de cadeau pour la fête")
        try env.memories.setPinned(true, for: first.id)
        env.dates.advance(by: 60)
        try env.memories.setPinned(true, for: second.id)
        #expect(try env.memories.pinnedMemories().map(\.id) == [second.id, first.id])
        #expect(try env.memories.isPinned(first.id))
        try env.memories.setPinned(false, for: second.id)
        #expect(try env.memories.pinnedMemories().map(\.id) == [first.id])
        _ = try env.memories.setStatus(.trashed, for: first.id, actor: .user)
        #expect(try env.memories.pinnedMemories().isEmpty)
    }

    @Test func aGoalSaidInANoteIsKeptAndTheNewestWins() throws {
        let env = try StoreTestEnvironment()
        let store = MeasurementStore(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
        try file(env, "Je pèse 165 livres, objectif 155 livres")
        #expect(try store.goal(metric: .weight)?.target == 155)
        #expect(try store.points(metric: .weight, weightUnit: "lb").map(\.value) == [165])
        env.dates.advance(by: 86_400)
        try file(env, "Nouvel objectif : 150 livres")
        #expect(try store.goal(metric: .weight)?.target == 150)
        // Fixé à la main, il garde son unité ; retiré, il disparaît.
        try store.setGoal(metric: .weight, target: 70, unit: "kg")
        #expect(try store.goal(metric: .weight)?.target == 70)
        #expect(try store.goal(metric: .weight)?.unit == "kg")
        try store.removeGoal(metric: .weight)
        #expect(try store.goal(metric: .weight) == nil)
    }
}
