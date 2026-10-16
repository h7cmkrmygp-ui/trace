import Foundation

/// F21 — une note d'où tirer des assertions : son identifiant, son texte et le moment où elle a été dite.
public struct AssertionNote: Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let saidAt: Date

    public init(id: UUID, text: String, saidAt: Date) {
        self.id = id
        self.text = text
        self.saidAt = saidAt
    }
}

/// F21 — un fait sur une personne : elle aime ou n'aime pas une chose, d'après une note, à un moment ; une assertion plus
/// récente sur la même chose la remplace (elle reste dans l'historique).
public struct Assertion: Sendable, Equatable {
    public enum Relation: String, Sendable { case likes, dislikes }

    public let subject: String
    public let relation: Relation
    public let value: String
    public let valueKey: String
    public let sourceID: UUID
    public let saidAt: Date
    public var supersededBy: UUID?

    public var isCurrent: Bool { supersededBy == nil }

    public init(subject: String, relation: Relation, value: String, valueKey: String, sourceID: UUID, saidAt: Date,
                supersededBy: UUID? = nil) {
        self.subject = subject
        self.relation = relation
        self.value = value
        self.valueKey = valueKey
        self.sourceID = sourceID
        self.saidAt = saidAt
        self.supersededBy = supersededBy
    }
}

public enum Assertions {
    /// Mots de début de phrase qui ne sont pas un nom de personne.
    static let notNames: Set<String> = [
        "elle", "il", "elles", "ils", "lui", "je", "j", "on", "nous", "vous", "tu", "la", "le", "les", "l", "un", "une",
        "mon", "ma", "mes", "son", "sa", "ses", "ce", "cette", "et", "mais", "pis", "puis", "aussi", "finalement",
        "maintenant", "depuis", "avant", "apres", "hier", "aujourd", "demain", "pour", "avec", "quand", "si", "selon",
        "en", "au", "aux", "a", "de", "du", "des", "chez", "ah", "oh", "bon", "ok", "she", "he", "they", "her", "his",
    ]
    static let pronouns: Set<String> = ["elle", "il", "elles", "ils", "lui", "she", "he", "they"]

    /// Les goûts d'une personne dans ses notes, de la plus ancienne à la plus récente. Chaque proposition est coupée à
    /// chaque nouveau sujet nommé (« Julie aime le thé et Marc aime le café ») ; une proposition sans nom (« Elle adore le
    /// chocolat ») n'est à la personne que si la note ne nomme personne d'autre. Une assertion plus récente sur la même
    /// chose remplace les précédentes (elles restent, marquées remplacées).
    public static func tastes(of person: String, in notes: [AssertionNote]) -> [Assertion] {
        let personKey = TextNormalizer.matchingForm(person)
        guard !personKey.isEmpty else { return [] }
        var found: [Assertion] = []
        for note in notes.enumerated().sorted(by: { ($0.element.saidAt, $0.offset) < ($1.element.saidAt, $1.offset) })
            .map(\.element) {
            let text = note.text.replacingOccurrences(of: "’", with: "'")
            let others = names(in: text).filter { $0 != personKey && !personKey.split(separator: " ").contains(Substring($0)) }
            for clause in text.components(separatedBy: CharacterSet(charactersIn: ".!?;\n")) {
                for part in subjects(in: clause) {
                    let form = " " + TextNormalizer.matchingForm(part) + " "
                    let named = form.contains(" " + personKey + " ")
                    let subject = names(in: part).first
                    guard named || (subject == nil && others.isEmpty) else { continue }
                    let relation: Assertion.Relation
                    let value: String
                    if let what = PersonQuestion.capture(PersonQuestion.dislike, in: part) {
                        (relation, value) = (.dislikes, what)
                    } else if let what = PersonQuestion.capture(PersonQuestion.like, in: part) {
                        (relation, value) = (.likes, what)
                    } else { continue }
                    let key = valueKey(value)
                    guard !key.isEmpty else { continue }
                    for index in found.indices where found[index].isCurrent && found[index].valueKey == key {
                        found[index].supersededBy = note.id
                    }
                    found.append(Assertion(subject: person, relation: relation, value: value, valueKey: key,
                                           sourceID: note.id, saidAt: note.saidAt))
                }
            }
        }
        return found
    }

    /// Les goûts actuels (les assertions remplacées n'en font plus partie), dans l'ordre où ils ont été dits.
    public static func currentTastes(_ assertions: [Assertion]) -> Tastes {
        var tastes = Tastes()
        var seen = Set<String>()
        for assertion in assertions where assertion.isCurrent && seen.insert(assertion.valueKey).inserted {
            switch assertion.relation {
            case .likes: tastes.likes.append(assertion.value)
            case .dislikes: tastes.dislikes.append(assertion.value)
            }
        }
        return tastes
    }

    /// « le café », « du café » → « cafe ».
    static func valueKey(_ value: String) -> String {
        var words = TextNormalizer.matchingForm(value).split(separator: " ").map(String.init)
        while let first = words.first, ["le", "la", "les", "l", "du", "de", "des", "d", "un", "une"].contains(first),
              words.count > 1 {
            words.removeFirst()
        }
        return words.map(TextNormalizer.singularize).joined(separator: " ")
    }

    /// Les noms de personnes d'un texte : les mots à majuscule qui ne sont pas un mot ordinaire de début de phrase.
    static func names(in text: String) -> [String] {
        var names: [String] = []
        for piece in text.split(whereSeparator: { $0.isWhitespace || ",:;«»\"()".contains($0) }) {
            let word = piece.split(separator: "'").last.map(String.init) ?? String(piece)
            guard let initial = word.first, initial.isUppercase else { continue }
            let key = TextNormalizer.matchingForm(word)
            if !key.isEmpty, !notNames.contains(key), !names.contains(key) { names.append(key) }
        }
        return names
    }

    /// Une proposition coupée devant chaque nouveau sujet nommé : « Julie aime le thé et Marc aime le café ».
    static func subjects(in clause: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:,|\bet\b|\bmais\b|\bpis\b|\bpuis\b)\s+(?=\p{Lu})"#) else {
            return [clause]
        }
        let source = clause as NSString
        var parts: [String] = []
        var start = 0
        for match in regex.matches(in: clause, range: NSRange(location: 0, length: source.length)) {
            parts.append(source.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = NSMaxRange(match.range)
        }
        parts.append(source.substring(from: start))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
