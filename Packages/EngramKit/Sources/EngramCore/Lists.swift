import Foundation

/// P15 — « ajoute du lait et des œufs à ma liste d'épicerie » : la liste visée et les choses à y mettre.
public struct ListCommand: Sendable, Equatable {
    /// Le nom de la liste tel qu'il se dit après « liste de » (« épicerie », « cadeaux », « Costco »).
    public let listName: String
    /// Les choses à ajouter, une par case (« Lait », « Œufs »).
    public let items: [String]

    public init(listName: String, items: [String]) {
        self.listName = listName
        self.items = items
    }
}

/// Reconnaît, sur l'iPhone et sans IA, une demande d'ajout à une liste.
public enum ListCommandParser {
    public static func parse(_ text: String) -> ListCommand? { nil }

    /// « Liste d'épicerie », « Liste de cadeaux ».
    public static func title(for name: String) -> String { name }

    /// La clé d'une liste : « Épicerie » et « epicerie » sont la même.
    public static func key(_ name: String) -> String { name }

    /// « Épicerie », « Cadeaux » (pour les cartes).
    public static func displayName(_ name: String) -> String { name }
}

/// Ajouter des cases à une liste, ou retirer celles qui sont cochées.
public enum ListMerge {
    /// Chaque chose devient une case à cocher ; déjà là et pas cochée, rien ne change ; cochée, elle redevient à faire.
    /// `added` : les choses à faire de nouveau (ajoutées ou décochées).
    public static func adding(_ items: [String], to body: String) -> (body: String, added: [String]) { (body, []) }

    public static func removingChecked(from body: String) -> String { body }
}
