import Foundation

/// P26 — ce que Siri dit d'une liste, et la phrase qu'Engram classe quand on lui demande d'ajouter quelque chose.
public enum ListSpeech {
    public static func read(_ list: ListsSnapshot.List?) -> String { "" }

    public static func addCommand(item: String, list: String?) -> String { "" }
}
