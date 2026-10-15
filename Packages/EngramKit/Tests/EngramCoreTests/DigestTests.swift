import Foundation
import Testing
@testable import EngramCore

/// Des tâches qui se font : reports, résumé du matin (avec les retards), pastille, résumé de la semaine, widget.
struct DigestTests {
    static let calendar: Calendar = {
        var calendar = DateResolverTests.calendar
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Jeudi 8 octobre 2026, 10 h.
    static let now = DateResolverTests.now

    static func day(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date { DateResolverTests.day(2026, month, day, hour, 0) }

    func item(_ title: String, kind: MemoryKind = .task, due: Date?, hasTime: Bool = false,
              isPrivate: Bool = false) -> ReminderPlanner.Item {
        ReminderPlanner.Item(id: UUID(), title: title, kind: kind, status: .active, dueAt: due, dueHasTime: hasTime,
                             isPrivate: isPrivate)
    }

    @Test func aSnoozedReminderComesBackLater() throws {
        let call = item("Appeler l'assurance", due: Self.day(10, 8, 9), hasTime: true)
        // L'heure était passée ; « Dans 1 h » l'a reportée à 11 h.
        let plan = ReminderPlanner.plan([call], snoozes: [call.id: Self.day(10, 8, 11)], now: Self.now, calendar: Self.calendar)
        #expect(plan.map(\.date) == [Self.day(10, 8, 11)])
    }

    @Test func theMorningDigestListsTodayAndWhatIsLate() throws {
        let late = item("Payer la facture", due: Self.day(10, 6))
        let tomorrow = item("Tailler la haie", due: Self.day(10, 9))
        let secret = item("Changer le code", due: Self.day(10, 9), isPrivate: true)
        let digests = DigestPlanner.mornings([late, tomorrow, secret], now: Self.now, calendar: Self.calendar, days: 2)
        // Ce matin est passé : le premier résumé est demain à 8 h.
        let first = try #require(digests.first)
        #expect(first.date == Self.day(10, 9, 8))
        #expect(first.title == "Aujourd'hui")
        #expect(first.body.contains("Tailler la haie"))
        #expect(first.body.contains("une note privée"))
        #expect(!first.body.contains("Changer le code"))
        #expect(first.body.contains("En retard : Payer la facture"))
        #expect(first.identifier == "engram.digest.2026-10-09")
    }

    @Test func noDigestOnAnEmptyDay() {
        let far = item("Renouveler le passeport", due: Self.day(11, 20))
        #expect(DigestPlanner.mornings([far], now: Self.now, calendar: Self.calendar, days: 3).isEmpty)
    }

    @Test func theBadgeCountsTodayAndLate() {
        let items = [item("En retard", due: Self.day(10, 6)), item("Aujourd'hui", due: Self.day(10, 8, 15), hasTime: true),
                     item("Demain", due: Self.day(10, 9)), item("Sans date", due: nil)]
        #expect(DigestPlanner.badgeCount(items, now: Self.now, calendar: Self.calendar) == 2)
    }

    @Test func theWeeklySummaryComesOnSundayEvening() throws {
        let stats = WeekStats(notes: 8, done: 3, open: 2)
        let weekly = try #require(DigestPlanner.weekly(stats, now: Self.now, calendar: Self.calendar))
        #expect(weekly.date == Self.day(10, 11, 18))
        #expect(weekly.title == "Ta semaine")
        #expect(weekly.body == "8 notes · 3 choses faites · 2 à faire")
        #expect(DigestPlanner.weekly(WeekStats(notes: 0, done: 0, open: 0), now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test func theWidgetShowsTodayWithoutSecrets() {
        let today = item("Dentiste", kind: .appointment, due: Self.day(10, 8, 14), hasTime: true)
        let secret = item("Changer le code", due: Self.day(10, 8), isPrivate: true)
        let late = item("Payer la facture", due: Self.day(10, 6))
        let snapshot = WidgetSnapshot.make([today, secret, late, item("Demain", due: Self.day(10, 9))],
                                           now: Self.now, calendar: Self.calendar)
        // D'abord ce qui est pour la journée (sans heure), puis par heure ; une note secrète n'a pas son titre.
        #expect(snapshot.today.map(\.title) == ["Rappel privé", "Dentiste"])
        #expect(snapshot.today.last?.time == "14 h")
        #expect(snapshot.lateCount == 1)
        #expect(!snapshot.today.contains { $0.title == "Changer le code" })
    }
}

extension DigestTests {
    /// Le widget reste juste les jours suivants, même si l'app n'a pas été ouverte : il recalcule « aujourd'hui ».
    @Test func theWidgetStaysRightTheNextDays() {
        let friday = item("Tailler la haie", due: Self.day(10, 9))
        let thursday = item("Payer la facture", due: Self.day(10, 8, 15), hasTime: true)
        let snapshot = WidgetSnapshot.make([friday, thursday], now: Self.now, calendar: Self.calendar)
        let seenFriday = snapshot.day(at: Self.day(10, 9, 7), calendar: Self.calendar)
        #expect(seenFriday.today.map(\.title) == ["Tailler la haie"])
        #expect(seenFriday.lateCount == 1)
    }
}

/// Partager vers Engram : l'extension dépose, l'app reprend une seule fois.
struct SharedInboxTests {
    @Test func sharedItemsAreTakenOnceAndInOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = SharedInbox(directory: directory)
        try inbox.add(SharedItem(text: "Recette de soupe à essayer", link: nil, createdAt: Date(timeIntervalSince1970: 10)))
        try inbox.add(SharedItem(text: "Article sur les jardins", link: "https://example.com/jardins",
                                 createdAt: Date(timeIntervalSince1970: 20)))
        #expect(inbox.drain().map(\.text) == ["Recette de soupe à essayer", "Article sur les jardins"])
        #expect(inbox.drain().isEmpty)
    }

    @Test func aSharedLinkBecomesTheNoteText() {
        let item = SharedItem(text: "Article sur les jardins", link: "https://example.com/jardins", createdAt: Date())
        #expect(item.noteText == "Article sur les jardins\nhttps://example.com/jardins")
        #expect(SharedItem(text: "", link: "https://example.com", createdAt: Date()).noteText == "https://example.com")
    }
}
