import Foundation

/// Une date comprise dans le texte. `hasTime` = une heure précise a été dite.
public struct ResolvedDate: Sendable, Hashable {
    public let date: Date
    public let hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// Calcule une date réelle à partir d'une expression française ou anglaise, relativement au moment de la capture.
/// Déterministe : l'IA ne fait que relever les expressions, la date n'est jamais inventée.
/// Une expression vague (« bientôt », « la semaine prochaine ») ne donne aucune date.
public enum DateResolver {
    /// Combine le premier jour et la première heure trouvés dans les expressions (« vendredi », « 14 h »),
    /// et complète ce qui manque avec l'extrait lui-même. Une heure ne vient que d'une expression sans jour
    /// ou du même jour : jamais de l'heure d'un autre jour (celle de l'événement collée au jour du rappel).
    public static func firstDate(in expressions: [String], excerpt: String, relativeTo now: Date,
                                 calendar: Calendar) -> ResolvedDate? {
        // « dans 10 minutes », « dans 2 heures » : un moment précis à partir de maintenant, prioritaire.
        for text in expressions + [excerpt] {
            if let moment = relativeMoment(normalize(text), now: now) { return ResolvedDate(date: moment, hasTime: true) }
        }
        let today = calendar.startOfDay(for: now)
        var day: Date?
        var time: (hour: Int, minute: Int)?
        // Heures dites pour un autre jour que celui retenu : jamais reprises, même depuis l'extrait.
        var otherDayTimes: [(hour: Int, minute: Int)] = []
        for expression in expressions {
            let parts = components(of: normalize(expression), today: today, calendar: calendar)
            if day == nil { day = parts.day }
            guard let found = parts.time else { continue }
            if parts.day == nil || parts.day == day {
                if time == nil { time = found }
            } else {
                otherDayTimes.append(found)
            }
        }
        if day == nil || time == nil {
            let text = normalize(excerpt)
            let whole = components(of: text, today: today, calendar: calendar)
            // Un extrait qui nomme plusieurs jours (« dentiste mardi, rappelle-moi ça lundi à 18 h ») est lu
            // proposition par proposition : l'heure vient de la proposition du jour retenu.
            let clauses = text.split(whereSeparator: { ",;.!?\n".contains($0) })
                .map { components(of: String($0), today: today, calendar: calendar) }
            let namesSeveralDays = Set(clauses.compactMap { $0.day }).count > 1
            if day == nil { day = namesSeveralDays ? clauses.lazy.compactMap { $0.day }.first : whole.day }
            if time == nil {
                let candidates = namesSeveralDays ? clauses.filter { $0.day == day }
                                                  : [whole].filter { $0.day == nil || $0.day == day }
                time = candidates.lazy.compactMap { $0.time }.first { found in !otherDayTimes.contains { $0 == found } }
            }
        }
        return combine(day: day, time: time, now: now, calendar: calendar)
    }

    public static func resolve(_ expression: String, relativeTo now: Date, calendar: Calendar) -> ResolvedDate? {
        if let moment = relativeMoment(normalize(expression), now: now) { return ResolvedDate(date: moment, hasTime: true) }
        let today = calendar.startOfDay(for: now)
        let parts = components(of: normalize(expression), today: today, calendar: calendar)
        return combine(day: parts.day, time: parts.time, now: now, calendar: calendar)
    }

    static func components(of text: String, today: Date, calendar: Calendar) -> (day: Date?, time: (hour: Int, minute: Int)?) {
        guard !text.isEmpty else { return (nil, nil) }
        let day = explicitDayMonth(text, today: today, calendar: calendar)
            ?? numericDate(text, today: today, calendar: calendar)
            ?? dayOfMonth(text, today: today, calendar: calendar)
            ?? relativeDay(text, today: today, calendar: calendar)
            ?? inSomeDays(text, today: today, calendar: calendar)
            ?? weekday(text, today: today, calendar: calendar)
        return (day, timeOfDay(text))
    }

    /// Une heure seule (« à 9 h ») déjà passée au moment de la dictée désigne le lendemain ;
    /// un jour dit explicitement (« aujourd'hui à 9 h ») est toujours respecté.
    static func combine(day: Date?, time: (hour: Int, minute: Int)?, now: Date, calendar: Calendar) -> ResolvedDate? {
        if day == nil && time == nil { return nil }
        let today = calendar.startOfDay(for: now)
        let base = day ?? today
        guard let time else { return ResolvedDate(date: base, hasTime: false) }
        guard var date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) else { return nil }
        if day == nil, date < now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            date = tomorrow
        }
        return ResolvedDate(date: date, hasTime: true)
    }

    // MARK: - Jours

    static let months: [(name: String, number: Int)] = [
        ("janvier", 1), ("janv", 1), ("january", 1), ("jan", 1),
        ("fevrier", 2), ("fevr", 2), ("fev", 2), ("february", 2), ("feb", 2),
        ("mars", 3), ("march", 3), ("mar", 3),
        ("avril", 4), ("avr", 4), ("april", 4), ("apr", 4),
        ("mai", 5), ("may", 5),
        ("juin", 6), ("june", 6), ("jun", 6),
        ("juillet", 7), ("juil", 7), ("july", 7), ("jul", 7),
        ("aout", 8), ("august", 8), ("aug", 8),
        ("septembre", 9), ("sept", 9), ("september", 9), ("sep", 9),
        ("octobre", 10), ("october", 10), ("oct", 10),
        ("novembre", 11), ("november", 11), ("nov", 11),
        ("decembre", 12), ("december", 12), ("dec", 12),
    ]

    static let monthAlternation = months.map(\.name).sorted { $0.count > $1.count }.joined(separator: "|")

    static func monthNumber(_ name: String) -> Int? {
        months.first { $0.name == name }?.number
    }

    /// « 24 novembre », « 1er mars 2027 », « 24 nov. », « November 24 », « nov 24, 2027 ».
    static func explicitDayMonth(_ text: String, today: Date, calendar: Calendar) -> Date? {
        if let groups = match(#"\b(\d{1,2})(?:er)?\s+("# + monthAlternation + #")\.?(?:\s+(\d{4}))?\b"#, in: text),
           let day = groups[1].flatMap(Int.init), let month = groups[2].flatMap(monthNumber) {
            return makeDate(year: groups[3].flatMap(Int.init), month: month, day: day, today: today, calendar: calendar)
        }
        if let groups = match(#"\b("# + monthAlternation + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#, in: text),
           let month = groups[1].flatMap(monthNumber), let day = groups[2].flatMap(Int.init) {
            return makeDate(year: groups[3].flatMap(Int.init), month: month, day: day, today: today, calendar: calendar)
        }
        return nil
    }

    /// « le 24/11 », « avant le 24/11 », « 24/11/2027 » (jour/mois). Sans mot de contexte ni année, « 24/7 » ou
    /// « 1/2 litre » ne sont pas des dates.
    static func numericDate(_ text: String, today: Date, calendar: Calendar) -> Date? {
        let groups = match(#"\b(?:le|du|au|pour|avant|apres|on|by|before|until)\s+(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#, in: text)
            ?? match(#"\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b"#, in: text)
        guard let groups, let day = groups[1].flatMap(Int.init), let month = groups[2].flatMap(Int.init) else { return nil }
        var year = groups[3].flatMap(Int.init)
        if let short = year, short < 100 { year = 2000 + short }
        return makeDate(year: year, month: month, day: day, today: today, calendar: calendar)
    }

    /// « le 24 » : ce mois-ci si le jour n'est pas passé, sinon le mois suivant.
    static func dayOfMonth(_ text: String, today: Date, calendar: Calendar) -> Date? {
        guard let groups = match(#"\ble\s+(\d{1,2})(?:er)?\b(?!\s*(?:h\b|h\d|:|heure))"#, in: text),
              let day = groups[1].flatMap(Int.init), (1...31).contains(day) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = components.year, let month = components.month, let todayDay = components.day else { return nil }
        if day >= todayDay, let date = validDate(year: year, month: month, day: day, calendar: calendar) { return date }
        let next = month == 12 ? (year + 1, 1) : (year, month + 1)
        return validDate(year: next.0, month: next.1, day: day, calendar: calendar)
    }

    /// Aujourd'hui, demain, après-demain (et leurs équivalents anglais).
    static func relativeDay(_ text: String, today: Date, calendar: Calendar) -> Date? {
        let offset: Int
        if contains(#"\b(apres[- ]demain|day after tomorrow)\b"#, in: text) {
            offset = 2
        } else if contains(#"\b(demain|tomorrow)\b"#, in: text) {
            offset = 1
        } else if contains(#"\b(aujourd'?hui|today|ce soir|tonight|ce matin|this morning)\b"#, in: text) {
            offset = 0
        } else {
            return nil
        }
        return calendar.date(byAdding: .day, value: offset, to: today)
    }

    /// « dans 3 jours », « dans 2 semaines », « in 3 days ».
    static func inSomeDays(_ text: String, today: Date, calendar: Calendar) -> Date? {
        guard let groups = match(#"\b(?:dans|in)\s+(\d{1,3})\s+(jours?|days?|semaines?|weeks?)\b"#, in: text),
              let count = groups[1].flatMap(Int.init), let unit = groups[2] else { return nil }
        let days = unit.hasPrefix("j") || unit.hasPrefix("d") ? count : count * 7
        return calendar.date(byAdding: .day, value: days, to: today)
    }

    static let weekdays: [String: Int] = [
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]

    /// Un jour de la semaine : sa prochaine occurrence (1 à 7 jours plus tard).
    static func weekday(_ text: String, today: Date, calendar: Calendar) -> Date? {
        let alternation = weekdays.keys.sorted().joined(separator: "|")
        guard let groups = match(#"\b("# + alternation + #")\b"#, in: text),
              let name = groups[1], let target = weekdays[name] else { return nil }
        let current = calendar.component(.weekday, from: today)
        var difference = (target - current + 7) % 7
        if difference == 0 { difference = 7 }
        return calendar.date(byAdding: .day, value: difference, to: today)
    }

    // MARK: - Heures

    /// « dans 10 minutes », « dans 2 heures », « dans une heure », « in 30 minutes » : maintenant + la durée dite.
    static func relativeMoment(_ text: String, now: Date) -> Date? {
        guard let groups = match(#"\b(?:dans|in)\s+(\d{1,3}|une|un|an|a|one)\s*(minutes?|min|mn|heures?|h|hours?)\b"#, in: text),
              let unit = groups[2] else { return nil }
        let count = groups[1].flatMap(Int.init) ?? 1
        return now.addingTimeInterval(Double(count) * (unit.hasPrefix("m") ? 60 : 3_600))
    }

    static func timeOfDay(_ rawText: String) -> (hour: Int, minute: Int)? {
        // Une durée n'est pas une heure : « dans 2 heures », « pendant 3 h », « 2 heures de route ».
        if contains(#"\b(dans|pendant|durant|in|for)\s+\d{1,2}\s*(h|heures?|hours?)\b"#, in: rawText)
            || contains(#"\b\d{1,2}\s*heures?\s+de\b(?!\s*l'?apres)"#, in: rawText) {
            return nil
        }
        let isAfternoon = contains(#"(apres[- ]midi|\bsoir\b|\bsoiree\b|this evening|tonight|in the evening|in the afternoon)"#, in: rawText)
        // « après-midi » n'est pas « midi ».
        let text = rawText.replacingOccurrences(of: "apres-midi", with: " ").replacingOccurrences(of: "apres midi", with: " ")
        if contains(#"\b(midi|noon)\b"#, in: text) { return (12, 0) }
        if contains(#"\b(minuit|midnight)\b"#, in: text) { return (0, 0) }
        var hour: Int?
        var minute = 0
        var meridiem: String?
        if let groups = match(#"\b(\d{1,2}):(\d{2})\s*(am|pm)?\b"#, in: text) {
            hour = groups[1].flatMap(Int.init)
            minute = groups[2].flatMap(Int.init) ?? 0
            meridiem = groups[3]
        } else if let groups = match(#"\b(\d{1,2})\s*(am|pm)\b"#, in: text) {
            hour = groups[1].flatMap(Int.init)
            meridiem = groups[2]
        } else if let groups = match(#"\b(\d{1,2})\s*h(?:eures?)?\s*(\d{2})?\b"#, in: text) {
            hour = groups[1].flatMap(Int.init)
            minute = groups[2].flatMap(Int.init) ?? 0
        }
        guard var resolvedHour = hour else { return nil }
        if let meridiem {
            guard (1...12).contains(resolvedHour) else { return nil }
            if meridiem == "pm" && resolvedHour < 12 { resolvedHour += 12 }
            if meridiem == "am" && resolvedHour == 12 { resolvedHour = 0 }
        } else if isAfternoon && (1...11).contains(resolvedHour) {
            // « 3 h de l'après-midi », « 8 h ce soir » : heures de l'après-midi et du soir.
            resolvedHour += 12
        }
        guard (0..<24).contains(resolvedHour), (0..<60).contains(minute) else { return nil }
        return (resolvedHour, minute)
    }

    // MARK: - Outils

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }

    static func makeDate(year: Int?, month: Int, day: Int, today: Date, calendar: Calendar) -> Date? {
        if let year { return validDate(year: year, month: month, day: day, calendar: calendar) }
        let currentYear = calendar.component(.year, from: today)
        guard let candidate = validDate(year: currentYear, month: month, day: day, calendar: calendar) else { return nil }
        return candidate < today ? validDate(year: currentYear + 1, month: month, day: day, calendar: calendar) : candidate
    }

    static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    /// Groupes capturés du premier résultat (index 0 = correspondance entière).
    static func match(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? Regex(pattern), let result = try? regex.firstMatch(in: text) else { return nil }
        return (0..<result.output.count).map { index in result.output[index].substring.map(String.init) }
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        match(pattern, in: text) != nil
    }
}
