import Foundation
import Testing
@testable import EngramCore

struct DateResolverTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    /// Jeudi 8 octobre 2026, 10 h, à Toronto.
    static let now = day(2026, 10, 8, 10, 0)

    static func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func resolve(_ expression: String) -> ResolvedDate? {
        DateResolver.resolve(expression, relativeTo: Self.now, calendar: Self.calendar)
    }

    @Test(arguments: [
        ("aujourd'hui", day(2026, 10, 8)),
        ("demain", day(2026, 10, 9)),
        ("après-demain", day(2026, 10, 10)),
        ("tomorrow", day(2026, 10, 9)),
        ("vendredi", day(2026, 10, 9)),
        ("jeudi", day(2026, 10, 15)),
        ("lundi", day(2026, 10, 12)),
        ("Monday", day(2026, 10, 12)),
        ("24 novembre", day(2026, 11, 24)),
        ("le 24", day(2026, 10, 24)),
        ("le 3", day(2026, 11, 3)),
        ("24 nov.", day(2026, 11, 24)),
        ("November 24", day(2026, 11, 24)),
        ("3 janvier", day(2027, 1, 3)),
        ("1er mars", day(2027, 3, 1)),
        ("15 mars 2027", day(2027, 3, 15)),
        ("dans 3 jours", day(2026, 10, 11)),
        ("dans 2 semaines", day(2026, 10, 22)),
        ("in 3 days", day(2026, 10, 11)),
    ])
    func resolvesDates(expression: String, expected: Date) throws {
        let resolved = try #require(resolve(expression), "« \(expression) » aurait dû être compris")
        #expect(resolved.date == expected)
        #expect(resolved.hasTime == false)
    }

    @Test(arguments: [
        ("vendredi à 14h", day(2026, 10, 9, 14, 0)),
        ("14h30", day(2026, 10, 8, 14, 30)),
        ("14 h 30", day(2026, 10, 8, 14, 30)),
        ("14:30", day(2026, 10, 8, 14, 30)),
        // 9 h est déjà passé à 10 h : c'est 9 h demain (une heure seule ne tombe jamais dans le passé).
        ("à 9 h", day(2026, 10, 9, 9, 0)),
        ("2 pm", day(2026, 10, 8, 14, 0)),
        ("midi", day(2026, 10, 8, 12, 0)),
        ("demain midi", day(2026, 10, 9, 12, 0)),
        ("24 novembre à 14 h", day(2026, 11, 24, 14, 0)),
        ("tomorrow at 9:15 am", day(2026, 10, 9, 9, 15)),
    ])
    func resolvesTimes(expression: String, expected: Date) throws {
        let resolved = try #require(resolve(expression), "« \(expression) » aurait dû être compris")
        #expect(resolved.date == expected)
        #expect(resolved.hasTime)
    }

    @Test(arguments: ["bientôt", "la semaine prochaine", "un jour", "", "Corolla 2020", "32 octobre", "25h"])
    func vagueOrInvalidExpressionsGiveNoDate(expression: String) {
        #expect(resolve(expression) == nil)
    }

    @Test func firstDateFallsBackToTheExcerpt() {
        let resolved = DateResolver.firstDate(in: [], excerpt: "Dentiste vendredi à 14h",
                                              relativeTo: Self.now, calendar: Self.calendar)
        #expect(resolved == ResolvedDate(date: Self.day(2026, 10, 9, 14, 0), hasTime: true))
    }

    @Test func firstDateUsesTheFirstUnderstoodExpression() {
        let resolved = DateResolver.firstDate(in: ["bientôt", "demain"], excerpt: "",
                                              relativeTo: Self.now, calendar: Self.calendar)
        #expect(resolved == ResolvedDate(date: Self.day(2026, 10, 9), hasTime: false))
    }
}
