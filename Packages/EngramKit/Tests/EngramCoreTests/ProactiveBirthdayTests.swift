import Foundation
import Testing
@testable import EngramCore

/// P44 — la veille d'une fête, le rappel qui existait déjà propose une idée de cadeau tirée des notes ; aucun rappel de plus,
/// et rien ne se lit quand Engram est verrouillé.
struct ProactiveBirthdayTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()
    static let julie = Birthday(personID: UUID(), name: "Julie", month: 3, day: 12, year: nil)
    static let now = calendar.date(from: DateComponents(year: 2027, month: 3, day: 10, hour: 10))!

    @Test func theEveReminderSuggestsAGiftWithoutAddingAnyReminder() throws {
        let ideas = [Self.julie.personID: "Idées de cadeaux : Foulard."]
        let plain = BirthdayPlanner.plan([Self.julie], now: Self.now, calendar: Self.calendar, hideNames: false)
        let enriched = BirthdayPlanner.plan([Self.julie], now: Self.now, calendar: Self.calendar, hideNames: false, ideas: ideas)
        #expect(enriched.count == plain.count)
        let eve = try #require(enriched.first { $0.identifier.hasSuffix(".veille") })
        #expect(eve.body == "Pense à souhaiter bonne fête. Idées de cadeaux : Foulard.")
        #expect(enriched.first { $0.identifier.hasSuffix(".jour") }?.body == plain.first { $0.identifier.hasSuffix(".jour") }?.body)
        // Engram verrouillé : rien ne se lit sur l'écran verrouillé.
        let hidden = BirthdayPlanner.plan([Self.julie], now: Self.now, calendar: Self.calendar, hideNames: true, ideas: ideas)
        #expect(hidden.allSatisfy { $0.body == "Ouvre Engram pour la voir." })
    }

    @Test func theIdeasComeFromWhatTheNotesSay() {
        let profile = PersonProfile(tastes: Tastes(likes: ["les parfums", "le chocolat", "les fleurs"]), giftIdeas: ["Foulard"])
        #expect(PersonQuestion.reminderIdeas(person: "Julie", profile: profile)
            == "Idées de cadeaux : Foulard. Julie aime les parfums et le chocolat.")
        #expect(PersonQuestion.reminderIdeas(person: "Julie", profile: PersonProfile(tastes: Tastes(likes: ["les parfums"])))
            == "Julie aime les parfums.")
        #expect(PersonQuestion.reminderIdeas(person: "Julie", profile: PersonProfile()) == nil)
    }
}
