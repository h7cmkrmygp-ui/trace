import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// F16 — chaque date dite garde son rôle jusqu'au stockage : un rendez-vous mardi à 14 h avec un rappel lundi à 18 h a
/// deux moments distincts ; les dates sont lues dans le fuseau de la capture (y compris au changement d'heure).
struct TemporalRolesStoreTests {
    static let appointment = "Rendez-vous chez le dentiste mardi à 14 h, rappelle-le-moi lundi à 18 h"

    func appointment(_ text: String = Self.appointment) -> ValidThought {
        ValidThought(title: "Dentiste", summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .appointment,
                     tags: [], categoryPath: ["Santé"], mentionedDates: ["mardi à 14 h", "lundi à 18 h"],
                     intent: .appointment,
                     temporal: [TemporalMention(role: .event, phrase: "mardi à 14 h"),
                                TemporalMention(role: .reminder, phrase: "lundi à 18 h")])
    }

    @Test func anAppointmentKeepsItsOwnTimeAndItsSeparateReminder() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote(Self.appointment)
        let memory = try #require(try env.filer.file([appointment()], sourceID: interim.sourceID).memories.first)
        let calendar = Fixtures.calendar
        // Le rendez-vous : mardi 19 janvier à 14 h (la capture est le vendredi 15).
        let due = try #require(memory.dueAt)
        #expect(calendar.dateComponents([.weekday, .day, .hour], from: due) == DateComponents(day: 19, hour: 14, weekday: 3))
        #expect(try env.memories.temporalMentions(of: memory.id).map(\.role) == [.event, .reminder])
        // Deux rappels : 1 h avant le rendez-vous, et celui demandé, lundi 18 janvier à 18 h.
        let item = try #require(try env.memories.reminderItems().first)
        let lundi = try #require(item.reminders.first)
        #expect(calendar.dateComponents([.day, .hour], from: lundi) == DateComponents(day: 18, hour: 18))
        let planned = ReminderPlanner.plan([item], now: Fixtures.date, calendar: calendar)
        #expect(planned.map { calendar.dateComponents([.day, .hour], from: $0.date) }
            == [DateComponents(day: 18, hour: 18), DateComponents(day: 19, hour: 13)])
        #expect(Set(planned.map(\.identifier)).count == 2)
    }

    @Test func datesAreReadInTheTimeZoneOfTheCapture() throws {
        let database = try AppDatabase.inMemory()
        // Samedi 31 octobre 2026, 14 h à Toronto : la nuit suivante, l'heure change (heure normale de l'Est).
        let dates = TestDateProvider(Date(timeIntervalSince1970: 1_793_469_600))
        var toronto = Calendar(identifier: .gregorian)
        toronto.timeZone = TimeZone(identifier: "America/Toronto")!
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let memories = MemoryStore(database: database, dates: dates, calendar: toronto)
        // Le classement se fait plus tard, sur un iPhone réglé sur un autre fuseau.
        let filer = ThoughtFiler(database: database, dates: dates, calendar: paris)
        let text = "Appeler le garage demain à 9 h"
        guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { throw CancellationError() }
        let thought = ValidThought(title: "Appeler le garage", summary: nil, excerpt: text, spanStart: nil, spanEnd: nil,
                                   kind: .task, tags: [], categoryPath: ["Auto"], mentionedDates: ["demain à 9 h"],
                                   intent: .obligation, temporal: [TemporalMention(role: .deadline, phrase: "demain à 9 h")])
        let memory = try #require(try filer.file([thought], sourceID: interim.sourceID).memories.first)
        let due = try #require(memory.dueAt)
        #expect(toronto.dateComponents([.month, .day, .hour], from: due) == DateComponents(month: 11, day: 1, hour: 9))
    }

    /// La convention, explicite : « lundi » dit un lundi désigne le lundi suivant (jamais le jour même).
    @Test func mondaySaidOnAMondayIsNextMonday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        // Lundi 18 janvier 2027, 10 h.
        let monday = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 10)))
        let resolved = try #require(DateResolver.resolve("lundi", relativeTo: monday, calendar: calendar))
        #expect(calendar.dateComponents([.month, .day], from: resolved.date) == DateComponents(month: 1, day: 25))
    }
}
