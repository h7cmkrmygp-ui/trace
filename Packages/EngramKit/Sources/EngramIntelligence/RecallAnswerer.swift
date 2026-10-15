#if canImport(FoundationModels)
import EngramCore
import Foundation
import FoundationModels

@Generable
struct GeneratedRecallAnswer {
    @Guide(description: "One to three short French sentences answering the question from the listed notes only.")
    var answer: String
}

/// Réponse de « Retrouver », rédigée **sur l'iPhone** par l'IA d'Apple à partir des seules notes trouvées.
/// Sans modèle disponible (ou en cas d'erreur), une phrase modèle dit simplement ce qui a été trouvé.
public struct RecallAnswerer: Sendable {
    static let maxLength = 700

    public init() {}

    public func answer(question: String, result: RecallResult, now: Date, calendar: Calendar) async -> String {
        let fallback = RecallAnswer.fallback(for: result.query, hits: result.hits)
        guard !result.hits.isEmpty, case .available = SystemLanguageModel.default.availability else { return fallback }
        do {
            let session = LanguageModelSession(instructions: RecallAnswerPrompt.instructions)
            let response = try await session.respond(
                to: RecallAnswerPrompt.prompt(question: question, hits: result.hits, now: now, calendar: calendar),
                generating: GeneratedRecallAnswer.self)
            let text = response.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fallback : String(text.prefix(Self.maxLength))
        } catch {
            return fallback
        }
    }
}
#endif
