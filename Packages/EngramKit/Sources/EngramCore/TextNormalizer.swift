import Foundation

/// Formes normalisées du texte, indépendantes de la casse, des accents et de la ponctuation.
public enum TextNormalizer {
    /// Forme canonique d'un nom de catégorie ou de tag : « Voyages d'été » → « voyage d ete ».
    /// Pluriel simple : un « s » final est retiré des mots de plus de 3 lettres (sauf « ss »).
    public static func normalizedName(_ raw: String) -> String {
        words(of: raw).map(singularize).joined(separator: " ")
    }

    /// Forme de comparaison d'un texte : minuscules, sans accents, sans ponctuation, espaces simples.
    public static func matchingForm(_ raw: String) -> String {
        words(of: raw).joined(separator: " ")
    }

    /// `phrase` apparaît-elle dans `text`, mot pour mot, aux limites de mots
    /// (sans tenir compte de la casse, des accents ni de la ponctuation) ?
    public static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let needle = matchingForm(phrase)
        guard !needle.isEmpty else { return false }
        return (" " + matchingForm(text) + " ").contains(" " + needle + " ")
    }

    static func words(of raw: String) -> [String] {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    static func singularize(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }
}
