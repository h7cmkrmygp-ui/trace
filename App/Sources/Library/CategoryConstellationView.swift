import EngramCore
import EngramStore
import SwiftUI

/// En haut d'un dossier des Notes : ses pensées en petit réseau, dans le style du Cerveau. Le dossier au centre, ses
/// sous-dossiers autour (avec leur nom), chaque pensée en point qui flotte à peine. Toucher un point ouvre la note ;
/// toucher un sous-dossier fait défiler jusqu'à sa section.
struct CategoryConstellationView: View {
    let root: EngramCategory
    let sections: [CategoryStore.CategorySection]
    let tint: Color
    let onOpenMemory: (UUID) -> Void
    let onSelectSection: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var tapCount = 0
    private let epoch = Date()

    private var subcategories: [EngramCategory] {
        sections.map(\.category).filter { $0.id != root.id }
    }

    private var nodes: [CategoryConstellation.Node] {
        // Une pensée rangée à la fois dans le dossier et dans un sous-dossier va près du sous-dossier.
        var seen = Set<UUID>()
        var items: [(UUID, UUID?)] = []
        let ordered = sections.filter { $0.category.id != root.id } + sections.filter { $0.category.id == root.id }
        for section in ordered {
            for memory in section.memories where seen.insert(memory.id).inserted { items.append((memory.id, section.category.id)) }
        }
        return CategoryConstellation.layout(rootID: root.id, subcategories: subcategories.map(\.id), items: items)
    }

    private var noteCount: Int { Set(sections.flatMap { $0.memories.map(\.id) }).count }

    var body: some View {
        GeometryReader { geometry in
            let layout = nodes
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                canvas(layout, time: reduceMotion ? 0 : timeline.date.timeIntervalSince(epoch))
            }
            .contentShape(Rectangle())
            .onTapGesture { location in tap(at: location, in: geometry.size, nodes: layout) }
        }
        .frame(height: 220)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sensoryFeedback(.selection, trigger: tapCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(root.name) : \(NotesView.count(noteCount, "pensée", nil))"
            + (subcategories.isEmpty ? "" : ", \(NotesView.count(subcategories.count, "sous-dossier", nil))"))
    }

    /// Un ou deux sous-dossiers vont sur les côtés (la carte est plus large que haute) ; à partir de trois, tout autour.
    private var turnsSideways: Bool { subcategories.count <= 2 }

    private func position(_ node: CategoryConstellation.Node, in size: CGSize, time: Double,
                          anchors: [UUID: CategoryConstellation.Node]) -> CGPoint {
        let drift = node.kind == .root ? (x: 0.0, y: 0.0)
            : BrainView.drift(seed: BrainMotion.seed(node.id), time: time, amplitude: node.kind == .item ? 0.012 : 0.02)
        // Une pensée suit le flottement de son dossier.
        let follow = node.anchorID.flatMap { anchors[$0] }.map { anchor in
            anchor.kind == .root ? (x: 0.0, y: 0.0) : BrainView.drift(seed: BrainMotion.seed(anchor.id), time: time, amplitude: 0.02)
        } ?? (x: 0.0, y: 0.0)
        let x = node.x + drift.x + follow.x
        let y = node.y + drift.y + follow.y
        let (dx, dy) = turnsSideways ? (-y, x) : (x, y)
        // Une ellipse qui épouse la carte, en laissant la place des noms.
        return CGPoint(x: size.width / 2 + dx * (size.width / 2 - 56), y: size.height / 2 + dy * (size.height / 2 - 30))
    }

    private func canvas(_ layout: [CategoryConstellation.Node], time: Double) -> some View {
        let dark = colorScheme == .dark
        let anchors = Dictionary(uniqueKeysWithValues: layout.filter { $0.kind != .item }.map { ($0.id, $0) })
        let names = Dictionary(uniqueKeysWithValues: subcategories.map { ($0.id, $0.name) })
        return Canvas { context, size in
            func circle(_ p: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            let center = position(layout[0], in: size, time: time, anchors: anchors)
            // Connexions du dossier vers ses sous-dossiers.
            for node in layout where node.kind == .subcategory {
                let p = position(node, in: size, time: time, anchors: anchors)
                var line = Path()
                line.move(to: center)
                line.addLine(to: p)
                context.stroke(line, with: .color(tint.opacity(dark ? 0.35 : 0.28)), lineWidth: 1)
            }
            // Pensées : de petits points de la couleur du dossier, avec un léger halo.
            for node in layout where node.kind == .item {
                let p = position(node, in: size, time: time, anchors: anchors)
                context.fill(circle(p, 7), with: .color(tint.opacity(dark ? 0.14 : 0.1)))
                context.fill(circle(p, 3.8), with: .color(tint.opacity(0.9)))
            }
            // Sous-dossiers et dossier : des sphères douces, éclairées d'en haut.
            for node in layout where node.kind != .item {
                let p = position(node, in: size, time: time, anchors: anchors)
                let radius: CGFloat = node.kind == .root ? 15 : 9
                context.fill(circle(p, radius + 5), with: .color(tint.opacity(dark ? 0.16 : 0.12)))
                context.fill(circle(p, radius), with: .radialGradient(
                    Gradient(colors: [tint.mix(with: .white, by: dark ? 0.3 : 0.4), tint]),
                    center: CGPoint(x: p.x - radius * 0.4, y: p.y - radius * 0.4), startRadius: 0, endRadius: radius * 1.7))
                if node.kind == .subcategory, let name = names[node.id] {
                    // Le nom vers l'extérieur, à l'opposé du dossier : il ne chevauche ni le trait ni le centre.
                    let label = Text(name).font(.caption.weight(.medium)).foregroundStyle(Color.primary.opacity(0.7))
                    let gap = radius + 6
                    let (at, anchor): (CGPoint, UnitPoint) = abs(p.x - center.x) > abs(p.y - center.y)
                        ? (p.x > center.x ? (CGPoint(x: p.x + gap, y: p.y), .leading) : (CGPoint(x: p.x - gap, y: p.y), .trailing))
                        : (p.y > center.y ? (CGPoint(x: p.x, y: p.y + gap), .top) : (CGPoint(x: p.x, y: p.y - gap), .bottom))
                    context.draw(context.resolve(label), at: at, anchor: anchor)
                }
            }
        }
    }

    private func tap(at location: CGPoint, in size: CGSize, nodes layout: [CategoryConstellation.Node]) {
        let time = reduceMotion ? 0 : Date().timeIntervalSince(epoch)
        let anchors = Dictionary(uniqueKeysWithValues: layout.filter { $0.kind != .item }.map { ($0.id, $0) })
        let nearest = layout.filter { $0.kind != .root }
            .map { ($0, hypot(position($0, in: size, time: time, anchors: anchors).x - location.x,
                              position($0, in: size, time: time, anchors: anchors).y - location.y)) }
            .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 < 24 else { return }
        tapCount += 1
        switch nearest.0.kind {
        case .item: onOpenMemory(nearest.0.id)
        case .subcategory: onSelectSection(nearest.0.id)
        case .root: break
        }
    }
}
