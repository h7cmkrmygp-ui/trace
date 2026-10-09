import Foundation

/// P20 — une fête dite dans une note : la personne (telle qu'elle est nommée) et la date.
public struct ParsedBirthday: Sendable, Equatable {
    public let person: String
    public let month: Int
    public let day: Int
    public let year: Int?

    public init(person: String, month: Int, day: Int, year: Int? = nil) {
        self.person = person
        self.month = month
        self.day = day
        self.year = year
    }
}

/// La fête d'une personne de la mémoire.
public struct Birthday: Sendable, Equatable, Identifiable {
    public let personID: UUID
    public let name: String
    public let month: Int
    public let day: Int
    public let year: Int?
    public var id: UUID { personID }

    public init(personID: UUID, name: String, month: Int, day: Int, year: Int?) {
        self.personID = personID
        self.name = name
        self.month = month
        self.day = day
        self.year = year
    }
}

public enum BirthdayParser {
    public static func parse(_ text: String) -> ParsedBirthday? { nil }

    public static func isValid(month: Int, day: Int) -> Bool { false }
}

public enum BirthdayPlanner {
    public static let identifierPrefix = "engram.birthday."

    public static func next(month: Int, day: Int, from now: Date, calendar: Calendar) -> Date? { nil }

    public static func age(turningOn date: Date, born year: Int?, calendar: Calendar) -> Int? { nil }

    public static func plan(_ birthdays: [Birthday], now: Date, calendar: Calendar, hideNames: Bool, eveHour: Int = 19,
                            dayHour: Int = 9) -> [PlannedReminder] { [] }

    public static func describe(_ birthday: Birthday, now: Date, calendar: Calendar) -> String { "" }
}
