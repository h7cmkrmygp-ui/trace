import EngramCore
import Foundation

/// Chemins de catégories (« Automobile › Lexus »).
public enum CategoryPaths {
    public static let separator = " › "

    /// Noms du parent le plus haut jusqu'à la catégorie elle-même.
    static func components(of category: EngramCategory, in all: [UUID: EngramCategory]) -> [String] {
        var components = [category.name]
        var current = category
        var depth = 0
        while let parentID = current.parentID, let parent = all[parentID], depth < 32 {
            components.insert(parent.name, at: 0)
            current = parent
            depth += 1
        }
        return components
    }

    static func display(_ components: [String]) -> String {
        components.joined(separator: separator)
    }
}
