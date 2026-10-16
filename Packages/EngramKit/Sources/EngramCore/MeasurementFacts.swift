import Foundation

/// F15 — une mesure lue dans une note n'est un fait du propriétaire que si la proposition qui la porte est affirmée,
/// actuelle et dite par lui (« je », ou sans sujet : « Poids : 74 kg ») : ni à propos d'un tiers (« mon frère pèse »,
/// « Julie a dormi »), ni niée, ni ancienne (« je pesais »), ni souhaitée (« je voudrais peser »), ni supposée, ni
/// demandée, ni rapportée. Ce sont des formes de la langue, pas des mots d'un sujet de vie.
extension MeasurementParser {
    static let firstPerson: Set<String> = ["je", "j", "i", "moi", "me", "m", "ai", "suis"]
    static let ownPossessives: Set<String> = ["mon", "ma", "mes", "my"]
    static let possessives: Set<String> = ownPossessives.union(["ton", "ta", "tes", "son", "sa", "ses", "notre", "nos",
                                                                "votre", "vos", "leur", "leurs", "his", "her", "their",
                                                                "your"])
    static let thirdPronouns: Set<String> = ["il", "elle", "ils", "elles", "lui", "eux", "he", "she", "they"]
    /// Ce qui se mesure : un possessif devant l'un d'eux reste la mesure du propriétaire (« mon poids »).
    static let metricNouns: Set<String> = [
        "poids", "balance", "pesee", "tension", "pression", "sommeil", "nuit", "pouls", "coeur", "frequence", "rythme",
        "cardiaque", "glycemie", "sucre", "taux", "pas", "podometre", "montre", "weight", "scale", "pressure", "sleep",
        "pulse", "heart", "rate", "blood", "steps",
    ]
    static let aspirations: Set<String> = [
        "voudrais", "veux", "voulais", "aimerais", "souhaite", "souhaiterais", "vise", "viser", "dois", "devrais",
        "objectif", "but", "cible", "espere", "want", "wish", "goal", "should", "hope",
    ]
    /// Un verbe de mesure : son sujet doit être le propriétaire (ou absent).
    static let measureVerbs: Set<String> = ["pese", "weigh", "weighs", "dormi", "slept"]
    /// Un temps passé de durée (« je pesais ») : un ancien fait, pas la mesure du jour.
    static let pastForms: Set<String> = ["pesais", "pesait", "pesaient", "weighed", "dormais", "dormait"]
    static let timeWords: Set<String> = ["ce", "cette", "matin", "soir", "midi", "nuit", "hier", "avant", "aujourd",
                                         "hui", "la", "le", "semaine", "journee", "today", "this", "morning", "tonight",
                                         "yesterday"]

    /// La proposition (coupée sur . ! ? ; et les retours à la ligne) qui contient `position`, avec sa ponctuation
    /// finale, et ses bornes ; « 8 000 pas » y devient « 8 000 » (l'unité des pas n'est pas une négation).
    static func sentence(_ folded: String, around position: Int) -> (text: String, start: Int, end: Int) {
        let source = folded as NSString
        let stops = CharacterSet(charactersIn: ".!?;\n")
        func isStop(_ index: Int) -> Bool {
            UnicodeScalar(source.character(at: index)).map { stops.contains($0) } ?? false
        }
        var start = min(position, source.length)
        while start > 0, !isStop(start - 1) { start -= 1 }
        var end = min(position, source.length)
        while end < source.length, !isStop(end) { end += 1 }
        let raw = source.substring(with: NSRange(location: start, length: min(end + 1, source.length) - start))
        let text = (try? NSRegularExpression(pattern: #"(\d)\s*(?:k\s*)?(?:pas|steps)\b"#))
            .map { $0.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length),
                                               withTemplate: "$1") } ?? raw
        return (text, start, end)
    }

    static func isOwnersFact(_ folded: String, at position: Int) -> Bool {
        let source = folded as NSString
        let (clause, start, end) = sentence(folded, around: position)
        guard LinguisticGuards.inspect(clause).isPlainRequest else { return false }
        let before = TextNormalizer.words(of: source.substring(with: NSRange(location: start, length: position - start)))
        let rest = TextNormalizer.words(of: source.substring(with: NSRange(location: position, length: end - position)))
        guard let keyword = rest.first else { return false }
        // « je pesais », « je voudrais peser » : un ancien poids, un souhait.
        if pastForms.contains(keyword) || keyword == "peser" { return false }
        if before.contains(where: aspirations.contains) || before.contains(where: thirdPronouns.contains) { return false }
        // « mon frère pèse », « la tension de mon père », « sa tension » : quelqu'un d'autre.
        let words = before + rest
        for (index, word) in words.enumerated() where possessives.contains(word) {
            guard ownPossessives.contains(word), index + 1 < words.count, metricNouns.contains(words[index + 1]) else {
                return false
            }
        }
        // « le poids de Julie ».
        if metricNouns.contains(keyword), rest.count > 2, ["de", "d", "du"].contains(rest[1]), Double(rest[2]) == nil,
           !metricNouns.contains(rest[2]), !timeWords.contains(rest[2]), !possessives.contains(rest[2]) {
            return false
        }
        // « Julie pèse », « Julie a dormi » : le sujet du verbe n'est pas le propriétaire.
        if measureVerbs.contains(keyword), let subject = before.last(where: { !timeWords.contains($0) }),
           !firstPerson.contains(subject) {
            return false
        }
        return true
    }
}
