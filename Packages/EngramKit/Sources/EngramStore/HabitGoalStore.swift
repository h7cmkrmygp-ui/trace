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

/// P21 — les objectifs des habitudes : dits dans une note ou fixés à la main ; le plus récent l'emporte.
extension MeasurementStore {
    public func habitGoals() throws -> [Habit: Int] {
        try database.writer.read { db in try Self.habitGoals(db) }
    }

    public func habitGoalsStream() -> AsyncThrowingStream<[Habit: Int], any Error> {
        database.stream { db in try Self.habitGoals(db) }
    }

    static func habitGoals(_ db: Database) throws -> [Habit: Int] {
        Dictionary(uniqueKeysWithValues: try HabitGoal.fetchAll(db).map { ($0.habit, $0.perWeek) })
    }

    public func setHabitGoal(_ habit: Habit, perWeek: Int) throws {
        guard (1...7).contains(perWeek) else { throw StoreError.invalidOperation("De 1 à 7 fois par semaine.") }
        let now = dates.now()
        try database.writer.write { db in
            try HabitGoal(habit: habit, perWeek: perWeek, setAt: now, memoryID: nil).save(db)
        }
    }

    public func removeHabitGoal(_ habit: Habit) throws {
        try database.writer.write { db in _ = try HabitGoal.deleteOne(db, key: habit.rawValue) }
    }

    /// Les objectifs dits dans une note ; un objectif plus récent (dit ou fixé à la main) n'est pas remplacé.
    func recordHabitGoals(_ db: Database, memoryID: UUID, text: String, capturedAt: Date) throws {
        for goal in HabitGoalParser.parse(text) {
            if let existing = try HabitGoal.fetchOne(db, key: goal.habit.rawValue), existing.setAt > capturedAt { continue }
            try HabitGoal(habit: goal.habit, perWeek: goal.perWeek, setAt: capturedAt, memoryID: memoryID).save(db)
        }
    }
}
