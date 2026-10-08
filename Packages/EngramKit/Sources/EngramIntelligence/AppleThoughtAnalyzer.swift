#if canImport(FoundationModels)
import EngramCore
import Foundation
import FoundationModels

// MARK: - Sortie guidée du modèle

@Generable
struct GeneratedThoughts {
    @Guide(description: "Every distinct thought found in the text, in the order they appear.")
    var thoughts: [GeneratedThought]
}

@Generable
struct GeneratedThought {
    @Guide(description: "Short, precise title in the user's own language (at most 8 words).")
    var title: String
    @Guide(description: "One sentence keeping dates, amounts and conditions; empty if the title says it all.")
    var summary: String
    @Guide(description: "The exact words of the text that express this thought, copied verbatim, never rephrased.")
    var excerpt: String
    var kind: GeneratedKind
    @Guide(description: "Up to 3 short tags in French.", .maximumCount(3))
    var tags: [String]
    @Guide(description: "Date or time expressions copied from the text, e.g. « vendredi », « 29 octobre ».")
    var mentionedDates: [String]
    @Guide(description: "Broad life domain in French, 1 to 3 words (Automobile, Finance, Travail, Santé, Maison, Famille, Achats, Voyages, Études, Projets…). Reuse an existing category name exactly when one fits.")
    var category: String
    @Guide(description: "Optional narrower subcategory in French for a specific named thing (brand, model, project, person, recurring topic), e.g. Lexus. Empty when not useful. Reuse an existing subcategory exactly when one fits.")
    var subcategory: String
}

@Generable
enum GeneratedKind {
    case idea, task, appointment, decision, preference, info, other
}

// MARK: - Consignes versionnées

enum AnalysisPrompt {
    static let version = "p2-v1"

    static let instructions = """
        You are the filing engine of a personal memory app running on the user's iPhone.
        The user dictates or types thoughts, often mixing French and English.
        Split the text into distinct thoughts. A single sentence can contain several thoughts.
        For each thought, choose where it belongs:
        - category: a broad life domain written in French, such as Automobile, Finance, Travail, Santé, Maison, Famille, Achats, Voyages, Études, Projets.
        - subcategory: only for a specific named thing such as a car model, a project, a person or a recurring topic; otherwise leave it empty.
        When an existing category or subcategory fits, reuse its exact spelling instead of creating a synonym.
        Copy each excerpt word for word from the text. Never invent facts that are not in the text.
        Keep titles in the user's language.
        """

    static func prompt(text: String, categories: [String]) -> String {
        let existing = categories.isEmpty ? "(none yet)" : categories.map { "- \($0)" }.joined(separator: "\n")
        return """
            Existing categories ("Parent › Child" means a subcategory):
            \(existing)

            Text to file:
            \(text)
            """
    }
}

// MARK: - Analyseur

/// Analyse des pensées par le modèle d'Apple, **sur l'iPhone** (aucun envoi sur Internet).
public struct AppleThoughtAnalyzer: MemoryAnalyzer {
    public static let promptVersion = AnalysisPrompt.version
    static let maxChunkLength = 2_500

    public init() {}

    /// État lisible du modèle, pour les Réglages.
    public static func availabilityDescription() -> (isAvailable: Bool, text: String) {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return (true, "Disponible sur cet iPhone") }
        return (false, describe(availability))
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else { throw AnalyzerError.unavailable(Self.describe(availability)) }
        var thoughts: [AnalyzedThought] = []
        for chunk in TextChunker.chunks(of: text, maxLength: Self.maxChunkLength) {
            thoughts += try await analyze(chunk: chunk, existingCategories: existingCategories, depth: 0)
        }
        return ThoughtAnalysis(thoughts: thoughts)
    }

    func analyze(chunk: String, existingCategories: [String], depth: Int) async throws -> [AnalyzedThought] {
        let session = LanguageModelSession(instructions: AnalysisPrompt.instructions)
        do {
            let response = try await session.respond(
                to: AnalysisPrompt.prompt(text: chunk, categories: existingCategories),
                generating: GeneratedThoughts.self)
            return response.content.thoughts.map(Self.convert)
        } catch let error as LanguageModelError {
            // iOS 27 : `LanguageModelError` remplace `LanguageModelSession.GenerationError`.
            switch error {
            case .contextSizeExceeded where depth < 3:
                return try await analyzeInHalves(chunk, existingCategories: existingCategories, depth: depth)
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
                return try await analyzeInHalves(chunk, existingCategories: existingCategories, depth: depth)
            }
            throw AnalyzerError.invalidOutput
        }
    }

    func analyzeInHalves(_ chunk: String, existingCategories: [String], depth: Int) async throws -> [AnalyzedThought] {
        let halves = TextChunker.halves(of: chunk)
        guard halves.count == 2 else { throw AnalyzerError.invalidOutput }
        let first = try await analyze(chunk: halves[0], existingCategories: existingCategories, depth: depth + 1)
        let second = try await analyze(chunk: halves[1], existingCategories: existingCategories, depth: depth + 1)
        return first + second
    }

    static func convert(_ generated: GeneratedThought) -> AnalyzedThought {
        let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let subcategory = generated.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        return AnalyzedThought(
            title: generated.title,
            summary: summary.isEmpty ? nil : summary,
            excerpt: generated.excerpt,
            kind: kind(generated.kind),
            tags: generated.tags,
            mentionedDates: generated.mentionedDates,
            category: generated.category,
            subcategory: subcategory.isEmpty ? nil : subcategory)
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
#endif
