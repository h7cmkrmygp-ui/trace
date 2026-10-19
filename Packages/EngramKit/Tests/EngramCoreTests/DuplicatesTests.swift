import Foundation
import Testing
@testable import EngramCore

/// P23 — la même pensée dite deux fois : Engram propose de réunir les deux notes.
struct DuplicatesTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func note(_ text: String, kind: MemoryKind? = .task, daysAgo: Double = 0) -> DuplicateFinder.Note {
        DuplicateFinder.Note(id: UUID(), text: text, kind: kind, capturedAt: Self.now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func theSameThoughtSaidTwiceIsFound() throws {
        let first = note("Appeler l'assurance pour la voiture", daysAgo: 2)
        let second = note("Il faut appeler l'assurance pour la voiture")
        let other = note("Acheter du lait")
        let pairs = DuplicateFinder.pairs([second, other, first])
        try #require(pairs.count == 1)
        // La plus ancienne est gardée.
        #expect(pairs[0].keep == first.id)
        #expect(pairs[0].duplicate == second.id)
        #expect(pairs[0].score >= 0.75)
    }

    @Test func differentNotesAreNotDuplicates() {
        #expect(DuplicateFinder.pairs([note("Appeler l'assurance pour la maison"), note("Appeler l'assurance pour la voiture")]).isEmpty)
        // Pas le même genre de note.
        #expect(DuplicateFinder.pairs([note("Une app de recettes de famille", kind: .idea),
                                       note("Une app de recettes de famille", kind: .task)]).isEmpty)
        // Trop loin dans le temps.
        #expect(DuplicateFinder.pairs([note("Réparer la poignée de la porte", daysAgo: 45),
                                       note("Réparer la poignée de la porte")]).isEmpty)
        // Trop court pour savoir.
        #expect(DuplicateFinder.pairs([note("Lait"), note("Lait")]).isEmpty)
    }

    @Test func aDismissedPairIsNotProposedAgain() {
        let first = note("Appeler l'assurance pour la voiture", daysAgo: 1)
        let second = note("Appeler l'assurance pour la voiture")
        let key = DuplicateFinder.key(first.id, second.id)
        #expect(key == DuplicateFinder.key(second.id, first.id))
        #expect(DuplicateFinder.pairs([first, second], dismissed: [key]).isEmpty)
    }

    @Test func mergingKeepsEveryWord() {
        #expect(DuplicateFinder.mergedBody(keep: "Appeler l'assurance", duplicate: "Demander le numéro de police")
            == "Appeler l'assurance\nDemander le numéro de police")
        // Rien de nouveau : rien n'est ajouté.
        #expect(DuplicateFinder.mergedBody(keep: "Appeler l'assurance pour la voiture", duplicate: "appeler l'assurance")
            == "Appeler l'assurance pour la voiture")
        #expect(DuplicateFinder.mergedBody(keep: "", duplicate: "Demander le numéro") == "Demander le numéro")
    }
}
