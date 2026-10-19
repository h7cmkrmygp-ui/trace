import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// P38 — les notes qui ressemblent vraiment à une note (par le sens, sur l'iPhone) : celles qu'on propose de déplacer avec elle.
struct SimilarNotesTests {
    @Test func onlyTrulySimilarNotesAreProposed() {
        let embedder = FakeEmbedder(vectors: [
            "Réévaluer l'assurance de la maison": [1, 0, 0],
            "Renouveler l'assurance habitation": [0.95, 0.05, 0],
            "Changer les pneus": [0.6, 0.8, 0],
        ])
        let close = FilingSample(id: UUID(), text: "Renouveler l'assurance habitation", paths: ["Automobile"], byOwner: false)
        let far = FilingSample(id: UUID(), text: "Changer les pneus", paths: ["Automobile"], byOwner: false)
        let unknown = FilingSample(id: UUID(), text: "Texte sans sens connu", paths: ["Automobile"], byOwner: false)
        let finder = SimilarNotesEvidence(embedder: embedder, samples: { [] })
        #expect(finder.closest(to: "Réévaluer l'assurance de la maison", among: [far, close, unknown]).map(\.id) == [close.id])
        #expect(finder.closest(to: "Texte sans sens connu", among: [close]).isEmpty)
    }
}

/// P40 — le vote des notes semblables pour une note déjà rangée ne compte jamais la note elle-même.
struct SimilarNotesVoteTests {
    @Test func aNoteNeverVotesForItself() {
        let embedder = FakeEmbedder(vectors: ["A": [1, 0, 0], "B": [0.99, 0.01, 0], "C": [0.98, 0.02, 0], "D": [0.97, 0.03, 0]])
        let note = FilingSample(id: UUID(), text: "A", paths: ["Automobile"], byOwner: false)
        let others = ["B", "C", "D"].map { FilingSample(id: UUID(), text: $0, paths: ["Finances"], byOwner: false) }
        let finder = SimilarNotesEvidence(embedder: embedder, samples: { [] })
        #expect(finder.vote(for: note, among: [note] + others) == [FolderEvidence(path: "Finances", notes: 3, byOwner: 0)])
    }
}
