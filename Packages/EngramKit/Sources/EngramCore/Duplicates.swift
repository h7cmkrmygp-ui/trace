import Foundation

/// P23 — la même pensée dite deux fois.
public enum DuplicateFinder {
    public struct Note: Sendable, Equatable {
        public let id: UUID
        public let text: String
        public let kind: MemoryKind?
        public let capturedAt: Date

        public init(id: UUID, text: String, kind: MemoryKind?, capturedAt: Date) {
            self.id = id
            self.text = text
            self.kind = kind
            self.capturedAt = capturedAt
        }
    }

    /// Deux notes qui se ressemblent : la plus ancienne est gardée.
    public struct Pair: Sendable, Equatable {
        public let keep: UUID
        public let duplicate: UUID
        public let score: Double
    }

    public static func pairs(_ notes: [Note], dismissed: Set<String> = []) -> [Pair] { [] }

    /// La clé d'une paire, dans n'importe quel ordre.
    public static func key(_ first: UUID, _ second: UUID) -> String { "" }

    public static func mergedBody(keep: String, duplicate: String) -> String { keep }
}
