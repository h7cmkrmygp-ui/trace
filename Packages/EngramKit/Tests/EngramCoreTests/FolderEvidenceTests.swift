import Foundation
import Testing
@testable import EngramCore

/// P34 — avant l'IA, l'iPhone regarde où sont rangées les notes qui ressemblent le plus à la nouvelle ; les notes rangées
/// par le propriétaire comptent triple. Seuls les noms des dossiers sont ensuite donnés à l'IA.
struct FolderEvidenceTests {
    func neighbor(_ path: String, _ similarity: Double, byOwner: Bool = false) -> FolderNeighbor {
        FolderNeighbor(paths: [path], similarity: similarity, byOwner: byOwner)
    }

    @Test func similarNotesVoteForTheirFolders() {
        let evidence = SimilarFolders.vote([
            neighbor("Automobile › Corolla", 0.9),
            neighbor("Automobile › Corolla", 0.8, byOwner: true),
            neighbor("Finances", 0.7),
            // Trop différente : elle ne compte pas.
            neighbor("Santé", 0.3, byOwner: true),
        ])
        #expect(evidence == [FolderEvidence(path: "Automobile › Corolla", notes: 2, byOwner: 1),
                             FolderEvidence(path: "Finances", notes: 1, byOwner: 0)])
        #expect(SimilarFolders.vote([neighbor("Santé", 0.2)]).isEmpty)
        #expect(SimilarFolders.vote([]).isEmpty)
    }

    @Test func theOwnersOwnFilingCountsTriple() {
        let evidence = SimilarFolders.vote([
            neighbor("Finances", 0.9),
            neighbor("Finances", 0.9),
            neighbor("Maison", 0.8, byOwner: true),
        ])
        #expect(evidence.map(\.path) == ["Maison", "Finances"])
    }

    @Test func onlyTheClosestNotesAndTheMainFoldersCount() {
        // 8 notes très proches dans Travail ; une neuvième, un peu moins proche, ne vote pas.
        let close = (0..<8).map { _ in neighbor("Travail", 0.95) }
        #expect(SimilarFolders.vote(close + [neighbor("Voyages", 0.9)]).map(\.path) == ["Travail"])
        let many = ["A", "B", "C", "D", "E"].enumerated().map { neighbor($1, 0.9 - Double($0) * 0.05) }
        #expect(SimilarFolders.vote(many).map(\.path) == ["A", "B", "C"])
    }

    @Test func geminiOnlySeesTheMainFolders() {
        let roots = SimilarFolders.roots([FolderEvidence(path: "Automobile › Corolla", notes: 2, byOwner: 1),
                                          FolderEvidence(path: "Automobile", notes: 1, byOwner: 0),
                                          FolderEvidence(path: "Finances", notes: 1, byOwner: 1)])
        #expect(roots == [FolderEvidence(path: "Automobile", notes: 3, byOwner: 1),
                          FolderEvidence(path: "Finances", notes: 1, byOwner: 1)])
    }

    @Test func theEvidenceIsWrittenForTheAI() {
        #expect(SimilarFolders.describe([FolderEvidence(path: "Automobile › Corolla", notes: 2, byOwner: 1),
                                         FolderEvidence(path: "Finances", notes: 1, byOwner: 0)])
            == "Automobile › Corolla (2 notes, dont 1 rangée par le propriétaire) ; Finances (1 note)")
    }
}
