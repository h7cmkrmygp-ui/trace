import Foundation
import Testing
@testable import EngramCore

/// P26 — les listes avec Siri : « qu'est-ce qu'il y a sur ma liste ? », « ajoute du lait à ma liste ».
struct ListSpeechTests {
    func list(_ title: String, open: [String], openCount: Int? = nil, done: Int = 0) -> ListsSnapshot.List {
        ListsSnapshot.List(memoryID: UUID(), title: title, open: open, openCount: openCount ?? open.count, done: done)
    }

    @Test func aListIsReadAloudSimply() {
        #expect(ListSpeech.read(list("Liste d'épicerie", open: ["Lait", "Pain", "Œufs"]))
            == "Sur ta liste d'épicerie : lait, pain et œufs.")
        #expect(ListSpeech.read(list("Liste de Costco", open: ["Papier de toilette"]))
            == "Sur ta liste de Costco : papier de toilette.")
        #expect(ListSpeech.read(list("Liste d'épicerie", open: [], done: 3)) == "Tout est coché sur ta liste d'épicerie.")
        #expect(ListSpeech.read(list("Liste d'épicerie", open: [])) == "Ta liste d'épicerie est vide.")
        #expect(ListSpeech.read(nil) == "Tu n'as pas encore de liste. Dis : « ajoute du lait à ma liste d'épicerie ».")
    }

    @Test func aLongOrPrivateListStaysShort() {
        let long = list("Liste d'épicerie", open: ["A1", "B2", "C3", "D4", "E5", "F6", "G7", "H8"], openCount: 11)
        #expect(ListSpeech.read(long) == "Sur ta liste d'épicerie : A1, B2, C3, D4, E5, F6, G7, H8 et 3 autres choses.")
        #expect(ListSpeech.read(list("Liste privée", open: [], openCount: 2))
            == "Ta liste privée a 2 choses. Ouvre Engram pour les voir.")
    }

    @Test func whatSiriHearsBecomesAListCommand() {
        #expect(ListCommandParser.parse(ListSpeech.addCommand(item: "du lait et des œufs", list: nil))
            == ListCommand(listName: "épicerie", items: ["Lait", "Œufs"]))
        #expect(ListCommandParser.parse(ListSpeech.addCommand(item: "un livre", list: "cadeaux"))
            == ListCommand(listName: "cadeaux", items: ["Livre"]))
        #expect(ListCommandParser.parse(ListSpeech.addCommand(item: "des piles", list: "Costco"))
            == ListCommand(listName: "Costco", items: ["Piles"]))
    }
}
