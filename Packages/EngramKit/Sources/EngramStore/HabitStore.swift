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
    public let total: Int
    public let streak: Int
    public let bestStreak: Int
    public let thisWeek: Int
    public let lastDoneAt: Date?
    public var id: Habit { habit }
}

/// P17 — les habitudes : relevées au classement et dans les anciennes notes, avec les mesures.
extension MeasurementStore {
    public func habitEntries(for habit: Habit) throws -> [HabitEntry] { [] }

    public func habitSummaries(today: Date) throws -> [HabitSummary] { [] }
}
