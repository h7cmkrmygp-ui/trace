import Foundation

/// Le petit réseau en haut d'un dossier des Notes : le dossier au centre, ses sous-dossiers en cercle autour, chaque
/// pensée près de son dossier. Coordonnées de −1 à 1, centrées sur (0, 0).
public enum CategoryConstellation {
    public struct Node: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable { case root, subcategory, item }

        public let id: UUID
        public let kind: Kind
        public let x: Double
        public let y: Double
        /// Dossier de rattachement (pensée) ; nil pour le centre et les sous-dossiers.
        public let anchorID: UUID?
    }

    /// - Parameter items: (pensée, dossier le plus précis) ; un dossier inconnu compte comme le centre.
    public static func layout(rootID: UUID, subcategories: [UUID], items: [(UUID, UUID?)]) -> [Node] {
        []
    }
}
