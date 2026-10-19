#if canImport(EventKit)
import EngramCore
import EventKit
import Foundation

public struct CalendarInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Compte du calendrier (iCloud, Google…).
    public let accountTitle: String
}

public struct CalendarEventInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
}

public enum CalendarAccess: Sendable, Equatable {
    case notDetermined, granted, writeOnly, denied
}

public enum CalendarError: Error, Equatable, Sendable {
    case noAccess, noCalendar
}

/// Accès au Calendrier de l'iPhone (EventKit). Un compte Google ajouté dans iOS est un calendrier comme un autre.
/// F18 — Engram ajoute ses rendez-vous (avec sa marque dans l'événement), et ne modifie ou ne retire que ses propres
/// événements, quand personne n'y a touché dans le calendrier (voir `CalendarOutbox`).
@MainActor
public final class CalendarService {
    private let store = EKEventStore()

    public init() {}

    public var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func writableCalendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, accountTitle: $0.source?.title ?? "") }
            .sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) }
    }

    public func events(from start: Date, to end: Date) -> [CalendarEventInfo] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEventInfo(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "",
                              start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                              calendarTitle: event.calendar?.title ?? "")
        }
    }

    /// F17 — le calendrier cible reste sur l'iPhone (« Sur mon iPhone ») ; sinon il est synchronisé (iCloud, Google…),
    /// donc une destination externe. Sans calendrier connu : considéré comme synchronisé (le plus prudent).
    public func isLocalCalendar(_ identifier: String?) -> Bool {
        guard access == .granted || access == .writeOnly,
              let calendar = identifier.flatMap({ store.calendar(withIdentifier: $0) }) ?? store.defaultCalendarForNewEvents
        else { return false }
        return calendar.source?.sourceType == .local
    }

    /// Ajoute un rendez-vous : 1 h si l'heure est connue (durée signalée comme estimée), sinon journée entière.
    public func addAppointment(title: String, start: Date, hasTime: Bool, notes: String?,
                               calendarIdentifier: String?) throws -> (eventID: String, calendarID: String) {
        guard access == .granted || access == .writeOnly else { throw CalendarError.noAccess }
        guard let calendar = calendarIdentifier.flatMap({ store.calendar(withIdentifier: $0) }) ?? store.defaultCalendarForNewEvents
        else { throw CalendarError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.startDate = start
        if hasTime {
            event.endDate = start.addingTimeInterval(3600)
            event.notes = [notes, "Ajouté par Engram — durée estimée (1 h)."].compactMap { $0 }.joined(separator: "\n\n")
        } else {
            event.isAllDay = true
            event.endDate = start
            event.notes = [notes, "Ajouté par Engram."].compactMap { $0 }.joined(separator: "\n\n")
        }
        try store.save(event, span: .thisEvent)
        return (event.eventIdentifier ?? "", calendar.calendarIdentifier)
    }
}

/// F18 — les effets de la boîte d'envoi du calendrier, sur EventKit. La marque Engram de la note est l'adresse de
/// l'événement (« engram://memory/… »), cherchée avant toute création.
extension CalendarService: CalendarEffects {
    public func findEvent(marker: String, around date: Date) async throws -> CalendarEventSnapshot? {
        guard access == .granted || access == .writeOnly else { throw CalendarEffectError.noAccess }
        // Accès en écriture seule : le calendrier ne peut pas être lu ; seule l'opération gardée protège du doublon.
        guard access == .granted else { return nil }
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-3 * 86_400),
                                                 end: date.addingTimeInterval(3 * 86_400), calendars: nil)
        return store.events(matching: predicate).first { $0.url?.absoluteString == marker }.map(Self.snapshot)
    }

    public func createEvent(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        guard access == .granted || access == .writeOnly else { throw CalendarEffectError.noAccess }
        guard let calendar = draft.calendarIdentifier.flatMap({ store.calendar(withIdentifier: $0) })
            ?? store.defaultCalendarForNewEvents else { throw CalendarEffectError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.url = URL(string: draft.marker)
        Self.fill(event, with: draft)
        try store.save(event, span: .thisEvent)
        return Self.snapshot(event)
    }

    public func updateEvent(_ identifier: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        guard access == .granted else { throw CalendarEffectError.noAccess }
        guard let event = store.event(withIdentifier: identifier) else { throw CalendarEffectError.noCalendar }
        Self.fill(event, with: draft)
        try store.save(event, span: .thisEvent)
        return Self.snapshot(event)
    }

    public func deleteEvent(_ identifier: String) async throws {
        guard access == .granted else { throw CalendarEffectError.noAccess }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent)
    }

    public func event(_ identifier: String) async throws -> CalendarEventSnapshot? {
        guard access == .granted else { throw CalendarEffectError.noAccess }
        return store.event(withIdentifier: identifier).map(Self.snapshot)
    }

    /// 1 h si l'heure est connue (durée signalée comme estimée), sinon journée entière.
    static func fill(_ event: EKEvent, with draft: CalendarEventDraft) {
        event.title = draft.title
        event.startDate = draft.start
        if draft.hasTime {
            event.isAllDay = false
            event.endDate = draft.start.addingTimeInterval(3600)
            event.notes = [draft.notes, "Ajouté par Engram — durée estimée (1 h)."].compactMap { $0 }.joined(separator: "\n\n")
        } else {
            event.isAllDay = true
            event.endDate = draft.start
            event.notes = [draft.notes, "Ajouté par Engram."].compactMap { $0 }.joined(separator: "\n\n")
        }
    }

    static func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        CalendarEventSnapshot(identifier: event.eventIdentifier ?? "", calendarIdentifier: event.calendar?.calendarIdentifier,
                              title: event.title ?? "", start: event.startDate, lastModified: event.lastModifiedDate)
    }
}
#endif
