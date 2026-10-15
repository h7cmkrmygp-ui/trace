import Foundation
import Testing
@testable import EngramCore

/// P25 — le widget « Liste » : les choses qui restent, l'épicerie d'abord ; jamais le détail d'une liste privée.
struct ListsWidgetTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func source(_ name: String, _ body: String, isPrivate: Bool = false) -> ListsSnapshot.Source {
        ListsSnapshot.Source(memoryID: UUID(), name: name, title: ListCommandParser.title(for: name.lowercased()), body: body,
                             isPrivate: isPrivate)
    }

    @Test func theGroceryListComesFirstWithWhatRemains() throws {
        let gifts = source("Cadeaux", "☐ Livre pour Julie")
        let grocery = source("Épicerie", "☐ Lait\n☑ Pain\nPour samedi\n☐ Œufs")
        let snapshot = ListsSnapshot.make([gifts, grocery], hideItems: false, now: Self.now)
        #expect(snapshot.generatedAt == Self.now)
        #expect(snapshot.lists.map(\.title) == ["Liste d'épicerie", "Liste de cadeaux"])
        let first = try #require(snapshot.lists.first)
        #expect(first.memoryID == grocery.memoryID)
        #expect(first.open == ["Lait", "Œufs"])
        #expect(first.openCount == 2)
        #expect(first.done == 1)
    }

    @Test func aPrivateListOrALockedEngramShowsOnlyCounts() throws {
        let secret = source("Pharmacie", "☐ Médicament", isPrivate: true)
        let grocery = source("Épicerie", "☐ Lait")
        let shown = ListsSnapshot.make([secret, grocery], hideItems: false, now: Self.now)
        let pharmacy = try #require(shown.lists.first { $0.memoryID == secret.memoryID })
        #expect(pharmacy.open.isEmpty)
        #expect(pharmacy.openCount == 1)
        #expect(pharmacy.title == "Liste privée")
        let locked = ListsSnapshot.make([grocery], hideItems: true, now: Self.now)
        #expect(locked.lists.first?.open.isEmpty == true)
        #expect(locked.lists.first?.openCount == 1)
        #expect(locked.lists.first?.title == "Liste d'épicerie")
    }

    @Test func aWidgetHoldsAtMostFourListsOfEightItems() {
        let long = source("Épicerie", (1...12).map { "☐ Chose \($0)" }.joined(separator: "\n"))
        let others = (1...5).map { source("Liste\($0)", "☐ Une chose") }
        let snapshot = ListsSnapshot.make([long] + others, hideItems: false, now: Self.now)
        #expect(snapshot.lists.count == 4)
        #expect(snapshot.lists.first?.open.count == 8)
        #expect(snapshot.lists.first?.openCount == 12)
    }
}
