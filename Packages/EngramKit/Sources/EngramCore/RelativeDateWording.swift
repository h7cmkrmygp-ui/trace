import Foundation

/// Les jours relatifs (« aujourd'hui », « demain »…) d'un titre ou d'un texte deviennent la vraie date de la dictée :
/// « Je pèse 162,5 livres aujourd'hui » → « Je pèse 162,5 livres le 15 janvier ». Relue plus tard, la note dit
/// toujours vrai. Les mots exacts de la dictée, eux, ne sont jamais touchés.
public enum RelativeDateWording {
    struct Rule {
        let pattern: String
        let offset: Int
        let part: String?
    }

    /// Les plus longues d'abord : « après-demain » et « demain matin » avant « demain ».
    static let rules: [Rule] = [
        Rule(pattern: "apr[eè]s[- ]demain", offset: 2, part: nil),
        Rule(pattern: "avant[- ]hier", offset: -2, part: nil),
        Rule(pattern: "aujourd['’]hui", offset: 0, part: nil),
        Rule(pattern: "demain matin", offset: 1, part: "au matin"),
        Rule(pattern: "demain soir", offset: 1, part: "au soir"),
        Rule(pattern: "demain apr[eè]s[- ]midi", offset: 1, part: "en après-midi"),
        Rule(pattern: "hier matin", offset: -1, part: "au matin"),
        Rule(pattern: "hier soir", offset: -1, part: "au soir"),
        Rule(pattern: "hier apr[eè]s[- ]midi", offset: -1, part: "en après-midi"),
        Rule(pattern: "ce matin", offset: 0, part: "au matin"),
        Rule(pattern: "ce soir", offset: 0, part: "au soir"),
        Rule(pattern: "cet apr[eè]s[- ]midi", offset: 0, part: "en après-midi"),
        Rule(pattern: "demain", offset: 1, part: nil),
        Rule(pattern: "hier", offset: -1, part: nil),
    ]

    static var expression: NSRegularExpression? {
        let alternatives = rules.map { "(\($0.pattern))" }.joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}-])(?:\(alternatives))(?![\\p{L}\\p{N}-])",
                                        options: [.caseInsensitive])
    }

    /// Ce qui précède le jour : « de demain » → « du 16 », « d'hier » → « du 14 », « à demain » → « au 16 ».
    static var contraction: NSRegularExpression? {
        try? NSRegularExpression(pattern: "(?:(?<![\\p{L}])([Dd]e|à|À) |([Dd])['’])$")
    }

    public static func anchored(_ text: String, on day: Date, calendar: Calendar) -> String {
        guard let expression, let contraction else { return text }
        let result = NSMutableString(string: text)
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        // De la fin vers le début : les positions des remplacements suivants restent justes.
        for match in matches.reversed() {
            guard let index = (1...rules.count).first(where: { match.range(at: $0).location != NSNotFound }),
                  let date = calendar.date(byAdding: .day, value: rules[index - 1].offset, to: calendar.startOfDay(for: day))
            else { continue }
            let rule = rules[index - 1]
            let matched = result.substring(with: match.range)
            var range = match.range
            var article = "le"
            let before = result.substring(to: range.location)
            if let found = contraction.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) {
                let word = found.range(at: 1).location != NSNotFound
                    ? (before as NSString).substring(with: found.range(at: 1)) : "de"
                article = word.lowercased() == "à" ? "au" : "du"
                let start = found.range(at: 1).location != NSNotFound ? found.range(at: 1).location : found.range(at: 2).location
                if (before as NSString).substring(with: NSRange(location: start, length: 1)).first?.isUppercase == true {
                    article = article.prefix(1).uppercased() + article.dropFirst()
                }
                range = NSRange(location: start, length: range.location + range.length - start)
            } else if matched.first?.isUppercase == true {
                article = "Le"
            }
            let words = [article, format(date, comparedTo: day, calendar: calendar), rule.part].compactMap { $0 }
            result.replaceCharacters(in: range, with: words.joined(separator: " "))
        }
        return result as String
    }

    /// « 15 janvier », « 1er janvier 2027 » (l'année seulement si elle change).
    static func format(_ date: Date, comparedTo day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM"
        let dayNumber = calendar.component(.day, from: date)
        var text = (dayNumber == 1 ? "1er" : String(dayNumber)) + " " + formatter.string(from: date)
        if calendar.component(.year, from: date) != calendar.component(.year, from: day) {
            text += " \(calendar.component(.year, from: date))"
        }
        return text
    }
}
