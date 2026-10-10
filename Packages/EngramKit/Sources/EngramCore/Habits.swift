import Foundation

/// P17 — une habitude qu'on dit avoir faite (« j'ai médité », « j'ai fait mon workout »).
public enum Habit: String, Codable, Sendable, CaseIterable {
    case meditation, exercise, running, walking, reading, water, vitamins
}

/// Une habitude dite dans une note, avec sa quantité si elle est dite (« 10 minutes », « 5 km »).
public struct ParsedHabit: Sendable, Equatable {
    public let habit: Habit
    public let quantity: Double?
    /// « min », « km », « pages », « L », « verres ».
    public let unit: String?
    /// « hier » : 1 ; « avant-hier » : 2.
    public let daysBefore: Int

    public init(habit: Habit, quantity: Double? = nil, unit: String? = nil, daysBefore: Int = 0) {
        self.habit = habit
        self.quantity = quantity
        self.unit = unit
        self.daysBefore = daysBefore
    }
}

/// Reconnaît, sur l'iPhone et sans IA, les habitudes faites. Un projet (« il faut que je médite »), un refus
/// (« j'ai pas médité ») ou un faux ami (« je suis allé au marché ») n'en sont pas.
public enum HabitParser {
    /// Sur le texte sans accents, en minuscules (« médité » → « medite »).
    static let patterns: [(habit: Habit, pattern: String)] = [
        (.meditation, #"\bj'ai medite\b|\bj'ai fait (?:de la |ma |une )?meditation\b|\bi meditated\b|\bi did (?:my )?meditation\b"#),
        (.exercise, #"\bj'ai fait (?:du sport|mon workout|un workout|mon entrainement|un entrainement|de l'exercice|du yoga|de la musculation|du cardio|du velo|de la natation|du crossfit|du spinning)\b|\bje suis allee?s? (?:au gym|au gymnase|a l'entrainement|au yoga|au crossfit)\b|\bje me suis entrainee?\b|\bj'ai nage\b|\bi (?:worked out|exercised|went to the gym|did yoga)\b"#),
        (.running, #"\bj'ai couru\b|\bj'ai fait (?:un |mon )?jogging\b|\bi ran\b|\bwent (?:for a run|jogging|running)\b"#),
        (.walking, #"\bj'ai marche\b|\bj'ai fait une (?:marche|promenade|randonnee)\b|\bi walked\b|\bwent for a walk\b"#),
        (.reading, #"\bj'ai lu (?:\d+ (?:pages|minutes|min|chapitres?)|un chapitre|mon livre|un livre|un peu|pendant)\b|\bj'ai fait de la lecture\b|\bi read (?:\d+ pages|a chapter|for)\b"#),
        (.water, #"\bj'ai bu (?:\d+(?:[.,]\d+)?|un|une|deux|trois|quatre|cinq|six|sept|huit) (?:litres?|l|verres?|bouteilles?) d'eau\b|\bi drank (?:\d+(?:[.,]\d+)?|two|three|four|five|six|seven|eight) (?:liters?|litres?|glasses|bottles) of water\b"#),
        (.vitamins, #"\bj'ai pris mes (?:vitamines|medicaments|pilules|supplements)\b|\bi took my (?:vitamins|meds|pills)\b"#),
    ]
    static let words: [String: Double] = ["un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6,
                                          "sept": 7, "huit": 8, "two": 2, "three": 3, "four": 4, "five": 5,
                                          "seven": 7, "eight": 8]

    public static func parse(_ text: String) -> [ParsedHabit] {
        let folded = MeasurementParser.normalized(text)
        let days = MeasurementParser.daysBefore(in: folded)
        var found: [(position: Int, habit: ParsedHabit)] = []
        for (habit, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
                  let start = Range(match.range, in: folded)?.lowerBound else { continue }
            // La quantité se cherche dans la même proposition (« j'ai médité et j'ai couru 5 km »).
            var clause = String(folded[start...])
            if let cut = clause.firstIndex(where: { ".;!?\n".contains($0) }) { clause = String(clause[..<cut]) }
            for separator in [" et ", " and ", " puis ", " pis ", ", "] {
                if let range = clause.range(of: separator) { clause = String(clause[..<range.lowerBound]) }
            }
            let amount = quantity(in: clause, for: habit)
            found.append((match.range.location, ParsedHabit(habit: habit, quantity: amount?.value, unit: amount?.unit,
                                                             daysBefore: days)))
        }
        return found.sorted { $0.position < $1.position }.map { $0.habit }
    }

    static func quantity(in clause: String, for habit: Habit) -> (value: Double, unit: String)? {
        func first(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)) else { return nil }
            return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: clause).map { String(clause[$0]) } ?? "" }
        }
        let number = #"(\d+(?:[.,]\d+)?)"#
        switch habit {
        case .water:
            guard let groups = first(#"(\d+(?:[.,]\d+)?|un|une|deux|trois|quatre|cinq|six|sept|huit|two|three|four|five|seven|eight) (litres?|liters?|l|verres?|glasses|bouteilles?|bottles)\b"#),
                  let value = MeasurementParser.parseNumber(groups[0]) ?? words[groups[0]] else { return nil }
            let unit = groups[1].hasPrefix("l") ? "L" : groups[1].hasPrefix("b") ? "bouteilles" : "verres"
            return (value, unit)
        case .running, .walking:
            if let groups = first(number + #" ?(?:km|kilometres?|kilometers?)\b"#), let value = MeasurementParser.parseNumber(groups[0]) {
                return (value, "km")
            }
        case .reading:
            if let groups = first(#"(\d+) pages\b"#), let value = Double(groups[0]) { return (value, "pages") }
        default:
            break
        }
        if let groups = first(number + #" ?(?:minutes?|min)\b"#), let value = MeasurementParser.parseNumber(groups[0]) {
            return (value, "min")
        }
        // « pendant 1 h », jamais « à 7 h » (l'heure qu'il était).
        if let groups = first(#"(?<!a )"# + number + #" ?(?:heures?|h)\b"#), let value = MeasurementParser.parseNumber(groups[0]) {
            return (value * 60, "min")
        }
        return nil
    }
}

/// Séries, semaine et grille d'une habitude, à partir des jours où elle a été faite.
public enum HabitStats {
    static func dayStarts(_ days: [Date], calendar: Calendar) -> Set<Date> { Set(days.map { calendar.startOfDay(for: $0) }) }

    /// Jours d'affilée jusqu'à aujourd'hui ; une série encore vivante si hier compte et aujourd'hui pas encore.
    public static func streak(_ days: [Date], today: Date, calendar: Calendar) -> Int {
        let done = dayStarts(days, calendar: calendar)
        var cursor = calendar.startOfDay(for: today)
        if !done.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), done.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while done.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    public static func bestStreak(_ days: [Date], calendar: Calendar) -> Int {
        let sorted = dayStarts(days, calendar: calendar).sorted()
        var best = 0
        var current = 0
        var previous: Date?
        for day in sorted {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }

    /// Jours faits cette semaine (la semaine du calendrier).
    public static func thisWeek(_ days: [Date], today: Date, calendar: Calendar) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }
        return dayStarts(days, calendar: calendar).filter { week.contains($0) && $0 < week.end }.count
    }

    /// Les `weeks` dernières semaines, une colonne par semaine (la plus ancienne d'abord), un jour par case dans l'ordre
    /// du calendrier ; nil pour les jours à venir.
    public static func grid(_ days: [Date], today: Date, weeks: Int, calendar: Calendar) -> [[Bool?]] {
        let done = dayStarts(days, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        guard weeks > 0, let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).reversed().map { back -> [Bool?] in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -back, to: currentWeek) else { return [] }
            return (0..<7).map { offset -> Bool? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
                let start = calendar.startOfDay(for: day)
                return start > todayStart ? nil : done.contains(start)
            }
        }
    }
}
