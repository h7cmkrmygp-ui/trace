import Foundation

/// P22 — ce que le Calendrier montre en plus des échéances : les prochaines fois des tâches qui reviennent, et les fêtes.
public enum CalendarProjection {
    /// Une tâche qui revient, avec sa prochaine échéance.
    public struct Recurring: Sendable, Equatable {
        public let memoryID: UUID
        public let title: String
        public let rule: RecurrenceRule
        public let anchor: Date
        public let due: Date
        public let hasTime: Bool

        public init(memoryID: UUID, title: String, rule: RecurrenceRule, anchor: Date, due: Date, hasTime: Bool) {
            self.memoryID = memoryID
            self.title = title
            self.rule = rule
            self.anchor = anchor
            self.due = due
            self.hasTime = hasTime
        }
    }

    /// Une fois à venir d'une tâche qui revient.
    public struct Occurrence: Sendable, Equatable, Identifiable {
        public let memoryID: UUID
        public let title: String
        public let date: Date
        public let hasTime: Bool
        public var id: String { memoryID.uuidString + "\(date.timeIntervalSince1970)" }
    }

    /// Une fête dans le mois.
    public struct BirthdayDay: Sendable, Equatable, Identifiable {
        public let personID: UUID
        public let date: Date
        public let age: Int?
        /// « Fête de Julie (35 ans) ».
        public let title: String
        public var id: UUID { personID }
    }

    public static func occurrences(_ items: [Recurring], from start: Date, to end: Date, calendar: Calendar) -> [Occurrence] {
        []
    }

    public static func birthdays(_ birthdays: [Birthday], from start: Date, to end: Date, calendar: Calendar) -> [BirthdayDay] {
        []
    }
}
