import Foundation

// Banc d'essai de la transcription (Whisper Turbo contre Large V3, et stratégies de langue).
// Tout se calcule sur l'iPhone : les enregistrements du propriétaire ne quittent jamais l'appareil.

/// Taux d'erreur sur les mots (WER) : (substitutions + suppressions + insertions) / mots de la référence.
public enum WordErrorRate {
    /// Mots normalisés : minuscules, ponctuation et apostrophes retirées, accents gardés,
    /// chiffres séparés des lettres (« 14h30 » → « 14 h 30 »).
    public static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        var currentIsDigit: Bool?
        func flush() {
            if !current.isEmpty { result.append(String(current)) }
            current = String.UnicodeScalarView()
            currentIsDigit = nil
        }
        for scalar in text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            let isDigit = CharacterSet.decimalDigits.contains(scalar)
            let isWordPart = isDigit || CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar)
            guard isWordPart else {
                flush()
                continue
            }
            if let kind = currentIsDigit, kind != isDigit { flush() }
            current.append(scalar)
            currentIsDigit = isDigit
        }
        flush()
        return result
    }

    public static func rate(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let produced = words(hypothesis)
        guard !expected.isEmpty else { return produced.isEmpty ? 0 : 1 }
        return Double(errors(reference: expected, hypothesis: produced)) / Double(expected.count)
    }

    /// Distance d'édition entre deux suites de mots.
    public static func errors(reference: [String], hypothesis: [String]) -> Int {
        guard !reference.isEmpty else { return hypothesis.count }
        guard !hypothesis.isEmpty else { return reference.count }
        var previous = Array(0...hypothesis.count)
        for (i, expected) in reference.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: hypothesis.count)
            for (j, produced) in hypothesis.enumerated() {
                let substitution = previous[j] + (expected == produced ? 0 : 1)
                row[j + 1] = min(substitution, previous[j + 1] + 1, row[j] + 1)
            }
            previous = row
        }
        return previous[hypothesis.count]
    }
}

/// Part des mots anglais de la référence retrouvés tels quels (ni traduits, ni francisés).
public enum EnglishRetention {
    public static func rate(englishWords: [String], hypothesis: String) -> Double? {
        guard !englishWords.isEmpty else { return nil }
        var available: [String: Int] = [:]
        for word in WordErrorRate.words(hypothesis) { available[word, default: 0] += 1 }
        var found = 0
        for word in englishWords {
            if let count = available[word], count > 0 {
                found += 1
                available[word] = count - 1
            }
        }
        return Double(found) / Double(englishWords.count)
    }
}

/// Un enregistrement transcrit par la configuration actuelle (« référence ») et par la candidate.
public struct BenchmarkItem: Sendable, Equatable {
    public let referenceWords: Int
    public let baselineErrors: Int
    public let candidateErrors: Int

    public init(referenceWords: Int, baselineErrors: Int, candidateErrors: Int) {
        self.referenceWords = referenceWords
        self.baselineErrors = baselineErrors
        self.candidateErrors = candidateErrors
    }
}

/// WER global des deux configurations et intervalle de confiance à 95 % de la différence (candidate − actuelle).
public struct PairedComparison: Sendable, Equatable {
    public let baselineRate: Double
    public let candidateRate: Double
    public let lower: Double
    public let upper: Double
}

/// Rééchantillonnage apparié : on retire des enregistrements au hasard (avec remise) et on regarde
/// si l'écart entre les deux configurations reste du même côté.
public enum PairedBootstrap {
    public static func compare(_ items: [BenchmarkItem], iterations: Int = 2_000, seed: UInt64 = 42) -> PairedComparison? {
        let totalWords = items.reduce(0) { $0 + $1.referenceWords }
        guard !items.isEmpty, totalWords > 0, iterations > 0 else { return nil }
        let baseline = Double(items.reduce(0) { $0 + $1.baselineErrors }) / Double(totalWords)
        let candidate = Double(items.reduce(0) { $0 + $1.candidateErrors }) / Double(totalWords)
        var generator = SplitMix64(seed: seed)
        var differences: [Double] = []
        differences.reserveCapacity(iterations)
        for _ in 0..<iterations {
            var words = 0
            var difference = 0
            for _ in items.indices {
                let item = items[Int(generator.next() % UInt64(items.count))]
                words += item.referenceWords
                difference += item.candidateErrors - item.baselineErrors
            }
            if words > 0 { differences.append(Double(difference) / Double(words)) }
        }
        guard !differences.isEmpty else { return nil }
        differences.sort()
        return PairedComparison(baselineRate: baseline, candidateRate: candidate,
                                lower: percentile(differences, 0.025), upper: percentile(differences, 0.975))
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }
}

/// Générateur pseudo-aléatoire à graine fixe (résultats reproductibles).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Ce que le banc d'essai a mesuré pour une comparaison (modèle ou stratégie).
public struct BenchmarkEvidence: Sendable, Equatable {
    public let sentencesRead: Int
    public let sentencesTotal: Int
    /// Notes réelles dont le propriétaire a corrigé la transcription (références fiables).
    public let correctedNotes: Int
    public let items: [BenchmarkItem]
    /// La candidate se charge sans erreur de mémoire, transcrit en au plus 1 × temps réel et sans surchauffe sérieuse.
    public let candidateRunsWell: Bool

    public init(sentencesRead: Int, sentencesTotal: Int, correctedNotes: Int, items: [BenchmarkItem], candidateRunsWell: Bool) {
        self.sentencesRead = sentencesRead
        self.sentencesTotal = sentencesTotal
        self.correctedNotes = correctedNotes
        self.items = items
        self.candidateRunsWell = candidateRunsWell
    }
}

/// Règle de la spec P4 (section 11.3) : Engram ne fait que **proposer** un changement, et seulement avec des preuves
/// suffisantes. Le propriétaire valide lui-même.
public enum ModelRecommendation: Sendable, Equatable {
    case needMoreData(String)
    case keepCurrent(String)
    case proposeSwitch(String)

    public static let minimumCorrectedNotes = 20
    public static let minimumAbsoluteGain = 0.02
    public static let minimumRelativeGain = 0.15

    public static func evaluate(_ evidence: BenchmarkEvidence) -> ModelRecommendation {
        if evidence.sentencesRead < evidence.sentencesTotal {
            return .needMoreData("Lis toutes les phrases du jeu d'essai (\(evidence.sentencesRead)/\(evidence.sentencesTotal)).")
        }
        if evidence.correctedNotes < minimumCorrectedNotes {
            let missing = minimumCorrectedNotes - evidence.correctedNotes
            return .needMoreData("Corrige encore \(missing) note\(missing > 1 ? "s" : "") réelle\(missing > 1 ? "s" : "") avec « Vérifie ta note ».")
        }
        guard evidence.candidateRunsWell else {
            return .keepCurrent("L'autre configuration est trop lente ou trop lourde pour cet iPhone.")
        }
        guard let comparison = PairedBootstrap.compare(evidence.items) else {
            return .needMoreData("Aucune comparaison disponible pour l'instant.")
        }
        let gain = comparison.baselineRate - comparison.candidateRate
        let relative = comparison.baselineRate > 0 ? gain / comparison.baselineRate : 0
        let summary = "Erreurs : \(percent(comparison.baselineRate)) contre \(percent(comparison.candidateRate))."
        guard gain >= minimumAbsoluteGain, relative >= minimumRelativeGain, comparison.upper < 0 else {
            return .keepCurrent("Pas de différence nette. \(summary)")
        }
        return .proposeSwitch("Nettement plus précis, avec une marge de confiance suffisante. \(summary)")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}

/// Une phrase du jeu d'essai, lue à voix haute par le propriétaire.
public struct BenchmarkSentence: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case french, english, mixed
    }

    public let id: Int
    public let text: String
    public let kind: Kind
    /// Mots anglais (normalisés) qui doivent rester tels quels ; pour une phrase anglaise, tous ses mots.
    public let englishWords: [String]

    init(_ id: Int, _ kind: Kind, _ text: String, english: [String] = []) {
        self.id = id
        self.text = text
        self.kind = kind
        self.englishWords = kind == .english ? WordErrorRate.words(text) : english
    }
}

/// Phrases fictives et neutres : français québécois, anglais, mélanges dans une même phrase,
/// verbes anglais conjugués en français, nombres et heures, marques, débit rapide.
public enum BilingualTestSet {
    public static let sentences: [BenchmarkSentence] = [
        BenchmarkSentence(1, .french, "Faut que j'aille porter les bouteilles vides au dépanneur avant la fin de semaine."),
        BenchmarkSentence(2, .french, "Pis là, j'ai réalisé que j'avais oublié mes clés dans l'auto."),
        BenchmarkSentence(3, .french, "Il faut rappeler le plombier pour la fuite en dessous de l'évier."),
        BenchmarkSentence(4, .french, "Acheter des pommes, du fromage et une pinte de lait."),
        BenchmarkSentence(5, .french, "Mon idée, c'est de réorganiser le garage par zones cet automne."),
        BenchmarkSentence(6, .french, "Le rendez-vous chez le dentiste est mardi le 17 à 14 h 30."),
        BenchmarkSentence(7, .french, "Payer la facture de 245 $ avant le 3 décembre."),
        BenchmarkSentence(8, .french, "Le vol part à 6 h 45, faut être à l'aéroport à 4 h 30."),
        BenchmarkSentence(9, .english, "Remind me to send the invoice to the client tomorrow morning."),
        BenchmarkSentence(10, .english, "I need to book a table for four people on Saturday night."),
        BenchmarkSentence(11, .english, "The meeting got moved to Thursday at two thirty."),
        BenchmarkSentence(12, .english, "Pick up the dry cleaning and grab some coffee beans."),
        BenchmarkSentence(13, .english, "Let's try the new hiking trail next weekend."),
        BenchmarkSentence(14, .english, "Call the bank at nine fifteen about the transfer."),
        BenchmarkSentence(15, .mixed, "Faut que je call mon manager demain pour changer mon shift.", english: ["call", "manager", "shift"]),
        BenchmarkSentence(16, .mixed, "J'ai un meeting à dix heures, pis après je vais au gym.", english: ["meeting", "gym"]),
        BenchmarkSentence(17, .mixed, "Peux-tu checker si le dossier est ready pour lundi?", english: ["checker", "ready"]),
        BenchmarkSentence(18, .mixed, "Je vais booker le rendez-vous pour le check-up de l'auto.", english: ["booker", "check", "up"]),
        BenchmarkSentence(19, .mixed, "On a un deadline serré, faque on va rusher un peu cette semaine.", english: ["deadline", "rusher"]),
        BenchmarkSentence(20, .mixed, "Le feedback du client était super positif sur le design.", english: ["feedback", "design"]),
        BenchmarkSentence(21, .mixed, "J'ai downloadé l'app, mais le login marche pas.", english: ["downloadé", "app", "login"]),
        BenchmarkSentence(22, .mixed, "Faut que je cancel mon abonnement avant la fin du trial.", english: ["cancel", "trial"]),
        BenchmarkSentence(23, .mixed, "Je suis full occupé aujourd'hui, on se parle tomorrow.", english: ["full", "tomorrow"]),
        BenchmarkSentence(24, .mixed, "Mets ça dans le budget, c'est un must pour le projet.", english: ["must"]),
        BenchmarkSentence(25, .mixed, "So basically, faut juste updater le fichier pis le renvoyer.", english: ["so", "basically", "updater"]),
        BenchmarkSentence(26, .mixed, "Le show commence à huit heures, on se rejoint au parking.", english: ["show", "parking"]),
        BenchmarkSentence(27, .mixed, "J'ai parké le char en avant du building.", english: ["parké", "building"]),
        BenchmarkSentence(28, .mixed, "C'est vraiment cute, le petit café sur la rue principale.", english: ["cute"]),
        BenchmarkSentence(29, .mixed, "I will handle the slides, toi tu fais la démo.", english: ["i", "will", "handle", "the", "slides"]),
        BenchmarkSentence(30, .mixed, "Anyway, on verra ça au prochain call.", english: ["anyway", "call"]),
        BenchmarkSentence(31, .mixed, "Faut scheduler une rencontre avec l'équipe marketing.", english: ["scheduler", "marketing"]),
        BenchmarkSentence(32, .mixed, "J'ai trouvé ça vraiment le fun, le souper chez les voisins.", english: ["fun"]),
        BenchmarkSentence(33, .mixed, "Acheter des AirPods pour remplacer ceux que j'ai perdus.", english: ["airpods"]),
        BenchmarkSentence(34, .mixed, "Regarder la nouvelle série sur Netflix ce soir.", english: ["netflix"]),
        BenchmarkSentence(35, .mixed, "Commander les pièces sur Amazon pour la Corolla.", english: ["amazon", "corolla"]),
        BenchmarkSentence(36, .mixed, "Mettre à jour Spotify pis Google Maps sur mon téléphone.", english: ["spotify", "google", "maps"]),
        BenchmarkSentence(37, .mixed, "Ok faque demain matin faut que je passe au bureau, prendre les papiers, pis revenir avant midi.", english: ["ok"]),
        BenchmarkSentence(38, .mixed, "Oublie pas, le party de bureau c'est samedi, faut amener le dessert.", english: ["party"]),
        BenchmarkSentence(39, .mixed, "Bon, j'ai pas le temps là, mais rappelle-moi de texter le coach ce soir.", english: ["texter", "coach"]),
        BenchmarkSentence(40, .mixed, "Le wifi marche pas, faut que je reset le router.", english: ["wifi", "reset", "router"]),
    ]
}
