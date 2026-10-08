import Foundation

/// Un rappel à programmer sur l'iPhone (notification locale).
public struct PlannedReminder: Sendable, Equatable {
    public let identifier: String
    public let memoryID: UUID
    public let date: Date
    public let title: String
    public let body: String
}

/// Calcule les rappels des tâches et rendez-vous datés.
public enum ReminderPlanner {
    public struct Item: Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let kind: MemoryKind?
        public let status: MemoryStatus
        public let dueAt: Date?
        public let dueHasTime: Bool
        /// Note gardée sur l'iPhone (secrète) : rien de son contenu sur l'écran verrouillé.
        public let isPrivate: Bool

        public init(id: UUID, title: String, kind: MemoryKind?, status: MemoryStatus, dueAt: Date?, dueHasTime: Bool,
                    isPrivate: Bool) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.dueAt = dueAt
            self.dueHasTime = dueHasTime
            self.isPrivate = isPrivate
        }
    }

    public static func plan(_ items: [Item], now: Date, calendar: Calendar, limit: Int = 60) -> [PlannedReminder] { [] }
}
