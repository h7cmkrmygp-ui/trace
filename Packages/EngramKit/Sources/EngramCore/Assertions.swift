import Foundation

/// F21 — une note d'où tirer des assertions : son identifiant, son texte et le moment où elle a été dite.
public struct AssertionNote: Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let saidAt: Date

    public init(id: UUID, text: String, saidAt: Date) {
        self.id = id
        self.text = text
        self.saidAt = saidAt
    }
}

/// F21 — un fait sur une personne : elle aime ou n'aime pas une chose, d'après une note, à un moment ; une assertion plus
/// récente sur la même chose la remplace (elle reste dans l'historique).
public struct Assertion: Sendable, Equatable {
    public enum Relation: String, Sendable { case likes, dislikes }

    public let subject: String
    public let relation: Relation
    public let value: String
    public let valueKey: String
    public let sourceID: UUID
    public let saidAt: Date
    public var supersededBy: UUID?

    public var isCurrent: Bool { supersededBy == nil }

    public init(subject: String, relation: Relation, value: String, valueKey: String, sourceID: UUID, saidAt: Date,
                supersededBy: UUID? = nil) {
        self.subject = subject
        self.relation = relation
        self.value = value
        self.valueKey = valueKey
        self.sourceID = sourceID
        self.saidAt = saidAt
        self.supersededBy = supersededBy
    }
}

public enum Assertions {
    /// Les goûts d'une personne dans ses notes, de la plus ancienne à la plus récente.
    public static func tastes(of person: String, in notes: [AssertionNote]) -> [Assertion] { [] }

    /// Les goûts actuels (les assertions remplacées n'en font plus partie).
    public static func currentTastes(_ assertions: [Assertion]) -> Tastes { Tastes() }
}
