import Foundation
import Testing
@testable import EngramCore

/// P27 — « Ma journée » avec Siri : ce qui est prévu aujourd'hui, ce qui est en retard, les fêtes, les séries à garder.
struct DaySpeechTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    static let morning = date(15, 8)

    func item(_ title: String, kind: MemoryKind = .task, due: Date?, hasTime: Bool = false, status: MemoryStatus = .active,
              isPrivate: Bool = false) -> ReminderPlanner.Item {
        ReminderPlanner.Item(id: UUID(), title: title, kind: kind, status: status, dueAt: due, dueHasTime: hasTime, isPrivate: isPrivate)
    }

    @Test func theDayIsToldInOrder() {
        let items = [item("Appeler le garage", due: Self.date(15)),
                     item("Dentiste", kind: .appointment, due: Self.date(15, 14), hasTime: true),
                     item("Payer la facture", due: Self.date(13)),
                     item("Plus tard", due: Self.date(18))]
        let text = DaySpeech.summary(items, birthdays: ["Julie"], streaks: ["Méditation"], now: Self.morning, calendar: Self.calendar)
        #expect(text == "Aujourd'hui : dentiste à 14 h et appeler le garage. 1 chose en retard : payer la facture. C'est la fête de Julie. Garde ta série : méditation.")
    }

    @Test func anEmptyDayIsSaidKindly() {
        #expect(DaySpeech.summary([], birthdays: [], streaks: [], now: Self.morning, calendar: Self.calendar)
            == "Rien de prévu aujourd'hui.")
        // Fait ou plus tard : rien aujourd'hui.
        let items = [item("Fait", due: Self.date(15), status: .archived), item("Demain", due: Self.date(16))]
        #expect(DaySpeech.summary(items, birthdays: [], streaks: [], now: Self.morning, calendar: Self.calendar)
            == "Rien de prévu aujourd'hui.")
    }

    @Test func privateNotesAndLongDaysStayShort() {
        let items = [item("Code du casier", due: Self.date(15), isPrivate: true)]
            + (1...6).map { item("Tâche \($0)", due: Self.date(15)) }
            + (1...4).map { item("Vieux \($0)", due: Self.date(10)) }
        let text = DaySpeech.summary(items, birthdays: [], streaks: [], now: Self.morning, calendar: Self.calendar)
        #expect(text == "Aujourd'hui, 7 choses : une note privée, tâche 1, tâche 2, tâche 3 et 3 autres. 4 choses en retard.")
    }
}
