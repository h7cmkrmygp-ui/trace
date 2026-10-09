import Foundation

/// P26 — ce que Siri dit d'une liste, et la phrase qu'Engram classe quand on lui demande d'ajouter quelque chose.
public enum ListSpeech {
    /// « Sur ta liste d'épicerie : lait, pain et œufs. » ; une liste privée ne dit que le nombre.
    public static func read(_ list: ListsSnapshot.List?) -> String {
        guard let list else { return "Tu n'as pas encore de liste. Dis : « ajoute du lait à ma liste d'épicerie »." }
        let name = lowerFirst(list.title)
        if list.open.isEmpty {
            if list.openCount > 0 {
                return list.openCount == 1 ? "Ta \(name) a 1 chose. Ouvre Engram pour la voir."
                                           : "Ta \(name) a \(list.openCount) choses. Ouvre Engram pour les voir."
            }
            return list.done > 0 ? "Tout est coché sur ta \(name)." : "Ta \(name) est vide."
        }
        let items = list.open.map(lowerFirst)
        let rest = list.openCount - items.count
        let spoken: String
        if rest > 0 {
            spoken = items.joined(separator: ", ") + " et \(rest) autre\(rest > 1 ? "s" : "") chose\(rest > 1 ? "s" : "")"
        } else if items.count > 1 {
            spoken = items.dropLast().joined(separator: ", ") + " et " + items[items.count - 1]
        } else {
            spoken = items[0]
        }
        return "Sur ta \(name) : \(spoken)."
    }

    /// « Ajoute du lait à ma liste d'épicerie » (sans liste nommée : l'épicerie).
    public static func addCommand(item: String, list: String?) -> String {
        let named = list?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = ListCommandParser.title(for: named.isEmpty ? "épicerie" : named)
        return "Ajoute \(item.trimmingCharacters(in: .whitespacesAndNewlines)) à ma \(lowerFirst(title))"
    }

    /// « C'est ajouté à ta liste d'épicerie. »
    public static func added(to list: String?) -> String {
        let named = list?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "C'est ajouté à ta \(lowerFirst(ListCommandParser.title(for: named.isEmpty ? "épicerie" : named)))."
    }

    /// La liste dite à Siri (« l'épicerie », « mes courses », « Costco ») est-elle celle-ci ?
    public static func matches(_ spoken: String, listName: String) -> Bool {
        var said = spoken.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for prefix in ["ma liste ", "la liste ", "liste ", "mes ", "ma ", "mon ", "la ", "le ", "les ", "l'"]
            where said.lowercased().hasPrefix(prefix) && said.count > prefix.count {
                said = String(said.dropFirst(prefix.count))
                changed = true
            }
        }
        return ListCommandParser.key(ListCommandParser.listName(said)) == ListCommandParser.key(ListCommandParser.listName(listName))
    }

    /// « Lait » → « lait », mais « A1 » ou « TV » restent tels quels.
    static func lowerFirst(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let second = text.dropFirst().first
        guard second.map({ $0.isLowercase || $0 == " " || $0 == "'" }) ?? true else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
