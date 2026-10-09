import Foundation

// P11 — le journal (notes jour par jour) et les objectifs des suivis.

/// Les jours tels qu'on les dit : « Aujourd'hui », « Hier », « Mercredi 13 janvier », « Jeudi 31 décembre 2026 ».
public enum DayGrouping {
    public static func title(for date: Date, now: Date, calendar: Calendar) -> String {
        ""
    }

    /// Les éléments regroupés par jour, du plus récent au plus ancien.
    public static func groups<Item>(_ items: [Item], date: (Item) -> Date, now: Date,
                                    calendar: Calendar) -> [(title: String, items: [Item])] {
        []
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

public enum GoalParser {
    public static func parse(_ text: String) -> [ParsedGoal] {
        []
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
    public static func evaluate(start: Double, current: Double, target: Double) -> GoalStatus {
        GoalStatus(fraction: 0, remaining: 0, reached: false)
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
