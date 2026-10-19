import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// F11 — une retranscription réconcilie la nouvelle analyse avec les notes que le propriétaire a modifiées (ou liées au
/// calendrier) au lieu de les recréer à côté. F12 — un nouvel essai ne supprime pas les bons résultats avant d'en avoir de
/// nouveaux, et les essais sont espacés puis bornés.
struct ReconciliationStoreTests {
    static let route = AnalysisRoute(level: .neutral, provider: "gemini", reason: "Neutre.", needsCloudRetry: false,
                                     basis: .judged)
    static let localRetry = AnalysisRoute(level: .neutral, provider: "apple", reason: "Gemini injoignable. Classée sur l'iPhone.",
                                          needsCloudRetry: true, basis: .judged)

    func thoughts(_ items: [(excerpt: String, kind: MemoryKind, dates: [String])], in text: String) -> [ValidThought] {
        items.map { item in
            let range = (text as NSString).range(of: item.excerpt)
            return ValidThought(title: item.excerpt, summary: nil, excerpt: item.excerpt, spanStart: range.location,
                                spanEnd: range.location + range.length, kind: item.kind, tags: [], categoryPath: ["Maison"],
                                mentionedDates: item.dates)
        }
    }

    func living(_ env: StoreTestEnvironment) throws -> [Memory] {
        try env.memories.memories(statuses: [.active, .unsorted])
    }

    @Test func aRetranscriptionKeepsTheOwnersEditWithoutDuplicatingIt() throws {
        let env = try StoreTestEnvironment()
        let first = "Appeler le garage. Acheter du lait."
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/r.caf", duration: 3, transcript: first, languages: [],
                                                   engine: nil)
        let filed = try env.filer.file(thoughts([("Appeler le garage", .task, []), ("Acheter du lait", .task, [])], in: first),
                                       sourceID: voice.sourceID, route: Self.route)
        let garage = try #require(filed.memories.first { $0.excerpt == "Appeler le garage" })
        _ = try env.memories.updateMemory(garage.id, with: MemoryEdit(title: "Appeler le garage Tremblay"), actor: .user)

        let second = "Appeler le garage demain. Acheter du lait."
        try env.memories.retranscribe(sourceID: voice.sourceID, transcript: second, languages: [], engine: "whisperkit")
        _ = try env.filer.file(thoughts([("Appeler le garage demain", .task, ["demain"]), ("Acheter du lait", .task, [])],
                                        in: second), sourceID: voice.sourceID, route: Self.route)
        let notes = try living(env)
        #expect(notes.filter { $0.title.localizedCaseInsensitiveContains("garage") }.count == 1)
        #expect(notes.contains { $0.id == garage.id && $0.title == "Appeler le garage Tremblay" })
        #expect(notes.filter { $0.excerpt == "Acheter du lait" }.count == 1)
    }

    @Test func aCalendarLinkedAppointmentIsNotDuplicated() throws {
        let env = try StoreTestEnvironment()
        let first = "Dentiste demain à 15 h"
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/d.caf", duration: 2, transcript: first, languages: [],
                                                   engine: nil)
        let filed = try env.filer.file(thoughts([(first, .appointment, ["demain à 15 h"])], in: first),
                                       sourceID: voice.sourceID, route: Self.route)
        let appointment = try #require(filed.memories.first)
        try CalendarLinkStore(database: env.database, dates: env.dates)
            .link(memoryID: appointment.id, eventIdentifier: "EV-1", calendarIdentifier: "CAL")
        let second = "Dentiste demain à 15 h au bureau"
        try env.memories.retranscribe(sourceID: voice.sourceID, transcript: second, languages: [], engine: "whisperkit")
        _ = try env.filer.file(thoughts([(second, .appointment, ["demain à 15 h"])], in: second),
                               sourceID: voice.sourceID, route: Self.route)
        let appointments = try living(env).filter { $0.kind == .appointment }
        #expect(appointments.map(\.id) == [appointment.id])
        #expect(try CalendarLinkStore(database: env.database, dates: env.dates).link(for: appointment.id) != nil)
    }

    @Test func aRetranscriptionKeepsTheOldResultsUntilTheNewOnesAreFiled() throws {
        let env = try StoreTestEnvironment()
        let first = "Appeler le garage"
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/g.caf", duration: 2, transcript: first, languages: [],
                                                   engine: nil)
        let filed = try env.filer.file(thoughts([(first, .task, [])], in: first), sourceID: voice.sourceID, route: Self.route)
        let old = try #require(filed.memories.first)
        try env.memories.retranscribe(sourceID: voice.sourceID, transcript: "Appeler le garage Tremblay", languages: [],
                                      engine: "whisperkit")
        // En attente de la nouvelle analyse : l'ancienne tâche reste utilisable.
        #expect(try living(env).map(\.id) == [old.id])
        // L'analyse échoue : rien n'est perdu.
        try env.filer.markFallback(sourceID: voice.sourceID)
        #expect(try living(env).map(\.id) == [old.id])
    }

    @Test func aCloudRetryKeepsTheGoodResultsUntilANewOneIsFiled() throws {
        let env = try StoreTestEnvironment()
        let text = "Appeler le garage"
        let interim = try env.saveNote(text)
        let filed = try env.filer.file(thoughts([(text, .task, [])], in: text), sourceID: interim.sourceID,
                                       route: Self.localRetry)
        let old = try #require(filed.memories.first)
        #expect(try env.memories.reopenForCloudRetry(sourceID: interim.sourceID))
        #expect(try living(env).map(\.id) == [old.id])
        try env.filer.markFallback(sourceID: interim.sourceID)
        #expect(try living(env).map(\.id) == [old.id])
        // Une nouvelle analyse réussie remplace l'ancienne d'un coup.
        env.dates.advance(by: 24 * 3600)
        #expect(try env.memories.reopenForCloudRetry(sourceID: interim.sourceID))
        let replaced = try env.filer.file(thoughts([(text, .task, [])], in: text), sourceID: interim.sourceID, route: Self.route)
        #expect(try living(env).map(\.id) == replaced.memories.map(\.id))
        #expect(!replaced.memories.map(\.id).contains(old.id))
    }

    @Test func retriesWaitLongerEachTimeAndStop() throws {
        let env = try StoreTestEnvironment()
        let text = "Appeler le garage"
        let interim = try env.saveNote(text)
        _ = try env.filer.file(thoughts([(text, .task, [])], in: text), sourceID: interim.sourceID, route: Self.localRetry)
        #expect(try env.memories.sourcesToRetry(cloudAvailable: true).map(\.id) == [interim.sourceID])
        var waited: [TimeInterval] = []
        for _ in 0..<ThoughtFiler.maxAnalysisAttempts {
            #expect(try env.memories.reopenForCloudRetry(sourceID: interim.sourceID))
            _ = try env.filer.file(thoughts([(text, .task, [])], in: text), sourceID: interim.sourceID, route: Self.localRetry)
            // Pas de nouvel essai tout de suite.
            #expect(try env.memories.sourcesToRetry(cloudAvailable: true).isEmpty)
            let source = try #require(try env.memories.source(id: interim.sourceID))
            let delay = try #require(source.retryAfter).timeIntervalSince(env.dates.now())
            waited.append(delay)
            env.dates.advance(by: delay + 1)
        }
        #expect(waited == waited.sorted())
        #expect(Set(waited).count == waited.count)
        // Limite atteinte : plus aucun essai, même plus tard.
        env.dates.advance(by: 30 * 24 * 3600)
        #expect(try env.memories.sourcesToRetry(cloudAvailable: true).isEmpty)
    }

    @Test func aFailedAnalysisIsRetriedLocallyEvenWithoutACloudKey() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Une note que l'IA n'a pas su classer")
        try env.filer.markFallback(sourceID: interim.sourceID)
        env.dates.advance(by: 24 * 3600)
        #expect(try env.memories.sourcesToRetry(cloudAvailable: false).map(\.id) == [interim.sourceID])
        // Classée sur l'iPhone faute de service : ne revient pas sans service en ligne.
        let other = try env.saveNote("Appeler le garage")
        _ = try env.filer.file(thoughts([("Appeler le garage", .task, [])], in: "Appeler le garage"), sourceID: other.sourceID,
                               route: Self.localRetry)
        #expect(try !env.memories.sourcesToRetry(cloudAvailable: false).map(\.id).contains(other.sourceID))
    }
}
