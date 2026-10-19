import Foundation

/// Titre de repli quand aucune analyse n'est disponible.
public enum TitleMaker {
    public static let maxLength = 80

    /// Première ligne non vide, espaces réduits, coupée proprement à 80 caractères (graphèmes).
    public static func fallbackTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first { !$0.allSatisfy(\.isWhitespace) }
            .map(String.init) ?? ""
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return "Note sans titre" }
        guard collapsed.count > maxLength else { return collapsed }
        let cut = collapsed.prefix(maxLength - 1)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= 40 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
