import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// F22 — le passage utile d'une note atteint le modèle, même après les 300 premiers caractères ; une note hors de la
/// période demandée est signalée comme telle.
struct RecallPassageTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()
    static let now = Date(timeIntervalSince1970: 1_791_475_200)

    func hit(_ text: String, outsidePeriod: Bool = false) -> RecallHit {
        RecallHit(document: RecallDocument(id: UUID(), title: "Garage", text: text, kind: .info, status: .active,
                                           capturedAt: Self.now, dueAt: nil, categories: [], tags: []),
                  score: 1.2, outsidePeriod: outsidePeriod)
    }

    @Test func theUsefulPassageReachesTheModelEvenAfter300Characters() {
        let filler = String(repeating: "Une longue introduction sans rapport avec la question. ", count: 8)
        let prompt = RecallAnswerPrompt.prompt(question: "C'est quoi le code de la porte du garage?",
                                               hits: [hit(filler + "Le code de la porte du garage est 4589.")],
                                               now: Self.now, calendar: Self.calendar)
        #expect(prompt.contains("4589"))
    }

    @Test func aNoteOutsideThePeriodIsMarkedForTheModel() {
        let prompt = RecallAnswerPrompt.prompt(question: "Combien j'ai payé en mars?",
                                               hits: [hit("J'ai payé 80 $ pour l'huile", outsidePeriod: true)],
                                               now: Self.now, calendar: Self.calendar)
        #expect(prompt.contains("hors de la période demandée"))
    }
}
