import EngramCore
import Foundation

/// Données de test fictives et neutres.
enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func source(text: String = "Acheter du lait", at date: Date = Fixtures.date) -> Source {
        Source(kind: .text, originalText: text, contentHash: ContentHasher.textHash(text),
               capturedAt: date, createdAt: date, updatedAt: date)
    }

    static func memory(sourceID: UUID, title: String = "Acheter du lait", content: String = "Acheter du lait",
                       status: MemoryStatus = .unsorted, at date: Date = Fixtures.date) -> Memory {
        Memory(draft: MemoryDraft(sourceID: sourceID, excerpt: content, title: title, content: content,
                                  status: status, analysisVersion: "test"),
               capturedAt: date, now: date)
    }
}
