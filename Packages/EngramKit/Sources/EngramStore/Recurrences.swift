import EngramCore
import Foundation
import GRDB

/// Le rythme d'une tâche (table `memory_recurrence`).
public struct MemoryRecurrence: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_recurrence" }
    public var memoryID: UUID
    public var rule: RecurrenceRule
    /// La première fois (pour « aux deux semaines » et l'heure).
    public var anchorAt: Date
    /// Combien de fois la tâche a été faite.
    public var doneCount: Int
    public var lastDoneAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case rule
        case memoryID = "memory_id"
        case anchorAt = "anchor_at"
        case doneCount = "done_count"
        case lastDoneAt = "last_done_at"
        case createdAt = "created_at"
    }
}

/// P16 — les tâches qui reviennent.
extension MemoryStore {
    public func recurrence(for memoryID: UUID) throws -> MemoryRecurrence? { nil }

    /// Pose, change ou (nil) retire le rythme d'une tâche.
    public func setRecurrence(_ rule: RecurrenceRule?, for memoryID: UUID) throws {}
}
