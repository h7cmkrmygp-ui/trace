import Foundation

/// P38 — corriger une fois partout : les notes qui peuvent suivre une note que le propriétaire vient de déplacer.
public enum MoveSuggestions {
    /// Les notes rangées par l'IA (jamais par le propriétaire) dans un des dossiers qu'il vient de quitter, sauf la note.
    public static func candidates(_ samples: [FilingSample], leaving folders: [String], excluding id: UUID) -> [FilingSample] {
        let left = Set(folders)
        guard !left.isEmpty else { return [] }
        return samples.filter { $0.id != id && !$0.byOwner && !left.isDisjoint(with: $0.paths) }
    }

    /// « Déplacer aussi 3 notes semblables dans « Finances » ? »
    public static func message(count: Int, folder: String) -> String {
        let notes = count == 1 ? "1 note semblable" : "\(count) notes semblables"
        return "Déplacer aussi \(notes) dans « \(folder) » ?"
    }
}
