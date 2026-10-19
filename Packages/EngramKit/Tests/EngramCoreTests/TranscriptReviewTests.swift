import Foundation
import Testing
@testable import EngramCore

/// F26 — le doute de la transcription remonte jusqu'à la décision : une dictée incertaine passe par « Vérifie ta note »
/// quand son sens dépend d'un mot fragile (négation, prénom, nombre, date, « dois/deux ») ; une dictée sûre, ou sans mot
/// fragile, est classée directement. Le choix du propriétaire (toujours vérifier) reste prioritaire.
struct TranscriptReviewTests {
    @Test func anUncertainTranscriptIsReviewedWhenItsMeaningDependsOnAFragileWord() {
        for text in ["Je ne dois pas appeler Marc", "Payer 450 $ au plombier", "Rendez-vous mardi à 14 h",
                     "Il me faut deux litres de lait"] {
            #expect(TranscriptReview.needsReview(text: text, averageLogProbability: -1.4, ownerWantsReview: false), "\(text)")
        }
        #expect(!TranscriptReview.needsReview(text: "Acheter du lait", averageLogProbability: -1.4, ownerWantsReview: false))
    }

    @Test func aConfidentOrUnmeasuredTranscriptIsNotHeldBack() {
        #expect(!TranscriptReview.needsReview(text: "Je ne dois pas appeler Marc", averageLogProbability: -0.2,
                                              ownerWantsReview: false))
        #expect(!TranscriptReview.needsReview(text: "Je ne dois pas appeler Marc", averageLogProbability: nil,
                                              ownerWantsReview: false))
        #expect(TranscriptReview.needsReview(text: "Acheter du lait", averageLogProbability: nil, ownerWantsReview: true))
    }
}
