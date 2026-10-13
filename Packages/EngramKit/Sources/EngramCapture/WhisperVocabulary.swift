import Foundation

/// P37 — l'amorce de Whisper avec les noms du propriétaire (personnes, lieux, dossiers), pour qu'il les écrive bien.
extension WhisperPrompt {
    /// Longueur maximale de la liste de noms ajoutée à l'amorce (Whisper n'en lit qu'une partie).
    public static let maxNamesLength = 300

    /// L'amorce bilingue, suivie des noms (« Julie, Marc, Costco. »), sans doublon ni nom d'une lettre.
    public static func make(names: [String]) -> String {
        var seen: Set<String> = []
        var kept: [String] = []
        var length = 0
        for raw in names {
            let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = normalized(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
            guard name.count >= 2, !key.isEmpty, seen.insert(key).inserted else { continue }
            let added = (kept.isEmpty ? 0 : 2) + name.count
            guard length + added <= maxNamesLength else { break }
            kept.append(name)
            length += added
        }
        guard !kept.isEmpty else { return bilingual }
        return bilingual + " " + kept.joined(separator: ", ") + "."
    }

    /// Vrai si Whisper a recopié l'amorce (ou sa liste de noms) au lieu de transcrire la parole.
    static func isEcho(_ text: String, prompt: String) -> Bool {
        let spoken = normalized(text)
        guard !spoken.isEmpty else { return false }
        let sentences = prompt.split(separator: ".").map { normalized(String($0)) }.filter { !$0.isEmpty }
        return isEcho(text) || spoken.contains(normalized(prompt)) || sentences.contains(spoken)
    }
}
