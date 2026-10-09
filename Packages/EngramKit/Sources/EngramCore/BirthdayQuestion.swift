import Foundation

/// P31 — « C'est quand déjà la fête à Amina ? » : Retrouver et Siri répondent avec la fête gardée sur la page de la personne.
public enum BirthdayQuestion {
    /// Le nom peut être écrit sans majuscule dans une question tapée (« la fête à amina »).
    static let name = #"(?<name>(?i:mon|ma|mes|notre)\s+\p{L}[\p{L}'-]*|\p{L}[\p{L}'-]*(?:\s+\p{Lu}[\p{L}'-]*)?)"#
    /// En anglais, le nom vient avant (« Julie's birthday ») : il commence par une majuscule.
    static let englishName = #"(?<name>\p{Lu}[\p{L}-]*(?:\s+\p{Lu}[\p{L}-]*)?)"#
    static let patterns: [String] = [
        #"(?i:l'anniversaire|l'anniv|la date de f[êe]te|la f[êe]te)\s+(?i:de\s+|d'|[àa]\s+)"# + name,
        englishName + #"(?i:'s)\s+(?i:birthday|bday)"#,
    ]
    /// La question demande une date (« quand », « quelle date », « when »).
    static let asksWhen = #"\b(quand|quelle date|quel jour|c est quel|when|what day|what date)\b"#
    /// Une question courte (« La fête d'Amina ? ») suffit, même sans « quand ».
    static let shortQuestion = 5
    static let notAPerson: Set<String> = ["qui", "quelqu'un", "quelqu un", "who", "mariage"]

    /// La personne dont on demande la date de fête ; nil si la question porte sur autre chose.
    public static func person(in question: String) -> String? {
        let cleaned = question.replacingOccurrences(of: "’", with: "'")
        let words = cleaned.split(whereSeparator: \.isWhitespace).count
        guard RecallText.contains(asksWhen, in: " " + RecallText.normalize(cleaned) + " ") || words <= shortQuestion else {
            return nil
        }
        let whole = NSRange(cleaned.startIndex..., in: cleaned)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: cleaned, range: whole) {
                guard let range = Range(match.range(withName: "name"), in: cleaned) else { continue }
                let person = String(cleaned[range])
                let key = MeasurementParser.normalized(person)
                guard EntityName.isAcceptable(person), !BirthdayParser.holidays.contains(key), !notAPerson.contains(key) else {
                    continue
                }
                return person
            }
        }
        return nil
    }

    /// La fête de cette personne : même nom, ou un nom entendu à une lettre près s'il n'y en a qu'un (« Amena »).
    public static func find(_ name: String, in birthdays: [Birthday]) -> Birthday? {
        let key = EntityName.key(name)
        guard !key.isEmpty else { return nil }
        if let same = birthdays.first(where: { EntityName.key($0.name) == key }) { return same }
        guard key.count >= 4 else { return nil }
        let close = birthdays.filter { birthday in
            let other = EntityName.key(birthday.name)
            return other.first == key.first && distance(other, key) <= 1
        }
        return close.count == 1 ? close[0] : nil
    }

    /// « La fête d'Amina, c'est le 13 octobre, dans 4 jours. », « La fête de Marc, c'est demain, le 10 octobre. Marc aura
    /// 36 ans. »
    public static func answer(_ birthday: Birthday, now: Date, calendar: Calendar) -> String {
        let feast = BirthdayPlanner.feast(birthday.name)
        let subject = feast.prefix(1).uppercased() + feast.dropFirst()
        let day = birthday.day == 1 ? "1er" : "\(birthday.day)"
        let date = "le \(day) \(WeeklyReviewText.months[birthday.month - 1])"
        guard let next = BirthdayPlanner.next(month: birthday.month, day: birthday.day, from: now, calendar: calendar) else {
            return "\(subject), c'est \(date)."
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: next).day ?? 0
        var sentence = switch days {
        case 0: "\(subject), c'est aujourd'hui, \(date)."
        case 1: "\(subject), c'est demain, \(date)."
        default: "\(subject), c'est \(date), dans \(days) jours."
        }
        if let age = BirthdayPlanner.age(turningOn: next, born: birthday.year, calendar: calendar) {
            let name = BirthdayPlanner.inSentence(birthday.name)
            let shown = name.prefix(1).uppercased() + name.dropFirst()
            sentence += days == 0 ? " \(shown) a \(age) ans aujourd'hui." : " \(shown) aura \(age) ans."
        }
        return sentence
    }

    /// Nombre de lettres à changer, ajouter ou retirer pour passer d'un nom à l'autre.
    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        for (i, letter) in left.enumerated() {
            var current = [i + 1]
            for (j, other) in right.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (letter == other ? 0 : 1)))
            }
            previous = current
        }
        return previous[right.count]
    }
}
