import Foundation
import Testing
@testable import EngramCore

/// F21 — un goût est une assertion (personne, relation, valeur, polarité, note source, moment) : une assertion plus
/// récente sur la même chose remplace l'ancienne, qui reste dans l'historique sans être présentée comme actuelle ; dans
/// une note qui nomme deux personnes, chacune ne reçoit que ses propres goûts.
struct AssertionTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aNewerPreferenceReplacesTheOlderOne() {
        let first = UUID()
        let second = UUID()
        let found = Assertions.tastes(of: "Julie", in: [
            AssertionNote(id: first, text: "Julie aime le café", saidAt: Self.t0),
            AssertionNote(id: second, text: "Julie n'aime plus le café", saidAt: Self.t0.addingTimeInterval(3_600)),
        ])
        #expect(found.count == 2)
        #expect(found.first?.supersededBy == second)
        #expect(found.first?.isCurrent == false)
        let current = Assertions.currentTastes(found)
        #expect(current.likes.isEmpty)
        #expect(current.dislikes == ["le café"])
    }

    @Test func eachPersonOfANoteOnlyGetsTheirOwnTaste() {
        let note = AssertionNote(id: UUID(), text: "Julie aime le thé et Marc aime le café", saidAt: Self.t0)
        #expect(Assertions.currentTastes(Assertions.tastes(of: "Julie", in: [note])).likes == ["le thé"])
        #expect(Assertions.currentTastes(Assertions.tastes(of: "Marc", in: [note])).likes == ["le café"])
        let mixed = AssertionNote(id: UUID(), text: "Julie aime le thé, Marc déteste le thé", saidAt: Self.t0)
        #expect(Assertions.currentTastes(Assertions.tastes(of: "Marc", in: [mixed])).dislikes == ["le thé"])
        #expect(Assertions.currentTastes(Assertions.tastes(of: "Julie", in: [mixed])).dislikes.isEmpty)
    }

    @Test func aPronounBelongsToTheOnlyPersonOfTheNote() {
        let note = AssertionNote(id: UUID(), text: "Elle adore le chocolat", saidAt: Self.t0)
        #expect(Assertions.currentTastes(Assertions.tastes(of: "Julie", in: [note])).likes == ["le chocolat"])
    }
}
