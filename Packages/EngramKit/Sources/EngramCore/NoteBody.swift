import Foundation

/// Un bloc du texte d'une note : un paragraphe, ou une case à cocher.
public struct NoteBlock: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text
        case check(done: Bool)
    }

    public let id: UUID
    public var kind: Kind
    public var text: String

    public init(id: UUID = UUID(), kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// Le texte d'une note, comme dans Notes d'Apple : des paragraphes et des cases à cocher (« ☐ » / « ☑ »).
public enum NoteBody {
    public static func blocks(from body: String) -> [NoteBlock] {
        []
    }

    public static func text(from blocks: [NoteBlock]) -> String {
        ""
    }
}
