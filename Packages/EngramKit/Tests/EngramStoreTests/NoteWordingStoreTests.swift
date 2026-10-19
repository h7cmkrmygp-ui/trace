import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// Demande du propriétaire : « Je pèse 162,5 livres aujourd'hui » devient une note datée du vrai jour,
/// tandis que ses mots exacts restent dans la note.
struct NoteWordingStoreTests {
    @Test func relativeDaysInTheTitleAndTheTextBecomeTheDayOfTheDictation() throws {
        let env = try StoreTestEnvironment()
        let spoken = "Je pèse 162,5 livres aujourd'hui"
        let interim = try env.saveNote(spoken)
        let thought = ValidThought(title: spoken, summary: "Pesée de ce matin", excerpt: spoken, spanStart: 0,
                                   spanEnd: (spoken as NSString).length, kind: .info, tags: [], categoryPath: ["Santé"],
                                   mentionedDates: ["aujourd'hui"])
        let memory = try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
        #expect(memory.title == "Je pèse 162,5 livres le 15 janvier")
        #expect(memory.summary == "Pesée du 15 janvier au matin")
        #expect(memory.content == spoken)
    }
}
