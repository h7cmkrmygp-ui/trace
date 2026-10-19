import Foundation
import Testing
@testable import EngramCore

/// F22 — la bonne note doit donner la bonne réponse : la valeur est choisie par son rôle dans la phrase (devis ou prix
/// payé, dette ou remboursement, numéro de qui), sinon la réponse cite le passage au lieu de trancher ; une note hors de
/// la période demandée n'est pas présentée comme la réponse ; une réponse rédigée qui ajoute un montant ou un nom
/// est refusée.
struct AnswerRolesTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10))!
    }

    func hit(_ title: String, _ text: String, at date: Date = Self.date(3, 3), score: Double = 1.2) -> RecallHit {
        RecallHit(document: RecallDocument(id: UUID(), title: title, text: text, kind: .info, status: .active,
                                           capturedAt: date, dueAt: nil, categories: [], tags: []),
                  score: score)
    }

    func answer(_ question: String, _ hits: [RecallHit]) -> String? {
        DirectAnswer.make(question: question, hits: hits, now: Self.date(10, 12), calendar: Self.calendar)
    }

    @Test func theAmountIsChosenByItsRole() {
        let roof = hit("Toiture", "Le devis est 900 $, mais j'ai payé 640 $")
        #expect(answer("Combien j'ai payé pour la toiture?", [roof]) == "640 $ — dans ta note « Toiture » du 3 mars.")
        #expect(answer("Combien coûte le devis de la toiture?", [roof]) == "900 $ — dans ta note « Toiture » du 3 mars.")
        let debt = hit("Marc", "Je dois 200 $ à Marc. Je lui ai remboursé 50 $.")
        #expect(answer("Combien j'ai remboursé à Marc?", [debt])?.hasPrefix("50 $") == true)
        #expect(answer("Combien je dois à Marc?", [debt])?.hasPrefix("200 $") == true)
    }

    @Test func severalPlausibleValuesAreQuotedInsteadOfGuessed() {
        let roof = hit("Toiture", "Le devis est 900 $, mais j'ai payé 640 $")
        #expect(answer("C'est combien la toiture?", [roof])
            == "« Le devis est 900 $, mais j'ai payé 640 $ » — dans ta note « Toiture » du 3 mars.")
    }

    @Test func theNumberIsTheOneOfWhatIsAsked() {
        let numbers = hit("Numéros", "Le numéro du garage est 514 555 0101 et celui du dentiste 514 555 0199")
        #expect(answer("C'est quoi le numéro du dentiste?", [numbers])?.hasPrefix("514 555 0199") == true)
        #expect(answer("C'est quoi le numéro du garage?", [numbers])?.hasPrefix("514 555 0101") == true)
    }

    @Test func aNoteOutsideTheAskedPeriodIsNotTheAnswer() {
        let query = RecallQuery.parse("Combien j'ai payé en mars?", now: Self.date(10, 12), calendar: Self.calendar)
        let march = RecallDocument(id: UUID(), title: "Pneus", text: "J'ai payé 640 $ pour les pneus", kind: .info,
                                   status: .active, capturedAt: Self.date(3, 10), dueAt: nil, categories: [], tags: [])
        let april = RecallDocument(id: UUID(), title: "Huile", text: "J'ai payé 80 $ pour l'huile", kind: .info,
                                   status: .active, capturedAt: Self.date(4, 10), dueAt: nil, categories: [], tags: [])
        let hits = RecallRanker.rank([april, march], for: query, now: Self.date(10, 12), limit: 10)
        #expect(hits.first?.document.id == march.id)
        #expect(hits.first?.outsidePeriod == false)
        // Une note hors période n'est jamais présentée comme exacte.
        #expect(!hits.contains { $0.document.id == april.id && !$0.outsidePeriod })
        // Seule une note hors période : pas de réponse directe.
        #expect(DirectAnswer.make(question: "Combien j'ai payé en mars?",
                                  hits: [RecallHit(document: april, score: 1.2, outsidePeriod: true)],
                                  now: Self.date(10, 12), calendar: Self.calendar) == nil)
    }

    @Test func aWrittenAnswerCannotAddAnAmountOrAName() {
        let notes = ["J'ai payé 640 $ pour les pneus d'hiver, chez Costco"]
        #expect(RecallAnswerCheck.isSupported("Tu as payé 640 $ pour tes pneus chez Costco.", by: notes))
        #expect(!RecallAnswerCheck.isSupported("Tu as payé 690 $ pour tes pneus.", by: notes))
        #expect(!RecallAnswerCheck.isSupported("Tu as payé 640 $ chez Canadian Tire.", by: notes))
    }
}
