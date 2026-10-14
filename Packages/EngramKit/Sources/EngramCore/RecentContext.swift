import Foundation

/// P42 — ce qui vient d'être dit : la dictée précédente, il y a moins de 30 minutes (ses personnes, ses listes, ses
/// dossiers). Engram s'en sert pour comprendre « elle », « lui », « cette liste », « ce projet », seulement quand c'est clair :
/// en cas de doute, aucun lien n'est inventé.
public struct RecentContext: Sendable, Equatable {
    /// Au-delà, la dictée précédente n'est plus « ce qui vient d'être dit ».
    public static let window: TimeInterval = 30 * 60

    public var people: [String]
    public var lists: [String]
    /// Chemins « Parent › Enfant » des notes de la dictée précédente (listes exclues).
    public var folders: [String]
    public var minutesAgo: Int

    public init(people: [String] = [], lists: [String] = [], folders: [String] = [], minutesAgo: Int = 0) {
        self.people = people
        self.lists = lists
        self.folders = folders
        self.minutesAgo = minutesAgo
    }

    public var isEmpty: Bool { people.isEmpty && lists.isEmpty && folders.isEmpty }
}

/// P42 — une note qui parle de quelqu'un, d'une liste ou d'un projet sans le nommer.
public enum ContextReferences {
    /// Formes repérées dans le texte sans accents ni ponctuation (« m'a dit » → « m a dit »). « elle doit aller au
    /// garage » (une voiture) ne compte pas : seulement ce qu'on dit d'une personne.
    static let someone = [
        #"\blui\b"#,
        #"\b(?:elle|il|elles|ils) (?:n |ne )?(?:aime|aimerait|aimait|adore|adorerait|deteste|prefere|veut|voudrait|souhaite|reve|cherche|collectionne|trouve|m a dit|a dit|kiffe|trippe|tripe)\b"#,
        #"\b(?:sa|son) (?:fete|anniversaire|date de fete)\b"#,
        #"\b(?:pour|avec|chez|a) (?:elle|eux|elles)\b"#,
    ]
    static let aList = [#"\b(?:cette|la meme) liste\b"#]
    static let aProject = [#"\b(?:ce|le meme|ce meme) (?:projet|dossier)\b"#]

    /// « elle adore », « lui acheter », « sa fête », « pour lui ».
    public static func refersToSomeone(_ text: String) -> Bool { matches(someone, text) }

    /// « cette liste », « la même liste ».
    public static func refersToAList(_ text: String) -> Bool { matches(aList, text) }

    /// « ce projet », « ce dossier ».
    public static func refersToAProject(_ text: String) -> Bool { matches(aProject, text) }

    /// « Ajoute un livre et des chandelles à cette liste » → « Livre », « Chandelles » ; nil sans « cette liste ».
    public static func listItems(in text: String) -> [String]? {
        let cleaned = text.replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        let pattern = "\b\(ListCommandParser.verbs)\s+(?:aussi\s+)?(?<items>.+?)\s+(?:à|a|sur|dans)\s+"
            + "(?:cette|la\s+m[eê]me)\s+liste\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range(withName: "items"), in: cleaned) else { return nil }
        let items = ListCommandParser.items(in: String(cleaned[range]))
        return items.isEmpty ? nil : items
    }

    static func matches(_ patterns: [String], _ text: String) -> Bool {
        let form = TextNormalizer.matchingForm(text)
        return patterns.contains { form.range(of: $0, options: .regularExpression) != nil }
    }
}

extension Array {
    /// Le seul élément, ou nil s'il y en a zéro ou plusieurs (ambigu).
    var onlyOne: Element? { count == 1 ? self[0] : nil }
}
