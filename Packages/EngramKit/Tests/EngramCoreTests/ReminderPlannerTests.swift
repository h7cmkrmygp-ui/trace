import Foundation
import Testing
@testable import EngramCore

/// Rappels : quand prévenir le propriétaire, et quoi afficher sur l'écran verrouillé.
struct ReminderPlannerTests {
    static let calendar = DateResolverTests.calendar
    /// Jeudi 8 octobre 2026, 10 h.
    static let now = DateResolverTests.now

    func item(_ title: String, kind: MemoryKind = .task, status: MemoryStatus = .active, due: Date?, hasTime: Bool,
              isPrivate: Bool = false) -> ReminderPlanner.Item {
        ReminderPlanner.Item(id: UUID(), title: title, kind: kind, status: status, dueAt: due, dueHasTime: hasTime,
                             isPrivate: isPrivate)
    }

    @Test func remindersComeAtTheRightMoment() throws {
        let call = item("Appeler l'assurance", due: DateResolverTests.day(2026, 10, 9, 15, 0), hasTime: true)
        let hedge = item("Tailler la haie", due: DateResolverTests.day(2026, 10, 10), hasTime: false)
        let dentist = item("Dentiste", kind: .appointment, due: DateResolverTests.day(2026, 10, 9, 14, 0), hasTime: true)
        let plan = ReminderPlanner.plan([hedge, call, dentist], now: Self.now, calendar: Self.calendar)
        // Dans l'ordre : le dentiste 1 h avant, l'appel à l'heure dite, la haie à 9 h le jour même.
        #expect(plan.map(\.date) == [DateResolverTests.day(2026, 10, 9, 13, 0), DateResolverTests.day(2026, 10, 9, 15, 0),
                                     DateResolverTests.day(2026, 10, 10, 9, 0)])
        #expect(plan[0].title == "Dentiste")
        #expect(plan[0].body == "Rendez-vous à 14:00")
        #expect(plan[1].body == "À faire maintenant")
        #expect(plan[2].body == "À faire aujourd'hui")
        #expect(plan.map(\.identifier) == [dentist, call, hedge].map { "engram.reminder.\($0.id.uuidString)" })
    }

    @Test func doneTrashedPastAndUndatedNotesAreNotReminded() {
        let items = [
            item("Fait", status: .archived, due: DateResolverTests.day(2026, 10, 9, 15, 0), hasTime: true),
            item("Jeté", status: .trashed, due: DateResolverTests.day(2026, 10, 9, 15, 0), hasTime: true),
            item("Passé", due: DateResolverTests.day(2026, 10, 8, 8, 0), hasTime: true),
            item("Sans date", due: nil, hasTime: false),
            item("Une idée datée", kind: .idea, due: DateResolverTests.day(2026, 10, 9), hasTime: false),
        ]
        #expect(ReminderPlanner.plan(items, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test func aPrivateNoteShowsNothingOnTheLockScreen() throws {
        let code = item("Changer le code du casier", due: DateResolverTests.day(2026, 10, 9, 15, 0), hasTime: true,
                        isPrivate: true)
        let only = try #require(ReminderPlanner.plan([code], now: Self.now, calendar: Self.calendar).first)
        #expect(only.title == "Rappel Engram")
        #expect(!only.body.contains("casier"))
    }

    @Test func iOSKeepsAtMostSixtyRemindersSoTheNextOnesComeFirst() {
        let items = (1...80).map { index in
            item("Tâche \(index)", due: Self.now.addingTimeInterval(Double(index) * 3_600), hasTime: true)
        }
        let plan = ReminderPlanner.plan(items, now: Self.now, calendar: Self.calendar)
        #expect(plan.count == 60)
        #expect(plan.first?.title == "Tâche 1")
    }
}
