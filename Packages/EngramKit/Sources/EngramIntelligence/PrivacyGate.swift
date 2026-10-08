import EngramCore
import Foundation
import NaturalLanguage

// Contrôleur de confidentialité : il décide, **sur l'iPhone**, où une note peut être classée.
// neutre → Gemini (palier gratuit : Google peut lire et entraîner) ; personnel → Groq (aucun entraînement) ;
// secret → iPhone seulement. Les mots-clés ne peuvent que monter le niveau ; le doute va toujours vers le plus protégé.

/// Verdict du modèle d'Apple sur l'iPhone (`unsure` : il ne sait pas).
public enum PrivacyVerdict: String, Sendable, Equatable, CaseIterable {
    case neutral, personal, secret, unsure
}

public struct PrivacyJudgement: Sendable, Equatable {
    public let verdict: PrivacyVerdict
    public let reason: String

    public init(verdict: PrivacyVerdict, reason: String) {
        self.verdict = verdict
        self.reason = reason
    }
}

/// Jugement sémantique de la confidentialité (le modèle d'Apple dans l'app, un faux juge dans les tests).
public protocol PrivacyJudge: Sendable {
    func judge(_ text: String) async throws -> PrivacyJudgement
}

/// Un indice trouvé dans le texte, avec son explication pour le propriétaire.
public struct PrivacySignal: Sendable, Equatable {
    public let level: PrivacyLevel
    public let reason: String
}

public struct PrivacyDecision: Sendable, Equatable {
    public let level: PrivacyLevel
    /// Pourquoi (affiché sur la note).
    public let reasons: [String]
}

public enum PrivacyGate {
    public static func evaluate(_ text: String, keepLocal: Bool, healthStaysLocal: Bool,
                                judge: (any PrivacyJudge)?) async -> PrivacyDecision {
        if keepLocal {
            return PrivacyDecision(level: .secret, reasons: ["Tu as choisi « Garder sur l'iPhone »."])
        }
        let signals = SensitiveDetectors.signals(in: text) + SensitiveLexicon.signals(in: text, healthStaysLocal: healthStaysLocal)
        var level = signals.map(\.level).max() ?? .neutral
        var reasons = signals.map(\.reason)
        // Déjà secret : inutile de demander l'avis du modèle.
        guard level < .secret else { return PrivacyDecision(level: .secret, reasons: unique(reasons)) }

        let judgement: PrivacyJudgement?
        if let judge { judgement = try? await judge.judge(text) } else { judgement = nil }
        switch judgement?.verdict {
        case nil:
            level = .secret
            reasons.append("L'IA d'Apple n'a pas pu vérifier la confidentialité : la note reste sur l'iPhone.")
        case .unsure?:
            level = .secret
            reasons.append("Doute sur la confidentialité : la note reste sur l'iPhone.")
        case .secret?:
            level = .secret
            reasons.append(judgement?.reason ?? "Information secrète.")
        case .personal?:
            level = max(level, .personal)
            reasons.append(judgement?.reason ?? "Information personnelle.")
        case .neutral?:
            break
        }
        if level == .neutral && reasons.isEmpty { reasons = ["Aucune information personnelle détectée."] }
        return PrivacyDecision(level: level, reasons: unique(reasons))
    }

    /// Noms de catégories qu'on peut joindre à une requête : ceux qui ne contiennent ni coordonnées, ni numéros, ni montants.
    public static func shareableCategoryNames(_ names: [String]) -> [String] {
        names.filter { SensitiveDetectors.signals(in: $0, includeNames: false).isEmpty }
    }

    /// Pour Gemini (palier gratuit) : seulement les grandes catégories (« Santé », « Maison »), jamais les
    /// sous-catégories, qui peuvent porter un nom propre (« Famille › Julie »), ni un nom de personne.
    public static func neutralCategoryNames(_ names: [String]) -> [String] {
        var roots: [String] = []
        for name in shareableCategoryNames(names) {
            let root = name.components(separatedBy: "›").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !root.isEmpty, !roots.contains(root), !SensitiveDetectors.containsPersonName(root) else { continue }
            roots.append(root)
        }
        return roots
    }

    static func unique(_ reasons: [String]) -> [String] {
        var seen: Set<String> = []
        return reasons.filter { seen.insert($0).inserted }
    }
}

// MARK: - Détecteurs déterministes

/// Coordonnées, numéros, montants, codes et noms propres. Ne déclarent jamais une note « neutre ».
public enum SensitiveDetectors {
    public static func signals(in text: String, includeNames: Bool = true) -> [PrivacySignal] {
        var signals: [PrivacySignal] = []
        let folded = SensitiveLexicon.fold(text)
        let tokens = WordErrorRate.words(folded)

        if SensitiveLexicon.containsAny(tokens, of: credentialWords) {
            signals.append(PrivacySignal(level: .secret, reason: "Mot de passe, NIP ou code."))
        }
        let digitRuns = Self.digitRuns(in: text)
        if digitRuns.contains(where: { (13...19).contains($0.count) && isLuhnValid($0) }) {
            signals.append(PrivacySignal(level: .secret, reason: "Numéro de carte."))
        }
        if digitRuns.contains(where: { $0.count == 9 && isLuhnValid($0) }) {
            signals.append(PrivacySignal(level: .secret, reason: "Numéro d'assurance sociale possible."))
        }
        if matches(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,30}\b"#, in: text, caseInsensitive: false) {
            signals.append(PrivacySignal(level: .secret, reason: "Numéro IBAN."))
        }
        if SensitiveLexicon.containsAny(tokens, of: accountWords), digitRuns.contains(where: { $0.count >= 5 }) {
            signals.append(PrivacySignal(level: .secret, reason: "Numéro de compte."))
        }
        if digitRuns.contains(where: { $0.count >= 7 }) {
            signals.append(PrivacySignal(level: .personal, reason: "Long numéro."))
        }
        if matches(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: text, caseInsensitive: true) {
            signals.append(PrivacySignal(level: .personal, reason: "Adresse courriel."))
        }
        if matches(#"(\d[\d .,]*\s?(\$|€|£|(dollars?|piasses?|bucks|cents?)\b))|(\$\s?\d)"#, in: text, caseInsensitive: true) {
            signals.append(PrivacySignal(level: .personal, reason: "Montant d'argent."))
        }
        signals += dataDetectorSignals(in: text)
        if includeNames { signals += nameSignals(in: text) }
        return signals
    }

    static let credentialWords: [String] = [
        "mot de passe", "mots de passe", "mdp", "password", "passwords", "passcode", "nip", "pin", "code d acces",
        "code secret", "code de securite", "code de la porte", "code de porte", "code du coffre", "code de l alarme",
        "combinaison du cadenas", "cvv", "cvc",
    ]

    static let accountWords: [String] = ["compte", "account", "transit", "folio", "institution"]

    /// Suites de chiffres (espaces et tirets internes permis), sans les séparateurs.
    static func digitRuns(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\d(?:[ -]?\d)*"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { text[$0].filter(\.isNumber) }
        }
    }

    /// Contrôle de Luhn (cartes de crédit, NAS canadien).
    public static func isLuhnValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 2 else { return false }
        var sum = 0
        for (index, value) in values.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }

    static func matches(_ pattern: String, in text: String, caseInsensitive: Bool) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func dataDetectorSignals(in text: String) -> [PrivacySignal] {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .address, .link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        var signals: [PrivacySignal] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            switch match.resultType {
            case .phoneNumber: signals.append(PrivacySignal(level: .personal, reason: "Numéro de téléphone."))
            case .address: signals.append(PrivacySignal(level: .personal, reason: "Adresse."))
            case .link where match.url?.scheme == "mailto": signals.append(PrivacySignal(level: .personal, reason: "Adresse courriel."))
            default: break
            }
        }
        return signals
    }

    /// Vrai si un nom de personne apparaît (pour un nom court comme une catégorie, sans ignorer le premier mot).
    static func containsPersonName(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, _ in
            if tag == .personalName { found = true }
            return !found
        }
        return found
    }

    /// Noms de personnes, de lieux et d'organisations. Le premier mot de chaque phrase est ignoré
    /// (une majuscule de début de phrase n'est pas un nom propre).
    static func nameSignals(in text: String) -> [PrivacySignal] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var sentenceStarts: Set<String.Index> = [text.startIndex]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .nameType, options: []) { _, range in
            if let first = text[range].firstIndex(where: { $0.isLetter }) { sentenceStarts.insert(first) }
            return true
        }
        var signals: [PrivacySignal] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            guard let tag, !sentenceStarts.contains(range.lowerBound), text[range].count > 1 else { return true }
            switch tag {
            case .personalName: signals.append(PrivacySignal(level: .personal, reason: "Nom de personne."))
            case .placeName: signals.append(PrivacySignal(level: .personal, reason: "Nom de lieu."))
            case .organizationName: signals.append(PrivacySignal(level: .personal, reason: "Nom d'organisation."))
            default: break
            }
            return true
        }
        return signals
    }
}

// MARK: - Lexique des domaines sensibles

/// Domaines sensibles en français et en anglais. Un mot du lexique **monte** le niveau (personnel, ou secret
/// pour l'identité) ; il ne rend jamais une note neutre. Comparaison sur des mots entiers, sans accents.
public enum SensitiveLexicon {
    enum Domain: CaseIterable {
        case health, money, work, family, legal, beliefs, identity

        var reason: String {
            switch self {
            case .health: "Santé."
            case .money: "Argent personnel."
            case .work: "Travail."
            case .family: "Famille ou relations."
            case .legal: "Questions juridiques."
            case .beliefs: "Opinions ou croyances."
            case .identity: "Pièce d'identité."
            }
        }

        var words: [String] {
            switch self {
            case .health:
                ["sante", "medecin", "docteur", "dentiste", "hopital", "clinique", "pharmacie", "pharmacien",
                 "medicament", "medicaments", "pilule", "pilules", "ordonnance", "prescription", "poids", "pese", "peser",
                 "pesee", "calories", "regime", "diete", "anxiete", "depression", "therapie", "therapeute", "psy",
                 "psychologue", "psychiatre", "maladie", "malade", "douleur", "symptome", "symptomes", "diabete", "cancer",
                 "grossesse", "enceinte", "physio", "chiro", "vaccin", "prise de sang", "pression arterielle",
                 "tension arterielle", "sommeil", "gym", "entrainement", "doctor", "dentist", "hospital", "pharmacy",
                 "medication", "pills", "weight", "therapy", "sick", "blood pressure", "workout"]
            case .money:
                ["argent", "salaire", "paie", "paye", "revenu", "revenus", "dette", "dettes", "pret", "hypotheque",
                 "banque", "bancaire", "carte de credit", "budget", "impot", "impots", "taxes", "facture", "factures",
                 "loyer", "placement", "placements", "investissement", "reer", "celi", "crypto", "bitcoin", "epargne",
                 "salary", "debt", "loan", "mortgage", "bank", "rent", "invoice", "paycheck"]
            case .work:
                ["patron", "patronne", "boss", "manager", "gerant", "gerante", "superviseur", "superviseure", "employeur",
                 "collegue", "collegues", "conge", "conges", "augmentation", "evaluation", "contrat", "shift",
                 "quart de travail", "rh", "ressources humaines", "demission", "congediement", "coworker", "job"]
            case .family:
                ["ma femme", "mon mari", "ma blonde", "mon chum", "mon conjoint", "ma conjointe", "mon fils", "ma fille",
                 "mes enfants", "mon enfant", "ma mere", "mon pere", "ma soeur", "mon frere", "mes parents", "ma famille",
                 "famille", "divorce", "separation", "rupture", "couple", "amoureux", "amoureuse", "sexe", "sexuel",
                 "sexuelle", "ma grand mere", "mon grand pere", "my wife", "my husband", "my girlfriend", "my boyfriend"]
            case .legal:
                ["avocat", "avocate", "notaire", "tribunal", "proces", "police", "amende", "contravention", "plainte",
                 "poursuite", "lawyer", "lawsuit"]
            case .beliefs:
                ["religion", "eglise", "mosquee", "synagogue", "priere", "politique", "voter", "syndicat",
                 "orientation sexuelle", "gai", "gay", "lesbienne"]
            case .identity:
                ["passeport", "permis de conduire", "nas", "assurance sociale", "carte soleil", "ramq",
                 "acte de naissance", "date de naissance", "passport", "social insurance", "driver s license"]
            }
        }
    }

    public static func signals(in text: String, healthStaysLocal: Bool) -> [PrivacySignal] {
        let tokens = WordErrorRate.words(fold(text))
        var signals: [PrivacySignal] = []
        for domain in Domain.allCases where containsAny(tokens, of: domain.words) || (domain == .health && mentionsBodyWeight(text)) {
            let level: PrivacyLevel = domain == .identity || (domain == .health && healthStaysLocal) ? .secret : .personal
            signals.append(PrivacySignal(level: level, reason: domain.reason))
        }
        return signals
    }

    /// « 75 kg », « 162,5 livres », « 160 lbs » : un poids, jamais des livres à lire.
    static func mentionsBodyWeight(_ text: String) -> Bool {
        SensitiveDetectors.matches(#"\d+([.,]\d+)?\s*(kg|kgs|kilos?|kilogrammes?|lb|lbs|livres|pounds)\b"#, in: text, caseInsensitive: true)
    }

    /// Minuscules et sans accents.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA"))
    }

    /// Vrai si l'un des mots ou groupes de mots (déjà sans accents) apparaît en entier dans `tokens`.
    static func containsAny(_ tokens: [String], of entries: [String]) -> Bool {
        let single = Set(tokens)
        for entry in entries {
            let parts = WordErrorRate.words(entry)
            if parts.count == 1 {
                if single.contains(parts[0]) { return true }
            } else if parts.count > 1, tokens.count >= parts.count {
                for start in 0...(tokens.count - parts.count) where Array(tokens[start..<(start + parts.count)]) == parts {
                    return true
                }
            }
        }
        return false
    }
}
