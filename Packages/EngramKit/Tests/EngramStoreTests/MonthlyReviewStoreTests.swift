import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// P28 — « Ton mois », lu dans la base.
struct MonthlyReviewStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String) throws {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task,
                                   tags: [], categoryPath: ["Maison"], mentionedDates: [])
        _ = try env.filer.file([thought], sourceID: interim.sourceID)
    }

    @Test func aMonthIsCountedDayByDay() throws {
        let env = try StoreTestEnvironment()
        // Le 26 décembre 2026, puis le 15 janvier 2027.
        env.dates.advance(by: -20 * 86_400)
        try file(env, "Appeler le garage")
        env.dates.advance(by: 20 * 86_400)
        try file(env, "Réparer la clôture")
        let january = try env.memories.review(.month, containing: Fixtures.date)
        #expect(Fixtures.calendar.component(.day, from: january.start) == 1)
        #expect(january.notes == 1)
        #expect(january.notesLastWeek == 1)
        #expect(january.perDay.count == 31)
        #expect(january.perDay[14] == 1)
        #expect(january.categories.map(\.name) == ["Maison"])
        // La semaine, elle, reste de 7 jours.
        #expect(try env.memories.weeklyReview(containing: Fixtures.date).perDay.count == 7)
    }
}
