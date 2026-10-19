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

/// Reconnaît, sur l'iPhone et sans IA, un rythme dans une phrase. « Le lundi de Pâques », « chaque fois que »,
/// « tous les deux » ou « deux fois par semaine » (quels jours ?) n'en sont pas.
public enum RecurrenceParser {
    static let weekdayNames: [(name: String, weekday: Int)] = [
        ("dimanche", 1), ("lundi", 2), ("mardi", 3), ("mercredi", 4), ("jeudi", 5), ("vendredi", 6), ("samedi", 7),
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]
    static let numbers: [String: Int] = ["deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "two": 2, "three": 3,
                                         "four": 4]
    static var dayAlternation: String { weekdayNames.map { $0.name }.joined(separator: "|") }

    public static func parse(_ text: String) -> RecurrenceRule? {
        // Sans accents, en minuscules : « année » → « annee », « à » → « a ».
        let t = " " + text.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ") + " "
        // « deux fois par semaine » : on ne sait pas quels jours.
        if has(t, "\\b(?:deux|trois|quatre|cinq|\\d+) fois par\\b") { return nil }
        let (hour, minute) = time(in: t)
        func rule(_ frequency: RecurrenceRule.Frequency, interval: Int = 1, weekdays: [Int] = [], dayOfMonth: Int? = nil,
                  defaultHour: Int? = nil) -> RecurrenceRule {
            let chosen = hour ?? defaultHour
            return RecurrenceRule(frequency: frequency, interval: interval, weekdays: weekdays, dayOfMonth: dayOfMonth,
                                  hour: chosen, minute: chosen == nil ? nil : (hour == nil ? 0 : minute))
        }
        let mentioned = weekdays(in: t)

        // « tous les 3 mois », « toutes les 2 semaines », « tous les 2 jours ».
        if let groups = capture(t, "\\b(?:tous|toutes) les (\\d+|deux|trois|quatre|cinq|six) (jours|semaines|mois|ans|annees)\\b"),
           let count = Int(groups[0]) ?? numbers[groups[0]] {
            switch groups[1] {
            case "jours": return rule(.daily, interval: count)
            case "semaines": return rule(.weekly, interval: count, weekdays: mentioned)
            case "mois": return rule(.monthly, interval: count)
            default: return rule(.yearly, interval: count)
            }
        }
        // « aux deux semaines » (comme au Québec), « une semaine sur deux », « every other week ».
        if has(t, "\\b(?:aux (?:deux|2) semaines|une semaine sur deux|every other week|every (?:two|2) weeks|biweekly)\\b") {
            return rule(.weekly, interval: 2, weekdays: mentioned)
        }
        if has(t, "\\b(?:en semaine|les jours de semaine|du lundi au vendredi|every weekday|on weekdays)\\b") {
            return rule(.weekly, weekdays: [2, 3, 4, 5, 6])
        }
        if has(t, "\\b(?:les|chaque|toutes les) fins? de semaine\\b|\\bevery weekend\\b|\\bon weekends\\b") {
            return rule(.weekly, weekdays: [7, 1])
        }
        if has(t, "\\b(?:chaque|tous les) matins?\\b|\\bevery morning\\b") { return rule(.daily, defaultHour: 8) }
        if has(t, "\\b(?:chaque|tous les) soirs?\\b|\\bevery (?:evening|night)\\b") { return rule(.daily, defaultHour: 19) }
        if has(t, "\\b(?:tous les jours|chaque jour|every day|everyday|daily|quotidiennement|une fois par jour)\\b") {
            return rule(.daily)
        }
        // « tous les lundis », « les mardis et jeudis », « chaque vendredi », « every Friday ».
        if has(t, "\\b(?:\(dayAlternation))s\\b") || has(t, "\\b(?:chaque|every|each) (?:\(dayAlternation))\\b") {
            return rule(.weekly, weekdays: mentioned)
        }
        if has(t, "\\b(?:toutes les semaines|chaque semaine|every week|weekly|une fois par semaine|hebdomadaire(?:ment)?)\\b") {
            return rule(.weekly, weekdays: mentioned)
        }
        // « le 1er de chaque mois », « le 15 du mois », « the 1st of every month ».
        if let groups = capture(t, "\\ble (1er|premier|\\d{1,2}) (?:de chaque mois|de tous les mois|du mois(?! prochain| dernier))"),
           let day = groups[0] == "1er" || groups[0] == "premier" ? 1 : Int(groups[0]), (1...31).contains(day) {
            return rule(.monthly, dayOfMonth: day)
        }
        if let groups = capture(t, "\\bthe (\\d{1,2})(?:st|nd|rd|th)? of (?:every|each) month\\b"), let day = Int(groups[0]),
           (1...31).contains(day) {
            return rule(.monthly, dayOfMonth: day)
        }
        if has(t, "\\b(?:tous les mois|chaque mois|every month|monthly|mensuellement|une fois par mois)\\b") {
            return rule(.monthly)
        }
        if has(t, "\\b(?:chaque annee|tous les ans|toutes les annees|every year|yearly|annually|annuellement|une fois par an(?:nee)?)\\b") {
            return rule(.yearly)
        }
        return nil
    }

    /// Les jours nommés (« lundi », « mardis », « Friday »), du lundi au dimanche.
    static func weekdays(in t: String) -> [Int] {
        var found: [Int] = []
        for (name, weekday) in weekdayNames where has(t, "\\b\(name)s?\\b") && !found.contains(weekday) {
            found.append(weekday)
        }
        return found.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
    }

    /// « à 18 h », « à 18 h 30 », « 18:30 », « at 7 pm ».
    static func time(in t: String) -> (hour: Int?, minute: Int?) {
        if let groups = capture(t, "\\ba (\\d{1,2}) ?h ?(\\d{2})?\\b") ?? capture(t, "\\b(\\d{1,2}):(\\d{2})\\b"),
           let hour = Int(groups[0]), (0...23).contains(hour) {
            return (hour, Int(groups[1]) ?? 0)
        }
        if let groups = capture(t, "\\bat (\\d{1,2})(?::(\\d{2}))? ?(am|pm)\\b"), var hour = Int(groups[0]), (1...12).contains(hour) {
            if groups[2] == "pm" && hour < 12 { hour += 12 }
            if groups[2] == "am" && hour == 12 { hour = 0 }
            return (hour, Int(groups[1]) ?? 0)
        }
        return (nil, nil)
    }

    static func has(_ text: String, _ pattern: String) -> Bool { capture(text, pattern) != nil }

    /// Les groupes du premier passage trouvé (vides s'ils n'ont rien pris) ; nil s'il n'y en a pas.
    static func capture(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<max(match.numberOfRanges, 1)).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

public enum Recurrence {
    /// La prochaine fois, strictement après `date`. `anchor` : la première fois (pour « aux deux semaines » et l'heure).
    public static func next(after date: Date, rule: RecurrenceRule, anchor: Date, calendar: Calendar) -> Date? {
        let anchorTime = calendar.dateComponents([.hour, .minute], from: anchor)
        let hour = rule.hour ?? anchorTime.hour ?? 0
        let minute = rule.hour != nil ? (rule.minute ?? 0) : (anchorTime.minute ?? 0)
        let interval = max(1, rule.interval)
        let anchorDay = calendar.startOfDay(for: anchor)
        let startDay = calendar.startOfDay(for: date)
        func at(_ day: Date) -> Date? { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) }
        func fits(_ steps: Int) -> Bool { abs(steps) % interval == 0 }
        func days(from: Date, to: Date) -> Int { calendar.dateComponents([.day], from: from, to: to).day ?? 0 }

        switch rule.frequency {
        case .daily:
            for offset in 0...(interval * 2 + 2) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                      fits(days(from: anchorDay, to: day)), let candidate = at(day), candidate > date else { continue }
                return candidate
            }
        case .weekly:
            let wanted = rule.weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : rule.weekdays
            func weekStart(_ day: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day }
            let anchorWeek = weekStart(anchorDay)
            for offset in 0...(7 * interval + 7) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                      wanted.contains(calendar.component(.weekday, from: day)),
                      fits(days(from: anchorWeek, to: weekStart(day)) / 7),
                      let candidate = at(day), candidate > date else { continue }
                return candidate
            }
        case .monthly, .yearly:
            let monthly = rule.frequency == .monthly
            let wantedDay = rule.dayOfMonth ?? calendar.component(.day, from: anchor)
            let anchorParts = calendar.dateComponents([.year, .month], from: anchor)
            guard let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else { return nil }
            for offset in 0...(monthly ? interval * 2 + 2 : 12 * (interval * 2 + 2)) {
                guard let monthStart = calendar.date(byAdding: .month, value: offset, to: firstMonth) else { continue }
                let parts = calendar.dateComponents([.year, .month], from: monthStart)
                let months = ((parts.year ?? 0) - (anchorParts.year ?? 0)) * 12 + (parts.month ?? 0) - (anchorParts.month ?? 0)
                if monthly {
                    guard fits(months) else { continue }
                } else {
                    guard parts.month == anchorParts.month, fits(months / 12) else { continue }
                }
                let length = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
                guard let day = calendar.date(byAdding: .day, value: min(wantedDay, length) - 1, to: monthStart),
                      let candidate = at(day), candidate > date else { continue }
                return candidate
            }
        }
        return nil
    }

    static let singular = [1: "dimanche", 2: "lundi", 3: "mardi", 4: "mercredi", 5: "jeudi", 6: "vendredi", 7: "samedi"]

    /// « lundi » pour 2 (comme `Calendar` : 1 = dimanche).
    public static func dayName(_ weekday: Int) -> String { singular[weekday] ?? "" }

    /// « Tous les lundis », « Aux deux semaines, le jeudi », « Le 1er de chaque mois », « Chaque jour à 8 h ».
    public static func describe(_ rule: RecurrenceRule) -> String {
        let interval = max(1, rule.interval)
        var text: String
        switch rule.frequency {
        case .daily:
            text = interval == 1 ? "Chaque jour" : "Tous les \(interval) jours"
        case .weekly:
            let days = rule.weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
            let names = days.compactMap { singular[$0] }
            if interval > 1 {
                text = interval == 2 ? "Aux deux semaines" : "Toutes les \(interval) semaines"
                if !names.isEmpty { text += ", le " + joined(names) }
            } else if Set(days) == [2, 3, 4, 5, 6] {
                text = "En semaine"
            } else if Set(days) == [7, 1] {
                text = "Les fins de semaine"
            } else if names.count == 1 {
                text = "Tous les \(names[0])s"
            } else if names.count > 1 {
                text = "Les " + joined(names.map { $0 + "s" })
            } else {
                text = "Chaque semaine"
            }
        case .monthly:
            if let day = rule.dayOfMonth {
                let ordinal = day == 1 ? "1er" : "\(day)"
                text = interval == 1 ? "Le \(ordinal) de chaque mois" : "Le \(ordinal), tous les \(interval) mois"
            } else {
                text = interval == 1 ? "Chaque mois" : "Tous les \(interval) mois"
            }
        case .yearly:
            text = interval == 1 ? "Chaque année" : "Tous les \(interval) ans"
        }
        if let hour = rule.hour {
            let minute = rule.minute ?? 0
            text += minute == 0 ? " à \(hour) h" : String(format: " à %d h %02d", hour, minute)
        }
        return text
    }

    /// « lundi », « lundi et jeudi », « lundi, mercredi et vendredi ».
    static func joined(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " et " + names[names.count - 1]
    }
}
