import Foundation
import NaturalLanguage

/// Vecteur de sens d'une phrase (le modèle de langue d'Apple dans l'app, un faux dans les tests).
public protocol SentenceEmbedder: Sendable {
    func vector(for text: String) -> [Double]?
}

/// Plongements de phrases d'Apple, calculés **sur l'iPhone** (aucune donnée ne sort de l'appareil).
public final class AppleSentenceEmbedder: SentenceEmbedder, @unchecked Sendable {
    private let lock = NSLock()
    private var isLoaded = false
    private var embedding: NLEmbedding?

    public init() {}

    public func vector(for text: String) -> [Double]? {
        lock.withLock {
            if !isLoaded {
                embedding = NLEmbedding.sentenceEmbedding(for: .french)
                isLoaded = true
            }
            return embedding?.vector(for: text)
        }
    }
}

/// Indices pour le classement local : les catégories existantes les plus proches du sens de la note.
/// On compare la note aux **noms** de catégories seulement, jamais aux autres notes.
public enum CategoryHints {
    /// Catégories triées de la plus proche à la plus éloignée ; l'ordre d'origine est gardé si le sens est indisponible.
    public static func rank(text: String, categories: [String], embedder: any SentenceEmbedder) -> [String] {
        guard !categories.isEmpty, let target = embedder.vector(for: text) else { return categories }
        let scored = categories.enumerated().map { index, name in
            (name: name, score: embedder.vector(for: name).map { cosine(target, $0) } ?? -2, index: index)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.name)
    }

    static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -2 }
        var dot = 0.0
        var left = 0.0
        var right = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            left += lhs[index] * lhs[index]
            right += rhs[index] * rhs[index]
        }
        guard left > 0, right > 0 else { return -2 }
        return dot / (left.squareRoot() * right.squareRoot())
    }
}
