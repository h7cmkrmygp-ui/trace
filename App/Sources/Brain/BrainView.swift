import EngramCore
import EngramStore
import SwiftUI

/// Le Cerveau : la mémoire en nuage de points. Pincer pour zoomer, glisser pour se déplacer, toucher pour ouvrir.
struct BrainView: View {
    @Environment(AppModel.self) private var model
    @State private var nodes: [BrainLayout.Node] = []
    @State private var categoryNames: [UUID: String] = [:]
    @State private var query = ""
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var path = NavigationPath()

    /// La disposition est calculée dans un carré de cette taille, puis adaptée à l'écran.
    private let layoutSize = 1000.0

    private var itemCount: Int { nodes.filter { $0.kind == .item }.count }
    private var matches: Set<UUID> {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return Set(nodes.filter { $0.kind != .center && $0.label.localizedStandardContains(needle) }.map(\.id))
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                let fit = fitScale(for: geometry.size)
                canvas(fit: fit)
                    .contentShape(Rectangle())
                    .gesture(magnify.simultaneously(with: drag))
                    .onTapGesture { location in open(at: location, in: geometry.size, fit: fit) }
            }
            // VoiceOver : le nuage n'est pas lisible, on propose la liste des catégories à ouvrir. Seul le nuage est
            // remplacé : le message « Ton cerveau est vide » reste lisible.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cerveau : \(categoryNames.count) catégories, \(itemCount) pensées")
            .accessibilityChildren {
                ForEach(categoryNodes, id: \.id) { node in
                    let count = itemCount(in: node.id)
                    Button("\(node.label), \(count) pensée\(count > 1 ? "s" : "")") { openCategory(node.id) }
                }
            }
            .accessibilityHidden(itemCount == 0)
            .overlay {
                if itemCount == 0 {
                    ContentUnavailableView("Ton cerveau est vide", systemImage: "circle.dotted",
                                           description: Text("Parle à Engram : chaque pensée apparaîtra ici."))
                }
            }
            .navigationTitle("Cerveau")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Chercher dans ton cerveau")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Recentrer", systemImage: "scope") { recenter() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(NotesView.count(itemCount, "note", nil)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .navigationDestination(for: NotesRoute.self) { $0.destination }
            .task {
                do {
                    for try await snapshot in model.categories.brainSnapshotStream() {
                        nodes = BrainLayout.layout(categories: snapshot.categories, items: snapshot.items, size: layoutSize)
                        categoryNames = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) })
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
        }
    }

    private func canvas(fit: CGFloat) -> some View {
        let highlighted = matches
        let isSearching = !highlighted.isEmpty
        let positions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return Canvas { context, size in
            let factor = fit * scale
            let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
            func point(_ node: BrainLayout.Node) -> CGPoint {
                CGPoint(x: center.x + node.x * factor, y: center.y + node.y * factor)
            }
            // Liens très fins vers la catégorie (ou le parent).
            for node in nodes where node.kind != .center {
                let anchor = node.anchorID.flatMap { positions[$0] } ?? positions[BrainLayout.centerID]
                guard let anchor else { continue }
                var line = Path()
                line.move(to: point(node))
                line.addLine(to: point(anchor))
                context.stroke(line, with: .color(.primary.opacity(node.kind == .category ? 0.10 : 0.05)), lineWidth: 0.5)
            }
            for node in nodes {
                let p = point(node)
                let radius = max(1.5, node.radius * min(1.6, max(0.6, factor * 1.4)))
                let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                let dimmed = isSearching && !highlighted.contains(node.id)
                switch node.kind {
                case .center:
                    context.fill(Path(ellipseIn: rect), with: .color(.primary))
                case .category:
                    context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(dimmed ? 0.15 : 0.85)))
                    if !dimmed {
                        context.draw(Text(node.label).font(.caption2).foregroundStyle(.secondary),
                                     at: CGPoint(x: p.x, y: p.y + radius + 8))
                    }
                case .item:
                    if highlighted.contains(node.id) {
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(.red))
                    } else {
                        context.stroke(Path(ellipseIn: rect), with: .color(.primary.opacity(dimmed ? 0.12 : 0.45)), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(6, max(0.4, lastScale * value.magnification)) }
            .onEnded { _ in lastScale = scale }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func recenter() {
        withAnimation(.easeOut(duration: 0.25)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    /// Ouvre le nœud le plus proche du toucher (catégorie ou pensée).
    private func open(at location: CGPoint, in size: CGSize, fit: CGFloat) {
        let factor = fit * scale
        let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        let candidates = nodes.filter { $0.kind != .center }.map { node -> (BrainLayout.Node, CGFloat) in
            let p = CGPoint(x: center.x + node.x * factor, y: center.y + node.y * factor)
            return (node, hypot(p.x - location.x, p.y - location.y))
        }
        guard let (node, distance) = candidates.min(by: { $0.1 < $1.1 }), distance < 22 else { return }
        switch node.kind {
        case .item:
            path.append(node.id)
        case .category:
            openCategory(node.id)
        case .center:
            break
        }
    }

    private var categoryNodes: [BrainLayout.Node] { nodes.filter { $0.kind == .category } }

    /// Échelle qui fait tenir tout le nuage dans l'écran, étiquettes comprises (une étiquette ne déborde plus du bord).
    private func fitScale(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) / layoutSize * 1.15
        guard !nodes.isEmpty else { return base }
        let maxX = nodes.map { abs($0.x) + $0.radius }.max() ?? 0
        let maxY = nodes.map { abs($0.y) + $0.radius }.max() ?? 0
        // Marges pour les étiquettes : environ 70 pt de large, 40 pt de haut.
        let fitX = maxX > 0 ? (size.width / 2 - 70) / maxX : base
        let fitY = maxY > 0 ? (size.height / 2 - 40) / maxY : base
        return max(0.05, min(base * 1.6, fitX, fitY))
    }

    /// Pensées rattachées directement à une catégorie.
    private func itemCount(in categoryID: UUID) -> Int {
        nodes.filter { $0.kind == .item && $0.anchorID == categoryID }.count
    }

    private func openCategory(_ id: UUID) {
        if let category = try? model.categories.activeCategories().first(where: { $0.id == id }) {
            path.append(NotesRoute.category(category))
        }
    }
}
