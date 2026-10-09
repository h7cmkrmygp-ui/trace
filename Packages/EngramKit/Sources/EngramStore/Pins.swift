import EngramCore
import Foundation
import GRDB

/// P11 — les notes épinglées en haut des Notes.
extension MemoryStore {
    public func setPinned(_ pinned: Bool, for memoryID: UUID) throws {}

    public func isPinned(_ memoryID: UUID) throws -> Bool { false }

    public func pinnedMemories() throws -> [Memory] { [] }
}

/// P11 — les objectifs des suivis.
extension MeasurementStore {
    public func goal(metric: Metric) throws -> TrackerGoal? { nil }

    public func setGoal(metric: Metric, target: Double, unit: String) throws {}

    public func removeGoal(metric: Metric) throws {}
}
