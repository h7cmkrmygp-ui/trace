import Foundation
import Testing
@testable import EngramCore

/// P19 — les listes à la voix : « coche le lait », « j'ai acheté le pain », « enlève les bananes de ma liste ».
struct ListActionTests {
    func action(_ text: String) -> ListAction? { ListActionParser.parse(text) }

    @Test func checkingOffIsRecognized() {
        #expect(action("Coche le lait sur ma liste d'épicerie")
            == ListAction(kind: .check, listName: "épicerie", items: ["Lait"], isExplicit: true))
        #expect(action("Coche le lait et les œufs") == ListAction(kind: .check, listName: nil, items: ["Lait", "Œufs"], isExplicit: true))
        #expect(action("J'ai acheté le pain pis le beurre")
            == ListAction(kind: .check, listName: nil, items: ["Pain", "Beurre"], isExplicit: false))
        #expect(action("I bought milk") == ListAction(kind: .check, listName: nil, items: ["Milk"], isExplicit: false))
    }

    @Test func removingIsRecognized() {
        #expect(action("Enlève les bananes de ma liste d'épicerie")
            == ListAction(kind: .remove, listName: "épicerie", items: ["Bananes"], isExplicit: true))
        #expect(action("Retire le livre de la liste de cadeaux")
            == ListAction(kind: .remove, listName: "cadeaux", items: ["Livre"], isExplicit: true))
        #expect(action("Remove bread from my grocery list")
            == ListAction(kind: .remove, listName: "épicerie", items: ["Bread"], isExplicit: true))
    }

    @Test func otherSentencesAreNotListActions() {
        #expect(action("Enlève tes souliers en entrant") == nil)
        #expect(action("Ajoute du lait à ma liste d'épicerie") == nil)
        #expect(action("Acheter du lait") == nil)
    }

    @Test func spokenItemsFindTheirBox() {
        #expect(ListMerge.matches("lait", "Lait 2 %"))
        #expect(ListMerge.matches("bananes", "Banane"))
        #expect(ListMerge.matches("Œufs", "oeufs"))
        #expect(!ListMerge.matches("lait", "Laitue"))
    }

    @Test func boxesAreCheckedOrRemoved() {
        let body = "☐ Pain\n☐ Lait 2 %\n☑ Café\nPour samedi"
        let checked = ListMerge.checking(["lait", "café", "beurre"], in: body)
        #expect(checked.body == "☐ Pain\n☑ Lait 2 %\n☑ Café\nPour samedi")
        #expect(checked.changed == ["Lait 2 %"])
        let removed = ListMerge.removing(["pain", "café"], from: body)
        #expect(removed.body == "☐ Lait 2 %\nPour samedi")
        #expect(removed.changed == ["Pain", "Café"])
    }
}
