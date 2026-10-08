import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// Petits défauts relevés aux relectures de P2, P3 et P4.
struct DeferredFixesStoreTests {
    func valid(_ title: String, kind: MemoryKind = .task, dates: [String] = [], path: [String] = ["Santé"]) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: title, spanStart: nil, spanEnd: nil, kind: kind,
                     tags: [], categoryPath: path, mentionedDates: dates)
    }

    /// Une dictée qui attend « Vérifie ta note » n'apparaît que dans « À vérifier », pas aussi dans « À classer ».
    @Test func notesAwaitingReviewAreNotCountedAsUnsorted() async throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/q.caf", duration: 2)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: "Acheter des piles", languages: [],
                                              engine: nil, needsReview: true)
        var summary = env.categories.librarySummaryStream().makeAsyncIterator()
        #expect(try #require(try await summary.next()).unsortedCount == 0)
        var unsorted = env.memories.memoriesStream(statuses: [.unsorted]).makeAsyncIterator()
        #expect(try #require(try await unsorted.next()).isEmpty)

        _ = try env.memories.confirmReview(sourceID: recording.sourceID, text: "Acheter des piles", keepLocal: false)
        var after = env.categories.librarySummaryStream().makeAsyncIterator()
        #expect(try #require(try await after.next()).unsortedCount == 1)
    }

    /// Un rendez-vous d'aujourd'hui sans heure, dicté l'après-midi, est quand même ajouté au calendrier.
    @Test func todaysAllDayAppointmentIsAddedEvenInTheAfternoon() throws {
        let env = try StoreTestEnvironment()
        env.dates.advance(by: 10 * 3600) // vendredi 15 janvier 2027, 13 h
        let interim = try env.saveNote("Garage aujourd'hui")
        _ = try env.filer.file([valid("Garage aujourd'hui", kind: .appointment, dates: ["aujourd'hui"], path: ["Automobile"])],
                               sourceID: interim.sourceID)
        let links = CalendarLinkStore(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
        #expect(try links.unlinkedAppointments().map(\.title) == ["Garage aujourd'hui"])
    }

    /// Une note provisoire que le propriétaire a modifiée garde son texte, mais reçoit l'échéance dictée.
    @Test func anEditedInterimStillGetsItsDueDate() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Dentiste vendredi")
        _ = try env.memories.updateMemory(interim.id, with: MemoryEdit(title: "Mon dentiste"), actor: .user)
        _ = try env.filer.file([valid("Dentiste vendredi", kind: .appointment, dates: ["vendredi"])], sourceID: interim.sourceID)
        let kept = try #require(try env.memories.memory(id: interim.id))
        #expect(kept.title == "Mon dentiste")
        #expect(kept.dueAt == CalendarDataTests.toronto(2027, 1, 22))
    }

    /// Le Calendrier d'Engram masque les événements qu'Engram a créés lui-même (sinon un rendez-vous apparaît deux fois).
    @Test func linkedEventIdentifiersAreListed() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Dentiste demain. Garage vendredi")
        let filed = try env.filer.file([valid("Dentiste demain", kind: .appointment, dates: ["demain"]),
                                        valid("Garage vendredi", kind: .appointment, dates: ["vendredi"], path: ["Automobile"])],
                                       sourceID: interim.sourceID)
        let links = CalendarLinkStore(database: env.database, dates: env.dates)
        try links.link(memoryID: filed.memories[0].id, eventIdentifier: "evt-a", calendarIdentifier: nil)
        try links.link(memoryID: filed.memories[1].id, eventIdentifier: "evt-b", calendarIdentifier: nil)
        #expect(try links.linkedEventIdentifiers() == ["evt-a", "evt-b"])
    }

    @Test func theExportIncludesCalendarLinks() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Dentiste demain")
        let filed = try env.filer.file([valid("Dentiste demain", kind: .appointment, dates: ["demain"])], sourceID: interim.sourceID)
        try CalendarLinkStore(database: env.database, dates: env.dates)
            .link(memoryID: filed.memories[0].id, eventIdentifier: "evenement-1", calendarIdentifier: nil)
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("calendar_links"))
        #expect(json.contains("evenement-1"))
    }
}
