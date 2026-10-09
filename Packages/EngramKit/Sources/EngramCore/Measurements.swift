import Foundation

// P10 — les suivis : mesures dites dans les notes (poids, sommeil, tension, pouls, pas, glycémie).

public enum Metric: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case weight, sleep
    case bloodPressure = "blood_pressure"
    case heartRate = "heart_rate"
    case steps, glucose

    public var id: String { rawValue }
}

/// Une mesure reconnue dans un texte.
public struct ParsedMeasurement: Sendable, Equatable {
    public let metric: Metric
    public let value: Double
    /// Pour la tension : la valeur basse (diastolique).
    public let secondValue: Double?
    public let unit: String
    /// Jours à retirer à la date de la note (« hier » : 1, « avant-hier » : 2).
    public let daysBefore: Int

    public init(metric: Metric, value: Double, secondValue: Double? = nil, unit: String, daysBefore: Int = 0) {
        self.metric = metric
        self.value = value
        self.secondValue = secondValue
        self.unit = unit
        self.daysBefore = daysBefore
    }
}

/// Une mesure enregistrée, rattachée à sa note.
public struct MetricMeasurement: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var memoryID: UUID
    public var metric: Metric
    public var value: Double
    public var secondValue: Double?
    public var unit: String
    public var measuredAt: Date
    public var createdAt: Date

    public init(id: UUID = UUID(), memoryID: UUID, metric: Metric, value: Double, secondValue: Double?, unit: String,
                measuredAt: Date, now: Date) {
        self.id = id
        self.memoryID = memoryID
        self.metric = metric
        self.value = value
        self.secondValue = secondValue
        self.unit = unit
        self.measuredAt = measuredAt
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, metric, value, unit
        case memoryID = "memory_id"
        case secondValue = "second_value"
        case measuredAt = "measured_at"
        case createdAt = "created_at"
    }
}

/// Un point d'un graphique.
public struct MetricPoint: Sendable, Equatable {
    public let date: Date
    public let value: Double
    public let secondValue: Double?

    public init(date: Date, value: Double, secondValue: Double? = nil) {
        self.date = date
        self.value = value
        self.secondValue = secondValue
    }
}

/// Le résumé d'un suivi : dernière valeur, évolution sur 30 jours, minimum, maximum, moyenne.
public struct MetricSummary: Sendable, Equatable {
    public let latest: Double
    public let latestSecond: Double?
    public let latestDate: Date
    /// Écart entre la dernière valeur et la première des 30 jours qui la précèdent ; nil s'il n'y en a pas d'autre.
    public let change30: Double?
    public let minimum: Double
    public let maximum: Double
    public let average: Double
    public let count: Int
}

public enum MeasurementParser {
    public static func parse(_ text: String) -> [ParsedMeasurement] {
        []
    }
}

public enum MetricUnits {
    public static let poundsPerKilogram = 2.2046226218

    public static func kilograms(fromPounds pounds: Double) -> Double { pounds / poundsPerKilogram }

    public static func pounds(fromKilograms kilograms: Double) -> Double { kilograms * poundsPerKilogram }

    public static func format(_ value: Double, second: Double?, metric: Metric, unit: String) -> String {
        ""
    }
}

public enum MetricStats {
    public static func summary(of points: [MetricPoint]) -> MetricSummary? {
        nil
    }
}
