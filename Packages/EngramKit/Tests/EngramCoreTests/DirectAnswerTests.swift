import Foundation
import Testing
@testable import EngramCore

/// P39 — Retrouver répond direct : pour une question de fait (un numéro, un montant, une date, un endroit), la réponse
/// exacte tirée de la note, avec la note d'où elle vient. Rien n'est inventé : sans valeur dans la note, pas de réponse.
struct DirectAnswerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    static let now = date(10, 12)

    func hit(_ title: String, _ text: String, dueAt: Date? = nil, score: Double = 1.2) -> RecallHit {
        RecallHit(document: RecallDocument(id: UUID(), title: title, text: text, kind: .info, status: .active,
                                           capturedAt: Self.date(3, 3), dueAt: dueAt, categories: [], tags: []),
                  score: score)
    }

    func answer(_ question: String, _ hits: [RecallHit]) -> String? {
        DirectAnswer.make(question: question, hits: hits, now: Self.now, calendar: Self.calendar)
    }

    @Test func aNumberComesStraightFromTheNote() {
        let policy = hit("Numéro de police d'assurance", "Le numéro de police est 4589-2231, chez Intact")
        #expect(answer("C'est quoi le numéro de ma police d'assurance?", [policy])
            == "4589-2231 — dans ta note « Numéro de police d'assurance » du 3 mars.")
    }

    @Test func anAmountComesStraightFromTheNote() {
        let tires = hit("Pneus d'hiver", "J'ai payé 640 $ pour les pneus d'hiver")
        #expect(answer("Combien j'ai payé pour les pneus?", [tires]) == "640 $ — dans ta note « Pneus d'hiver » du 3 mars.")
    }

    @Test func aDateComesFromTheNotesDueDate() {
        let dentist = hit("Dentiste", "Rendez-vous chez le dentiste", dueAt: Self.date(10, 20, 14))
        #expect(answer("C'est quand le dentiste?", [dentist]) == "Le mardi 20 octobre à 14 h — dans ta note « Dentiste ».")
        let morning = hit("Garage", "Laisser l'auto au garage", dueAt: Self.date(10, 22, 8, 30))
        #expect(answer("À quelle heure le garage?", [morning]) == "Le jeudi 22 octobre à 8 h 30 — dans ta note « Garage ».")
    }

    @Test func aPlaceIsTheSentenceThatSaysIt() {
        let passport = hit("Passeport", "Le passeport est dans le tiroir du bureau. Il expire en 2029.")
        #expect(answer("Où j'ai mis mon passeport?", [passport])
            == "« Le passeport est dans le tiroir du bureau » — dans ta note « Passeport » du 3 mars.")
    }

    @Test func nothingIsInventedOrGuessed() {
        // Pas de numéro dans la note : pas de réponse directe (la réponse habituelle prend le relais).
        #expect(answer("C'est quoi le numéro de police?", [hit("Assurance", "Appeler l'assurance")]) == nil)
        // Une note trop peu sûre.
        #expect(answer("C'est quoi le numéro de police?", [hit("Police", "Numéro 4589-2231", score: 0.6)]) == nil)
        // Une question qui n'est pas une question de fait.
        #expect(answer("Résume mes idées de la semaine", [hit("Idée", "Une app de recettes")]) == nil)
        #expect(answer("C'est quoi le numéro de police?", []) == nil)
    }
}
