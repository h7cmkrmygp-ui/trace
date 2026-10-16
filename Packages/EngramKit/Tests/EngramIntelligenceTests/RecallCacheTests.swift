import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// F27 — les vecteurs de sens gardés en mémoire sont bornés (les plus anciens partent).
struct RecallCacheTests {
    struct ConstantEmbedder: SentenceEmbedder {
        func vector(for text: String) -> [Double]? { [1, 0] }
    }

    @Test func theVectorCacheIsBounded() {
        let engine = RecallEngine(embedder: ConstantEmbedder(), neighbors: nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let documents = (0..<(RecallEngine.maxCachedVectors + 100)).map { index in
            RecallDocument(id: UUID(), title: "Note \(index)", text: "Texte \(index)", kind: .info, status: .active,
                           capturedAt: now, dueAt: nil, categories: [], tags: [])
        }
        _ = engine.similarities(of: "Texte", to: documents)
        #expect(engine.cachedVectorCount <= RecallEngine.maxCachedVectors)
    }
}
