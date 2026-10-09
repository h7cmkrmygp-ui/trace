import Foundation
import Testing
@testable import EngramCore

/// P13 — « Te souviens-tu ? » : chaque soir, une vieille idée revient ; et un résumé du dimanche plus riche.
struct ResurfacingTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    /// Vendredi 15 janvier 2027, 10 h, à Toronto.
    static let friday = Date(timeIntervalSince1970: 1_800_025_200)

    func candidate(_ title: String, kind: MemoryKind = .idea, daysAgo: Double, isPrivate: Bool = false) -> Resurfacing.Candidate {
        Resurfacing.Candidate(id: UUID(), title: title, kind: kind, capturedAt: Self.friday.addingTimeInterval(-daysAgo * 86_400),
                              isPrivate: isPrivate)
    }

    @Test func anOldIdeaComesBackAtSevenInTheEvening() throws {
        let idea = candidate("Une app de recettes", daysAgo: 60)
        let reminder = try #require(Resurfacing.reminder(from: [idea], now: Self.friday, calendar: Self.calendar, hideTitle: false))
        #expect(reminder.identifier == Resurfacing.identifier)
        #expect(reminder.memoryID == idea.id)
        #expect(reminder.title == "Te souviens-tu ?")
        #expect(reminder.body == "Une app de recettes")
        #expect(Self.calendar.component(.hour, from: reminder.date) == 19)
        #expect(Self.calendar.isDate(reminder.date, inSameDayAs: Self.friday))
        // Engram verrouillé : pas de titre.
        #expect(Resurfacing.reminder(from: [idea], now: Self.friday, calendar: Self.calendar, hideTitle: true)?.body
            == "Une ancienne idée t'attend")
    }

    @Test func tasksRecentNotesAndPrivateNotesNeverComeBack() {
        let notes = [candidate("Payer le loyer", kind: .task, daysAgo: 90), candidate("Idée d'hier", daysAgo: 2),
                     candidate("Code du casier", kind: .info, daysAgo: 90, isPrivate: true)]
        #expect(Resurfacing.reminder(from: notes, now: Self.friday, calendar: Self.calendar, hideTitle: false) == nil)
    }

    @Test func eachEveningBringsADifferentIdeaUntilAllHaveComeBack() throws {
        let ideas = (1...5).map { candidate("Idée \($0)", daysAgo: Double(30 + $0 * 10)) }
        var seen: [UUID] = []
        for day in 0..<5 {
            let evening = Self.friday.addingTimeInterval(Double(day) * 86_400)
            let pick = try #require(Resurfacing.pick(ideas, on: evening, calendar: Self.calendar))
            seen.append(pick.id)
        }
        #expect(Set(seen).count == 5)
    }

    @Test func afterSevenTheIdeaIsForTomorrowEvening() throws {
        let late = Self.friday.addingTimeInterval(10 * 3_600) // 20 h
        let reminder = try #require(Resurfacing.reminder(from: [candidate("Une idée", daysAgo: 40)], now: late,
                                                         calendar: Self.calendar, hideTitle: false))
        #expect(Self.calendar.component(.day, from: reminder.date) == 16)
    }

    @Test func theSundaySummaryNamesThePeopleAndTheTrends() throws {
        let stats = WeekStats(notes: 12, done: 4, open: 3, people: ["Julie", "Marc"], highlights: ["Poids −1,2 lb"])
        let weekly = try #require(DigestPlanner.weekly(stats, now: Self.friday, calendar: Self.calendar))
        #expect(weekly.body.contains("12 notes · 4 choses faites · 3 à faire"))
        #expect(weekly.body.contains("Avec Julie et Marc"))
        #expect(weekly.body.contains("Poids −1,2 lb"))
    }
}
