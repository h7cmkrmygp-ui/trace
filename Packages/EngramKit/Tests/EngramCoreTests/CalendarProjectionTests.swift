import Foundation
import Testing
@testable import EngramCore

/// P22 — le Calendrier montre aussi les prochaines fois des tâches qui reviennent et les fêtes.
struct CalendarProjectionTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func month(_ year: Int, _ month: Int) -> (start: Date, end: Date) {
        let start = date(year, month, 1)
        return (start, calendar.date(byAdding: .month, value: 1, to: start)!)
    }

    @Test func aWeeklyTaskShowsEachMondayAfterItsDueDate() {
        let cal = Self.calendar
        // Due le lundi 18 janvier 2027 ; janvier : les lundis 25 seulement (le 18 est déjà dans les échéances).
        let trash = CalendarProjection.Recurring(memoryID: UUID(), title: "Sortir les poubelles",
                                                 rule: RecurrenceRule(frequency: .weekly, weekdays: [2]),
                                                 anchor: Self.date(2027, 1, 18), due: Self.date(2027, 1, 18), hasTime: false)
        let january = Self.month(2027, 1)
        let occurrences = CalendarProjection.occurrences([trash], from: january.start, to: january.end, calendar: cal)
        #expect(occurrences.map(\.date) == [Self.date(2027, 1, 25)])
        // Février : les quatre lundis.
        let february = Self.month(2027, 2)
        #expect(CalendarProjection.occurrences([trash], from: february.start, to: february.end, calendar: cal).map(\.date)
            == [1, 8, 15, 22].map { Self.date(2027, 2, $0) })
    }

    @Test func nothingIsProjectedBeforeTheDueDate() {
        let cal = Self.calendar
        let rent = CalendarProjection.Recurring(memoryID: UUID(), title: "Payer le loyer",
                                                rule: RecurrenceRule(frequency: .monthly, dayOfMonth: 1),
                                                anchor: Self.date(2027, 3, 1), due: Self.date(2027, 3, 1), hasTime: false)
        let january = Self.month(2027, 1)
        #expect(CalendarProjection.occurrences([rent], from: january.start, to: january.end, calendar: cal).isEmpty)
        let april = Self.month(2027, 4)
        #expect(CalendarProjection.occurrences([rent], from: april.start, to: april.end, calendar: cal).map(\.date)
            == [Self.date(2027, 4, 1)])
    }

    @Test func birthdaysFallOnTheirDayWithTheAge() {
        let cal = Self.calendar
        let julie = Birthday(personID: UUID(), name: "Julie", month: 3, day: 12, year: 1992)
        let leap = Birthday(personID: UUID(), name: "Léo", month: 2, day: 29, year: nil)
        let march = Self.month(2027, 3)
        let found = CalendarProjection.birthdays([julie, leap], from: march.start, to: march.end, calendar: cal)
        #expect(found.map(\.date) == [Self.date(2027, 3, 12)])
        #expect(found.first?.age == 35)
        #expect(found.first?.title == "Fête de Julie (35 ans)")
        // Né un 29 février : le 28 en 2027.
        let february = Self.month(2027, 2)
        #expect(CalendarProjection.birthdays([julie, leap], from: february.start, to: february.end, calendar: cal).map(\.date)
            == [Self.date(2027, 2, 28)])
        #expect(CalendarProjection.birthdays([leap], from: february.start, to: february.end, calendar: cal).first?.title
            == "Fête de Léo")
    }
}
