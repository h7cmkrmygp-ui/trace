import Foundation
import Testing
@testable import EngramCore

/// P38 — corriger une fois partout : quand le propriétaire sort une note d'un dossier, les notes que l'IA avait rangées
/// dans ce même dossier peuvent suivre ; jamais celles qu'il a rangées lui-même.
struct MoveSuggestionsTests {
    @Test func onlyNotesTheAIFiledInTheFolderBeingLeftCanFollow() {
        let current = UUID()
        let sameFolder = FilingSample(id: UUID(), text: "Assurance de la maison", paths: ["Automobile › Pièces"], byOwner: false)
        let ownerChoice = FilingSample(id: UUID(), text: "Assurance de l'auto", paths: ["Automobile › Pièces"], byOwner: true)
        let elsewhere = FilingSample(id: UUID(), text: "Payer l'assurance", paths: ["Finances"], byOwner: false)
        let itself = FilingSample(id: current, text: "Réévaluer l'assurance", paths: ["Automobile › Pièces"], byOwner: false)
        let candidates = MoveSuggestions.candidates([sameFolder, ownerChoice, elsewhere, itself],
                                                    leaving: ["Automobile › Pièces"], excluding: current)
        #expect(candidates.map(\.id) == [sameFolder.id])
        #expect(MoveSuggestions.candidates([sameFolder], leaving: [], excluding: current).isEmpty)
    }

    @Test func theProposalIsWrittenForTheOwner() {
        #expect(MoveSuggestions.message(count: 1, folder: "Finances › Assurances")
            == "Déplacer aussi 1 note semblable dans « Finances › Assurances » ?")
        #expect(MoveSuggestions.message(count: 3, folder: "Finances")
            == "Déplacer aussi 3 notes semblables dans « Finances » ?")
    }
}
