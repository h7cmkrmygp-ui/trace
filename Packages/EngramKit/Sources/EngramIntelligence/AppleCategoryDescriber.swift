#if canImport(FoundationModels)
import EngramCore
import Foundation
import FoundationModels

@Generable
struct GeneratedCategoryDescription {
    @Guide(description: "One short French sentence, at most 12 words, describing what this folder contains. No names, no private details.")
    var description: String
}

/// Écrit **sur l'iPhone** la courte description d'une catégorie qui n'en a pas (catégories créées avant P4).
/// Les titres des notes ne quittent jamais l'appareil.
public struct AppleCategoryDescriber: Sendable {
    static let maxLength = 120

    public init() {}

    static let instructions = """
        You write the one-line description shown under a folder in a personal notes app, in French.
        Describe the kind of notes the folder holds, in general terms, like "Suivi de la santé, du poids et de la condition physique".
        Never copy names, numbers or private details from the examples.
        """

    static func prompt(name: String, titles: [String]) -> String {
        """
        Folder name: \(name)
        Examples of notes it contains:
        \(titles.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    public func describe(name: String, titles: [String]) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AnalyzerError.unavailable("Apple Intelligence est indisponible.")
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: Self.prompt(name: name, titles: titles),
                                                 generating: GeneratedCategoryDescription.self)
        return Self.clean(response.content.description)
    }

    static func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"«»")))
        return String(trimmed.prefix(maxLength))
    }
}
#endif
