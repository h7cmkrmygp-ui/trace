import Foundation
import Testing
@testable import EngramCore

/// P15 — les listes : « ajoute du lait à ma liste d'épicerie » va dans la liste, pas dans une nouvelle note.
struct ListsTests {
    func command(_ text: String) -> ListCommand? { ListCommandParser.parse(text) }

    @Test func addingToAListIsRecognized() {
        #expect(command("Ajoute du lait et des œufs à ma liste d'épicerie") == ListCommand(listName: "épicerie", items: ["Lait", "Œufs"]))
        #expect(command("Rajoute du papier de toilette sur la liste de Costco")
            == ListCommand(listName: "Costco", items: ["Papier de toilette"]))
        #expect(command("Mets du pain, du beurre pis des bananes sur la liste")
            == ListCommand(listName: "épicerie", items: ["Pain", "Beurre", "Bananes"]))
        #expect(command("Sur ma liste de cadeaux, ajoute un livre pour Julie")
            == ListCommand(listName: "cadeaux", items: ["Livre pour Julie"]))
        #expect(command("Liste d'épicerie : lait, café") == ListCommand(listName: "épicerie", items: ["Lait", "Café"]))
        #expect(command("Ajoute Julie à la liste des invités") == ListCommand(listName: "invités", items: ["Julie"]))
        #expect(command("Faut ajouter 2 litres de lait à ma liste de courses")
            == ListCommand(listName: "épicerie", items: ["2 litres de lait"]))
        #expect(command("Add milk and eggs to my grocery list") == ListCommand(listName: "épicerie", items: ["Milk", "Eggs"]))
    }

    @Test func ordinarySentencesAreNotListAdditions() {
        #expect(command("Ajoute une réunion jeudi à mon calendrier") == nil)
        #expect(command("J'ai perdu ma liste d'épicerie") == nil)
        #expect(command("Ma liste de choses à faire est trop longue") == nil)
        #expect(command("Acheter du lait et des œufs") == nil)
    }

    @Test func aListHasANaturalTitle() {
        #expect(ListCommandParser.title(for: "épicerie") == "Liste d'épicerie")
        #expect(ListCommandParser.title(for: "cadeaux") == "Liste de cadeaux")
        #expect(ListCommandParser.title(for: "Costco") == "Liste de Costco")
        #expect(ListCommandParser.title(for: "invités") == "Liste d'invités")
        #expect(ListCommandParser.key("Épicerie") == ListCommandParser.key("epicerie"))
    }

    @Test func itemsAreAddedOnceAndComeBackWhenNeededAgain() {
        let merged = ListMerge.adding(["Lait", "Œufs", "pain"], to: "☐ Pain\n☑ Lait")
        #expect(merged.body == "☐ Pain\n☐ Lait\n☐ Œufs")
        #expect(merged.added == ["Lait", "Œufs"])
        #expect(ListMerge.adding(["Café"], to: "").body == "☐ Café")
        #expect(ListMerge.adding(["Café"], to: "Pour samedi").body == "Pour samedi\n☐ Café")
    }

    @Test func checkedItemsCanBeCleared() {
        #expect(ListMerge.removingChecked(from: "☐ Pain\n☑ Lait\nPour samedi\n☑ Café") == "☐ Pain\nPour samedi")
    }
}
