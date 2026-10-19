import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// Un calendrier imité pour les tests : il garde ses événements, peut refuser l'accès, et compte les créations.
actor FakeCalendar: CalendarEffects {
    var events: [String: CalendarEventSnapshot] = [:]
    var markers: [String: String] = [:]
    var creations = 0
    var updates = 0
    var deletions = 0
    var denied = false

    func deny() { denied = true }

    func editInCalendar(_ identifier: String, title: String, at date: Date) {
        guard let event = events[identifier] else { return }
        events[identifier] = CalendarEventSnapshot(identifier: identifier, calendarIdentifier: event.calendarIdentifier,
                                                   title: title, start: event.start, lastModified: date)
    }

    func findEvent(marker: String, around date: Date) async throws -> CalendarEventSnapshot? {
        if denied { throw CalendarEffectError.noAccess }
        return markers.first { $0.value == marker }.flatMap { events[$0.key] }
    }

    func createEvent(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        if denied { throw CalendarEffectError.noAccess }
        creations += 1
        let identifier = "event-\(creations)"
        let event = CalendarEventSnapshot(identifier: identifier, calendarIdentifier: "local", title: draft.title,
                                          start: draft.start, lastModified: nil)
        events[identifier] = event
        markers[identifier] = draft.marker
        return event
    }

    func updateEvent(_ identifier: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        if denied { throw CalendarEffectError.noAccess }
        updates += 1
        let event = CalendarEventSnapshot(identifier: identifier, calendarIdentifier: "local", title: draft.title,
                                          start: draft.start, lastModified: nil)
        events[identifier] = event
        return event
    }

    func deleteEvent(_ identifier: String) async throws {
        if denied { throw CalendarEffectError.noAccess }
        deletions += 1
        events[identifier] = nil
    }

    func event(_ identifier: String) async throws -> CalendarEventSnapshot? {
        if denied { throw CalendarEffectError.noAccess }
        return events[identifier]
    }
}

/// F18 — chaque effet sur le calendrier passe par une opération durable, écrite avant l'effet ; l'événement porte une
/// marque Engram retrouvée avant toute nouvelle création : une interruption entre la création et le lien ne crée
/// jamais de doublon, un accès refusé n'est jamais un succès silencieux, une modification faite dans le calendrier
/// n'est pas écrasée, et une note modifiée ou supprimée met à jour son événement quand personne n'y a touché.
struct CalendarOutboxStoreTests {
    func appointment(_ env: StoreTestEnvironment, _ text: String = "Dentiste mardi à 14 h") throws -> Memory {
        let interim = try env.saveNote(text)
        return try #require(try env.filer.file([
            ValidThought(title: "Dentiste", summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .appointment,
                         tags: [], categoryPath: ["Santé"], mentionedDates: ["mardi à 14 h"], intent: .appointment),
        ], sourceID: interim.sourceID, route: AnalysisRoute(level: .personal, provider: "apple", reason: "Personnel.",
                                                            needsCloudRetry: false, basis: .judged)).memories.first)
    }

    func outbox(_ env: StoreTestEnvironment) -> CalendarOutbox {
        CalendarOutbox(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
    }

    @Test func anInterruptionBetweenTheEventAndItsLinkNeverDuplicates() async throws {
        let env = try StoreTestEnvironment()
        let memory = try appointment(env)
        let calendar = FakeCalendar()
        let first = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        #expect(first.created == 1)
        // L'app s'arrête juste après la création : le lien n'a jamais été écrit.
        try await env.database.writer.write { db in
            try db.execute(sql: "DELETE FROM calendar_link WHERE memory_id = ?", arguments: [memory.id])
            try db.execute(sql: "UPDATE calendar_operation SET state = 'pending' WHERE memory_id = ?", arguments: [memory.id])
        }
        let second = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        #expect(second.linkedExisting == 1)
        #expect(await calendar.creations == 1)
        #expect(try CalendarLinkStore(database: env.database).link(for: memory.id)?.eventIdentifier == "event-1")
    }

    @Test func aRefusedAccessIsAFailureNotASilentSuccess() async throws {
        let env = try StoreTestEnvironment()
        let memory = try appointment(env)
        let calendar = FakeCalendar()
        await calendar.deny()
        let report = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        #expect(report.failed == 1)
        #expect(report.created == 0)
        #expect(try outbox(env).operation(for: memory.id)?.state == .failed)
        #expect(try CalendarLinkStore(database: env.database).link(for: memory.id) == nil)
    }

    @Test func aChangeMadeInTheCalendarIsNotOverwritten() async throws {
        let env = try StoreTestEnvironment()
        let memory = try appointment(env)
        let calendar = FakeCalendar()
        _ = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        env.dates.advance(by: 3_600)
        await calendar.editInCalendar("event-1", title: "Dentiste (déplacé)", at: env.dates.now())
        env.dates.advance(by: 60)
        _ = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Dentiste et radiographie"), actor: .user)
        let report = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        #expect(report.conflicts == 1)
        #expect(await calendar.updates == 0)
        #expect(await calendar.events["event-1"]?.title == "Dentiste (déplacé)")
    }

    @Test func anEditedOrDeletedNoteUpdatesItsUntouchedEvent() async throws {
        let env = try StoreTestEnvironment()
        let memory = try appointment(env)
        let calendar = FakeCalendar()
        _ = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        env.dates.advance(by: 60)
        _ = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Dentiste et radiographie"), actor: .user)
        let edited = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        #expect(edited.updated == 1)
        #expect(await calendar.events["event-1"]?.title == "Dentiste et radiographie")
        // Une deuxième synchronisation ne refait rien.
        #expect(await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar).updated == 0)
        _ = try env.memories.setStatus(.trashed, for: memory.id, actor: .user)
        let deleted = await outbox(env).sync(destination: .localCalendar, calendarIdentifier: nil, effects: calendar)
        #expect(deleted.deleted == 1)
        #expect(await calendar.events["event-1"] == nil)
    }
}
