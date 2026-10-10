import Foundation

/// Les deux grands modèles Whisper pris en charge sur la puce A19 (table officielle d'Argmax).
public enum WhisperModel: String, CaseIterable, Identifiable, Sendable {
    /// Whisper Large V3 Turbo d'OpenAI (décodeur de 4 couches) : plusieurs fois plus rapide, précision proche.
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_626MB"
    /// Whisper Large V3 complet (décodeur de 32 couches) : le plus précis, plus lent.
    case largeV3 = "openai_whisper-large-v3_947MB"

    public static let `default` = WhisperModel.largeV3Turbo

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .largeV3Turbo: "Large V3 Turbo (rapide)"
        case .largeV3: "Large V3 (précision maximale)"
        }
    }

    public var approximateSizeMB: Int {
        switch self {
        case .largeV3Turbo: 626
        case .largeV3: 947
        }
    }

    /// Nom enregistré dans `source.transcription_engine`.
    public var engineName: String {
        switch self {
        case .largeV3Turbo: "whisperkit-large-v3-turbo"
        case .largeV3: "whisperkit-large-v3"
        }
    }
}

/// Langue(s) dans laquelle décoder un morceau de parole. Le français n'est jamais imposé :
/// seule une langue nettement dominante (français ou anglais) est décodée seule, sinon on décode les deux.
public enum LanguagePlan: Equatable, Sendable {
    case single(String)
    case both

    public static let supportedLanguages = ["fr", "en"]
    /// Probabilité à partir de laquelle la langue détectée est jugée dominante.
    public static let dominance = 0.85

    /// `detected` et `probability` : la langue la plus probable selon Whisper, et sa probabilité.
    public static func decide(detected: String, probability: Double) -> LanguagePlan {
        guard supportedLanguages.contains(detected), probability >= dominance else { return .both }
        return .single(detected)
    }

    /// WhisperKit renvoie une log-probabilité ; une valeur absente ou invalide compte pour 0.
    public static func probability(fromLog value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(1, max(0, exp(value)))
    }

    public var languages: [String] {
        switch self {
        case .single(let language): [language]
        case .both: Self.supportedLanguages
        }
    }
}

/// Façon de choisir la langue de chaque morceau de parole. Le banc d'essai compare les trois ;
/// le propriétaire valide lui-même un éventuel changement.
public enum TranscriptionStrategy: String, CaseIterable, Identifiable, Sendable {
    /// Langue dominante si elle est nette, sinon double décodage français et anglais (par défaut).
    case bilingual
    /// Toujours en français (les mots anglais restent souvent tels quels, mais une phrase anglaise peut être traduite).
    case frenchOnly = "french"
    /// Détection libre de Whisper, sans double décodage.
    case automatic

    public static let `default` = TranscriptionStrategy.bilingual

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bilingual: "Bilingue (par défaut)"
        case .frenchOnly: "Français imposé"
        case .automatic: "Détection libre"
        }
    }

    /// Plan fixe, sans détection de langue ; nil quand il dépend de chaque morceau.
    public var fixedPlan: LanguagePlan? {
        self == .frenchOnly ? .single("fr") : nil
    }
}

/// Un décodage d'un morceau de parole dans une langue.
public struct Hypothesis: Equatable, Sendable {
    public let language: String
    public let text: String
    /// Moyenne des log-probabilités des segments (plus c'est haut, plus le modèle est sûr).
    public let averageLogProbability: Double

    public init(language: String, text: String, averageLogProbability: Double) {
        self.language = language
        self.text = text
        self.averageLogProbability = averageLogProbability
    }
}

/// Amorce donnée à Whisper : du français québécois parlé, des mots anglais gardés tels quels, une ponctuation soignée.
/// Elle oriente le style sans jamais être ajoutée au texte. Elle ne doit ressembler à rien que le propriétaire dirait
/// vraiment : une dictée identique à l'amorce est prise pour un écho et jetée (c'était arrivé avec sa phrase d'exemple).
public enum WhisperPrompt {
    public static let bilingual = "Bon ben, faque j'ai checké mes courriels pis j'ai booké le meeting avec l'équipe pour jeudi. OK, sounds good, see you then."

    /// Vrai si Whisper a recopié l'amorce (cela arrive sur un silence) au lieu de transcrire la parole.
    static func isEcho(_ text: String) -> Bool {
        let spoken = normalized(text)
        guard !spoken.isEmpty else { return false }
        let prompt = normalized(bilingual)
        let sentences = bilingual.split(separator: ".").map { normalized(String($0)) }.filter { !$0.isEmpty }
        return spoken.contains(prompt) || sentences.contains(spoken)
    }

    static func normalized(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}

public enum HypothesisPicker {
    /// L'hypothèse dont le modèle est le plus sûr, parmi celles qui contiennent vraiment de la parole.
    /// À égalité, le français l'emporte (langue principale du propriétaire).
    public static func best(_ hypotheses: [Hypothesis]) -> Hypothesis? {
        hypotheses
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !WhisperPrompt.isEcho($0.text) }
            .max { lhs, rhs in
                if lhs.averageLogProbability != rhs.averageLogProbability {
                    return lhs.averageLogProbability < rhs.averageLogProbability
                }
                return lhs.language != "fr" && rhs.language == "fr"
            }
    }
}

public enum TranscriptAssembler {
    /// Assemble les morceaux dans l'ordre ; la langue indiquée est « fr », « en » ou « fr+en ».
    public static func assemble(_ pieces: [Hypothesis]) -> Transcript {
        let spoken = pieces.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var languages: [String] = []
        for piece in spoken where !languages.contains(piece.language) { languages.append(piece.language) }
        return Transcript(text: spoken.map(\.text).joined(separator: " "), localeIdentifier: languages.joined(separator: "+"))
    }
}
