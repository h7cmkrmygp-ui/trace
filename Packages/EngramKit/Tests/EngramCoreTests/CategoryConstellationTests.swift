import Foundation
import Testing
@testable import EngramCore

/// Le petit réseau en haut d'un dossier des Notes : le dossier au centre, ses sous-dossiers autour, chaque pensée
/// près de son dossier, le tout dans un carré de −1 à 1.
struct CategoryConstellationTests {
    let root = UUID()

    func distance(_ a: CategoryConstellation.Node, _ b: CategoryConstellation.Node) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    @Test func theFolderIsAtTheCenterAndItsSubfoldersSurroundIt() throws {
        let subfolders = [UUID(), UUID(), UUID()]
        let nodes = CategoryConstellation.layout(rootID: root, subcategories: subfolders, items: [])
        let center = try #require(nodes.first { $0.kind == .root })
        #expect(center.x == 0 && center.y == 0)
        let around = nodes.filter { $0.kind == .subcategory }
        #expect(around.map(\.id) == subfolders)
        #expect(around.allSatisfy { abs(distance($0, center) - 0.62) < 1e-9 })
        // Le premier en haut, puis les autres répartis tout autour.
        #expect(around[0].y < 0 && abs(around[0].x) < 1e-9)
        #expect(Set(around.map { "\(Int(($0.x * 100).rounded())),\(Int(($0.y * 100).rounded()))" }).count == 3)
    }

    @Test func eachThoughtStaysNearItsFolder() throws {
        let subfolder = UUID()
        let inSub = UUID()
        let inRoot = UUID()
        let elsewhere = UUID()
        let nodes = CategoryConstellation.layout(rootID: root, subcategories: [subfolder],
                                                 items: [(inSub, subfolder), (inRoot, root), (elsewhere, UUID())])
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let center = try #require(byID[root])
        let sub = try #require(byID[subfolder])
        let subThought = try #require(byID[inSub])
        #expect(subThought.anchorID == subfolder)
        #expect(distance(subThought, sub) < distance(subThought, center))
        #expect(byID[inRoot]?.anchorID == root)
        // Une pensée d'un dossier inconnu reste près du centre.
        #expect(byID[elsewhere]?.anchorID == root)
        #expect(nodes.filter { $0.kind == .item }.count == 3)
    }

    @Test func everythingFitsInTheSquare() {
        let subfolder = UUID()
        let items = (0..<200).map { _ in (UUID(), Optional(root)) } + (0..<50).map { _ in (UUID(), Optional(subfolder)) }
        let nodes = CategoryConstellation.layout(rootID: root, subcategories: [subfolder], items: items)
        #expect(nodes.allSatisfy { abs($0.x) <= 1 && abs($0.y) <= 1 })
    }

    @Test func anEmptyFolderIsJustItsCenter() {
        let nodes = CategoryConstellation.layout(rootID: root, subcategories: [], items: [])
        #expect(nodes.map(\.kind) == [.root])
    }
}
