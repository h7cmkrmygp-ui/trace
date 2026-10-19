import Foundation
import Testing
@testable import EngramCore

/// P45 — « Qu'est-ce que j'avais prévu pour ce projet ? » : le dossier du projet, nommé ou dont on vient de parler.
struct ProjectQuestionTests {
    static let folders = ["Projets", "Projets › Chalet", "Projets › Cuisine", "Travail"]

    @Test func aQuestionAboutAProjectFindsItsFolder() {
        #expect(ProjectQuestion.folder(in: "Qu'est-ce que j'avais prévu pour le chalet?", among: Self.folders, recent: nil)
            == "Projets › Chalet")
        #expect(ProjectQuestion.folder(in: "Qu'est-ce qu'il reste à faire pour ce projet?", among: Self.folders,
                                       recent: RecentContext(folders: ["Projets › Cuisine"])) == "Projets › Cuisine")
        // « Ce projet » sans dictée récente : rien n'est deviné.
        #expect(ProjectQuestion.folder(in: "Qu'est-ce qu'il reste à faire pour ce projet?", among: Self.folders, recent: nil) == nil)
        #expect(ProjectQuestion.folder(in: "C'est quoi le numéro du garage?", among: Self.folders, recent: nil) == nil)
    }

    @Test func theAnswerSaysWhatIsLeftToDo() {
        #expect(ProjectQuestion.answer(folder: "Projets › Chalet", open: ["Réparer le quai", "Acheter du bois"],
                                       notes: ["Budget du chalet"])
            == "Pour « Projets › Chalet », à faire : Réparer le quai et Acheter du bois. Aussi noté : Budget du chalet.")
        #expect(ProjectQuestion.answer(folder: "Projets › Chalet", open: [], notes: ["Budget du chalet"])
            == "Pour « Projets › Chalet », rien à faire pour l'instant. Noté : Budget du chalet.")
    }
}
