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
