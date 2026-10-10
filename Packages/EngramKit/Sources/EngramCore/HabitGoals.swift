import Foundation

/// P21 — un objectif d'habitude par semaine : « mon objectif : méditer 5 fois par semaine ».
public struct ParsedHabitGoal: Sendable, Equatable {
    public let habit: Habit
    /// De 1 à 7 fois par semaine (« tous les jours » : 7).
    public let perWeek: Int

    public init(habit: Habit, perWeek: Int) {
        self.habit = habit
        self.perWeek = perWeek
    }
}

/// Reconnaît, sur l'iPhone et sans IA, un objectif d'habitude. « J'ai médité 5 fois cette semaine » (ce qui a été
/// fait) ou « mon objectif : 155 livres » (un suivi, P11) n'en sont pas.
public enum HabitGoalParser {
    /// Sur le texte sans accents, en minuscules.
    static let words: [(habit: Habit, pattern: String)] = [
        (.meditation, #"mediter|meditation|meditate"#),
        (.exercise, #"(?:aller )?au gym|faire du sport|du sport|m'entrainer|entrainement|workout|faire de l'exercice|exercise|work out|yoga"#),
        (.running, #"courir|course a pied|jogging|\brun\b"#),
        (.walking, #"marcher|faire une marche|walk"#),
        (.reading, #"\blire\b|lecture|\bread\b"#),
        (.water, #"boire (?:de l'eau|\d+ (?:litres?|verres?) d'eau)|drink water"#),
        (.vitamins, #"prendre mes vitamines|vitamines|vitamins"#),
    ]
    static let numbers: [String: Int] = ["une": 1, "un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6,
                                         "sept": 7, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "seven": 7]

    public static func parse(_ text: String) -> [ParsedHabitGoal] {
        let folded = MeasurementParser.normalized(text)
        guard let goal = try? NSRegularExpression(pattern: #"\b(?:objectif|mon but|notre but|le but|goal|target)\b"#),
              let start = goal.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let from = Range(start.range, in: folded)?.upperBound else { return [] }
        // La phrase de l'objectif seulement.
        var clause = String(folded[from...])
        if let cut = clause.firstIndex(where: { ".;!?\n".contains($0) }) { clause = String(clause[..<cut]) }
        let range = NSRange(clause.startIndex..., in: clause)
        guard let rhythm = try? NSRegularExpression(
            pattern: #"\b(\d+|une|un|deux|trois|quatre|cinq|six|sept|one|two|three|four|five|seven) (?:fois|times) (?:par|a|per) (?:semaine|week)\b|\b(tous les jours|chaque jour|every day|daily)\b"#),
              let match = rhythm.firstMatch(in: clause, range: range) else { return [] }
        let perWeek: Int
        if Range(match.range(at: 2), in: clause) != nil {
            perWeek = 7
        } else if let countRange = Range(match.range(at: 1), in: clause) {
            let raw = String(clause[countRange])
            guard let count = Int(raw) ?? numbers[raw] else { return [] }
            perWeek = count
        } else {
            return []
        }
        guard (1...7).contains(perWeek) else { return [] }
        return words.compactMap { habit, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: clause, range: range) != nil else { return nil }
            return ParsedHabitGoal(habit: habit, perWeek: perWeek)
        }
    }
}

/// « Garde ta série » : à 20 h, les habitudes d'au moins deux jours d'affilée pas encore faites aujourd'hui.
public enum HabitNudgePlanner {
    public static let identifier = "engram.habits.streak"

    public struct Item: Sendable, Equatable {
        public let habit: Habit
        public let days: [Date]

        public init(habit: Habit, days: [Date]) {
            self.habit = habit
            self.days = days
        }
    }

    /// `title` : le nom affiché d'une habitude (« Méditation ») ; nil s'il n'y a rien à rappeler ou s'il est trop tard.
    /// `hideNames` : Engram est verrouillé, rien de précis sur l'écran verrouillé.
    public static func plan(_ items: [Item], now: Date, calendar: Calendar, hour: Int = 20, hideNames: Bool = false,
                            title: (Habit) -> String) -> PlannedReminder? {
        guard let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now), moment > now else { return nil }
        let today = calendar.startOfDay(for: now)
        let waiting = items.compactMap { item -> (habit: Habit, streak: Int)? in
            guard !item.days.contains(where: { calendar.startOfDay(for: $0) == today }) else { return nil }
            let streak = HabitStats.streak(item.days, today: now, calendar: calendar)
            return streak >= 2 ? (item.habit, streak) : nil
        }
        .sorted { ($0.streak, $1.habit.rawValue) > ($1.streak, $0.habit.rawValue) }
        guard let first = waiting.first else { return nil }
        let body: String
        if hideNames {
            body = "Une habitude t'attend aujourd'hui."
        } else if waiting.count == 1 {
            body = "\(title(first.habit)) : \(first.streak) jours d'affilée. Pas encore aujourd'hui."
        } else {
            let parts = waiting.map { "\(title($0.habit)) (\($0.streak) jours)" }
            body = parts.dropLast().joined(separator: ", ") + " et " + parts[parts.count - 1] + " : pas encore aujourd'hui."
        }
        return PlannedReminder(identifier: identifier, memoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                               date: moment, title: "Garde ta série", body: body)
    }
}
