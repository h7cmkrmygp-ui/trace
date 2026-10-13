import Foundation

/// P38 — corriger une fois partout : les notes qui peuvent suivre une note que le propriétaire vient de déplacer.
public enum MoveSuggestions {
    /// Les notes rangées par l'IA (jamais par le propriétaire) dans un des dossiers qu'il vient de quitter, sauf la note.
    public static func candidates(_ samples: [FilingSample], leaving folders: [String], excluding id: UUID) -> [FilingSample] {
        []
    }

    /// « Déplacer aussi 3 notes semblables dans « Finances » ? »
    public static func message(count: Int, folder: String) -> String {
        ""
    }
}
