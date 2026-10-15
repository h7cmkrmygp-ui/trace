import Foundation

/// Nettoyage d'une dictée : les hésitations (« euh », « hum », « mmm ») disparaissent, les vrais mots restent.
/// « Rappelle-moi de euhmmm appeler l'assurance » → « Rappelle-moi d'appeler l'assurance ».
public enum SpeechCleanup {
    /// Mots-outils qu'aucune virgule ne suit : la virgule de « de, euh, appeler » était celle de l'hésitation.
    static let neverBeforeComma: Set<String> = [
        "de", "du", "des", "le", "la", "les", "un", "une", "à", "au", "aux", "pour", "que", "qui", "je", "tu", "il",
        "elle", "on", "nous", "vous", "ils", "elles", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "ce",
        "cette", "et", "me", "te", "se", "ne",
    ]
    /// Mots qui s'élident devant une voyelle, une fois l'hésitation retirée : « de appeler » → « d'appeler ».
    static let elisions: [String: String] = [
        "de": "d'", "je": "j'", "me": "m'", "te": "t'", "se": "s'", "le": "l'", "la": "l'", "ne": "n'", "que": "qu'",
    ]
    static let vowels = Set("aeiouyàâäéèêëîïôöùûüœæ")
    static let sentenceEnds = Set(".?!…")

    public static func removingHesitations(_ text: String) -> String {
        var kept: [String] = []
        var justRemoved = false
        var capitalizeNext = false
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let core = word.trimmingCharacters(in: .punctuationCharacters)
            if isHesitation(core) {
                let startsSentence = kept.last.map { $0.last.map(sentenceEnds.contains) ?? false } ?? true
                if startsSentence, word.first?.isUppercase == true { capitalizeNext = true }
                // La fin de phrase portée par l'hésitation (« euh... », « hum. ») passe au mot d'avant.
                let ending = String(word.reversed().prefix { sentenceEnds.contains($0) }.reversed())
                if !ending.isEmpty, let last = kept.popLast() {
                    kept.append((last.hasSuffix(",") ? String(last.dropLast()) : last) + ending)
                }
                justRemoved = true
                continue
            }
            var current = word
            if capitalizeNext {
                current = current.prefix(1).uppercased() + current.dropFirst()
                capitalizeNext = false
            }
            if justRemoved, var previous = kept.last {
                let previousCore = previous.trimmingCharacters(in: .punctuationCharacters).lowercased()
                if previous.hasSuffix(","), neverBeforeComma.contains(previousCore) { previous.removeLast() }
                if previous.lowercased() == previousCore, let elision = elisions[previousCore],
                   let first = current.lowercased().first, vowels.contains(first) {
                    let prefix = previous.first?.isUppercase == true ? elision.prefix(1).uppercased() + elision.dropFirst() : elision
                    kept[kept.count - 1] = prefix + current
                    justRemoved = false
                    continue
                }
                kept[kept.count - 1] = previous
            }
            kept.append(current)
            justRemoved = false
        }
        return kept.joined(separator: " ")
    }

    /// « euh », « euhmmm », « heu », « hum », « hmm », « mmm », « uh », « um » ; jamais « eu » (« j'ai eu »).
    static func isHesitation(_ word: String) -> Bool {
        word.lowercased()
            .wholeMatch(of: #/e+u+(h+m*|m+)|e{2,}u+h*|e+u{2,}h*|h+e+u+h*|u+h+m*|u+m+|h+m+|m{2,}h*|h+u+m+/#) != nil
    }
}
