import Foundation
import Testing
@testable import EngramCore

/// P16 — les tâches qui reviennent : « sortir les poubelles tous les lundis », « aux deux semaines », « le 1er de chaque
/// mois ». Faite, la tâche passe à la prochaine fois.
struct RecurrenceTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    /// Une date à Toronto.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func rule(_ text: String) -> RecurrenceRule? { RecurrenceParser.parse(text) }

    @Test func everyDayAndEveryWeekdayAreRecognized() {
        #expect(rule("Prendre mes vitamines tous les jours") == RecurrenceRule(frequency: .daily))
        #expect(rule("Chaque matin, faire mes étirements") == RecurrenceRule(frequency: .daily, hour: 8, minute: 0))
        #expect(rule("Sortir les poubelles tous les lundis") == RecurrenceRule(frequency: .weekly, weekdays: [2]))
        #expect(rule("Cours de yoga les mardis et jeudis à 18 h, chaque semaine")
            == RecurrenceRule(frequency: .weekly, weekdays: [3, 5], hour: 18, minute: 0))
        #expect(rule("Every Friday call mom") == RecurrenceRule(frequency: .weekly, weekdays: [6]))
        #expect(rule("Arroser les plantes chaque semaine") == RecurrenceRule(frequency: .weekly))
        #expect(rule("Faire le lunch des enfants en semaine") == RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6]))
    }

    @Test func longerRhythmsAreRecognized() {
        #expect(rule("Le recyclage aux deux semaines le jeudi") == RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [5]))
        #expect(rule("Payer le loyer le 1er de chaque mois") == RecurrenceRule(frequency: .monthly, dayOfMonth: 1))
        #expect(rule("Changer le filtre tous les 3 mois") == RecurrenceRule(frequency: .monthly, interval: 3))
        #expect(rule("Renouveler l'assurance chaque année") == RecurrenceRule(frequency: .yearly))
        #expect(rule("Faire le ménage une fois par semaine") == RecurrenceRule(frequency: .weekly))
    }

    @Test func ordinarySentencesDoNotRepeat() {
        #expect(rule("Le lundi de Pâques, souper chez Julie") == nil)
        #expect(rule("Chaque fois que je vois Marc, il parle de son char") == nil)
        #expect(rule("On ira tous les deux au chalet") == nil)
        #expect(rule("Appeler le garage demain à 9 h") == nil)
        #expect(rule("Aller au gym deux fois par semaine") == nil)
    }

    @Test func theNextTimeFollowsTheRhythm() {
        let cal = Self.calendar
        // Mercredi 13 janvier 2027 à 10 h.
        let wednesday = Self.date(2027, 1, 13, 10)
        #expect(Recurrence.next(after: wednesday, rule: RecurrenceRule(frequency: .weekly, weekdays: [2]), anchor: wednesday,
                                calendar: cal) == Self.date(2027, 1, 18, 10))
        // Mardis et jeudis à 18 h : le jeudi de la même semaine.
        #expect(Recurrence.next(after: wednesday, rule: RecurrenceRule(frequency: .weekly, weekdays: [3, 5], hour: 18, minute: 0),
                                anchor: wednesday, calendar: cal) == Self.date(2027, 1, 14, 18))
        // Chaque jour : demain, même heure.
        #expect(Recurrence.next(after: wednesday, rule: RecurrenceRule(frequency: .daily), anchor: wednesday, calendar: cal)
            == Self.date(2027, 1, 14, 10))
        // Aux deux semaines le jeudi, à partir du jeudi 14 : le 28, pas le 21.
        let firstThursday = Self.date(2027, 1, 14, 0)
        #expect(Recurrence.next(after: firstThursday, rule: RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [5]),
                                anchor: firstThursday, calendar: cal) == Self.date(2027, 1, 28, 0))
        // Le 31 de chaque mois : le 28 février quand février n'a pas de 31.
        let january31 = Self.date(2027, 1, 31, 0)
        #expect(Recurrence.next(after: january31, rule: RecurrenceRule(frequency: .monthly, dayOfMonth: 31), anchor: january31,
                                calendar: cal) == Self.date(2027, 2, 28, 0))
        // Chaque année : un an plus tard.
        #expect(Recurrence.next(after: january31, rule: RecurrenceRule(frequency: .yearly), anchor: january31, calendar: cal)
            == Self.date(2028, 1, 31, 0))
    }

    @Test func aRuleSaysItselfSimply() {
        #expect(Recurrence.describe(RecurrenceRule(frequency: .daily)) == "Chaque jour")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .daily, hour: 8, minute: 0)) == "Chaque jour à 8 h")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .weekly, weekdays: [2])) == "Tous les lundis")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .weekly, weekdays: [3, 5], hour: 18, minute: 30))
            == "Les mardis et jeudis à 18 h 30")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])) == "En semaine")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [5])) == "Aux deux semaines, le jeudi")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .weekly)) == "Chaque semaine")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .monthly, dayOfMonth: 1)) == "Le 1er de chaque mois")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .monthly, interval: 3)) == "Tous les 3 mois")
        #expect(Recurrence.describe(RecurrenceRule(frequency: .yearly)) == "Chaque année")
    }
}
