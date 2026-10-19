import EngramCore
import Foundation
import GRDB

extension TrackerGoal: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "tracker_goal" }
}

/// Une note épinglée (pour l'export).
public struct PinnedMemory: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_pin" }
    public var memoryID: UUID
    public var pinnedAt: Date

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case pinnedAt = "pinned_at"
    }
}

/// P11 — les notes épinglées en haut des Notes, la plus récemment épinglée d'abord. Une note à la corbeille n'y est plus.
extension MemoryStore {
    public func setPinned(_ pinned: Bool, for memoryID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            if pinned {
                guard try Memory.exists(db, key: memoryID) else { throw StoreError.notFound }
                try PinnedMemory(memoryID: memoryID, pinnedAt: now).save(db)
            } else {
                _ = try PinnedMemory.deleteOne(db, key: memoryID)
            }
        }
    }

    public func isPinned(_ memoryID: UUID) throws -> Bool {
        try database.writer.read { db in try PinnedMemory.exists(db, key: memoryID) }
    }

    public func pinnedMemories() throws -> [Memory] {
        try database.writer.read { db in try Self.pinned(db) }
    }

    public func pinnedStream() -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in try Self.pinned(db) }
    }

    static func pinned(_ db: Database) throws -> [Memory] {
        try Memory.fetchAll(db, sql: """
            SELECT m.* FROM memory m JOIN memory_pin p ON p.memory_id = m.id
            WHERE m.status IN ('active','unsorted','archived')
            ORDER BY p.pinned_at DESC
            """)
    }
}

/// P11 — les objectifs des suivis : fixés à la main, ou dits dans une note (le plus récent l'emporte).
extension MeasurementStore {
    public func goal(metric: Metric) throws -> TrackerGoal? {
        try database.writer.read { db in try TrackerGoal.fetchOne(db, key: metric.rawValue) }
    }

    public func goalStream(metric: Metric) -> AsyncThrowingStream<TrackerGoal?, any Error> {
        database.stream { db in try TrackerGoal.fetchOne(db, key: metric.rawValue) }
    }

    public func setGoal(metric: Metric, target: Double, unit: String) throws {
        let now = dates.now()
        try database.writer.write { db in
            try TrackerGoal(metric: metric, target: target, unit: unit, setAt: now).save(db)
        }
    }

    public func removeGoal(metric: Metric) throws {
        try database.writer.write { db in _ = try TrackerGoal.deleteOne(db, key: metric.rawValue) }
    }

    /// Les objectifs dits dans une note ; un objectif plus récent (dit ou fixé à la main) n'est pas remplacé.
    func recordGoals(_ db: Database, memoryID: UUID, text: String, capturedAt: Date) throws {
        for goal in GoalParser.parse(text) {
            if let existing = try TrackerGoal.fetchOne(db, key: goal.metric.rawValue), existing.setAt > capturedAt { continue }
            try TrackerGoal(metric: goal.metric, target: goal.value, unit: goal.unit, setAt: capturedAt, memoryID: memoryID)
                .save(db)
        }
    }
}
