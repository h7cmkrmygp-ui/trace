import Foundation

/// Une question posée à « Retrouver », comprise sur l'iPhone.
public struct RecallQuery: Sendable, Equatable {
    public enum Intent: String, Sendable, Equatable { case find, list, summarize }

    public var keywords: [String] = []
    public var kinds: Set<MemoryKind> = []
    public var period: DateInterval?
    public var periodMeansDue = false
    public var intent: Intent = .find

    public init() {}

    public static func parse(_ question: String, now: Date, calendar: Calendar) -> RecallQuery { RecallQuery() }
}

/// Une note telle que « Retrouver » la lit.
public struct RecallDocument: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let text: String
    public let kind: MemoryKind?
    public let status: MemoryStatus
    public let capturedAt: Date
    public let dueAt: Date?
    public let categories: [String]
    public let tags: [String]

    public init(id: UUID, title: String, text: String, kind: MemoryKind?, status: MemoryStatus, capturedAt: Date,
                dueAt: Date?, categories: [String], tags: [String]) {
        self.id = id
        self.title = title
        self.text = text
        self.kind = kind
        self.status = status
        self.capturedAt = capturedAt
        self.dueAt = dueAt
        self.categories = categories
        self.tags = tags
    }
}

public struct RecallHit: Sendable, Equatable {
    public let document: RecallDocument
    public let score: Double

    public init(document: RecallDocument, score: Double) {
        self.document = document
        self.score = score
    }
}

public enum RecallRanker {
    public static func rank(_ documents: [RecallDocument], for query: RecallQuery, now: Date,
                            semanticScores: [UUID: Double] = [:], expansions: [String: [String]] = [:],
                            limit: Int = 8) -> [RecallHit] { [] }
}

public enum RecallAnswer {
    public static let nothingFound = "Je ne trouve rien là-dessus dans ta mémoire."

    public static func fallback(for query: RecallQuery, hits: [RecallHit]) -> String { "" }
}
