import Foundation

/// P25 — ce que le widget « Liste » affiche, écrit par l'app dans le dossier partagé : les choses qui restent, l'épicerie
/// d'abord. Une liste privée (ou Engram verrouillé) ne montre que des nombres.
public struct ListsSnapshot: Codable, Sendable, Equatable {
    /// Une liste telle que l'app la lit dans la base.
    public struct Source: Sendable, Equatable {
        public let memoryID: UUID
        public let name: String
        public let title: String
        public let body: String
        public let isPrivate: Bool

        public init(memoryID: UUID, name: String, title: String, body: String, isPrivate: Bool) {
            self.memoryID = memoryID
            self.name = name
            self.title = title
            self.body = body
            self.isPrivate = isPrivate
        }
    }

    public struct List: Codable, Sendable, Equatable, Identifiable {
        public let memoryID: UUID
        public let title: String
        /// Les choses qui restent (vide si la liste est privée ou Engram verrouillé).
        public let open: [String]
        public let openCount: Int
        public let done: Int
        public var id: UUID { memoryID }
    }

    public static let maximumLists = 4
    public static let maximumItems = 8

    public var generatedAt: Date
    public var lists: [List]

    public init(generatedAt: Date = .distantPast, lists: [List] = []) {
        self.generatedAt = generatedAt
        self.lists = lists
    }

    public static func make(_ sources: [Source], hideItems: Bool, now: Date) -> ListsSnapshot {
        let grocery = ListCommandParser.key("épicerie")
        let ordered = sources.enumerated()
            .sorted { first, second in
                let a = ListCommandParser.key(first.element.name) == grocery
                let b = ListCommandParser.key(second.element.name) == grocery
                return a != b ? a : first.offset < second.offset
            }
            .map { $0.element }
        let lists = ordered.prefix(maximumLists).map { source -> List in
            var open: [String] = []
            var done = 0
            for block in NoteBody.blocks(from: source.body) {
                if case .check(let checked) = block.kind {
                    if checked { done += 1 } else { open.append(block.text) }
                }
            }
            let hidden = hideItems || source.isPrivate
            return List(memoryID: source.memoryID, title: source.isPrivate ? "Liste privée" : source.title,
                        open: hidden ? [] : Array(open.prefix(maximumItems)), openCount: open.count, done: done)
        }
        return ListsSnapshot(generatedAt: now, lists: Array(lists))
    }
}
