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

/// Le texte d'une note, comme dans Notes d'Apple : des paragraphes et des cases à cocher (« ☐ » / « ☑ » en début de
/// ligne). Les cases écrites à la manière Markdown par une IA (« - [ ] ») sont comprises aussi.
public enum NoteBody {
    public static let unchecked = "☐"
    public static let checked = "☑"

    static let markers: [(prefix: String, done: Bool)] = [
        ("☐", false), ("☑", true), ("✅", true), ("- [ ]", false), ("- [x]", true), ("- [X]", true),
        ("* [ ]", false), ("* [x]", true), ("[ ]", false), ("[x]", true), ("[X]", true),
    ]

    public static func blocks(from body: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var paragraph: [String] = []
        func flush() {
            let text = paragraph.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(NoteBlock(kind: .text, text: text)) }
            paragraph = []
        }
        for line in body.components(separatedBy: "\n") {
            if let check = checkbox(line) {
                flush()
                blocks.append(NoteBlock(kind: .check(done: check.done), text: check.text))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    public static func text(from blocks: [NoteBlock]) -> String {
        blocks.map { block in
            switch block.kind {
            case .text: block.text
            case .check(let done): (done ? checked : unchecked) + " " + block.text
            }
        }
        .joined(separator: "\n")
    }

    /// Cases cochées sur le total, pour les listes (« 2/3 ») ; nil sans case.
    public static func progress(of body: String?) -> (done: Int, total: Int)? {
        guard let body else { return nil }
        let checks = blocks(from: body).compactMap { block -> Bool? in
            if case .check(let done) = block.kind { return done }
            return nil
        }
        guard !checks.isEmpty else { return nil }
        return (checks.filter { $0 }.count, checks.count)
    }

    static func checkbox(_ line: String) -> (done: Bool, text: String)? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        for marker in markers where trimmed.hasPrefix(marker.prefix) {
            let rest = trimmed.dropFirst(marker.prefix.count).drop { $0 == " " }
            return (marker.done, String(rest))
        }
        return nil
    }
}
