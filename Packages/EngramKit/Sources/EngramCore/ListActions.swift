import Foundation

/// P19 — « coche le lait », « j'ai acheté le pain », « enlève les bananes de ma liste ».
public struct ListAction: Sendable, Equatable {
    public enum Kind: String, Sendable { case check, remove }

    public let kind: Kind
    /// La liste nommée ; nil = celle qui contient ces choses (l'épicerie d'abord).
    public let listName: String?
    public let items: [String]
    /// Une demande claire (« coche », « enlève … de ma liste ») ; « j'ai acheté le pain » ne l'est pas : sans case qui
    /// correspond, c'est une note ordinaire.
    public let isExplicit: Bool

    public init(kind: Kind, listName: String?, items: [String], isExplicit: Bool) {
        self.kind = kind
        self.listName = listName
        self.items = items
        self.isExplicit = isExplicit
    }
}

/// Reconnaît, sur l'iPhone et sans IA, une case à cocher ou à retirer.
public enum ListActionParser {
    static let listPart = #"(?:\s+(?:sur|dans|de|from|on)\s+(?:ma|la|notre|my|the|our)\s+(?:(?<before>\S+)\s+)?(?:liste|list)(?<name>\s+.+)?)?"#
    static let patterns: [(kind: ListAction.Kind, explicit: Bool, needsList: Bool, pattern: String)] = [
        (.check, true, false, #"^\s*(?:coche|cocher|check off|cross off)\s+(?<items>.+?)"# + listPart + #"$"#),
        (.remove, true, true, #"^\s*(?:enl[eè]ve|enlever|retire|retirer|efface|effacer|supprime|supprimer|remove|delete)\s+(?<items>.+?)"# + listPart + #"$"#),
        (.check, false, false, #"^\s*(?:j'ai achet[ée]|j'ai pris|on a achet[ée]|i bought|i got|we bought)\s+(?<items>.+?)"# + listPart + #"$"#),
    ]

    public static func parse(_ text: String) -> ListAction? {
        let cleaned = text.replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        let whole = NSRange(cleaned.startIndex..., in: cleaned)
        for (kind, explicit, needsList, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: cleaned, range: whole),
                  let itemsRange = Range(match.range(withName: "items"), in: cleaned) else { continue }
            let hasList = match.range(withName: "name").location != NSNotFound
                || cleaned.range(of: "liste", options: .caseInsensitive) != nil
                || cleaned.range(of: " list", options: .caseInsensitive) != nil
            // « enlève tes souliers » n'est pas une liste.
            if needsList && !hasList { continue }
            let rawName = [match.range(withName: "before"), match.range(withName: "name")]
                .compactMap { Range($0, in: cleaned).map { String(cleaned[$0]) } }
                .joined(separator: " ")
            let items = ListCommandParser.items(in: String(cleaned[itemsRange]))
            guard !items.isEmpty else { continue }
            let name: String? = hasList && !rawName.trimmingCharacters(in: .whitespaces).isEmpty
                ? ListCommandParser.listName(rawName) : (hasList && explicit && kind == .remove ? "épicerie" : nil)
            return ListAction(kind: kind, listName: name, items: items, isExplicit: explicit)
        }
        return nil
    }
}

extension ListMerge {
    /// La clé d'une chose dite : sans accents ni ligatures, au singulier (« Œufs » → « oeuf »).
    static func itemKey(_ text: String) -> String {
        var key = ListCommandParser.key(text.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae"))
        if key.count > 3, key.hasSuffix("s") || key.hasSuffix("x") { key.removeLast() }
        return key
    }

    /// « lait » trouve « Lait 2 % » ; « bananes » trouve « Banane » ; jamais « Laitue ».
    public static func matches(_ spoken: String, _ box: String) -> Bool {
        let said = itemKey(spoken)
        let written = itemKey(box)
        guard !said.isEmpty else { return false }
        if said == written { return true }
        let firstWord = ListCommandParser.key(box).split(separator: " ").first.map(String.init) ?? ""
        return written.hasPrefix(said + " ") || itemKey(firstWord) == said
    }

    /// Coche les cases dites (pas encore cochées). `changed` : le texte des cases cochées.
    public static func checking(_ items: [String], in body: String) -> (body: String, changed: [String]) {
        var blocks = NoteBody.blocks(from: body)
        var changed: [String] = []
        for item in items {
            guard let index = blocks.firstIndex(where: { block in
                block.kind == .check(done: false) && matches(item, block.text)
            }) else { continue }
            blocks[index].kind = .check(done: true)
            changed.append(blocks[index].text)
        }
        return (NoteBody.text(from: blocks), changed)
    }

    /// Retire les cases dites (cochées ou pas).
    public static func removing(_ items: [String], from body: String) -> (body: String, changed: [String]) {
        var blocks = NoteBody.blocks(from: body)
        var changed: [String] = []
        for item in items {
            guard let index = blocks.firstIndex(where: { block in
                if case .check = block.kind { return matches(item, block.text) }
                return false
            }) else { continue }
            changed.append(blocks[index].text)
            blocks.remove(at: index)
        }
        return (NoteBody.text(from: blocks), changed)
    }
}
