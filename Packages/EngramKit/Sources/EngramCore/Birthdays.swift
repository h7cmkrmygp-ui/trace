import Foundation

/// P20 — une fête dite dans une note : la personne (telle qu'elle est nommée) et la date.
public struct ParsedBirthday: Sendable, Equatable {
    public let person: String
    public let month: Int
    public let day: Int
    public let year: Int?
    /// « Inès fête ses 30 ans le 13 octobre » : l'âge fêté (P31).
    public let turning: Int?

    public init(person: String, month: Int, day: Int, year: Int? = nil, turning: Int? = nil) {
        self.person = person
        self.month = month
        self.day = day
        self.year = year
        self.turning = turning
    }

    /// L'année de naissance : dite, ou déduite de l'âge fêté à la prochaine fête suivant le jour de la note.
    public func birthYear(saidOn date: Date, calendar: Calendar) -> Int? {
        if let year { return year }
        guard let turning, let next = BirthdayPlanner.next(month: month, day: day, from: date, calendar: calendar) else {
            return nil
        }
        return calendar.component(.year, from: next) - turning
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

/// Reconnaît, sur l'iPhone et sans IA : « l'anniversaire de Julie est le 12 mars », « Marc a sa fête le 3 juin »,
/// « la fête de Léa, c'est le 1er août », « Sophie est née le 24 décembre 1990 », « Julie's birthday is March 12 ».
/// P31 : aussi « la fête à Inès, c'est le treize octobre », « C'est la fête de Marc le premier mars »,
/// « Inès fête ses 30 ans le 13 octobre ». « La fête de Noël », « l'anniversaire de mariage » n'en sont pas.
public enum BirthdayParser {
    static let months: [String: Int] = [
        "janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7, "aout": 8, "septembre": 9,
        "octobre": 10, "novembre": 11, "decembre": 12, "january": 1, "february": 2, "march": 3, "april": 4, "may": 5,
        "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
    ]
    /// Ces fêtes ne sont pas des personnes.
    static let holidays: Set<String> = ["noel", "paques", "saint-jean", "saint-valentin", "halloween", "mardi gras",
                                        "la reine", "dollard", "travail", "action de grace", "christmas", "easter"]
    static let longest = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    /// Les jours dits en lettres (« le treize octobre », « le vingt-deux mai »).
    static let dayWords: [String: Int] = {
        let units = ["deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf"]
        var words: [String: Int] = ["premier": 1, "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14,
                                    "quinze": 15, "seize": 16, "dix sept": 17, "dix huit": 18, "dix neuf": 19, "vingt": 20,
                                    "vingt et un": 21, "trente": 30, "trente et un": 31]
        for (index, unit) in units.enumerated() {
            words[unit] = index + 2
            words["vingt " + unit] = index + 22
        }
        return words
    }()

    static let name = #"(?<name>(?i:mon|ma|mes|notre)\s+\p{Ll}[\p{L}'’-]*|\p{Lu}[\p{L}'’-]*(?:\s+\p{Lu}[\p{L}'’-]*)?)"#
    static let day = #"(?<day>1er|\d{1,2}|(?i:premier|trente(?:[\s-]et[\s-]un)?|vingt(?:[\s-](?:et[\s-]un|deux|trois|quatre|cinq|six|sept|huit|neuf))?|dix(?:[\s-](?:sept|huit|neuf))?|onze|douze|treize|quatorze|quinze|seize|deux|trois|quatre|cinq|six|sept|huit|neuf))"#
    static let frenchDate = #"(?i:le)\s+"# + day + #"\s+(?<month>(?i:janvier|f[ée]vrier|mars|avril|mai|juin|juillet|ao[uû]t|septembre|octobre|novembre|d[ée]cembre))(?:\s+(?<year>\d{4}))?"#
    static let patterns: [String] = [
        // « l'anniversaire de Julie est le 12 mars », « la fête à Inès, c'est le 13 octobre », « la fête de Marc le 1er mars ».
        #"(?i:l['’]anniversaire|la f[êe]te)\s+(?i:de\s+|d['’]|[àa]\s+)"# + name
            + #"\s*,?\s+(?:(?i:est|c['’]est|tombe|sera)\s+)?"# + frenchDate,
        name + #"\s+(?i:a sa f[êe]te|aura sa f[êe]te|f[êe]te son anniversaire)\s+"# + frenchDate,
        // « Inès fête ses 30 ans le 13 octobre », « Marc aura 40 ans le 3 juin ».
        name + #"\s+(?i:f[êe]te\s+ses|f[êe]tera\s+ses|aura|va\s+avoir|a)\s+(?<turning>\d{1,3})\s+(?i:ans)\s+"# + frenchDate,
        name + #"\s+(?i:est n[ée]e?)\s+"# + frenchDate,
        name + #"(?i:['’]s birthday is)\s+(?i:on\s+)?(?<month>(?i:january|february|march|april|may|june|july|august|september|october|november|december))\s+(?<day>\d{1,2})(?i:st|nd|rd|th)?(?:,?\s+(?<year>\d{4}))?"#,
    ]

    public static func parse(_ text: String) -> ParsedBirthday? {
        let cleaned = text.replacingOccurrences(of: "’", with: "'")
        let whole = NSRange(cleaned.startIndex..., in: cleaned)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: cleaned, range: whole) {
                func group(_ name: String) -> String? {
                    Range(match.range(withName: name), in: cleaned).map { String(cleaned[$0]) }
                }
                guard let person = group("name"), let dayText = group("day"), let monthText = group("month") else { continue }
                let key = MeasurementParser.normalized(person)
                guard EntityName.isAcceptable(person), !holidays.contains(key),
                      let month = months[MeasurementParser.normalized(monthText)],
                      let day = dayNumber(dayText), isValid(month: month, day: day) else { continue }
                let turning = pattern.contains("?<turning>") ? group("turning").flatMap { Int($0) } : nil
                return ParsedBirthday(person: person, month: month, day: day, year: group("year").flatMap { Int($0) },
                                      turning: turning.flatMap { (1...130).contains($0) ? $0 : nil })
            }
        }
        return nil
    }

    /// P33 — la phrase dit seulement une fête (« Retiens l'anniversaire de Inès c'est le 13 octobre ») : rien d'autre à
    /// faire. « Acheter un cadeau pour la fête de Julie le 12 mars » est une tâche.
    public static func isOnlyABirthday(_ text: String) -> Bool {
        false
    }

    /// « 13 », « 1er », « treize », « vingt-deux ».
    static func dayNumber(_ text: String) -> Int? {
        let key = MeasurementParser.normalized(text).replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").joined(separator: " ")
        if key == "1er" { return 1 }
        return Int(key) ?? dayWords[key]
    }

    /// Le 31 février n'existe pas ; le 29 février, oui.
    public static func isValid(month: Int, day: Int) -> Bool {
        (1...12).contains(month) && day >= 1 && day <= longest[month - 1]
    }
}

public enum BirthdayPlanner {
    public static let identifierPrefix = "engram.birthday."

    /// La prochaine fête (le jour même compte), à minuit. Né un 29 février : le 28 les autres années.
    public static func next(month: Int, day: Int, from now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for candidate in [year, year + 1, year + 2] {
            guard let first = calendar.date(from: DateComponents(year: candidate, month: month, day: 1)),
                  let length = calendar.range(of: .day, in: .month, for: first)?.count,
                  let date = calendar.date(from: DateComponents(year: candidate, month: month, day: min(day, length))),
                  date >= today else { continue }
            return date
        }
        return nil
    }

    /// L'âge fêté ce jour-là ; nil sans année de naissance.
    public static func age(turningOn date: Date, born year: Int?, calendar: Calendar) -> Int? {
        guard let year else { return nil }
        let age = calendar.component(.year, from: date) - year
        return age > 0 ? age : nil
    }

    /// « Julie », « ma mère » (au milieu d'une phrase).
    static func inSentence(_ name: String) -> String {
        let words = name.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = words.first, ["mon", "ma", "mes", "notre"].contains(first.lowercased()) else { return name }
        return ([first.lowercased()] + words.dropFirst()).joined(separator: " ")
    }

    /// « la fête de Julie », « la fête d'Ahmed », « la fête de ma mère ».
    static func feast(_ name: String) -> String {
        let shown = inSentence(name)
        let first = MeasurementParser.normalized(String(shown.prefix(1)))
        return "aeiouyh".contains(first) && !first.isEmpty ? "la fête d'\(shown)" : "la fête de \(shown)"
    }

    /// La veille à 19 h et le jour même à 9 h, pour chaque fête à venir. `hideNames` : Engram est verrouillé.
    public static func plan(_ birthdays: [Birthday], now: Date, calendar: Calendar, hideNames: Bool, eveHour: Int = 19,
                            dayHour: Int = 9) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        for birthday in birthdays {
            guard let day = next(month: birthday.month, day: birthday.day, from: now, calendar: calendar) else { continue }
            let age = age(turningOn: day, born: birthday.year, calendar: calendar)
            let name = inSentence(birthday.name)
            let id = identifierPrefix + birthday.personID.uuidString
            if let eveDay = calendar.date(byAdding: .day, value: -1, to: day),
               let eve = calendar.date(bySettingHour: eveHour, minute: 0, second: 0, of: eveDay), eve > now {
                planned.append(PlannedReminder(
                    identifier: id + ".veille", memoryID: birthday.personID, date: eve,
                    title: hideNames ? "Demain : une fête" : "Demain : \(feast(birthday.name))",
                    body: hideNames ? "Ouvre Engram pour la voir."
                        : age.map { "\(name.prefix(1).uppercased() + name.dropFirst()) aura \($0) ans." } ?? "Pense à souhaiter bonne fête."))
            }
            if let moment = calendar.date(bySettingHour: dayHour, minute: 0, second: 0, of: day), moment > now {
                planned.append(PlannedReminder(
                    identifier: id + ".jour", memoryID: birthday.personID, date: moment,
                    title: hideNames ? "Aujourd'hui : une fête" : "Aujourd'hui : \(feast(birthday.name))",
                    body: hideNames ? "Ouvre Engram pour la voir."
                        : age.map { "\(name.prefix(1).uppercased() + name.dropFirst()) a \($0) ans aujourd'hui." } ?? "C'est le jour de souhaiter bonne fête."))
            }
        }
        return planned.sorted { $0.date < $1.date }
    }

    /// « 12 mars · dans 5 jours · 35 ans », « 3 juin · demain ».
    public static func describe(_ birthday: Birthday, now: Date, calendar: Calendar) -> String {
        let dayText = birthday.day == 1 ? "1er" : "\(birthday.day)"
        var parts = ["\(dayText) \(WeeklyReviewText.months[birthday.month - 1])"]
        if let day = next(month: birthday.month, day: birthday.day, from: now, calendar: calendar) {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
            parts.append(days == 0 ? "aujourd'hui" : days == 1 ? "demain" : "dans \(days) jours")
            if let age = age(turningOn: day, born: birthday.year, calendar: calendar) { parts.append("\(age) ans") }
        }
        return parts.joined(separator: " · ")
    }
}
