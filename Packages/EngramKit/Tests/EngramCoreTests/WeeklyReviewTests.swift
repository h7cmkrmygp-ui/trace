import Foundation
import Testing
@testable import EngramCore

/// P18 — « Ta semaine » : ce que la semaine a été, en mots simples.
struct WeeklyReviewTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func theWeekHasAReadableTitle() {
        let cal = Self.calendar
        #expect(WeeklyReviewText.title(start: Self.date(2027, 1, 10), calendar: cal) == "Semaine du 10 au 16 janvier")
        #expect(WeeklyReviewText.title(start: Self.date(2027, 2, 28), calendar: cal) == "Semaine du 28 février au 6 mars")
        #expect(WeeklyReviewText.title(start: Self.date(2026, 12, 27), calendar: cal)
            == "Semaine du 27 décembre 2026 au 2 janvier 2027")
    }

    @Test func theWeekIsComparedToTheOneBefore() {
        #expect(WeeklyReviewText.comparison(notes: 12, lastWeek: 9) == "3 notes de plus que la semaine d'avant")
        #expect(WeeklyReviewText.comparison(notes: 8, lastWeek: 9) == "1 note de moins que la semaine d'avant")
        #expect(WeeklyReviewText.comparison(notes: 5, lastWeek: 5) == "Autant de notes que la semaine d'avant")
        #expect(WeeklyReviewText.comparison(notes: 4, lastWeek: 0) == nil)
    }

    @Test func theBusiestDayIsNamed() {
        let cal = Self.calendar
        // Du dimanche au samedi : le mercredi l'emporte.
        #expect(WeeklyReviewText.busiestDay(perDay: [0, 2, 1, 5, 0, 1, 0], start: Self.date(2027, 1, 10), calendar: cal)
            == "mercredi")
        // À égalité, le premier jour.
        #expect(WeeklyReviewText.busiestDay(perDay: [0, 3, 3, 0, 0, 0, 0], start: Self.date(2027, 1, 10), calendar: cal)
            == "lundi")
        #expect(WeeklyReviewText.busiestDay(perDay: [0, 0, 0, 0, 0, 0, 0], start: Self.date(2027, 1, 10), calendar: cal) == nil)
    }
}
