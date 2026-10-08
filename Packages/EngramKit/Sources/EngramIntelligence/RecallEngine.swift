import EngramCore
import Foundation

/// Mots proches d'un mot (le modèle de langue d'Apple dans l'app, un faux dans les tests).
public protocol WordNeighbors: Sendable {
    func neighbors(of word: String) -> [String]
}

public struct RecallResult: Sendable, Equatable {
    public let query: RecallQuery
    public let hits: [RecallHit]
}

public final class RecallEngine: @unchecked Sendable {
    let embedder: any SentenceEmbedder
    let neighbors: (any WordNeighbors)?

    public init(embedder: any SentenceEmbedder, neighbors: (any WordNeighbors)?) {
        self.embedder = embedder
        self.neighbors = neighbors
    }

    public func search(_ question: String, in documents: [RecallDocument], now: Date, calendar: Calendar) -> RecallResult {
        RecallResult(query: RecallQuery(), hits: [])
    }

    public func related(to document: RecallDocument, in documents: [RecallDocument], now: Date) -> [RecallHit] { [] }
}

public enum RecallAnswerPrompt {
    public static let instructions = ""

    public static func prompt(question: String, hits: [RecallHit], now: Date, calendar: Calendar) -> String { "" }
}
