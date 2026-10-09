import Foundation
import Testing
@testable import EngramCore

/// Ce qu'Engram donne à un assistant (ChatGPT, Claude) quand le propriétaire le demande dans un raccourci :
/// seulement les notes trouvées, jamais une note gardée sur l'iPhone.
struct AssistantExportTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    /// Vendredi 15 janvier 2027, 10 h, à Toronto.
    static let now = Date(timeIntervalSince1970: 1_800_025_200)

    func hit(_ title: String, text: String = "", kind: MemoryKind = .idea, daysAgo: Int = 1, isPrivate: Bool = false) -> RecallHit {
        let document = RecallDocument(id: UUID(), title: title, text: text, kind: kind, status: .active,
                                      capturedAt: Self.now.addingTimeInterval(-Double(daysAgo) * 86_400), dueAt: nil,
                                      categories: ["Projets"], tags: [], isPrivate: isPrivate)
        return RecallHit(document: document, score: 1)
    }

    @Test func foundNotesAreListedWithTheirKindAndDate() {
        let text = AssistantExport.text(question: "Mon idée de la semaine passée ?",
                                        hits: [hit("Une app de recettes", text: "Avec ce qu'il y a dans le frigo", daysAgo: 6)],
                                        calendar: Self.calendar, now: Self.now)
        #expect(text.contains("Mon idée de la semaine passée ?"))
        #expect(text.contains("1. Une app de recettes (idée, notée le 9 janvier 2027)"))
        #expect(text.contains("Avec ce qu'il y a dans le frigo"))
    }

    @Test func notesKeptOnTheIPhoneAreNeverIncluded() {
        let text = AssistantExport.text(question: "Mon code ?",
                                        hits: [hit("Code du casier 4521", isPrivate: true), hit("Acheter un cadenas", kind: .task)],
                                        calendar: Self.calendar, now: Self.now)
        #expect(!text.contains("4521"))
        #expect(text.contains("Acheter un cadenas"))
        #expect(text.contains("1 note gardée sur l'iPhone n'est pas incluse."))
    }

    @Test func atMostFiveNotesAreGiven() {
        let hits = (1...8).map { hit("Idée \($0)") }
        let text = AssistantExport.text(question: "Mes idées", hits: hits, calendar: Self.calendar, now: Self.now)
        #expect(text.contains("5. Idée 5"))
        #expect(!text.contains("6. Idée 6"))
    }

    @Test func nothingShareableSaysSo() {
        let text = AssistantExport.text(question: "Mon code ?", hits: [hit("Code du casier", isPrivate: true)],
                                        calendar: Self.calendar, now: Self.now)
        #expect(text.contains("Aucune note partageable"))
        #expect(!text.contains("Code du casier"))
    }
}
