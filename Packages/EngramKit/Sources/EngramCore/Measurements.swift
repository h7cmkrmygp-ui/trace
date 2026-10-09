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

/// Reconnaissance des mesures dans le texte d'une note, **sur l'iPhone** et sans IA. Chaque suivi exige son mot
/// (« pèse », « dormi », « tension »…) et une valeur plausible : « 2 livres de bœuf » n'est pas un poids.
public enum MeasurementParser {
    /// Un nombre : « 162,5 », « 162.5 », « 8 000 ».
    static let number = #"(\d{1,3}(?: \d{3})+|\d+(?:[.,]\d+)?)"#

    public static func parse(_ text: String) -> [ParsedMeasurement] {
        let folded = normalized(text)
        let days = daysBefore(in: folded)
        var found: [(position: Int, measurement: ParsedMeasurement)] = []
        func add(_ position: Int, _ metric: Metric, _ value: Double, second: Double? = nil, unit: String) {
            // Une seule mesure par suivi et par note : la première dite.
            guard !found.contains(where: { $0.measurement.metric == metric }) else { return }
            found.append((position, ParsedMeasurement(metric: metric, value: value, secondValue: second, unit: unit,
                                                      daysBefore: days)))
        }

        // Poids : « je pèse 162,5 livres », « poids : 74 kg », « I weigh 158 pounds ».
        for match in matches(#"(?:pese|pesee|pesais|pesait|poids|balance|weigh|weighs|weighed|weight)\D{0,25}?"#
                             + number + #"\s*(livres?|lbs?|pounds?|kilogrammes?|kilos?|kg)\b"#, in: folded) {
            guard let value = parseNumber(match.groups[0]) else { continue }
            let unit = match.groups[1].hasPrefix("k") ? "kg" : "lb"
            let plausible = unit == "kg" ? (35...250).contains(value) : (77...550).contains(value)
            if plausible { add(match.position, .weight, value, unit: unit) }
        }

        // Sommeil : « j'ai dormi 7 h 30 », « dormi 6 heures et demie », « slept 7 hours », « 8 heures de sommeil ».
        // « 7 h 30 », « 7h30 », « 7 heures et demie », « 7 hours » (le « h » peut être collé aux minutes).
        let hoursAndMinutes = #"(\d{1,2})\s*(?:heures?|hours?|hrs?|h)(?=\b|\d)(?:\s*(\d{1,2})\b|\s*(et demie?|and a half))?"#
        for match in matches(#"(?:dormi|slept|nuit de)\D{0,15}?"# + hoursAndMinutes, in: folded)
            + matches(hoursAndMinutes + #"\s*(?:de sommeil|of sleep)"#, in: folded) {
            guard let hours = Double(match.groups[0]) else { continue }
            var total = hours
            if let minutes = Double(match.groups[1]), minutes < 60 { total += minutes / 60 }
            if !match.groups[2].isEmpty { total += 0.5 }
            if (0.5...16).contains(total) { add(match.position, .sleep, total, unit: "h") }
        }

        // Tension : « tension 120 sur 80 », « pression 118/76 », « blood pressure 125 over 82 ».
        for match in matches(#"(?:tension|pression|blood pressure)\D{0,20}?(\d{2,3})\s*(?:/|sur|over)\s*(\d{2,3})"#,
                             in: folded) {
            guard let high = Double(match.groups[0]), let low = Double(match.groups[1]) else { continue }
            if (70...250).contains(high), (40...150).contains(low), high > low {
                add(match.position, .bloodPressure, high, second: low, unit: "mmHg")
            }
        }

        // Pouls : « pouls 62 », « fréquence cardiaque 71 », « 64 bpm ».
        for match in matches(#"(?:pouls|frequence cardiaque|rythme cardiaque|heart rate)\D{0,15}?(\d{2,3})"#, in: folded)
            + matches(#"(\d{2,3})\s*bpm\b"#, in: folded) {
            guard let value = Double(match.groups[0]) else { continue }
            if (30...220).contains(value) { add(match.position, .heartRate, value, unit: "bpm") }
        }

        // Pas : « 8 000 pas », « 10k pas », « 12000 steps ».
        for match in matches(number + #"\s*(k)?\s*(?:pas|steps)\b"#, in: folded) {
            guard var value = parseNumber(match.groups[0]) else { continue }
            if !match.groups[1].isEmpty { value *= 1_000 }
            if (100...100_000).contains(value) { add(match.position, .steps, value.rounded(), unit: "pas") }
        }

        // Glycémie : « glycémie 5,6 », « taux de sucre à 6,1 » (mmol/L).
        for match in matches(#"(?:glycemie|taux de sucre|blood sugar)\D{0,15}?(\d{1,2}(?:[.,]\d)?)"#, in: folded) {
            guard let value = parseNumber(match.groups[0]) else { continue }
            if (2...30).contains(value) { add(match.position, .glucose, value, unit: "mmol/L") }
        }

        return found.sorted { $0.position < $1.position }.map(\.measurement)
    }

    /// « hier » recule la mesure d'un jour, « avant-hier » de deux.
    static func daysBefore(in folded: String) -> Int {
        if !matches(#"\bavant[- ]hier\b"#, in: folded).isEmpty { return 2 }
        return matches(#"\bhier\b"#, in: folded).isEmpty ? 0 : 1
    }

    /// Minuscules, sans accents, espaces insécables remplacées.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "’", with: "'")
    }

    static func parseNumber(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
    }

    struct Match {
        let position: Int
        /// Les groupes capturés, dans l'ordre (vides s'ils n'ont rien capturé).
        let groups: [String]
    }

    static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map { result in
            let groups = (1..<max(1, result.numberOfRanges)).map { index -> String in
                let range = result.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            return Match(position: result.range.location, groups: groups)
        }
    }
}

public enum MetricUnits {
    public static let poundsPerKilogram = 2.2046226218

    public static func kilograms(fromPounds pounds: Double) -> Double { pounds / poundsPerKilogram }

    public static func pounds(fromKilograms kilograms: Double) -> Double { kilograms * poundsPerKilogram }

    /// À la québécoise : « 162,5 lb », « 7 h 30 », « 120/80 », « 62 bpm », « 8 000 pas », « 5,6 mmol/L ».
    public static func format(_ value: Double, second: Double?, metric: Metric, unit: String) -> String {
        switch metric {
        case .sleep:
            let minutes = Int((value * 60).rounded())
            let rest = minutes % 60
            return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest < 10 ? "0" : "")\(rest)"
        case .bloodPressure:
            return "\(Int(value.rounded()))/\(Int((second ?? 0).rounded()))"
        case .steps:
            return grouped(Int(value.rounded())) + " pas"
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .weight, .glucose:
            return decimal(value) + " " + unit
        }
    }

    /// Une décimale au plus, avec la virgule : « 162,5 », « 160 ».
    public static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// Milliers séparés par une espace insécable : « 8 000 ».
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var groups: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(String(digits[start..<end]), at: 0)
            end = start
        }
        return (value < 0 ? "-" : "") + groups.joined(separator: "\u{00A0}")
    }
}

public enum MetricStats {
    public static func summary(of points: [MetricPoint]) -> MetricSummary? {
        let sorted = points.sorted { $0.date < $1.date }
        guard let last = sorted.last else { return nil }
        let windowStart = last.date.addingTimeInterval(-30 * 86_400)
        let start = sorted.first { $0.date >= windowStart && $0.date < last.date }
        let values = sorted.map(\.value)
        return MetricSummary(latest: last.value, latestSecond: last.secondValue, latestDate: last.date,
                             change30: start.map { last.value - $0.value },
                             minimum: values.min() ?? last.value, maximum: values.max() ?? last.value,
                             average: values.reduce(0, +) / Double(values.count), count: values.count)
    }
}
