import Foundation
import Testing
@testable import EngramCore

/// F24 — le voisinage n'impose un dossier que s'il repose sur des exemples rangés par le propriétaire et qu'il se
/// détache nettement du suivant ; des notes rangées par l'IA ne font pas une habitude de classement. Le ménage suit les
/// mêmes règles (un suivi ou un dossier d'action incompatible n'est jamais visé).
/// F25 — les dossiers donnés au modèle sont choisis selon le sens de la note, pas l'ordre alphabétique.
struct NeighborhoodAndBudgetTests {
    func neighbor(_ path: String, _ similarity: Double, owner: Bool) -> FolderNeighbor {
        FolderNeighbor(paths: [path], similarity: similarity, byOwner: owner)
    }

    @Test func notesFiledByTheAINeverImposeAFolder() {
        let votes = SimilarFolders.vote([neighbor("Achats", 0.9, owner: false), neighbor("Achats", 0.88, owner: false),
                                         neighbor("Achats", 0.86, owner: false)])
        #expect(votes.first?.path == "Achats")
        #expect(SimilarFolders.confidentChoice(votes) == nil)
    }

    @Test func competingNeighborhoodsNeedAClearMargin() {
        let close = SimilarFolders.vote([neighbor("Maison", 0.9, owner: true), neighbor("Achats", 0.89, owner: true)])
        #expect(SimilarFolders.confidentChoice(close) == nil)
        let clear = SimilarFolders.vote([neighbor("Maison", 0.9, owner: true), neighbor("Maison", 0.85, owner: true),
                                         neighbor("Achats", 0.6, owner: false)])
        #expect(SimilarFolders.confidentChoice(clear)?.path == "Maison")
    }

    @Test func theTidyOnlyProposesMovesBackedByTheOwnerAndAllowedByTheFolder() {
        let id = UUID()
        let aiOnly = TidyNote(id: id, paths: ["Divers"], evidence: [FolderEvidence(path: "Achats", notes: 4, byOwner: 0)],
                              text: "Acheter du lait")
        #expect(TidyPlanner.moves([aiOnly]).isEmpty)
        // Vers un suivi qui refuse la note (le poids ne reçoit que des pesées).
        let tracker = TidyNote(id: id, paths: ["Divers"],
                               evidence: [FolderEvidence(path: "Santé › Poids", notes: 4, byOwner: 3)],
                               text: "Appeler le dentiste")
        #expect(TidyPlanner.moves([tracker]).isEmpty)
        let owner = TidyNote(id: id, paths: ["Divers"], evidence: [FolderEvidence(path: "Maison", notes: 4, byOwner: 3)],
                             text: "Réparer la clôture")
        #expect(TidyPlanner.moves([owner]) == [.move(memory: id, from: "Divers", to: "Maison")])
    }

    @Test func theFoldersGivenToTheModelAreChosenByMeaning() {
        let paths = (1...200).map { String(format: "Dossier %03d", $0) } + ["Zoo › Vétérinaire"]
        let chosen = CategoryBudget.select(paths, for: "Prendre rendez-vous chez le vétérinaire pour le chat",
                                           evidence: [], counts: [:], limit: 150)
        #expect(chosen.count == 150)
        #expect(chosen.contains("Zoo › Vétérinaire"))
        // Les dossiers des notes semblables et les plus grands passent ensuite, avant l'ordre alphabétique.
        let ranked = CategoryBudget.select(paths, for: "Une note", evidence: [FolderEvidence(path: "Dossier 200", notes: 2,
                                                                                            byOwner: 1)],
                                           counts: ["Dossier 199": 40], limit: 3)
        #expect(ranked == ["Dossier 200", "Dossier 199", "Dossier 001"])
    }
}
