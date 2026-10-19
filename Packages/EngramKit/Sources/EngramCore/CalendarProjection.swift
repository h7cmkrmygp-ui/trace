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

    /// Les fois à venir dans [début, fin[, après l'échéance actuelle (déjà montrée parmi les échéances). Au plus 62 par
    /// tâche (une tâche de chaque jour, sur un mois).
    public static func occurrences(_ items: [Recurring], from start: Date, to end: Date, calendar: Calendar) -> [Occurrence] {
        var found: [Occurrence] = []
        for item in items {
            var cursor = max(item.due, start.addingTimeInterval(-1))
            var count = 0
            while count < 62,
                  let next = Recurrence.next(after: cursor, rule: item.rule, anchor: item.anchor, calendar: calendar),
                  next < end {
                if next >= start {
                    found.append(Occurrence(memoryID: item.memoryID, title: item.title, date: next, hasTime: item.hasTime))
                }
                cursor = next
                count += 1
            }
        }
        return found.sorted { $0.date < $1.date }
    }

    /// Les fêtes qui tombent dans [début, fin[, avec l'âge fêté si l'année est connue.
    public static func birthdays(_ birthdays: [Birthday], from start: Date, to end: Date, calendar: Calendar) -> [BirthdayDay] {
        birthdays.compactMap { birthday in
            guard let date = BirthdayPlanner.next(month: birthday.month, day: birthday.day, from: start, calendar: calendar),
                  date < end else { return nil }
            let age = BirthdayPlanner.age(turningOn: date, born: birthday.year, calendar: calendar)
            let name = BirthdayPlanner.inSentence(birthday.name)
            let first = MeasurementParser.normalized(String(name.prefix(1)))
            let feast = "aeiouyh".contains(first) && !first.isEmpty ? "Fête d'\(name)" : "Fête de \(name)"
            return BirthdayDay(personID: birthday.personID, date: date, age: age,
                               title: age.map { "\(feast) (\($0) ans)" } ?? feast)
        }
        .sorted { $0.date < $1.date }
    }
}
