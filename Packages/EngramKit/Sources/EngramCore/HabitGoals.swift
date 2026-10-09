import Foundation

/// P21 — un objectif d'habitude par semaine : « mon objectif : méditer 5 fois par semaine ».
public struct ParsedHabitGoal: Sendable, Equatable {
    public let habit: Habit
    /// De 1 à 7 fois par semaine (« tous les jours » : 7).
    public let perWeek: Int

    public init(habit: Habit, perWeek: Int) {
        self.habit = habit
        self.perWeek = perWeek
    }
}

public enum HabitGoalParser {
    public static func parse(_ text: String) -> [ParsedHabitGoal] { [] }
}

public enum HabitNudgePlanner {
    public static let identifier = "engram.habits.streak"

    public struct Item: Sendable, Equatable {
        public let habit: Habit
        public let days: [Date]

        public init(habit: Habit, days: [Date]) {
            self.habit = habit
            self.days = days
        }
    }

    public static func plan(_ items: [Item], now: Date, calendar: Calendar, hour: Int = 20,
                            title: (Habit) -> String) -> PlannedReminder? { nil }
}
