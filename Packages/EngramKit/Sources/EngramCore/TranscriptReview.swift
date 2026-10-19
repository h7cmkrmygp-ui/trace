import Foundation

/// F26 — quand une dictée doit passer par « Vérifie ta note » avant d'être classée : toujours si le propriétaire l'a
/// demandé ; sinon seulement si la transcription est incertaine (confiance mesurée sous le seuil) et que son sens dépend
/// d'un mot fragile — une négation, un nombre (« dois/deux »), une date, un prénom ou un nom. Une confiance inconnue
/// (moteur qui ne la donne pas) ne retient pas la note.
public enum TranscriptReview {
    /// En dessous, le modèle hésite (moyenne des log-probabilités du morceau le moins sûr).
    public static let uncertainty = -0.8

    static let fragileWords: Set<String> = [
        "pas", "plus", "jamais", "rien", "aucun", "aucune", "ne", "n", "non", "sans", "dois", "doit", "deux", "trois",
        "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "onze", "douze", "quinze", "vingt", "trente",
        "quarante", "cinquante", "soixante", "cent", "cents", "mille", "lundi", "mardi", "mercredi", "jeudi",
        "vendredi", "samedi", "dimanche", "demain", "hier", "janvier", "fevrier", "mars", "avril", "mai", "juin",
        "juillet", "aout", "septembre", "octobre", "novembre", "decembre", "not", "never", "two", "three", "tomorrow",
    ]

    public static func needsReview(text: String, averageLogProbability: Double?, ownerWantsReview: Bool) -> Bool {
        if ownerWantsReview { return true }
        guard let probability = averageLogProbability, probability < uncertainty else { return false }
        return hasFragileWord(text)
    }

    static func hasFragileWord(_ text: String) -> Bool {
        let words = TextNormalizer.words(of: text.replacingOccurrences(of: "’", with: "'"))
        if words.contains(where: { $0.allSatisfy(\.isNumber) }) || words.contains(where: fragileWords.contains) {
            return true
        }
        // Un nom propre : un mot à majuscule qui ne commence pas une phrase.
        var startsSentence = true
        for piece in text.split(whereSeparator: \.isWhitespace) {
            defer { startsSentence = piece.last.map { ".!?:\n".contains($0) } ?? false }
            guard !startsSentence else { continue }
            let word = piece.split(separator: "'").last.map(String.init) ?? String(piece)
            if let initial = word.first, initial.isUppercase, word.count >= 2 { return true }
        }
        return false
    }
}
