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

/// Le Cerveau : la mémoire comme un réseau de neurones. Chaque catégorie est un neurone de sa couleur qui respire,
/// ses notes tournent autour d'elle, des signaux parcourent les connexions. Pincer pour zoomer, glisser pour se
/// déplacer, toucher pour ouvrir ; la rangée de catégories centre un neurone d'un toucher (un deuxième l'ouvre).
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
    @State private var path = NavigationPath()
    @State private var tapCount = 0
    private let epoch = Date()

    /// La disposition est calculée dans un carré de cette taille, puis adaptée à l'écran.
    private let layoutSize = 1000.0

    private var itemCount: Int { nodes.filter { $0.kind == .item }.count }
    private var categoryNodes: [BrainLayout.Node] { nodes.filter { $0.kind == .category } }
    private var rootNodes: [BrainLayout.Node] { categoryNodes.filter { $0.anchorID == nil } }
    private var matches: Set<UUID> {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return Set(nodes.filter { $0.kind != .center && $0.label.localizedStandardContains(needle) }.map(\.id))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BrainBackdrop(isEmpty: itemCount == 0)
                GeometryReader { geometry in
                    let fit = fitScale(for: geometry.size)
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion && cameraMove == nil)) { timeline in
                        canvas(fit: fit, time: animationTime(at: timeline.date), camera: currentCamera(at: timeline.date))
                    }
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
                        nodes = BrainLayout.layout(categories: snapshot.categories, items: snapshot.items, size: layoutSize)
                        categoryNames = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) })
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
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
                        if isFocused {
                            openCategory(node.id)
                        } else {
                            focus(on: node)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color.category(node.label)).frame(width: 8, height: 8)
                            Text(node.label).font(.subheadline.weight(isFocused ? .semibold : .regular))
                            Text("\(totalCount(under: node.id))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isFocused ? Color.category(node.label).opacity(0.22) : Color.clear, in: Capsule())
                        .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isFocused ? "Ouvre la catégorie" : "Centre la catégorie dans le cerveau")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Dessin

    private func canvas(fit: CGFloat, time: Double, camera: BrainCamera) -> some View {
        let highlighted = matches
        let isSearching = !highlighted.isEmpty
        let positions = animatedPositions(time: time)
        let dark = colorScheme == .dark
        return Canvas { context, size in
            let factor = fit * camera.scale
            let center = CGPoint(x: size.width / 2 + camera.offset.width, y: size.height / 2 + camera.offset.height)
            func point(_ id: UUID) -> CGPoint? {
                positions[id].map { CGPoint(x: center.x + $0.x * factor, y: center.y + $0.y * factor) }
            }
            let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

            // Synapses : courbes douces de la couleur des neurones qu'elles relient.
            for node in nodes where node.kind != .center {
                let anchorID = node.anchorID ?? BrainLayout.centerID
                guard let start = point(anchorID), let end = point(node.id) else { continue }
                let control = Self.control(from: start, to: end, seed: BrainMotion.seed(node.id))
                var curve = Path()
                curve.move(to: start)
                curve.addQuadCurve(to: end, control: control)
                let color = self.color(for: node, in: nodeByID)
                let dimmed = isSearching && !highlighted.contains(node.id)
                let opacity = node.kind == .category ? (dark ? 0.35 : 0.3) : (dark ? 0.12 : 0.1)
                context.stroke(curve, with: .linearGradient(
                    Gradient(colors: [self.color(forID: anchorID, in: nodeByID).opacity(opacity), color.opacity(opacity)]),
                    startPoint: start, endPoint: end), lineWidth: node.kind == .category ? 1.4 : 0.6)
                // Signaux : une petite lumière parcourt la connexion de temps en temps.
                if node.kind == .category, !dimmed, let progress = BrainMotion.signal(seed: BrainMotion.seed(node.id), time: time) {
                    let spot = Self.point(onCurveFrom: start, control: control, to: end, at: progress)
                    let glow = CGRect(x: spot.x - 6, y: spot.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: glow), with: .radialGradient(
                        Gradient(colors: [color.opacity(0.9), color.opacity(0)]), center: spot, startRadius: 0, endRadius: 6))
                    context.fill(Path(ellipseIn: CGRect(x: spot.x - 1.6, y: spot.y - 1.6, width: 3.2, height: 3.2)),
                                 with: .color(.white.opacity(0.95)))
                }
            }

            // Halo des neurones (flou), dessiné à part pour la profondeur.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 14))
                for node in nodes where node.kind != .item {
                    guard let p = point(node.id) else { continue }
                    let dimmed = isSearching && !highlighted.contains(node.id)
                    let radius = haloRadius(node, factor: factor, time: time)
                    let color = node.kind == .center ? Color.white : self.color(for: node, in: nodeByID)
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(color.opacity(dimmed ? 0.08 : (dark ? 0.55 : 0.35))))
                }
            }

            // Notes : des étincelles en orbite autour de leur catégorie.
            for node in nodes where node.kind == .item {
                guard let p = point(node.id) else { continue }
                let color = self.color(for: node, in: nodeByID)
                let isMatch = highlighted.contains(node.id)
                let dimmed = isSearching && !isMatch
                let radius = CGFloat(max(1.6, min(4, 2.4 * Double(factor) * 1.6)) * (isMatch ? 1.8 : 1))
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius * 2.2, y: p.y - radius * 2.2, width: radius * 4.4, height: radius * 4.4)),
                             with: .radialGradient(Gradient(colors: [color.opacity(dimmed ? 0.05 : 0.45), color.opacity(0)]),
                                                   center: p, startRadius: 0, endRadius: radius * 2.2))
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(isMatch ? .white : color.opacity(dimmed ? 0.2 : 0.95)))
            }

            // Neurones : sphères lumineuses qui respirent ; le centre, c'est toi.
            for node in nodes where node.kind != .item {
                guard let p = point(node.id) else { continue }
                let dimmed = isSearching && !highlighted.contains(node.id)
                let radius = coreRadius(node, factor: factor, time: time)
                let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                if node.kind == .center {
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [.white, dark ? Color(white: 0.85) : Color(white: 0.75)]),
                        center: CGPoint(x: p.x - radius * 0.3, y: p.y - radius * 0.3), startRadius: 0, endRadius: radius * 1.4))
                    continue
                }
                let color = self.color(for: node, in: nodeByID)
                context.opacity = dimmed ? 0.25 : 1
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.95), color, color.opacity(0.75)]),
                    center: CGPoint(x: p.x - radius * 0.35, y: p.y - radius * 0.35), startRadius: 0, endRadius: radius * 1.5))
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(color.opacity(0.5)), lineWidth: 1)
                let label = Text(node.label)
                    .font(.system(size: node.anchorID == nil ? 13 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(dark ? Color.white.opacity(0.92) : Color.primary.opacity(0.85))
                context.draw(context.resolve(label), at: CGPoint(x: p.x, y: p.y + radius + 5), anchor: .top)
                context.opacity = 1
            }
        }
    }

    /// Rayon d'un neurone, qui respire (sauf avec « Réduire les animations », où le temps est arrêté).
    private func coreRadius(_ node: BrainLayout.Node, factor: CGFloat, time: Double) -> CGFloat {
        let base: Double = node.kind == .center ? 9 : node.radius * 1.15
        let seed: UInt64 = node.kind == .center ? 1 : BrainMotion.seed(node.id)
        let zoom = min(1.8, max(0.7, Double(factor) * 1.5))
        return CGFloat(max(4, base * zoom) * BrainMotion.pulse(seed: seed, time: time))
    }

    private func haloRadius(_ node: BrainLayout.Node, factor: CGFloat, time: Double) -> CGFloat {
        coreRadius(node, factor: factor, time: time) * (node.kind == .center ? 3 : 2.4)
    }

    /// Positions au temps donné : les notes tournent autour de leur catégorie (ou du centre), le reste ne bouge pas.
    private func animatedPositions(time: Double) -> [UUID: (x: Double, y: Double)] {
        var positions: [UUID: (x: Double, y: Double)] = [:]
        for node in nodes where node.kind != .item { positions[node.id] = (node.x, node.y) }
        for node in nodes where node.kind == .item {
            let anchor = positions[node.anchorID ?? BrainLayout.centerID] ?? (0, 0)
            positions[node.id] = BrainMotion.orbit((node.x, node.y), around: anchor, seed: BrainMotion.seed(node.id), time: time)
        }
        return positions
    }

    private func animationTime(at date: Date) -> Double {
        reduceMotion ? 0 : date.timeIntervalSince(epoch)
    }

    /// Couleur d'un nœud : celle de sa grande catégorie (une note prend la couleur de la sienne).
    private func color(for node: BrainLayout.Node, in all: [UUID: BrainLayout.Node]) -> Color {
        color(forID: node.id, in: all)
    }

    private func color(forID id: UUID, in all: [UUID: BrainLayout.Node]) -> Color {
        var current = all[id]
        var depth = 0
        while let node = current, depth < 8 {
            if node.kind == .center { return colorScheme == .dark ? Color.white : Color(white: 0.55) }
            if node.kind == .category && node.anchorID == nil { return Color.category(node.label) }
            current = node.anchorID.flatMap { all[$0] } ?? all[BrainLayout.centerID]
            depth += 1
        }
        return .gray
    }

    /// Point de contrôle d'une synapse : un peu de courbure, toujours du même côté pour un même neurone.
    static func control(from start: CGPoint, to end: CGPoint, seed: UInt64) -> CGPoint {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let bend = (seed % 2 == 0 ? 1.0 : -1.0) * 0.18
        return CGPoint(x: middle.x - dy * bend, y: middle.y + dx * bend)
    }

    static func point(onCurveFrom start: CGPoint, control: CGPoint, to end: CGPoint, at t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }

    // MARK: - Caméra

    /// Caméra au temps donné : une animation douce (0,6 s) quand on centre une catégorie.
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

    private func focus(on node: BrainLayout.Node) {
        let scale = 2.4
        // La caméra amène le neurone au centre de l'écran, agrandi.
        let fit = lastFit
        move(to: BrainCamera(scale: scale, offset: CGSize(width: -node.x * fit * scale, height: -node.y * fit * scale)),
             focus: node.id)
    }

    @State private var lastFit: CGFloat = 0.4

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

    /// Ouvre le nœud le plus proche du toucher (catégorie ou pensée), à sa position du moment.
    private func open(at location: CGPoint, in size: CGSize, fit: CGFloat) {
        let current = currentCamera(at: Date())
        let factor = fit * current.scale
        let center = CGPoint(x: size.width / 2 + current.offset.width, y: size.height / 2 + current.offset.height)
        let positions = animatedPositions(time: animationTime(at: Date()))
        let candidates = nodes.filter { $0.kind != .center }.compactMap { node -> (BrainLayout.Node, CGFloat)? in
            guard let position = positions[node.id] else { return nil }
            let p = CGPoint(x: center.x + position.x * factor, y: center.y + position.y * factor)
            return (node, hypot(p.x - location.x, p.y - location.y))
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 < 30 else { return }
        tapCount += 1
        switch nearest.0.kind {
        case .item: path.append(nearest.0.id)
        case .category: openCategory(nearest.0.id)
        case .center: break
        }
    }

    /// Échelle qui fait tenir tout le nuage dans l'écran, étiquettes comprises (une étiquette ne déborde plus du bord).
    private func fitScale(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) / layoutSize * 1.15
        guard !nodes.isEmpty else { return base }
        let maxX = nodes.map { abs($0.x) + $0.radius }.max() ?? 0
        let maxY = nodes.map { abs($0.y) + $0.radius }.max() ?? 0
        let fitX = maxX > 0 ? (size.width / 2 - 70) / maxX : base
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
            path.append(NotesRoute.category(category))
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

/// Fond du Cerveau : un dégradé profond et la silhouette d'un cerveau, très légère, qui respire lentement.
private struct BrainBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isEmpty: Bool
    @State private var breathing = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                RadialGradient(colors: colorScheme == .dark
                               ? [Color(hue: 0.72, saturation: 0.55, brightness: 0.2), Color(hue: 0.68, saturation: 0.6, brightness: 0.06), .black]
                               : [Color(hue: 0.7, saturation: 0.06, brightness: 1), Color(hue: 0.7, saturation: 0.1, brightness: 0.95)],
                               center: .center, startRadius: 0, endRadius: max(geometry.size.width, geometry.size.height) * 0.75)
                if !isEmpty {
                    Image(systemName: "brain")
                        .font(.system(size: side * 0.82, weight: .ultraLight))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.05) : Color(hue: 0.7, saturation: 0.4, brightness: 0.5).opacity(0.06))
                        .scaleEffect(breathing ? 1.025 : 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .accessibilityHidden(true)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}
