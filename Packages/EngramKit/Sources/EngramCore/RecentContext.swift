import Foundation

/// P42 — ce qui vient d'être dit : la dictée précédente, il y a moins de 30 minutes (ses personnes, ses listes, ses
/// dossiers). Engram s'en sert pour comprendre « elle », « lui », « cette liste », « ce projet », seulement quand c'est clair :
/// en cas de doute, aucun lien n'est inventé.
public struct RecentContext: Sendable, Equatable {
    /// Au-delà, la dictée précédente n'est plus « ce qui vient d'être dit ».
    public static let window: TimeInterval = 30 * 60

    public var people: [String]
    public var lists: [String]
    /// Chemins « Parent › Enfant » des notes de la dictée précédente (listes exclues).
    public var folders: [String]
    public var minutesAgo: Int

    public init(people: [String] = [], lists: [String] = [], folders: [String] = [], minutesAgo: Int = 0) {
        self.people = people
        self.lists = lists
        self.folders = folders
        self.minutesAgo = minutesAgo
    }

    public var isEmpty: Bool { people.isEmpty && lists.isEmpty && folders.isEmpty }
}

/// P42 — une note qui parle de quelqu'un, d'une liste ou d'un projet sans le nommer.
public enum ContextReferences {
    /// « elle adore », « lui acheter », « sa fête », « pour lui ».
    public static func refersToSomeone(_ text: String) -> Bool { false }

    /// « cette liste », « la même liste ».
    public static func refersToAList(_ text: String) -> Bool { false }

    /// « ce projet », « ce dossier ».
    public static func refersToAProject(_ text: String) -> Bool { false }

    /// « Ajoute un livre et des chandelles à cette liste » → « Livre », « Chandelles » ; nil sans « cette liste ».
    public static func listItems(in text: String) -> [String]? { nil }
}
