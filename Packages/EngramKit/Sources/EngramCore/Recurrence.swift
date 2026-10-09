import Foundation

/// P16 — le rythme d'une tâche qui revient : « tous les lundis », « aux deux semaines le jeudi », « le 1er de chaque
/// mois », « chaque jour à 8 h ».
public struct RecurrenceRule: Codable, Sendable, Equatable, Hashable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    /// 1 = chaque fois, 2 = une fois sur deux (« aux deux semaines »).
    public var interval: Int
    /// Jours de la semaine (1 = dimanche … 7 = samedi, comme `Calendar`) ; vide = le jour de la première fois.
    public var weekdays: [Int]
    /// Jour du mois ; nil = le jour de la première fois.
    public var dayOfMonth: Int?
    /// Heure dite ; nil = l'heure de la première fois (ou la journée, sans heure).
    public var hour: Int?
    public var minute: Int?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], dayOfMonth: Int? = nil, hour: Int? = nil,
                minute: Int? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.hour = hour
        self.minute = minute
    }

    enum CodingKeys: String, CodingKey {
        case frequency, interval, weekdays, hour, minute
        case dayOfMonth = "day_of_month"
    }
}

/// Reconnaît, sur l'iPhone et sans IA, un rythme dans une phrase.
public enum RecurrenceParser {
    public static func parse(_ text: String) -> RecurrenceRule? { nil }
}

public enum Recurrence {
    /// La prochaine fois, strictement après `date`. `anchor` : la première fois (pour « aux deux semaines » et l'heure).
    public static func next(after date: Date, rule: RecurrenceRule, anchor: Date, calendar: Calendar) -> Date? { nil }

    /// « Tous les lundis », « Aux deux semaines, le jeudi », « Le 1er de chaque mois », « Chaque jour à 8 h ».
    public static func describe(_ rule: RecurrenceRule) -> String { "" }
}
