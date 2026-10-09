import Foundation
import Testing
@testable import EngramCore

/// P17 — les habitudes : « j'ai médité 10 minutes », « j'ai fait mon workout », « j'ai couru 5 km »… et leurs séries.
struct HabitsTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: month, day: day, hour: 12))!
    }

    func habits(_ text: String) -> [ParsedHabit] { HabitParser.parse(text) }

    @Test func doneHabitsAreRecognized() {
        #expect(habits("J'ai médité 10 minutes ce matin") == [ParsedHabit(habit: .meditation, quantity: 10, unit: "min")])
        #expect(habits("J'ai fait mon workout") == [ParsedHabit(habit: .exercise)])
        #expect(habits("Je suis allé au gym avec Marc") == [ParsedHabit(habit: .exercise)])
        #expect(habits("J'ai couru 5,5 km") == [ParsedHabit(habit: .running, quantity: 5.5, unit: "km")])
        #expect(habits("J'ai marché 30 minutes après le souper") == [ParsedHabit(habit: .walking, quantity: 30, unit: "min")])
        #expect(habits("J'ai lu 20 pages de mon livre") == [ParsedHabit(habit: .reading, quantity: 20, unit: "pages")])
        #expect(habits("J'ai bu 2 litres d'eau") == [ParsedHabit(habit: .water, quantity: 2, unit: "L")])
        #expect(habits("J'ai pris mes vitamines") == [ParsedHabit(habit: .vitamins)])
        #expect(habits("I meditated and went for a run") == [ParsedHabit(habit: .meditation), ParsedHabit(habit: .running)])
    }

    @Test func yesterdayCountsForYesterday() {
        #expect(habits("Hier j'ai fait du yoga") == [ParsedHabit(habit: .exercise, daysBefore: 1)])
    }

    @Test func plansAndRefusalsAreNotHabits() {
        #expect(habits("Il faut que je médite plus souvent").isEmpty)
        #expect(habits("Je dois aller au gym demain").isEmpty)
        #expect(habits("J'ai pas médité aujourd'hui").isEmpty)
        #expect(habits("Je n'ai pas couru cette semaine").isEmpty)
        #expect(habits("J'ai lu tes messages").isEmpty)
        #expect(habits("Je suis allé au marché").isEmpty)
    }

    @Test func aStreakCountsTheDaysInARow() {
        let cal = Self.calendar
        let days: [Date] = [Self.day(1, 10), Self.day(1, 12), Self.day(1, 13), Self.day(1, 14)]
        // Fait les 12, 13 et 14 : 3 jours d'affilée, encore vivante le 15 tant que la journée n'est pas finie.
        #expect(HabitStats.streak(days, today: Self.day(1, 14), calendar: cal) == 3)
        #expect(HabitStats.streak(days, today: Self.day(1, 15), calendar: cal) == 3)
        #expect(HabitStats.streak(days, today: Self.day(1, 16), calendar: cal) == 0)
        #expect(HabitStats.bestStreak(days, calendar: cal) == 3)
        // Deux fois le même jour ne compte qu'une fois.
        #expect(HabitStats.streak(days + [Self.day(1, 14)], today: Self.day(1, 14), calendar: cal) == 3)
    }

    @Test func theWeekAndTheGridShowTheRhythm() throws {
        let cal = Self.calendar
        // Vendredi 15 janvier 2027 ; la semaine commence le dimanche 10.
        let days: [Date] = [Self.day(1, 3), Self.day(1, 10), Self.day(1, 11), Self.day(1, 15)]
        #expect(HabitStats.thisWeek(days, today: Self.day(1, 15), calendar: cal) == 3)
        let grid = HabitStats.grid(days, today: Self.day(1, 15), weeks: 2, calendar: cal)
        try #require(grid.count == 2)
        try #require(grid[1].count == 7)
        // Dernière colonne : dimanche 10 (fait), lundi 11 (fait), … vendredi 15 (fait), samedi 16 (à venir).
        #expect(grid[1] == [true, true, false, false, false, true, nil])
        // Colonne d'avant : seulement le dimanche 3.
        #expect(grid[0] == [true, false, false, false, false, false, false])
    }
}
