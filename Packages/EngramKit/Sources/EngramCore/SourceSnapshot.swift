import Foundation

/// F10 — la version exacte d'une source au moment où son analyse commence : un résultat n'est écrit que si la source n'a
/// pas changé depuis (texte, révision, confidentialité).
public struct SourceSnapshot: Sendable, Equatable {
    public let sourceID: UUID
    public let revision: Int
    public let textHash: String
    public let policyVersion: Int
    public let keepLocal: Bool

    public init(sourceID: UUID, revision: Int, textHash: String, policyVersion: Int, keepLocal: Bool) {
        self.sourceID = sourceID
        self.revision = revision
        self.textHash = textHash
        self.policyVersion = policyVersion
        self.keepLocal = keepLocal
    }
}

extension Source {
    /// La version analysée de cette source.
    public var snapshot: SourceSnapshot {
        SourceSnapshot(sourceID: id, revision: revision, textHash: ContentHasher.textHash(referenceText ?? ""),
                       policyVersion: policyVersion, keepLocal: keepLocal)
    }
}
