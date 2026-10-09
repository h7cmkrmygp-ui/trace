import Foundation
import Testing
@testable import EngramCore

/// P20 — les fêtes : « l'anniversaire de Julie est le 12 mars », « Marc a sa fête le 3 juin ».
struct BirthdaysTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func birthday(_ text: String) -> ParsedBirthday? { BirthdayParser.parse(text) }

    @Test func birthdaysAreRecognized() {
        #expect(birthday("L'anniversaire de Julie est le 12 mars") == ParsedBirthday(person: "Julie", month: 3, day: 12))
        #expect(birthday("Marc a sa fête le 3 juin") == ParsedBirthday(person: "Marc", month: 6, day: 3))
        #expect(birthday("La fête de Léa, c'est le 1er août") == ParsedBirthday(person: "Léa", month: 8, day: 1))
        #expect(birthday("Sophie Tremblay est née le 24 décembre 1990")
            == ParsedBirthday(person: "Sophie Tremblay", month: 12, day: 24, year: 1990))
        #expect(birthday("L'anniversaire de ma mère est le 4 mai") == ParsedBirthday(person: "ma mère", month: 5, day: 4))
        #expect(birthday("Julie's birthday is March 12") == ParsedBirthday(person: "Julie", month: 3, day: 12))
    }

    @Test func otherSentencesAreNotBirthdays() {
        #expect(birthday("Ma fête préférée, c'est Noël") == nil)
        #expect(birthday("L'anniversaire de mariage est le 12 mars") == nil)
        #expect(birthday("Souper chez Julie le 12 mars") == nil)
        #expect(birthday("L'anniversaire de Julie est le 31 février") == nil)
    }

    @Test func theNextBirthdayAndTheAge() {
        let cal = Self.calendar
        let now = Self.date(2027, 1, 15)
        #expect(BirthdayPlanner.next(month: 3, day: 12, from: now, calendar: cal) == cal.startOfDay(for: Self.date(2027, 3, 12)))
        // Le jour même compte encore ; le lendemain, c'est l'an prochain.
        #expect(BirthdayPlanner.next(month: 1, day: 15, from: now, calendar: cal) == cal.startOfDay(for: now))
        #expect(BirthdayPlanner.next(month: 1, day: 14, from: now, calendar: cal) == cal.startOfDay(for: Self.date(2028, 1, 14)))
        // Né un 29 février : le 28 les autres années.
        #expect(BirthdayPlanner.next(month: 2, day: 29, from: now, calendar: cal) == cal.startOfDay(for: Self.date(2027, 2, 28)))
        #expect(BirthdayPlanner.age(turningOn: Self.date(2027, 12, 24), born: 1990, calendar: cal) == 37)
        #expect(BirthdayPlanner.age(turningOn: Self.date(2027, 12, 24), born: nil, calendar: cal) == nil)
    }

    @Test func theEveAndTheDayAreReminded() {
        let cal = Self.calendar
        let julie = Birthday(personID: UUID(), name: "Julie", month: 3, day: 12, year: 1992)
        let planned = BirthdayPlanner.plan([julie], now: Self.date(2027, 1, 15), calendar: cal, hideNames: false)
        #expect(planned.count == 2)
        #expect(planned[0].date == Self.date(2027, 3, 11, 19))
        #expect(planned[0].title == "Demain : la fête de Julie")
        #expect(planned[0].body == "Julie aura 35 ans.")
        #expect(planned[1].date == Self.date(2027, 3, 12, 9))
        #expect(planned[1].title == "Aujourd'hui : la fête de Julie")
        #expect(planned.allSatisfy { $0.memoryID == julie.personID && $0.identifier.hasPrefix(BirthdayPlanner.identifierPrefix) })
        // Engram verrouillé : pas de nom sur l'écran verrouillé.
        let hidden = BirthdayPlanner.plan([julie], now: Self.date(2027, 1, 15), calendar: cal, hideNames: true)
        #expect(hidden.allSatisfy { !$0.title.contains("Julie") && !$0.body.contains("Julie") })
        // La veille déjà passée : seulement le jour même.
        #expect(BirthdayPlanner.plan([julie], now: Self.date(2027, 3, 11, 20), calendar: cal, hideNames: false).count == 1)
    }

    @Test func aBirthdaySaysItselfSimply() {
        let cal = Self.calendar
        let julie = Birthday(personID: UUID(), name: "Julie", month: 3, day: 12, year: 1992)
        #expect(BirthdayPlanner.describe(julie, now: Self.date(2027, 3, 7), calendar: cal) == "12 mars · dans 5 jours · 35 ans")
        #expect(BirthdayPlanner.describe(julie, now: Self.date(2027, 3, 12), calendar: cal) == "12 mars · aujourd'hui · 35 ans")
        let marc = Birthday(personID: UUID(), name: "Marc", month: 6, day: 3, year: nil)
        #expect(BirthdayPlanner.describe(marc, now: Self.date(2027, 6, 2), calendar: cal) == "3 juin · demain")
    }
}
