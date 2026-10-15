import Foundation

/// Découpe les longs textes aux fins de phrase, pour rester dans la fenêtre de contexte du modèle.
public enum TextChunker {
    /// Morceaux d'au plus `maxLength` caractères (une phrase seule plus longue reste entière).
    public static func chunks(of text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(of: text) {
            if !current.isEmpty && current.count + sentence.count > maxLength {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
            current += sentence
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { chunks.append(rest) }
        return chunks
    }

    /// Deux moitiés (par phrases, sinon par mots). Un seul élément si le texte ne peut pas être coupé.
    public static func halves(of text: String) -> [String] {
        let parts = sentences(of: text)
        if parts.count >= 2 {
            let middle = parts.count / 2
            return [parts[..<middle].joined(), parts[middle...].joined()]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let words = text.split(separator: " ")
        guard words.count >= 2 else { return [text] }
        let middle = words.count / 2
        return [words[..<middle].joined(separator: " "), words[middle...].joined(separator: " ")]
    }

    static func sentences(of text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .substringNotRequired]) { _, _, enclosing, _ in
            result.append(String(text[enclosing]))
        }
        return result.isEmpty ? [text] : result
    }
}
