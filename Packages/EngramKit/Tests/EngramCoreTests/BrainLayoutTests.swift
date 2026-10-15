import Foundation
import Testing
@testable import EngramCore

struct BrainLayoutTests {
    let automobile = BrainLayout.CategoryInput(id: UUID(), name: "Automobile", parentID: nil)
    let finance = BrainLayout.CategoryInput(id: UUID(), name: "Finance", parentID: nil)
    var corolla: BrainLayout.CategoryInput { BrainLayout.CategoryInput(id: corollaID, name: "Corolla", parentID: automobile.id) }
    let corollaID = UUID()

    func items(_ count: Int, in categoryID: UUID?) -> [BrainLayout.ItemInput] {
        (0..<count).map { BrainLayout.ItemInput(id: UUID(), title: "Pensée \($0)", categoryID: categoryID) }
    }

    func distance(_ a: BrainLayout.Node, _ b: BrainLayout.Node) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Bug signalé : « Ton cerveau est vide » s'affichait par-dessus des points. Mémoire vide : aucun point, pas même le centre.
    @Test func emptyMemoryHasNoNodes() {
        #expect(BrainLayout.layout(categories: [], items: [], size: 800).isEmpty)
        // Une seule pensée « À classer » suffit pour revoir le centre.
        #expect(BrainLayout.layout(categories: [], items: items(1, in: nil), size: 800).map(\.kind) == [.center, .item])
    }

    @Test func placesEveryCategoryAndThoughtDeterministically() {
        let categories = [automobile, finance, corolla]
        let thoughts = items(12, in: corollaID) + items(5, in: finance.id) + items(3, in: nil)
        let first = BrainLayout.layout(categories: categories, items: thoughts, size: 800)
        let second = BrainLayout.layout(categories: categories, items: thoughts, size: 800)
        #expect(first == second)
        #expect(first.count == 1 + categories.count + thoughts.count)
        #expect(first.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.radius > 0 })
    }

    @Test func rootCategoriesSitOnACircle() {
        let nodes = BrainLayout.layout(categories: [automobile, finance], items: [], size: 1000)
        for node in nodes where node.kind == .category {
            #expect(abs((node.x * node.x + node.y * node.y).squareRoot() - 320) < 0.001)
        }
    }

    @Test func thoughtsStayCloseToTheirCategory() throws {
        let thoughts = items(20, in: finance.id)
        let nodes = BrainLayout.layout(categories: [automobile, finance], items: thoughts, size: 800)
        let financeNode = try #require(nodes.first { $0.id == finance.id })
        let center = try #require(nodes.first { $0.kind == .center })
        for node in nodes where node.kind == .item {
            #expect(node.anchorID == finance.id)
            #expect(distance(node, financeNode) < distance(node, center))
        }
    }

    @Test func biggerCategoriesHaveBiggerNodes() throws {
        let nodes = BrainLayout.layout(categories: [automobile, finance],
                                       items: items(25, in: finance.id) + items(1, in: automobile.id), size: 800)
        let financeNode = try #require(nodes.first { $0.id == finance.id })
        let autoNode = try #require(nodes.first { $0.id == automobile.id })
        #expect(financeNode.radius > autoNode.radius)
    }
}
