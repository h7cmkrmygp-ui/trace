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

    /// Distance des sous-dossiers au centre.
    static let ring = 0.62
    static let goldenAngle = 2.399963229728653

    /// - Parameter items: (pensée, dossier le plus précis) ; un dossier inconnu compte comme le centre.
    public static func layout(rootID: UUID, subcategories: [UUID], items: [(UUID, UUID?)]) -> [Node] {
        var nodes = [Node(id: rootID, kind: .root, x: 0, y: 0, anchorID: nil)]
        var anchors: [UUID: (x: Double, y: Double)] = [rootID: (0, 0)]
        for (index, id) in subcategories.enumerated() {
            // Le premier en haut, les autres répartis tout autour.
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(subcategories.count)
            let point = (x: cos(angle) * ring, y: sin(angle) * ring)
            nodes.append(Node(id: id, kind: .subcategory, x: point.x, y: point.y, anchorID: nil))
            anchors[id] = point
        }
        // Les pensées en spirale (angle d'or) autour de leur dossier, sans jamais s'en éloigner trop.
        var counts: [UUID: Int] = [:]
        for (id, category) in items {
            let anchorID = category.flatMap { anchors[$0] == nil ? nil : $0 } ?? rootID
            let index = counts[anchorID, default: 0]
            counts[anchorID] = index + 1
            let anchor = anchors[anchorID] ?? (0, 0)
            let isCenter = anchorID == rootID
            let distance = min(isCenter ? 0.5 : 0.3,
                               (isCenter ? 0.14 : 0.09) + (isCenter ? 0.035 : 0.03) * Double(index + 1).squareRoot())
            let angle = Double(index) * goldenAngle
            nodes.append(Node(id: id, kind: .item,
                              x: max(-1, min(1, anchor.x + cos(angle) * distance)),
                              y: max(-1, min(1, anchor.y + sin(angle) * distance)),
                              anchorID: anchorID))
        }
        return nodes
    }
}
