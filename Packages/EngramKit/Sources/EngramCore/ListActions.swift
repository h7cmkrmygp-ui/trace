import Foundation

/// P19 — « coche le lait », « j'ai acheté le pain », « enlève les bananes de ma liste ».
public struct ListAction: Sendable, Equatable {
    public enum Kind: String, Sendable { case check, remove }

    public let kind: Kind
    /// La liste nommée ; nil = celle qui contient ces choses (l'épicerie d'abord).
    public let listName: String?
    public let items: [String]
    /// Une demande claire (« coche », « enlève … de ma liste ») ; « j'ai acheté le pain » ne l'est pas : sans case qui
    /// correspond, c'est une note ordinaire.
    public let isExplicit: Bool

    public init(kind: Kind, listName: String?, items: [String], isExplicit: Bool) {
        self.kind = kind
        self.listName = listName
        self.items = items
        self.isExplicit = isExplicit
    }
}

/// Reconnaît, sur l'iPhone et sans IA, une case à cocher ou à retirer.
public enum ListActionParser {
    public static func parse(_ text: String) -> ListAction? { nil }
}

extension ListMerge {
    public static func matches(_ spoken: String, _ box: String) -> Bool { false }

    public static func checking(_ items: [String], in body: String) -> (body: String, changed: [String]) { (body, []) }

    public static func removing(_ items: [String], from body: String) -> (body: String, changed: [String]) { (body, []) }
}
