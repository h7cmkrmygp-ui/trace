import Foundation

// P11 — le journal (notes jour par jour) et les objectifs des suivis.

/// Les jours tels qu'on les dit : « Aujourd'hui », « Hier », « Mercredi 13 janvier », « Jeudi 31 décembre 2026 ».
public enum DayGrouping {
    public static func title(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        let day = calendar.component(.day, from: date)
        var text = "\(weekday) \(day == 1 ? "1er" : String(day)) \(month)"
        let year = calendar.component(.year, from: date)
        if year != calendar.component(.year, from: now) { text += " \(year)" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Les éléments regroupés par jour, du plus récent au plus ancien.
    public static func groups<Item>(_ items: [Item], date: (Item) -> Date, now: Date,
                                    calendar: Calendar) -> [(title: String, items: [Item])] {
        var groups: [(title: String, items: [Item])] = []
        var lastDay: Date?
        for item in items.sorted(by: { date($0) > date($1) }) {
            let day = calendar.startOfDay(for: date(item))
            if day == lastDay, !groups.isEmpty {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((title: title(for: date(item), now: now, calendar: calendar), items: [item]))
                lastDay = day
            }
        }
        return groups
    }
}

/// Un objectif dit dans une note (« mon objectif : 155 livres »).
public struct ParsedGoal: Sendable, Equatable {
    public let metric: Metric
    public let value: Double
    public let unit: String

    public init(metric: Metric, value: Double, unit: String) {
        self.metric = metric
        self.value = value
        self.unit = unit
    }
}

/// Les objectifs dits dans une note : « mon objectif : 155 livres », « objectif 10 000 pas », « objectif 8 h de
/// sommeil », « goal 150 pounds ». La valeur doit être plausible (comme pour les mesures).
public enum GoalParser {
    static let goalWord = #"(?:objectif|mon but|notre but|le but|goal|target)"#

    public static func parse(_ text: String) -> [ParsedGoal] {
        matches(in: MeasurementParser.normalized(text)).map(\.goal)
    }

    /// Les objectifs et leur place dans le texte (déjà mis en forme par `MeasurementParser.normalized`).
    static func matches(in folded: String) -> [(range: NSRange, goal: ParsedGoal)] {
        var found: [(range: NSRange, goal: ParsedGoal)] = []
        func add(_ range: NSRange, _ goal: ParsedGoal) {
            guard !found.contains(where: { $0.goal.metric == goal.metric }) else { return }
            found.append((range, goal))
        }
        let number = MeasurementParser.number
        for match in MeasurementParser.ranged(goalWord + #"\D{0,25}?"# + number
                                              + #"\s*(livres?|lbs?|pounds?|kilogrammes?|kilos?|kg)\b"#, in: folded) {
            guard let value = MeasurementParser.parseNumber(match.groups[0]) else { continue }
            let unit = match.groups[1].hasPrefix("k") ? "kg" : "lb"
            let plausible = unit == "kg" ? (35...250).contains(value) : (77...550).contains(value)
            if plausible { add(match.range, ParsedGoal(metric: .weight, value: value, unit: unit)) }
        }
        for match in MeasurementParser.ranged(goalWord + #"\D{0,25}?"# + number + #"\s*(k)?\s*(?:pas|steps)\b"#, in: folded) {
            guard var value = MeasurementParser.parseNumber(match.groups[0]) else { continue }
            if !match.groups[1].isEmpty { value *= 1_000 }
            if (100...100_000).contains(value) { add(match.range, ParsedGoal(metric: .steps, value: value.rounded(), unit: "pas")) }
        }
        for match in MeasurementParser.ranged(goalWord + #"\D{0,25}?(\d{1,2})\s*(?:heures?|hours?|h)\b\s*(?:de sommeil|of sleep|par nuit)"#,
                                              in: folded) {
            guard let value = Double(match.groups[0]) else { continue }
            if (0.5...16).contains(value) { add(match.range, ParsedGoal(metric: .sleep, value: value, unit: "h")) }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }
}

/// Où on en est d'un objectif.
public struct GoalStatus: Sendable, Equatable {
    /// Part du chemin parcouru depuis le départ (0 à 1).
    public let fraction: Double
    /// Ce qu'il reste (toujours positif).
    public let remaining: Double
    public let reached: Bool
}

public enum GoalProgress {
    /// Que l'objectif soit de descendre (le poids) ou de monter (les pas), à partir de la valeur de départ.
    public static func evaluate(start: Double, current: Double, target: Double) -> GoalStatus {
        let reached: Bool
        if target < start {
            reached = current <= target
        } else if target > start {
            reached = current >= target
        } else {
            reached = current == target
        }
        let total = target - start
        let fraction = reached ? 1 : (total == 0 ? 0 : min(1, max(0, (current - start) / total)))
        return GoalStatus(fraction: fraction, remaining: reached ? 0 : abs(target - current), reached: reached)
    }
}

/// L'objectif d'un suivi.
public struct TrackerGoal: Codable, Sendable, Hashable {
    public var metric: Metric
    public var target: Double
    public var unit: String
    public var setAt: Date
    /// La note qui l'a fixé (nil s'il a été fixé à la main).
    public var memoryID: UUID?

    public init(metric: Metric, target: Double, unit: String, setAt: Date, memoryID: UUID? = nil) {
        self.metric = metric
        self.target = target
        self.unit = unit
        self.setAt = setAt
        self.memoryID = memoryID
    }

    enum CodingKeys: String, CodingKey {
        case metric, target, unit
        case setAt = "set_at"
        case memoryID = "memory_id"
    }
}
