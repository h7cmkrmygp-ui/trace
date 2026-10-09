import EngramCore
import Foundation
import GRDB

/// Une habitude faite, relevée dans une note (table `habit_entry`). Recalculable depuis le texte.
public struct HabitEntry: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "habit_entry" }
    public var id: UUID
    public var memoryID: UUID
    public var habit: Habit
    public var quantity: Double?
    public var unit: String?
    public var doneAt: Date
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, habit, quantity, unit
        case memoryID = "memory_id"
        case doneAt = "done_at"
        case createdAt = "created_at"
    }
}

/// Une habitude, pour les cartes des Suivis.
public struct HabitSummary: Sendable, Equatable, Identifiable {
    public let habit: Habit
    public let days: [Date]
    /// Jours où elle a été faite.
    public let total: Int
    public let streak: Int
    public let bestStreak: Int
    public let thisWeek: Int
    public let lastDoneAt: Date?
    public var id: Habit { habit }
}

/// P17 — les habitudes : relevées au classement et dans les anciennes notes, avec les mesures.
extension MeasurementStore {
    /// Les fois où l'habitude a été faite (sans la corbeille), la plus récente d'abord.
    public func habitEntries(for habit: Habit) throws -> [HabitEntry] {
        try database.writer.read { db in try Self.habitEntries(db, habit: habit) }
    }

    public func habitEntriesStream(for habit: Habit) -> AsyncThrowingStream<[HabitEntry], any Error> {
        database.stream { db in try Self.habitEntries(db, habit: habit) }
    }

    static func habitEntries(_ db: Database, habit: Habit?) throws -> [HabitEntry] {
        try HabitEntry.fetchAll(db, sql: """
            SELECT h.* FROM habit_entry h JOIN memory m ON m.id = h.memory_id
            WHERE m.status IN ('active','unsorted','archived') AND (? IS NULL OR h.habit = ?)
            ORDER BY h.done_at DESC
            """, arguments: [habit?.rawValue, habit?.rawValue])
    }

    /// Chaque habitude faite au moins une fois : série, meilleure série, cette semaine. La plus récente d'abord.
    public func habitSummaries(today: Date) throws -> [HabitSummary] {
        let calendar = self.calendar
        return try database.writer.read { db in Self.summaries(try Self.habitEntries(db, habit: nil), today: today, calendar: calendar) }
    }

    public func habitSummariesStream(today: Date) -> AsyncThrowingStream<[HabitSummary], any Error> {
        let calendar = self.calendar
        return database.stream { db in Self.summaries(try Self.habitEntries(db, habit: nil), today: today, calendar: calendar) }
    }

    static func summaries(_ entries: [HabitEntry], today: Date, calendar: Calendar) -> [HabitSummary] {
        Dictionary(grouping: entries, by: \.habit).map { habit, list in
            let days = list.map(\.doneAt)
            return HabitSummary(habit: habit, days: days,
                                total: Set(days.map { calendar.startOfDay(for: $0) }).count,
                                streak: HabitStats.streak(days, today: today, calendar: calendar),
                                bestStreak: HabitStats.bestStreak(days, calendar: calendar),
                                thisWeek: HabitStats.thisWeek(days, today: today, calendar: calendar),
                                lastDoneAt: days.max())
        }
        .sorted { ($0.lastDoneAt ?? .distantPast, $0.habit.rawValue) > ($1.lastDoneAt ?? .distantPast, $1.habit.rawValue) }
    }

    // MARK: - Relevé

    /// Relit le texte d'une note et remplace ses habitudes. Renvoie le nombre gardé.
    @discardableResult
    func recordHabits(_ db: Database, memoryID: UUID, text: String, capturedAt: Date, now: Date) throws -> Int {
        try HabitEntry.filter(Column("memory_id") == memoryID).deleteAll(db)
        let found = HabitParser.parse(text)
        for parsed in found {
            let doneAt = calendar.date(byAdding: .day, value: -parsed.daysBefore, to: capturedAt) ?? capturedAt
            try HabitEntry(id: UUID(), memoryID: memoryID, habit: parsed.habit, quantity: parsed.quantity, unit: parsed.unit,
                           doneAt: doneAt, createdAt: now).insert(db)
        }
        return found.count
    }

    /// Les notes nouvelles ou modifiées depuis `since` (toutes si nil) : leurs habitudes sont relues, sur l'iPhone.
    /// Seules les notes qui en ont (ou en avaient) sont écrites.
    @discardableResult
    public func backfillHabits(since: Date? = nil) throws -> Int {
        let now = dates.now()
        let (notes, known) = try database.writer.read { db in
            (try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m WHERE \(Self.countedNotes) AND (? IS NULL OR m.updated_at > ?)
                """, arguments: [since, since]),
             Set(try UUID.fetchAll(db, sql: "SELECT DISTINCT memory_id FROM habit_entry")))
        }
        let changed = notes.filter { !HabitParser.parse($0.content).isEmpty || known.contains($0.id) }
        guard !changed.isEmpty else { return 0 }
        return try database.writer.write { db in
            try changed.reduce(0) { total, memory in
                total + (try recordHabits(db, memoryID: memory.id, text: memory.content, capturedAt: memory.capturedAt,
                                          now: now))
            }
        }
    }
}
