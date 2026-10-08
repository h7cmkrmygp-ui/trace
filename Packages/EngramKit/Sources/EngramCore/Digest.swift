import Foundation

public struct WeekStats: Sendable, Equatable {
    public let notes: Int
    public let done: Int
    public let open: Int
    public init(notes: Int, done: Int, open: Int) {
        self.notes = notes
        self.done = done
        self.open = open
    }
}

public enum DigestPlanner {
    public static func mornings(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar, days: Int = 3,
                                hour: Int = 8) -> [PlannedReminder] { [] }
    public static func badgeCount(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar) -> Int { -1 }
    public static func weekly(_ stats: WeekStats, now: Date, calendar: Calendar) -> PlannedReminder? { nil }
}

public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let title: String
        public let time: String?
    }
    public var today: [Entry] = []
    public var lateCount = 0
    public static func make(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar) -> WidgetSnapshot { WidgetSnapshot() }
}

extension ReminderPlanner {
    public static func plan(_ items: [Item], snoozes: [UUID: Date], now: Date, calendar: Calendar,
                            limit: Int = 60) -> [PlannedReminder] { [] }
}
