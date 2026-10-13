import Foundation

/// P37 — l'amorce de Whisper avec les noms du propriétaire (personnes, lieux, dossiers), pour qu'il les écrive bien.
extension WhisperPrompt {
    /// Longueur maximale de la liste de noms ajoutée à l'amorce (Whisper n'en lit qu'une partie).
    public static let maxNamesLength = 300

    /// L'amorce bilingue, suivie des noms (« Julie, Marc, Costco. »), sans doublon ni nom d'une lettre.
    public static func make(names: [String]) -> String {
        bilingual
    }

    /// Vrai si Whisper a recopié l'amorce (ou sa liste de noms) au lieu de transcrire la parole.
    static func isEcho(_ text: String, prompt: String) -> Bool {
        isEcho(text)
    }
}
