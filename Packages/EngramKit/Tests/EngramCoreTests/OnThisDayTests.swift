import Foundation
import Testing
@testable import EngramCore

/// P24 — « Ce jour-là » : ce que tu notais il y a un mois, six mois, un an.
struct OnThisDayTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func note(_ title: String, _ year: Int, _ month: Int, _ day: Int, isPrivate: Bool = false) -> OnThisDay.Note {
        OnThisDay.Note(id: UUID(), title: title, capturedAt: Self.date(year, month, day), isPrivate: isPrivate)
    }

    @Test func theSameDayComesBackAMonthSixMonthsAndYearsLater() {
        let today = Self.date(2027, 3, 15)
        let notes = [
            note("Idée de cadeau", 2027, 2, 15),
            note("Souper chez Julie", 2026, 9, 15),
            note("Premier jour au nouveau bureau", 2026, 3, 15),
            note("Voyage à Québec", 2025, 3, 15),
            note("Autre jour", 2027, 2, 14),
            note("Aujourd'hui même", 2027, 3, 15),
        ]
        let groups = OnThisDay.groups(notes, today: today, calendar: Self.calendar)
        #expect(groups.map(\.label) == ["Il y a un mois", "Il y a six mois", "Il y a un an", "Il y a 2 ans"])
        #expect(groups.map { $0.notes.map(\.title) } == [["Idée de cadeau"], ["Souper chez Julie"],
                                                          ["Premier jour au nouveau bureau"], ["Voyage à Québec"]])
    }

    @Test func privateNotesAndMissingDaysStayOut() {
        // Le 31 mars : février n'a pas de 31, rien « il y a un mois ».
        let today = Self.date(2027, 3, 31)
        let notes = [note("Code du casier", 2026, 3, 31, isPrivate: true), note("Fin février", 2027, 2, 28)]
        #expect(OnThisDay.groups(notes, today: today, calendar: Self.calendar).isEmpty)
    }

    @Test func atMostThreeNotesADay() {
        let today = Self.date(2027, 3, 15)
        let notes = (1...5).map { note("Note \($0)", 2026, 3, 15) }
        #expect(OnThisDay.groups(notes, today: today, calendar: Self.calendar).first?.notes.count == 3)
    }
}
