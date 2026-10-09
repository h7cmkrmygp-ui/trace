#if canImport(FoundationModels)
import EngramCore
import Foundation
import FoundationModels

// MARK: - Sortie guidée du modèle

@Generable
struct GeneratedThoughts {
    @Guide(description: "One item per distinct subject of the note, in the order they appear. A sentence about a single subject is ONE item.")
    var thoughts: [GeneratedThought]
}

@Generable
struct GeneratedThought {
    @Guide(description: "Clear, natural French title with only the essential, the action first (« Appeler l'assurance »), English and slang words translated (call → appeler, shift → quart de travail), at most 8 words, never « aujourd'hui » or « demain ».")
    var title: String
    @Guide(description: "The note itself, written in clear French as in Apple Notes, every fact kept, no hesitation, the real date instead of « aujourd'hui » or « demain ». Several steps: one per line starting with « ☐ ». Empty if the title says it all.")
    var summary: String
    @Guide(description: "The exact words of the note that express this item, copied verbatim, never rephrased or translated.")
    var excerpt: String
    var kind: GeneratedKind
    @Guide(description: "Up to 3 short tags in French.", .maximumCount(3))
    var tags: [String]
    @Guide(description: "Date or time expressions copied from the note, e.g. « demain », « 24 novembre ». Put the reminder date first; for an appointment, put its own date and time first.")
    var mentionedDates: [String]
    @Guide(description: "Broad life domain in French, 1 to 3 words (Santé, Travail, Finance, Maison, Famille, Automobile, Achats, Alimentation, Loisirs, Sport, Voyages, Études, Projets…). Reuse an existing category name exactly when one fits.")
    var category: String
    @Guide(description: "If the category is new: one short French sentence describing what it will contain. Otherwise empty.")
    var categoryDescription: String
    @Guide(description: "Precise, lasting topic inside the category, in French, 1 to 3 words (Finance › Assurances, Travail › Horaire, Santé › Poids, Sport › Gym, Maison › Entretien, Automobile › Corolla). Reuse an existing subcategory exactly when one fits. Empty only when no lasting topic fits.")
    var subcategory: String
    @Guide(description: "People this item involves, copied from the note: first names or names (« Julie »), or words for a specific person in the owner's life (« maman », « mon manager »). Never « je », « moi » or « quelqu'un ». Empty if nobody is named.", .maximumCount(4))
    var people: [String]
    @Guide(description: "Specific places this item involves, copied from the note (« Costco », « le gym », « le bureau »). Never a vague place. Empty if none.", .maximumCount(4))
    var places: [String]
}

@Generable
enum GeneratedKind {
    case idea, task, appointment, decision, preference, info, other
}

// MARK: - Consignes versionnées

enum AnalysisPrompt {
    static let version = "p9-v1"

    static let instructions = """
        You are the filing engine of a personal memory app running on the owner's iPhone.
        The owner dictates or types notes in Québec French, often mixed with English words. Ignore hesitations (« euh », « hum »).
        Understand the whole meaning of the note before filing it; never file by keywords alone.
        Create one item per distinct subject or action. One sentence can hold two: « faut que je call mon manager demain \
        pour changer mon shift, pis après je vais au gym » is two tasks, « Appeler mon gestionnaire pour changer mon \
        quart de travail » and « Aller au gym », both for « demain ».
        But never split a request about one subject: a reminder about the same thing stays in the same item. In \
        "rappelle-moi de réserver la salle le 24 novembre, rappelle-moi ça demain" there is ONE item, a task, and \
        « demain » is its reminder date.
        Two unrelated subjects, such as "appeler le garage pour les pneus, pis acheter du lait", are two items.
        For each item:
        - excerpt: the exact words of the note, copied verbatim, never rephrased or translated.
        - title and summary: clear, natural French without hesitation, English and slang words translated, and the \
        real date instead of « aujourd'hui » or « demain ».
        - kind: task (something to do), appointment (something at a given time or place), idea, decision, preference, \
        info (a fact to remember, such as a measurement), other.
        - category: a broad life domain written in French. Reuse an existing category exactly when one fits.
        A body measurement, such as a weight in kg or in pounds (« livres »), belongs to Santé, never to Finance or Rendez-vous.
        Money spent, owed or earned belongs to Finance.
        - categoryDescription: only when the category is new, one short French sentence describing it.
        - subcategory: a precise, lasting topic inside the category that will gather several notes; reuse an existing one.
        - mentionedDates: an item that follows another one in time (« pis après ») also gets that item's date expression.
        - people and places: the named people and the specific places of the item, copied from the note; never « je » or « moi ».
        Never invent facts, dates or names that are not in the note.
        """

    static func prompt(text: String, categories: [String], likely: [String], today: String? = nil,
                       facts: [String] = []) -> String {
        let existing = categories.isEmpty ? "(none yet)" : categories.map { "- \($0)" }.joined(separator: "\n")
        let hint = likely.isEmpty ? "" : "\nMost likely existing categories for this note: \(likely.joined(separator: ", "))\n"
        let date = today.map { "Today: \($0)\n" } ?? ""
        return """
            \(date)Existing categories ("Parent › Child" means a subcategory):
            \(existing)
            \(hint)
            Note to file:
            \(text)
            """
    }
}

// MARK: - Analyseur

/// Analyse des pensées par le modèle d'Apple, **sur l'iPhone** (aucun envoi sur Internet).
/// Il classe les notes secrètes et sert de secours quand les services en ligne ne répondent pas.
public struct AppleThoughtAnalyzer: MemoryAnalyzer {
    public static let promptVersion = AnalysisPrompt.version
    static let maxChunkLength = 2_500
    /// Nombre de catégories proches du sens de la note données en indice au modèle.
    static let hintCount = 5

    let embedder: any SentenceEmbedder

    public init(embedder: any SentenceEmbedder = AppleSentenceEmbedder()) {
        self.embedder = embedder
    }

    /// État lisible du modèle, pour les Réglages.
    public static func availabilityDescription() -> (isAvailable: Bool, text: String) {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return (true, "Disponible sur cet iPhone") }
        return (false, describe(availability))
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories, context: AnalysisContext())
    }

    /// Le jour de la dictée est donné au modèle : il écrit la vraie date plutôt que « aujourd'hui ».
    public func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else { throw AnalyzerError.unavailable(Self.describe(availability)) }
        let likely = Array(CategoryHints.rank(text: text, categories: existingCategories, embedder: embedder).prefix(Self.hintCount))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        let today = formatter.string(from: context.capturedAt)
        var thoughts: [AnalyzedThought] = []
        for chunk in TextChunker.chunks(of: text, maxLength: Self.maxChunkLength) {
            thoughts += try await analyze(chunk: chunk, existingCategories: existingCategories, likely: likely, today: today,
                                          depth: 0)
        }
        return ThoughtAnalysis(thoughts: thoughts)
    }

    func analyze(chunk: String, existingCategories: [String], likely: [String], today: String?,
                 depth: Int) async throws -> [AnalyzedThought] {
        let session = LanguageModelSession(instructions: AnalysisPrompt.instructions)
        do {
            let response = try await session.respond(
                to: AnalysisPrompt.prompt(text: chunk, categories: existingCategories, likely: likely, today: today),
                generating: GeneratedThoughts.self)
            return response.content.thoughts.map(Self.convert)
        } catch let error as LanguageModelError {
            // iOS 27 : `LanguageModelError` remplace `LanguageModelSession.GenerationError`.
            switch error {
            case .contextSizeExceeded where depth < 3:
                return try await analyzeInHalves(chunk, existingCategories: existingCategories, likely: likely, today: today,
                                                 depth: depth)
            case .unsupportedLanguageOrLocale, .guardrailViolation, .refusal:
                // Problème propre à cette note : repli pour elle seule (ne bloque pas les suivantes).
                throw AnalyzerError.refused
            case .rateLimited, .timeout:
                throw AnalyzerError.busy
            default:
                throw AnalyzerError.invalidOutput
            }
        } catch {
            // Autres erreurs (ressources du modèle absentes, anciennes erreurs) : reconnues par leur description.
            let name = String(describing: error)
            if name.localizedCaseInsensitiveContains("assetsUnavailable") {
                throw AnalyzerError.unavailable("Le modèle d'Apple Intelligence se télécharge encore.")
            }
            if name.localizedCaseInsensitiveContains("exceededContextWindowSize"), depth < 3 {
                return try await analyzeInHalves(chunk, existingCategories: existingCategories, likely: likely, today: today,
                                                 depth: depth)
            }
            throw AnalyzerError.invalidOutput
        }
    }

    func analyzeInHalves(_ chunk: String, existingCategories: [String], likely: [String], today: String?,
                         depth: Int) async throws -> [AnalyzedThought] {
        let halves = TextChunker.halves(of: chunk)
        guard halves.count == 2 else { throw AnalyzerError.invalidOutput }
        let first = try await analyze(chunk: halves[0], existingCategories: existingCategories, likely: likely, today: today,
                                      depth: depth + 1)
        let second = try await analyze(chunk: halves[1], existingCategories: existingCategories, likely: likely, today: today,
                                       depth: depth + 1)
        return first + second
    }

    static func convert(_ generated: GeneratedThought) -> AnalyzedThought {
        func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return AnalyzedThought(
            title: generated.title,
            summary: clean(generated.summary),
            excerpt: generated.excerpt,
            kind: kind(generated.kind),
            tags: generated.tags,
            mentionedDates: generated.mentionedDates,
            category: generated.category,
            subcategory: clean(generated.subcategory),
            categoryDescription: clean(generated.categoryDescription),
            people: generated.people,
            places: generated.places)
    }

    static func kind(_ generated: GeneratedKind) -> MemoryKind {
        switch generated {
        case .idea: .idea
        case .task: .task
        case .appointment: .appointment
        case .decision: .decision
        case .preference: .preference
        case .info: .info
        case .other: .other
        }
    }

    static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Disponible sur cet iPhone"
        case .unavailable(let reason):
            // Les noms des raisons varient selon les versions du SDK : on lit leur description plutôt que de les énumérer.
            let name = String(describing: reason)
            if name.contains("deviceNotEligible") {
                return "Cet appareil ne prend pas en charge Apple Intelligence."
            } else if name.contains("NotEnabled") {
                return "Active Apple Intelligence dans Réglages › Apple Intelligence et Siri."
            } else if name.contains("NotReady") {
                return "Apple Intelligence n'est pas encore prêt (téléchargement du modèle en cours)."
            }
            return "Apple Intelligence est indisponible pour l'instant."
        @unknown default:
            return "Apple Intelligence est indisponible."
        }
    }
}

// MARK: - Jugement de confidentialité

@Generable
struct GeneratedPrivacy {
    @Guide(description: "neutral, personal, secret or unsure — see the instructions. When you hesitate, answer unsure.")
    var level: GeneratedPrivacyLevel
    @Guide(description: "One short French sentence explaining the choice, without repeating any detail of the note.")
    var reason: String
}

@Generable
enum GeneratedPrivacyLevel {
    case neutral, personal, secret, unsure
}

/// Le modèle d'Apple juge, **sur l'iPhone**, si une note contient quelque chose de personnel avant tout envoi.
/// Une erreur, un refus ou une hésitation gardent la note sur l'iPhone (le contrôleur s'en charge).
public struct ApplePrivacyJudge: PrivacyJudge {
    static let instructions = """
        You decide whether a note from a personal memory app may be sent to a free online AI service whose terms \
        forbid any personal, sensitive or confidential information. The note may mix Québec French and English.
        Answer:
        - neutral: nothing about a specific person's life. Examples: "acheter du lait", "idée d'une app de recettes", \
        "regarder un film ce soir", "réparer la poignée de la porte".
        - personal: anything about the life of the owner or of someone else: health or body, money, job or colleagues, \
        family, relationships, people's names, places where someone lives or goes, appointments with others, beliefs, \
        legal matters.
        - secret: passwords, PIN or access codes, card, bank or identity numbers, or anything clearly confidential.
        - unsure: when you hesitate between two answers.
        Never answer neutral when you have any doubt.
        """

    public init() {}

    public func judge(_ text: String) async throws -> PrivacyJudgement {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            throw AnalyzerError.unavailable(AppleThoughtAnalyzer.describe(availability))
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: "Note:\n\(text)", generating: GeneratedPrivacy.self)
        return PrivacyJudgement(verdict: Self.verdict(response.content.level), reason: response.content.reason)
    }

    static func verdict(_ level: GeneratedPrivacyLevel) -> PrivacyVerdict {
        switch level {
        case .neutral: .neutral
        case .personal: .personal
        case .secret: .secret
        case .unsure: .unsure
        }
    }
}
#endif
