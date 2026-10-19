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
        // F22 — une note hors de la période demandée n'est jamais la réponse.
        guard let kind = kind(of: question), let top = hits.first, top.score >= minimumScore, !top.outsidePeriod else {
            return nil
        }
        let note = top.document
        let source = "dans ta note « \(note.title) »"
        let sentence = SearchSnippet.make(note.text, query: question) ?? SearchSnippet.make(note.title, query: question)
        switch kind {
        case .amount, .number:
            // F22 — la valeur dont le rôle répond à la question (devis ou prix payé, numéro de qui) ; plusieurs valeurs
            // possibles : le passage est cité, sans trancher.
            let pattern = kind == .amount ? moneyPattern : numberPattern
            switch choose(pattern, in: note.text, question: question) {
            case .value(let raw)?:
                return "\(kind == .amount ? cleanAmount(raw) : raw) — \(source) du \(day(note.capturedAt, calendar: calendar))."
            case .passage(let passage)?:
                return "« \(passage) » — \(source) du \(day(note.capturedAt, calendar: calendar))."
            case nil:
                return nil
            }
        case .when:
            guard let due = note.dueAt else { return nil }
            let moment = when(due, calendar: calendar)
            return "\(moment.prefix(1).uppercased() + moment.dropFirst()) — \(source)."
        case .place:
            guard let sentence else { return nil }
            return "« \(sentence) » — \(source) du \(day(note.capturedAt, calendar: calendar))."
        }
    }

    enum Choice: Equatable {
        case value(String)
        case passage(String)
    }

    /// Mots d'une question qui disent ce qu'on cherche, pas à quoi il sert.
    static let questionWords: Set<String> = [
        "combien", "prix", "montant", "coute", "coutait", "cout", "couts", "numero", "numeros", "num", "code", "quoi",
        "quel", "quelle", "quels", "quelles", "cest", "est", "etait", "dollars", "dollar", "piasses", "cher", "matricule",
        "pour", "avec", "dans", "les", "des", "une", "que", "qui",
    ]

    /// F22 — chaque valeur trouvée, avec les mots qui la précèdent dans sa phrase (son rôle : « le devis est »,
    /// « j'ai payé ») ; la seule, ou celle dont le rôle rejoint le mieux la question ; sinon le passage.
    static func choose(_ pattern: String, in text: String, question: String) -> Choice? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let source = text as NSString
        var candidates: [(value: String, range: NSRange, role: Set<String>)] = []
        var previousEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let value = source.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            // Un numéro compte au moins 4 chiffres (pas une date courte ni un petit nombre).
            if pattern == numberPattern, value.filter(\.isNumber).count < 4 { continue }
            var start = match.range.location
            while start > previousEnd, !".!?;\n".contains(source.substring(with: NSRange(location: start - 1, length: 1))) {
                start -= 1
            }
            let before = source.substring(with: NSRange(location: start, length: match.range.location - start))
            candidates.append((value, match.range, stems(before)))
            previousEnd = NSMaxRange(match.range)
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return .value(candidates[0].value) }
        let wanted = stems(question).subtracting(questionWords.map(stem))
        let scores = candidates.map { $0.role.intersection(wanted).count }
        let best = scores.max() ?? 0
        if best > 0, scores.filter({ $0 == best }).count == 1, let index = scores.firstIndex(of: best) {
            return .value(candidates[index].value)
        }
        // Aucune valeur ne se détache : les phrases qui les portent, telles qu'écrites.
        let sentences = candidates.indices.filter { scores[$0] == best }.compactMap { sentence(around: candidates[$0].range, in: source) }
        var seen = Set<String>()
        return .passage(sentences.filter { seen.insert($0).inserted }.joined(separator: " "))
    }

    /// La phrase (coupée sur . ! ? ; et les retours à la ligne) qui contient `range`.
    static func sentence(around range: NSRange, in source: NSString) -> String? {
        var start = range.location
        while start > 0, !".!?;\n".contains(source.substring(with: NSRange(location: start - 1, length: 1))) { start -= 1 }
        var end = NSMaxRange(range)
        while end < source.length, !".!?;\n".contains(source.substring(with: NSRange(location: end, length: 1))) { end += 1 }
        let text = source.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Les racines (5 premières lettres) des mots porteurs de sens : « payé », « payer » ; « rembourse », « remboursé ».
    static func stems(_ text: String) -> Set<String> {
        Set(TextNormalizer.matchingForm(text).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }
            .map(stem))
    }

    static func stem(_ word: String) -> String { String(word.prefix(5)) }

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
