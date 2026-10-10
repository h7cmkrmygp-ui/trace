import Foundation

/// Disposition déterministe du « Cerveau » : catégories racines sur un cercle, sous-catégories un peu plus loin
/// dans l'angle de leur parent, pensées en spirale (angle d'or) autour de leur catégorie, « À classer » au centre.
/// Coordonnées centrées sur (0, 0).
public enum BrainLayout {
    public struct CategoryInput: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let name: String
        public let parentID: UUID?
        public init(id: UUID, name: String, parentID: UUID?) {
            self.id = id
            self.name = name
            self.parentID = parentID
        }
    }

    public struct ItemInput: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let title: String
        /// Catégorie la plus précise ; nil = « À classer ».
        public let categoryID: UUID?
        public init(id: UUID, title: String, categoryID: UUID?) {
            self.id = id
            self.title = title
            self.categoryID = categoryID
        }
    }

    public enum NodeKind: Sendable, Hashable { case center, category, item }

    public struct Node: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let kind: NodeKind
        public let label: String
        public let x: Double
        public let y: Double
        public let radius: Double
        /// Catégorie de rattachement (pensée) ou parent (sous-catégorie).
        public let anchorID: UUID?
    }

    public static let centerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let goldenAngle = 2.399963229728653

    public static func layout(categories: [CategoryInput], items: [ItemInput], size: Double) -> [Node] {
        // Mémoire vide : rien à dessiner, pas même le centre (sinon un point apparaît sous « Ton cerveau est vide »).
        if categories.isEmpty && items.isEmpty { return [] }
        let ringRadius = size * 0.32
        let known = Set(categories.map(\.id))
        var counts: [UUID: Int] = [:]
        for item in items { if let id = item.categoryID, known.contains(id) { counts[id, default: 0] += 1 } }

        let byName: (CategoryInput, CategoryInput) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let roots = categories.filter { $0.parentID == nil || !known.contains($0.parentID!) }.sorted(by: byName)
        let children = Dictionary(grouping: categories.filter { $0.parentID != nil && known.contains($0.parentID!) },
                                  by: { $0.parentID! })

        var nodes = [Node(id: centerID, kind: .center, label: "Toi", x: 0, y: 0, radius: 8, anchorID: nil)]
        var positions: [UUID: (x: Double, y: Double, radius: Double)] = [centerID: (0, 0, 8)]

        func categoryRadius(_ id: UUID) -> Double { 6 + Double(counts[id] ?? 0).squareRoot() * 2 }

        func place(_ category: CategoryInput, angle: Double, distance: Double, spread: Double, depth: Int) {
            let radius = categoryRadius(category.id)
            let x = cos(angle) * distance
            let y = sin(angle) * distance
            nodes.append(Node(id: category.id, kind: .category, label: category.name, x: x, y: y, radius: radius,
                              anchorID: category.parentID))
            positions[category.id] = (x, y, radius)
            guard depth < 4 else { return }
            let kids = (children[category.id] ?? []).sorted(by: byName)
            guard !kids.isEmpty else { return }
            let step = min(0.35, spread * 0.6 / Double(kids.count))
            for (index, kid) in kids.enumerated() {
                let offset = (Double(index) - Double(kids.count - 1) / 2) * step
                place(kid, angle: angle + offset, distance: distance + ringRadius * 0.38, spread: step, depth: depth + 1)
            }
        }

        let sector = roots.isEmpty ? 0 : 2 * Double.pi / Double(roots.count)
        for (index, root) in roots.enumerated() {
            place(root, angle: Double(index) * sector - Double.pi / 2, distance: ringRadius, spread: sector, depth: 0)
        }

        let grouped = Dictionary(grouping: items, by: { item -> UUID in
            if let id = item.categoryID, known.contains(id) { return id }
            return centerID
        })
        for anchorID in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let anchor = positions[anchorID] else { continue }
            let members = (grouped[anchorID] ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
            let base = anchorID == centerID ? 16.0 : anchor.radius + 6
            for (index, item) in members.enumerated() {
                let distance = base + 4 * Double(index + 1).squareRoot()
                let angle = Double(index) * goldenAngle
                nodes.append(Node(id: item.id, kind: .item, label: item.title,
                                  x: anchor.x + cos(angle) * distance, y: anchor.y + sin(angle) * distance,
                                  radius: 3, anchorID: anchorID == centerID ? nil : anchorID))
            }
        }
        return nodes
    }
}
