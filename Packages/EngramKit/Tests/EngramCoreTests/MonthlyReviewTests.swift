import Foundation
import Testing
@testable import EngramCore

/// P28 — « Ton mois » : la même page que « Ta semaine », pour un mois entier.
struct MonthlyReviewTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func aMonthHasItsTitleAndComparison() {
        #expect(WeeklyReviewText.title(start: Self.date(2027, 1, 1), period: .month, calendar: Self.calendar) == "Janvier 2027")
        #expect(WeeklyReviewText.title(start: Self.date(2027, 1, 10), period: .week, calendar: Self.calendar)
            == "Semaine du 10 au 16 janvier")
        #expect(WeeklyReviewText.comparison(notes: 40, lastWeek: 30, period: .month) == "10 notes de plus que le mois d'avant")
        #expect(WeeklyReviewText.comparison(notes: 30, lastWeek: 30, period: .month) == "Autant de notes que le mois d'avant")
    }

    @Test func theBusiestDayOfAMonthIsItsDate() {
        var perDay = Array(repeating: 0, count: 31)
        perDay[13] = 6
        perDay[20] = 2
        #expect(WeeklyReviewText.busiestDay(perDay: perDay, start: Self.date(2027, 1, 1), period: .month, calendar: Self.calendar)
            == "le 14 janvier")
        #expect(WeeklyReviewText.busiestDay(perDay: Array(repeating: 0, count: 31), start: Self.date(2027, 1, 1), period: .month,
                                            calendar: Self.calendar) == nil)
    }

    @Test func aPeriodKnowsItsRange() throws {
        let cal = Self.calendar
        let month = try #require(ReviewPeriod.month.interval(containing: Self.date(2027, 2, 14), calendar: cal))
        #expect(month.start == Self.date(2027, 2, 1))
        #expect(month.end == Self.date(2027, 3, 1))
        #expect(ReviewPeriod.month.previousStart(of: month.start, calendar: cal) == Self.date(2027, 1, 1))
        #expect(ReviewPeriod.week.previousStart(of: Self.date(2027, 1, 10), calendar: cal) == Self.date(2027, 1, 3))
    }
}
