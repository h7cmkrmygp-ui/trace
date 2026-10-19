import Foundation
import Testing
@testable import EngramCore

/// P21 — garder ses séries : un petit rappel à 20 h, et un objectif par semaine (« méditer 5 fois par semaine »).
struct HabitGoalsTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour))!
    }

    @Test func weeklyGoalsAreRecognized() {
        #expect(HabitGoalParser.parse("Mon objectif : méditer 5 fois par semaine") == [ParsedHabitGoal(habit: .meditation, perWeek: 5)])
        #expect(HabitGoalParser.parse("Objectif d'aller au gym trois fois par semaine")
            == [ParsedHabitGoal(habit: .exercise, perWeek: 3)])
        #expect(HabitGoalParser.parse("Mon but c'est de courir 2 fois par semaine") == [ParsedHabitGoal(habit: .running, perWeek: 2)])
        #expect(HabitGoalParser.parse("Objectif : lire tous les jours") == [ParsedHabitGoal(habit: .reading, perWeek: 7)])
        #expect(HabitGoalParser.parse("Goal: meditate 4 times a week") == [ParsedHabitGoal(habit: .meditation, perWeek: 4)])
    }

    @Test func otherSentencesAreNotHabitGoals() {
        #expect(HabitGoalParser.parse("J'ai médité 5 fois cette semaine").isEmpty)
        #expect(HabitGoalParser.parse("Mon objectif : 155 livres").isEmpty)
        #expect(HabitGoalParser.parse("Objectif : méditer 9 fois par semaine").isEmpty)
    }

    func streak(_ habit: Habit, days: [Int]) -> HabitNudgePlanner.Item {
        HabitNudgePlanner.Item(habit: habit, days: days.map { Self.date($0) })
    }

    @Test func aLiveStreakNotDoneTodayIsRemindedAtEight() throws {
        let cal = Self.calendar
        // Le 15 à midi : méditation faite les 12, 13, 14 (pas encore aujourd'hui) ; sport fait aujourd'hui.
        let items = [streak(.meditation, days: [12, 13, 14]), streak(.exercise, days: [13, 14, 15]), streak(.reading, days: [14])]
        let reminder = try #require(HabitNudgePlanner.plan(items, now: Self.date(15), calendar: cal, title: { $0.rawValue }))
        #expect(reminder.identifier == HabitNudgePlanner.identifier)
        #expect(cal.component(.hour, from: reminder.date) == 20)
        #expect(cal.isDate(reminder.date, inSameDayAs: Self.date(15)))
        #expect(reminder.title == "Garde ta série")
        #expect(reminder.body == "meditation : 3 jours d'affilée. Pas encore aujourd'hui.")
    }

    @Test func nothingWhenEverythingIsDoneOrTooLate() {
        let cal = Self.calendar
        #expect(HabitNudgePlanner.plan([streak(.meditation, days: [13, 14, 15])], now: Self.date(15), calendar: cal,
                                       title: { $0.rawValue }) == nil)
        #expect(HabitNudgePlanner.plan([streak(.meditation, days: [12, 13, 14])], now: Self.date(15, 21), calendar: cal,
                                       title: { $0.rawValue }) == nil)
        // Une seule journée n'est pas encore une série.
        #expect(HabitNudgePlanner.plan([streak(.meditation, days: [14])], now: Self.date(15), calendar: cal,
                                       title: { $0.rawValue }) == nil)
    }

    @Test func severalStreaksShareOneReminder() throws {
        let cal = Self.calendar
        let items = [streak(.meditation, days: [12, 13, 14]), streak(.exercise, days: [13, 14])]
        let reminder = try #require(HabitNudgePlanner.plan(items, now: Self.date(15), calendar: cal, title: { $0.rawValue }))
        #expect(reminder.body == "meditation (3 jours) et exercise (2 jours) : pas encore aujourd'hui.")
    }
}
