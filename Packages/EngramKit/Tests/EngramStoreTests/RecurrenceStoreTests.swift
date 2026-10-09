import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P16 — une tâche qui revient : dictée (« tous les lundis ») ou posée à la main ; « Fait » la passe à la prochaine fois.
struct RecurrenceStoreTests {
    /// Une date à Toronto (comme `Fixtures.calendar`).
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        Fixtures.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind = .task) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind,
                                   tags: [], categoryPath: ["Maison"], mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func theMigrationCreatesTheTable() throws {
        let env = try StoreTestEnvironment()
        #expect(try env.database.writer.read { db in try db.tableExists("memory_recurrence") })
    }

    @Test func aDictatedRhythmIsKeptAndGivesTheFirstDate() throws {
        let env = try StoreTestEnvironment()
        // Dit le vendredi 15 janvier 2027 : la première fois est le lundi 18.
        let trash = try file(env, "Sortir les poubelles tous les lundis")
        let recurrence = try #require(try env.memories.recurrence(for: trash.id))
        #expect(recurrence.rule == RecurrenceRule(frequency: .weekly, weekdays: [2]))
        #expect(trash.dueAt == Self.date(2027, 1, 18))
        #expect(trash.dueHasTime == false)
        // Avec une heure : le jour même si elle n'est pas passée.
        let vitamins = try file(env, "Prendre mes vitamines tous les jours à 8 h")
        #expect(vitamins.dueAt == Self.date(2027, 1, 15, 8))
        #expect(vitamins.dueHasTime)
        // Une idée ou une info ne se répète pas.
        let gym = try file(env, "Je vais au gym tous les lundis", kind: .info)
        #expect(try env.memories.recurrence(for: gym.id) == nil)
    }

    @Test func doneMovesTheTaskToTheNextTime() throws {
        let env = try StoreTestEnvironment()
        let trash = try file(env, "Sortir les poubelles tous les lundis")
        let done = try env.memories.setStatus(.archived, for: trash.id, actor: .user)
        #expect(done.status == trash.status)
        #expect(done.dueAt == Self.date(2027, 1, 25))
        let recurrence = try #require(try env.memories.recurrence(for: trash.id))
        #expect(recurrence.doneCount == 1)
        #expect(recurrence.lastDoneAt == Fixtures.date)
        #expect(try env.memories.versions(of: trash.id).first?.changeReason?.hasPrefix("fait") == true)
        // La corbeille reste la corbeille.
        #expect(try env.memories.setStatus(.trashed, for: trash.id, actor: .user).status == .trashed)
    }

    @Test func theOwnerCanSetChangeOrStopTheRhythm() throws {
        let env = try StoreTestEnvironment()
        let filter = try file(env, "Changer le filtre de la fournaise")
        #expect(filter.dueAt == nil)
        try env.memories.setRecurrence(RecurrenceRule(frequency: .monthly, dayOfMonth: 1), for: filter.id)
        #expect(try env.memories.memory(id: filter.id)?.dueAt == Self.date(2027, 2, 1))
        try env.memories.setRecurrence(nil, for: filter.id)
        #expect(try env.memories.recurrence(for: filter.id) == nil)
        // Sans rythme, « Fait » range la tâche dans les Archives.
        #expect(try env.memories.setStatus(.archived, for: filter.id, actor: .user).status == .archived)
    }

    @Test func theExportContainsTheRhythms() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "Sortir les poubelles tous les lundis")
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"recurrences\""))
    }
}
