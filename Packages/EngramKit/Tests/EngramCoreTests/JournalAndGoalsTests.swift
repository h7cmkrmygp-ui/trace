import Foundation
import Testing
@testable import EngramCore

/// P11 — le journal (notes jour par jour) et les objectifs des suivis.
struct JournalAndGoalsTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    /// Vendredi 15 janvier 2027, 10 h, à Toronto.
    static let friday = Date(timeIntervalSince1970: 1_800_025_200)

    func hoursAgo(_ hours: Double) -> Date { Self.friday.addingTimeInterval(-hours * 3_600) }

    // MARK: - Journal

    @Test func daysAreNamedTheWayWeSpeak() {
        #expect(DayGrouping.title(for: hoursAgo(2), now: Self.friday, calendar: Self.calendar) == "Aujourd'hui")
        #expect(DayGrouping.title(for: hoursAgo(20), now: Self.friday, calendar: Self.calendar) == "Hier")
        #expect(DayGrouping.title(for: hoursAgo(48), now: Self.friday, calendar: Self.calendar) == "Mercredi 13 janvier")
        #expect(DayGrouping.title(for: hoursAgo(15 * 24 + 1), now: Self.friday, calendar: Self.calendar)
            == "Jeudi 31 décembre 2026")
        #expect(DayGrouping.title(for: hoursAgo(14 * 24), now: Self.friday, calendar: Self.calendar) == "Vendredi 1er janvier")
    }

    @Test func notesAreGroupedDayByDayNewestFirst() {
        let dates = [hoursAgo(48), hoursAgo(1), hoursAgo(20), hoursAgo(2)]
        let groups = DayGrouping.groups(dates, date: { $0 }, now: Self.friday, calendar: Self.calendar)
        #expect(groups.map(\.title) == ["Aujourd'hui", "Hier", "Mercredi 13 janvier"])
        #expect(groups.map(\.items.count) == [2, 1, 1])
        #expect(groups[0].items == [hoursAgo(1), hoursAgo(2)])
    }

    // MARK: - Objectifs

    @Test(arguments: [
        ("Mon objectif : 155 livres", Metric.weight, 155.0, "lb"),
        ("objectif de 70 kg d'ici l'été", .weight, 70, "kg"),
        ("Mon but c'est 150 lbs", .weight, 150, "lb"),
        ("objectif 10 000 pas par jour", .steps, 10_000, "pas"),
        ("objectif 8 h de sommeil", .sleep, 8, "h"),
        ("goal 150 pounds", .weight, 150, "lb"),
    ])
    func goalsAreRecognized(text: String, metric: Metric, value: Double, unit: String) throws {
        let goal = try #require(GoalParser.parse(text).first)
        #expect(goal.metric == metric && goal.value == value && goal.unit == unit)
    }

    @Test(arguments: ["Objectif : finir le rapport", "Mon but est de courir plus", "objectif 2 livres de farine"])
    func goalTrapsAreIgnored(text: String) {
        #expect(GoalParser.parse(text).isEmpty)
    }

    /// Un objectif n'est pas une pesée : « objectif poids 155 livres » ne devient pas une mesure.
    @Test func aGoalIsNotAMeasurement() {
        #expect(MeasurementParser.parse("Objectif poids 155 livres").isEmpty)
        let both = MeasurementParser.parse("Je pèse 162 livres, objectif 155 livres")
        #expect(both.map(\.value) == [162])
        #expect(GoalParser.parse("Je pèse 162 livres, objectif 155 livres").map(\.value) == [155])
    }

    @Test func progressTowardsAGoalWorksBothWays() {
        let losing = GoalProgress.evaluate(start: 165, current: 160, target: 155)
        #expect(losing.fraction == 0.5 && losing.remaining == 5 && !losing.reached)
        #expect(GoalProgress.evaluate(start: 165, current: 154, target: 155).reached)
        let walking = GoalProgress.evaluate(start: 4_000, current: 8_000, target: 10_000)
        #expect(abs(walking.fraction - 4.0 / 6.0) < 1e-9 && walking.remaining == 2_000 && !walking.reached)
        #expect(GoalProgress.evaluate(start: 155, current: 155, target: 155).reached)
        // Parti dans le mauvais sens : rien d'accompli, pas de valeur négative.
        #expect(GoalProgress.evaluate(start: 160, current: 163, target: 155).fraction == 0)
    }
}
