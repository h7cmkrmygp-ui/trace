import Foundation
import Testing
@testable import EngramCore

/// Les « euh », « hum » et « mmm » d'une dictée disparaissent ; les vrais mots restent tels quels.
struct SpeechCleanupTests {
    @Test(arguments: [
        ("Rappelle-moi de euhmmmmmmm appeler l'assurance demain ok", "Rappelle-moi d'appeler l'assurance demain ok"),
        ("Euh, faut que je passe au garage", "Faut que je passe au garage"),
        ("Bon, euh, je pense que hmm c'est correct", "Bon, je pense que c'est correct"),
        ("Je dois euh aller chez le dentiste", "Je dois aller chez le dentiste"),
        ("Faut que euh il vienne samedi", "Faut qu'il vienne samedi"),
        ("Acheter du lait, euh...", "Acheter du lait..."),
        ("Hum. OK, I'll call him", "OK, I'll call him"),
        ("Rappelle-moi de, euh, appeler Julie", "Rappelle-moi d'appeler Julie"),
        ("Euuuh mmmh ça c'est une bonne idée", "Ça c'est une bonne idée"),
    ])
    func hesitationsAreRemoved(spoken: String, expected: String) {
        #expect(SpeechCleanup.removingHesitations(spoken) == expected)
    }

    @Test(arguments: [
        "J'ai eu une idée pour le chalet",
        "Le plan est ok pour moi",
        "Ah oui, l'humeur était bonne",
        "Acheter du thé et des œufs",
    ])
    func realWordsAreKept(text: String) {
        #expect(SpeechCleanup.removingHesitations(text) == text)
    }

    @Test func onlyHesitationsLeaveNothing() {
        #expect(SpeechCleanup.removingHesitations("Euh... hmm.").isEmpty)
    }
}
