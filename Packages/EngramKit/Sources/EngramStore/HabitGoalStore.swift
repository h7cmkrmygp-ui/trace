import EngramCore
import Foundation
import GRDB

/// L'objectif d'une habitude par semaine (table `habit_goal`).
public struct HabitGoal: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "habit_goal" }
    public var habit: Habit
    public var perWeek: Int
    public var setAt: Date
    /// La note où il a été dit (nil s'il a été fixé à la main).
    public var memoryID: UUID?

    enum CodingKeys: String, CodingKey {
        case habit
        case perWeek = "per_week"
        case setAt = "set_at"
        case memoryID = "memory_id"
    }
}

/// P21 — les objectifs des habitudes.
extension MeasurementStore {
    public func habitGoals() throws -> [Habit: Int] { [:] }

    public func setHabitGoal(_ habit: Habit, perWeek: Int) throws {}

    public func removeHabitGoal(_ habit: Habit) throws {}
}
