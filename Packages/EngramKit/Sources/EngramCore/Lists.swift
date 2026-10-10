import Foundation

/// P15 — « ajoute du lait et des œufs à ma liste d'épicerie » : la liste visée et les choses à y mettre.
public struct ListCommand: Sendable, Equatable {
    /// Le nom de la liste tel qu'il se dit après « liste de » (« épicerie », « cadeaux », « Costco »).
    public let listName: String
    /// Les choses à ajouter, une par case (« Lait », « Œufs »).
    public let items: [String]

    public init(listName: String, items: [String]) {
        self.listName = listName
        self.items = items
    }
}

/// Reconnaît, sur l'iPhone et sans IA, une demande d'ajout à une liste : « ajoute du lait à ma liste d'épicerie »,
/// « mets du pain sur la liste », « sur ma liste de cadeaux, ajoute un livre », « liste d'épicerie : lait, café »,
/// « add milk to my grocery list ». Sans nom, c'est la liste d'épicerie.
public enum ListCommandParser {
    static let verbs = "(?:r?ajout(?:e|es|er)|mets|mettre|met|inscris|inscrire)"
    static let patterns = [
        // « Ajoute du lait et des œufs à ma liste d'épicerie »
        "\\b\(verbs)\\s+(?<items>.+?)\\s+(?:à|a|sur|dans)\\s+(?:ma|la|notre|ta|mes|les)\\s+listes?(?<name>\\s+.+)?$",
        // « Sur ma liste de cadeaux, ajoute un livre pour Julie »
        "\\b(?:sur|dans|à)\\s+(?:ma|la|notre)\\s+liste(?<name>\\s+(?:d'|de\\s+|des\\s+|du\\s+)[^,:]+?)?\\s*[,:]\\s*\(verbs)\\s+(?<items>.+)$",
        // « Liste d'épicerie : lait, café »
        "^\\s*(?:ma\\s+)?liste(?<name>\\s+(?:d'|de\\s+|des\\s+|du\\s+)[^:]+?)?\\s*:\\s*(?<items>.+)$",
        // « Add milk and eggs to my grocery list »
        "\\b(?:add|put)\\s+(?<items>.+?)\\s+(?:to|on)\\s+(?:my|the|our)\\s+(?:(?<name>.+?)\\s+)?list\\b",
    ]

    /// Ces noms désignent tous la liste d'épicerie.
    static let groceries: Set<String> = ["epicerie", "courses", "commissions", "grocery", "groceries", "shopping", "marche"]
    static let leadingWords = ["de la ", "de l'", "d'", "des ", "du ", "de ", "pour ", "à ", "of ", "for "]
    static let articles = ["de la ", "de l'", "d'", "du ", "des ", "un ", "une ", "le ", "la ", "les ", "l'", "some ",
                           "the ", "a ", "an "]
    static let politeness = [" s'il te plaît", " s'il te plait", " s'il vous plaît", " stp", " svp", " please", " merci"]

    public static func parse(_ text: String) -> ListCommand? {
        let cleaned = text.replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        let whole = NSRange(cleaned.startIndex..., in: cleaned)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: cleaned, range: whole),
                  let itemsRange = Range(match.range(withName: "items"), in: cleaned) else { continue }
            let name = Range(match.range(withName: "name"), in: cleaned).map { String(cleaned[$0]) }
            let items = self.items(in: String(cleaned[itemsRange]))
            guard !items.isEmpty else { continue }
            return ListCommand(listName: listName(name), items: items)
        }
        return nil
    }

    /// « d'épicerie pour samedi » → « épicerie » ; « de courses » → « épicerie » ; rien → « épicerie ».
    static func listName(_ raw: String?) -> String {
        var name = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if let cut = name.firstIndex(where: { ",.;!?".contains($0) }) { name = String(name[..<cut]) }
        name = withoutPoliteness(name)
        var changed = true
        while changed {
            changed = false
            for word in leadingWords where name.lowercased().hasPrefix(word) {
                name = String(name.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        // « épicerie pour samedi », « courses de la semaine » : le nom s'arrête avant.
        for separator in [" pour ", " for ", " de la semaine", " demain", " ce soir", " aujourd'hui"] {
            if let range = name.range(of: separator, options: .caseInsensitive) { name = String(name[..<range.lowerBound]) }
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || groceries.contains(key(name)) { return "épicerie" }
        return name
    }

    /// « du lait, des œufs pis du pain » → « Lait », « Œufs », « Pain ».
    static func items(in raw: String) -> [String] {
        let separators = try? NSRegularExpression(pattern: "\\s*(?:,|;|&|\\bet\\b|\\bpis\\b|\\bpuis\\b|\\band\\b|\\bainsi que\\b)\\s*",
                                                  options: [.caseInsensitive])
        let whole = NSRange(raw.startIndex..., in: raw)
        let marked = separators?.stringByReplacingMatches(in: raw, range: whole, withTemplate: "\u{1F}") ?? raw
        var seen = Set<String>()
        var kept: [String] = []
        for piece in marked.split(separator: "\u{1F}") {
            var item = withoutPoliteness(piece.trimmingCharacters(in: .whitespacesAndNewlines))
            if let article = articles.first(where: { item.lowercased().hasPrefix($0) }), item.count > article.count {
                item = String(item.dropFirst(article.count))
            }
            item = item.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?")))
            guard !item.isEmpty, item.count <= 80, seen.insert(key(item)).inserted else { continue }
            kept.append(item.prefix(1).uppercased() + item.dropFirst())
        }
        return kept
    }

    static func withoutPoliteness(_ text: String) -> String {
        var result = text
        for phrase in politeness where result.lowercased().hasSuffix(phrase) {
            result = String(result.dropLast(phrase.count))
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// « Liste d'épicerie », « Liste de cadeaux », « Liste de Costco ».
    public static func title(for name: String) -> String {
        let first = key(String(name.prefix(1)))
        return "aeiouyh".contains(first) && !first.isEmpty ? "Liste d'\(name)" : "Liste de \(name)"
    }

    /// La clé d'une liste : « Épicerie » et « epicerie » sont la même.
    public static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// « Épicerie », « Cadeaux » (pour les cartes).
    public static func displayName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Ajouter des cases à une liste, ou retirer celles qui sont cochées.
public enum ListMerge {
    /// Chaque chose devient une case à cocher ; déjà là et pas cochée, rien ne change ; cochée, elle redevient à faire.
    /// `added` : les choses à faire de nouveau (ajoutées ou décochées).
    public static func adding(_ items: [String], to body: String) -> (body: String, added: [String]) {
        var blocks = NoteBody.blocks(from: body)
        var added: [String] = []
        for item in items {
            let wanted = ListCommandParser.key(item)
            if let index = blocks.firstIndex(where: { block in
                if case .check = block.kind { return ListCommandParser.key(block.text) == wanted }
                return false
            }) {
                if case .check(done: true) = blocks[index].kind {
                    blocks[index].kind = .check(done: false)
                    added.append(blocks[index].text)
                }
                continue
            }
            blocks.append(NoteBlock(kind: .check(done: false), text: item))
            added.append(item)
        }
        return (NoteBody.text(from: blocks), added)
    }

    public static func removingChecked(from body: String) -> String {
        NoteBody.text(from: NoteBody.blocks(from: body).filter { $0.kind != .check(done: true) })
    }
}
