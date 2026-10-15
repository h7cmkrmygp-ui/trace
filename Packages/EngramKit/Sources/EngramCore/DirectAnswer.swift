import Foundation

/// P39 — Retrouver répond direct : pour une question de fait (un numéro, un montant, une date, un endroit), la réponse
/// exacte tirée de la meilleure note, avec la note d'où elle vient. Sans valeur dans la note, pas de réponse : la réponse
/// habituelle prend le relais. Rien n'est inventé.
public enum DirectAnswer {
    /// Ce que demande la question.
    enum Kind: Equatable { case amount, number, when, place }

    /// Score minimal de la meilleure note pour répondre directement.
    static let minimumScore = 0.8

    public static func make(question: String, hits: [RecallHit], now: Date, calendar: Calendar) -> String? {
        guard let kind = kind(of: question), let top = hits.first, top.score >= minimumScore else { return nil }
        let note = top.document
        let source = "dans ta note « \(note.title) »"
        let sentence = SearchSnippet.make(note.text, query: question) ?? SearchSnippet.make(note.title, query: question)
        switch kind {
        case .amount:
            guard let amount = firstMatch(of: moneyPattern, in: sentence ?? note.text).map(cleanAmount) else { return nil }
            return "\(amount) — \(source) du \(day(note.capturedAt, calendar: calendar))."
        case .number:
            guard let number = firstMatch(of: numberPattern, in: sentence ?? note.text) else { return nil }
            return "\(number) — \(source) du \(day(note.capturedAt, calendar: calendar))."
        case .when:
            guard let due = note.dueAt else { return nil }
            let moment = when(due, calendar: calendar)
            return "\(moment.prefix(1).uppercased() + moment.dropFirst()) — \(source)."
        case .place:
            guard let sentence else { return nil }
            return "« \(sentence) » — \(source) du \(day(note.capturedAt, calendar: calendar))."
        }
    }

    /// Le genre de réponse attendue ; nil pour une question qui n'est pas une question de fait.
    static func kind(of question: String) -> Kind? {
        let text = " " + RecallText.normalize(question) + " "
        if RecallText.contains(#"\b(combien|prix|montant|coute|coutait|coute t il)\b"#, in: text)
            && RecallText.contains(#"\b(combien|prix|montant|paye|payer|payes|coute|coutait|cher|dollars?|piasses?)\b"#, in: text) {
            return .amount
        }
        if RecallText.contains(#"\b(numero|numeros|no|num|matricule|code)\b"#, in: text) { return .number }
        if RecallText.contains(#"\b(quand|quelle date|quel jour|quelle heure|a quelle heure)\b"#, in: text) { return .when }
        if question.lowercased().contains("où") { return .place }
        return nil
    }

    /// « 640 $ », « 12,50 $ », « $ 80 », « 30 dollars ».
    static let moneyPattern = #"(\d[\d  ]*(?:[.,]\d{1,2})?\s?(?:\$|dollars?|piasses?))|(\$\s?\d[\d  ]*(?:[.,]\d{1,2})?)"#
    /// Au moins 4 chiffres, avec espaces, tirets, points ou barres entre eux (« 4589-2231 », « 123 456 789 »).
    static let numberPattern = #"\d[\d .\-/]{2,}\d"#

    static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let value = text[range].trimmingCharacters(in: .whitespaces)
            // Un numéro compte au moins 4 chiffres (pas une date courte ni un petit nombre).
            if pattern == numberPattern, value.filter(\.isNumber).count < 4 { continue }
            return value
        }
        return nil
    }

    /// « 640 $ » (une espace avant le dollar, comme au Québec).
    static func cleanAmount(_ raw: String) -> String {
        let digits = raw.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "dollars", with: "")
            .replacingOccurrences(of: "dollar", with: "").replacingOccurrences(of: "piasses", with: "")
            .replacingOccurrences(of: "piasse", with: "").trimmingCharacters(in: .whitespaces)
        return "\(digits) $"
    }

    /// « 3 mars », « 1er mars ».
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        let day = parts.day == 1 ? "1er" : "\(parts.day ?? 1)"
        return "\(day) \(WeeklyReviewText.months[(parts.month ?? 1) - 1])"
    }

    /// « le mardi 20 octobre à 14 h », « le jeudi 22 octobre à 8 h 30 » ; sans heure si elle est minuit.
    static func when(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        var text = "le \(weekday) \(day(date, calendar: calendar))"
        if hour != 0 || minute != 0 { text += minute == 0 ? " à \(hour) h" : " à \(hour) h \(String(format: "%02d", minute))" }
        return text
    }
}
