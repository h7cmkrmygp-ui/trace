import EngramCore
import EngramStore
import SwiftUI
import UIKit

/// Couleurs de l'app tirées de la palette des catégories (les mêmes dans le Cerveau, les Notes et Retrouver).
extension Color {
    static func category(_ name: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hue: CategoryPalette.hue(for: name), saturation: traits.userInterfaceStyle == .dark ? 0.6 : 0.68,
                    brightness: traits.userInterfaceStyle == .dark ? 1 : 0.8, alpha: 1)
        })
    }
}

/// Le Cerveau : ta mémoire comme un réseau de neurones, sobre et calme. Chaque catégorie est un neurone de sa couleur,
/// ses notes sont de petits points autour d'elle, reliés au centre par de fines connexions ; tout flotte à peine.
/// Toucher un neurone le centre et ouvre, en bas, ses notes les plus récentes ; un deuxième toucher ouvre la catégorie.
/// Toucher un point ouvre la note. Pincer pour zoomer (les titres des notes apparaissent de près), glisser pour se déplacer.
struct BrainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var nodes: [BrainLayout.Node] = []
    @State private var categoryNames: [UUID: String] = [:]
    @State private var query = ""
    @State private var camera = BrainCamera()
    /// Animation de caméra en cours (centrer une catégorie, recentrer).
    @State private var cameraMove: (from: BrainCamera, to: BrainCamera, start: Date)?
    @State private var gestureStart: BrainCamera?
    @State private var focused: UUID?
    /// Notes affichées dans le panneau du bas (catégorie touchée ou résultats de recherche).
    @State private var panelNotes: [Memory] = []
    @State private var tapCount = 0
    /// Apparition du réseau (une fois, à l'arrivée des données).
    @State private var revealStart: Date?
    @State private var lastFit: CGFloat = 0.4
    private let epoch = Date()

    /// La disposition est calculée dans un carré de cette taille, puis adaptée à l'écran.
    private let layoutSize = 1000.0
    /// Les notes s'écartent un peu de leur neurone (la disposition les place tout contre lui).
    private let spread = 2.2

    private var itemCount: Int { nodes.filter { $0.kind == .item }.count }
    private var categoryNodes: [BrainLayout.Node] { nodes.filter { $0.kind == .category } }
    private var rootNodes: [BrainLayout.Node] { categoryNodes.filter { $0.anchorID == nil } }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var matches: Set<UUID> {
        guard !trimmedQuery.isEmpty else { return [] }
        return Set(nodes.filter { $0.kind != .center && $0.label.localizedStandardContains(trimmedQuery) }.map(\.id))
    }
    /// Le neurone touché, ses sous-catégories et toutes leurs notes.
    private var focusedFamily: Set<UUID> {
        guard let focused else { return [] }
        var family: Set<UUID> = [focused]
        for node in categoryNodes where node.anchorID == focused { family.insert(node.id) }
        for node in nodes where node.kind == .item {
            if let anchor = node.anchorID, family.contains(anchor) { family.insert(node.id) }
        }
        return family
    }
    private var isStill: Bool {
        reduceMotion && cameraMove == nil
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.brainPath) {
            ZStack {
                BrainBackdrop()
                GeometryReader { geometry in
                    let fit = fitScale(for: geometry.size)
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill)) { timeline in
                        canvas(fit: fit, date: timeline.date)
                    }
                    .contentShape(Rectangle())
                    .gesture(magnify.simultaneously(with: drag))
                    .onTapGesture { location in tap(at: location, in: geometry.size, fit: fit) }
                }
                // VoiceOver : le réseau n'est pas lisible, on propose la liste des catégories à ouvrir. Seul le réseau est
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
            }
            .overlay {
                if itemCount == 0 {
                    ContentUnavailableView("Ton cerveau est vide", systemImage: "brain",
                                           description: Text("Parle à Engram : chaque pensée apparaîtra ici, comme un neurone."))
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !rootNodes.isEmpty { categoryStrip }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focused != nil || !matches.isEmpty { panel }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: focused)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: matches)
            .navigationTitle("Cerveau")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Chercher dans ton cerveau")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Recentrer", systemImage: "scope") { move(to: BrainCamera(), focus: nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(NotesView.count(itemCount, "note", nil)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .sensoryFeedback(.selection, trigger: tapCount)
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .navigationDestination(for: NotesRoute.self) { $0.destination }
            .task {
                do {
                    for try await snapshot in model.categories.brainSnapshotStream() {
                        let wasEmpty = nodes.isEmpty
                        nodes = BrainLayout.layout(categories: snapshot.categories, items: snapshot.items, size: layoutSize)
                        categoryNames = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) })
                        if wasEmpty, !nodes.isEmpty, revealStart == nil { revealStart = Date() }
                        if let focused, !nodes.contains(where: { $0.id == focused }) { self.focused = nil }
                        loadPanel()
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
            .onChange(of: focused) { _, _ in loadPanel() }
            .onChange(of: query) { _, _ in loadPanel() }
        }
    }

    // MARK: - Rangée de catégories

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rootNodes, id: \.id) { node in
                    let isFocused = focused == node.id
                    Button {
                        tapCount += 1
                        if isFocused { openCategory(node.id) } else { focus(on: node) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color.category(node.label)).frame(width: 8, height: 8)
                            Text(node.label).font(.subheadline.weight(isFocused ? .semibold : .regular))
                            Text("\(totalCount(under: node.id))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isFocused ? Color.category(node.label).opacity(0.18) : Color.clear, in: Capsule())
                        .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isFocused ? "Ouvre la catégorie" : "Montre ses notes")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Panneau du bas : les notes du neurone touché, ou les résultats de la recherche

    private var panelTitle: String {
        if !trimmedQuery.isEmpty { return "Résultats" }
        return focused.flatMap { id in nodes.first { $0.id == id }?.label } ?? ""
    }

    private var panelColor: Color {
        guard trimmedQuery.isEmpty, let focused, let node = nodes.first(where: { $0.id == focused }) else { return .accentColor }
        return color(for: node, in: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }))
    }

    private var panelCount: Int {
        if !trimmedQuery.isEmpty { return nodes.filter { $0.kind == .item && matches.contains($0.id) }.count }
        return nodes.filter { $0.kind == .item && focusedFamily.contains($0.id) }.count
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(panelColor).frame(width: 10, height: 10)
                Text(panelTitle).font(.headline).lineLimit(1)
                Text(NotesView.count(panelCount, "note", nil)).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if trimmedQuery.isEmpty, let focused {
                    Button("Tout voir") { openCategory(focused) }
                        .font(.subheadline.weight(.semibold))
                }
                Button {
                    if trimmedQuery.isEmpty { move(to: BrainCamera(), focus: nil) } else { query = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer le panneau")
            }
            .padding(.bottom, 4)
            if panelNotes.isEmpty {
                Text(trimmedQuery.isEmpty ? "Ses notes sont dans ses sous-catégories." : "Aucune note ne correspond.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(panelNotes.prefix(4)) { memory in
                NavigationLink(value: memory.id) {
                    HStack(spacing: 10) {
                        Image(systemName: RecallHitRow.symbol(for: memory.kind))
                            .foregroundStyle(panelColor)
                            .frame(width: 22)
                        Text(memory.title)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 6)
                        Text(memory.capturedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Les notes du panneau, les plus récentes d'abord.
    private func loadPanel() {
        let ids: [UUID]
        if !trimmedQuery.isEmpty {
            ids = nodes.filter { $0.kind == .item && matches.contains($0.id) }.map(\.id)
        } else if focused != nil {
            ids = nodes.filter { $0.kind == .item && focusedFamily.contains($0.id) }.map(\.id)
        } else {
            panelNotes = []
            return
        }
        let found = (try? model.memories.memories(ids: ids)) ?? []
        panelNotes = found.sorted { $0.capturedAt > $1.capturedAt }
    }

    // MARK: - Dessin

    private func canvas(fit: CGFloat, date: Date) -> some View {
        let time = reduceMotion ? 0 : date.timeIntervalSince(epoch)
        let reveal = reduceMotion ? 1 : min(1, max(0, date.timeIntervalSince(revealStart ?? .distantPast) / 0.9))
        let camera = currentCamera(at: date)
        let highlighted = matches
        let isSearching = !trimmedQuery.isEmpty
        let family = focusedFamily
        let focusedID = focused
        let positions = animatedPositions(time: time)
        let dark = colorScheme == .dark
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        // Une couleur par nœud, calculée une fois par image (et non pour chaque trait).
        let colors = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, color(for: $0, in: nodeByID)) })
        return Canvas { context, size in
            let factor = fit * camera.scale
            let center = CGPoint(x: size.width / 2 + camera.offset.width, y: size.height / 2 + camera.offset.height)
            func point(_ id: UUID) -> CGPoint? {
                positions[id].map { CGPoint(x: center.x + $0.x * factor, y: center.y + $0.y * factor) }
            }
            func circle(_ p: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            /// Apparition douce, les neurones d'abord, puis leurs notes.
            func appearance(_ node: BrainLayout.Node) -> Double {
                let delay = node.kind == .item ? 0.35 : (node.kind == .category ? 0.1 : 0)
                let local = min(1, max(0, (reveal - delay) / (1 - delay)))
                return 1 - pow(1 - local, 3)
            }
            /// Recherche ou neurone touché : le reste s'efface un peu.
            func emphasis(_ node: BrainLayout.Node) -> Double {
                if isSearching { return highlighted.contains(node.id) ? 1 : 0.15 }
                if focusedID != nil { return family.contains(node.id) || node.kind == .center ? 1 : 0.22 }
                return 1
            }

            // Connexions : de fines courbes de la couleur des neurones.
            for node in nodes where node.kind == .category {
                let anchorID = node.anchorID ?? BrainLayout.centerID
                guard let start = point(anchorID), let end = point(node.id) else { continue }
                var curve = Path()
                curve.move(to: start)
                curve.addQuadCurve(to: end, control: Self.control(from: start, to: end, seed: BrainMotion.seed(node.id)))
                let strength = appearance(node) * emphasis(node)
                context.stroke(curve, with: .color((colors[node.id] ?? .gray).opacity((dark ? 0.34 : 0.28) * strength)),
                               lineWidth: node.anchorID == nil ? 1 : 0.75)
            }

            // Le centre : toi.
            if let p = point(BrainLayout.centerID) {
                context.fill(circle(p, 4), with: .color((dark ? Color.white : Color.black).opacity(dark ? 0.55 : 0.3)))
            }

            // Notes : de petits points ; leur titre apparaît de près (neurone touché) ou quand elles répondent à la recherche.
            let showsTitles = camera.scale >= 1.8
            for node in nodes where node.kind == .item {
                guard let p = point(node.id) else { continue }
                let strength = appearance(node) * emphasis(node)
                let isMatch = highlighted.contains(node.id)
                let color = colors[node.id] ?? .gray
                let radius = CGFloat(isMatch ? 3.6 : max(1.8, min(3.2, Double(factor) * 4)))
                context.fill(circle(p, radius), with: .color(color.opacity(0.85 * strength)))
                if isMatch { context.stroke(circle(p, radius + 3), with: .color(color.opacity(0.5 * strength)), lineWidth: 1) }
                if strength > 0.5, isMatch || (showsTitles && family.contains(node.id)) {
                    let title = Text(Self.short(node.label)).font(.caption2).foregroundStyle(Color.secondary)
                    context.draw(context.resolve(title), at: CGPoint(x: p.x + radius + 5, y: p.y), anchor: .leading)
                }
            }

            // Neurones : une sphère douce éclairée d'en haut, une fine membrane autour ; le neurone touché a un anneau.
            for node in nodes where node.kind == .category {
                guard let p = point(node.id) else { continue }
                let shown = appearance(node)
                let radius = coreRadius(node, factor: factor, time: time) * CGFloat(0.6 + 0.4 * shown)
                let color = colors[node.id] ?? .gray
                context.opacity = shown * emphasis(node)
                context.fill(circle(p, radius + 5), with: .color(color.opacity(dark ? 0.16 : 0.12)))
                context.fill(circle(p, radius), with: .radialGradient(
                    Gradient(colors: [color.mix(with: .white, by: dark ? 0.3 : 0.4), color]),
                    center: CGPoint(x: p.x - radius * 0.4, y: p.y - radius * 0.4), startRadius: 0, endRadius: radius * 1.7))
                if node.id == focusedID {
                    context.stroke(circle(p, radius + 9), with: .color(color.opacity(0.7)), lineWidth: 1.5)
                }
                let isRoot = node.anchorID == nil
                // Les sous-catégories ne se nomment que de près, ou quand leur famille est touchée : moins de bruit.
                if isRoot || camera.scale >= 1.4 || family.contains(node.id) {
                    let label = Text(node.label)
                        .font(.system(size: isRoot ? 13 : 11, weight: isRoot ? .semibold : .medium))
                        .foregroundStyle(Color.primary.opacity(isRoot ? 0.85 : 0.6))
                    if isRoot {
                        context.draw(context.resolve(label), at: CGPoint(x: p.x, y: p.y + radius + 8), anchor: .top)
                    } else {
                        // À côté, du côté opposé à son parent : il ne chevauche pas le sien.
                        let parent = node.anchorID.flatMap { point($0) } ?? center
                        let toRight = p.x >= parent.x
                        context.draw(context.resolve(label), at: CGPoint(x: p.x + (toRight ? radius + 7 : -radius - 7), y: p.y),
                                     anchor: toRight ? .leading : .trailing)
                    }
                }
                context.opacity = 1
            }
        }
    }

    /// Rayon d'un neurone : il respire à peine (± 2 %), sauf avec « Réduire les animations ».
    private func coreRadius(_ node: BrainLayout.Node, factor: CGFloat, time: Double) -> CGFloat {
        let zoom = min(1.8, max(0.7, Double(factor) * 1.5))
        let breath = 1 + (BrainMotion.pulse(seed: BrainMotion.seed(node.id), time: time) - 1) / 3
        return CGFloat(max(5, node.radius * 1.2 * zoom) * breath)
    }

    /// Positions au temps donné : chaque neurone flotte doucement (quelques points, sur 6 à 10 s) et ses notes le
    /// suivent en flottant elles aussi. À l'arrêt (temps 0), tout est à sa place.
    private func animatedPositions(time: Double) -> [UUID: (x: Double, y: Double)] {
        var positions: [UUID: (x: Double, y: Double)] = [:]
        var resting: [UUID: (x: Double, y: Double)] = [:]
        for node in nodes where node.kind != .item {
            resting[node.id] = (node.x, node.y)
            let drift = node.kind == .center ? (x: 0.0, y: 0.0) : Self.drift(seed: BrainMotion.seed(node.id), time: time, amplitude: 3)
            positions[node.id] = (node.x + drift.x, node.y + drift.y)
        }
        for node in nodes where node.kind == .item {
            let anchorID = node.anchorID ?? BrainLayout.centerID
            let anchor = positions[anchorID] ?? (0, 0)
            let rest = resting[anchorID] ?? (0, 0)
            let drift = Self.drift(seed: BrainMotion.seed(node.id), time: time, amplitude: 1.5)
            positions[node.id] = (anchor.x + (node.x - rest.x) * spread + drift.x, anchor.y + (node.y - rest.y) * spread + drift.y)
        }
        return positions
    }

    /// Petit flottement, nul au temps 0, borné par deux fois `amplitude`.
    static func drift(seed: UInt64, time: Double, amplitude: Double) -> (x: Double, y: Double) {
        let period = 6 + Double(seed % 41) / 10
        let phase = Double(seed % 628) / 100
        let angle = 2 * Double.pi * time / period
        return (amplitude * (sin(angle + phase) - sin(phase)),
                amplitude * (cos(angle * 0.8 + phase) - cos(phase)))
    }

    static func short(_ title: String) -> String {
        title.count > 26 ? String(title.prefix(25)) + "…" : title
    }

    /// Couleur d'un nœud : celle de sa grande catégorie (une note prend la couleur de la sienne).
    private func color(for node: BrainLayout.Node, in all: [UUID: BrainLayout.Node]) -> Color {
        var current: BrainLayout.Node? = node
        var depth = 0
        while let item = current, depth < 8 {
            if item.kind == .center { return Color(.systemGray) }
            if item.kind == .category && item.anchorID == nil { return Color.category(item.label) }
            current = item.anchorID.flatMap { all[$0] }
            depth += 1
        }
        return Color(.systemGray)
    }

    /// Point de contrôle d'une connexion : un peu de courbure, toujours du même côté pour un même neurone.
    static func control(from start: CGPoint, to end: CGPoint, seed: UInt64) -> CGPoint {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let bend = (seed % 2 == 0 ? 1.0 : -1.0) * 0.12
        return CGPoint(x: middle.x - dy * bend, y: middle.y + dx * bend)
    }

    // MARK: - Caméra

    /// Caméra au temps donné : un mouvement doux (0,6 s) quand on centre une catégorie.
    private func currentCamera(at date: Date) -> BrainCamera {
        guard let move = cameraMove else { return camera }
        let progress = min(1, date.timeIntervalSince(move.start) / 0.6)
        let eased = 1 - pow(1 - progress, 3)
        if progress >= 1 {
            Task { @MainActor in
                if cameraMove?.start == move.start { cameraMove = nil }
            }
        }
        return BrainCamera.interpolate(move.from, move.to, eased)
    }

    private func move(to target: BrainCamera, focus id: UUID?) {
        focused = id
        if reduceMotion {
            camera = target
            cameraMove = nil
            return
        }
        cameraMove = (from: currentCamera(at: Date()), to: target, start: Date())
        camera = target
    }

    /// Centre le neurone, un peu au-dessus du milieu (le panneau de ses notes s'ouvre en bas).
    private func focus(on node: BrainLayout.Node) {
        let scale = 2.2
        let fit = lastFit
        move(to: BrainCamera(scale: scale, offset: CGSize(width: -node.x * fit * scale, height: -node.y * fit * scale - 90)),
             focus: node.id)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = gestureStart ?? camera
                gestureStart = start
                cameraMove = nil
                camera.scale = min(6, max(0.4, start.scale * value.magnification))
            }
            .onEnded { _ in gestureStart = nil }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = gestureStart ?? camera
                gestureStart = start
                cameraMove = nil
                camera.offset = CGSize(width: start.offset.width + value.translation.width,
                                       height: start.offset.height + value.translation.height)
            }
            .onEnded { _ in gestureStart = nil }
    }

    /// Toucher : une note s'ouvre, un neurone se centre (ou s'ouvre s'il l'était déjà), ailleurs on referme.
    private func tap(at location: CGPoint, in size: CGSize, fit: CGFloat) {
        let current = currentCamera(at: Date())
        let factor = fit * current.scale
        let center = CGPoint(x: size.width / 2 + current.offset.width, y: size.height / 2 + current.offset.height)
        let positions = animatedPositions(time: reduceMotion ? 0 : Date().timeIntervalSince(epoch))
        let candidates = nodes.filter { $0.kind != .center }.compactMap { node -> (BrainLayout.Node, CGFloat)? in
            guard let position = positions[node.id] else { return nil }
            let p = CGPoint(x: center.x + position.x * factor, y: center.y + position.y * factor)
            return (node, hypot(p.x - location.x, p.y - location.y))
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 < 30 else {
            if focused != nil { move(to: BrainCamera(), focus: nil) }
            return
        }
        tapCount += 1
        switch nearest.0.kind {
        case .item: model.brainPath.append(nearest.0.id)
        case .category: if focused == nearest.0.id { openCategory(nearest.0.id) } else { focus(on: nearest.0) }
        case .center: break
        }
    }

    /// Échelle qui fait tenir tout le réseau dans l'écran, étiquettes comprises.
    private func fitScale(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) / layoutSize * 1.15
        guard !nodes.isEmpty else { return base }
        let maxX = nodes.map { abs($0.x) + $0.radius }.max() ?? 0
        let maxY = nodes.map { abs($0.y) + $0.radius }.max() ?? 0
        // Marge assez large pour le nom d'une sous-catégorie placé à côté de son neurone.
        let fitX = maxX > 0 ? (size.width / 2 - 100) / maxX : base
        let fitY = maxY > 0 ? (size.height / 2 - 50) / maxY : base
        let fit = max(0.05, min(base * 1.6, fitX, fitY))
        if abs(fit - lastFit) > 0.0001 { Task { @MainActor in lastFit = fit } }
        return fit
    }

    /// Pensées rattachées directement à une catégorie.
    private func itemCount(in categoryID: UUID) -> Int {
        nodes.filter { $0.kind == .item && $0.anchorID == categoryID }.count
    }

    /// Pensées d'une grande catégorie, sous-catégories comprises.
    private func totalCount(under rootID: UUID) -> Int {
        let children = Set(categoryNodes.filter { $0.anchorID == rootID }.map(\.id))
        return nodes.filter { $0.kind == .item && ($0.anchorID == rootID || children.contains($0.anchorID ?? UUID())) }.count
    }

    private func openCategory(_ id: UUID) {
        if let category = try? model.categories.activeCategories().first(where: { $0.id == id }) {
            model.brainPath.append(NotesRoute.category(category))
        }
    }
}

/// Position et zoom du Cerveau.
struct BrainCamera: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    static func interpolate(_ from: BrainCamera, _ to: BrainCamera, _ t: Double) -> BrainCamera {
        BrainCamera(scale: from.scale + (to.scale - from.scale) * t,
                    offset: CGSize(width: from.offset.width + (to.offset.width - from.offset.width) * t,
                                   height: from.offset.height + (to.offset.height - from.offset.height) * t))
    }
}

/// Fond du Cerveau : une lumière très douce au centre, sur le fond du système.
private struct BrainBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            RadialGradient(colors: colorScheme == .dark
                           ? [Color(hue: 0.68, saturation: 0.4, brightness: 0.17), Color(white: 0.03)]
                           : [Color(hue: 0.68, saturation: 0.06, brightness: 1), Color(.systemGroupedBackground)],
                           center: .center, startRadius: 0,
                           endRadius: max(geometry.size.width, geometry.size.height) * 0.7)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
