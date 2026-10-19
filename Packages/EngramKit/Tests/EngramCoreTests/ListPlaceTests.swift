import Foundation
import Testing
@testable import EngramCore

/// P29 — ce que dit le rappel d'une liste en arrivant au magasin.
struct ListPlaceTests {
    @Test func theReminderSaysWhatToBuy() {
        #expect(ListSpeech.waitingTitle("Liste de Costco", open: ["Piles", "Papier de toilette"])
            == "Liste de Costco : piles et papier de toilette")
        #expect(ListSpeech.waitingTitle("Liste d'épicerie", open: ["Lait", "Pain", "Œufs", "Café", "Beurre"])
            == "Liste d'épicerie : lait, pain, œufs et 2 autres")
        #expect(ListSpeech.waitingTitle("Liste de Costco", open: ["Piles"]) == "Liste de Costco : piles")
    }
}
