import Foundation
import Testing
@testable import EngramCore

/// P12 — le texte lu sur une photo est remis au propre : les phrases coupées sont recollées, les listes restent des
/// listes, les traits parasites disparaissent.
struct OCRTextTests {
    @Test func aSentenceCutOverSeveralLinesIsJoined() {
        #expect(OCRText.clean(lines: ["Rappel : apporter les", "documents au bureau", "avant vendredi."])
            == "Rappel : apporter les documents au bureau avant vendredi.")
    }

    @Test func aWordCutWithAHyphenIsJoined() {
        #expect(OCRText.clean(lines: ["Prendre rendez-", "vous chez le dentiste"]) == "Prendre rendez-vous chez le dentiste")
    }

    @Test func separateLinesStaySeparate() {
        #expect(OCRText.clean(lines: ["Facture Hydro-Québec", "Montant dû : 84,32 $", "Échéance : 24 novembre"])
            == "Facture Hydro-Québec\nMontant dû : 84,32 $\nÉchéance : 24 novembre")
        #expect(OCRText.clean(lines: ["Liste", "", "Lait", "Pain"]) == "Liste\n\nLait\nPain")
    }

    @Test func noiseAndSpacesAreCleaned() {
        #expect(OCRText.clean(lines: ["|", "  Lait   2  %  ", "—", ""]) == "Lait 2 %")
        #expect(OCRText.clean(lines: []).isEmpty)
    }
}
