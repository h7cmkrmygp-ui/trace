import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// P22 — les tâches qui reviennent, lues pour le Calendrier.
struct CalendarProjectionStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task,
                                   tags: [], categoryPath: ["Maison"], mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func livingRecurringTasksAreListed() throws {
        let env = try StoreTestEnvironment()
        let trash = try file(env, "Sortir les poubelles tous les lundis")
        _ = try file(env, "Appeler le garage")
        let gone = try file(env, "Arroser les plantes chaque semaine")
        _ = try env.memories.setStatus(.trashed, for: gone.id, actor: .user)
        let items = try env.memories.recurringTasks()
        #expect(items.map(\.memoryID) == [trash.id])
        let item = try #require(items.first)
        #expect(item.rule == RecurrenceRule(frequency: .weekly, weekdays: [2]))
        #expect(item.due == trash.dueAt)
        #expect(item.hasTime == false)
    }
}
