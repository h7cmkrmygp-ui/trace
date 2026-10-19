import Foundation

/// F05/F06 — un passage exact du texte analysé. Les positions sont en unités UTF-16 (comme `NSString` et `NSRange`),
/// dans le texte de référence de la source tel qu'il a été analysé.
public struct EvidenceSpan: Sendable, Hashable, Codable {
    public let start: Int
    public let end: Int
    public let text: String

    public init(start: Int, end: Int, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    public var range: NSRange { NSRange(location: start, length: end - start) }
}
