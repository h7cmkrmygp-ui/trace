#if canImport(EventKit)
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
/// Engram ne fait qu'**ajouter** des événements : il ne modifie ni ne supprime jamais ceux qui existent.
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
#endif
