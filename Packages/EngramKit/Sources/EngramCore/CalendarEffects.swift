import Foundation

/// F18 — un événement à écrire dans le calendrier de l'iPhone, avec la marque Engram de sa note.
public struct CalendarEventDraft: Sendable, Equatable {
    public let title: String
    public let start: Date
    public let hasTime: Bool
    public let notes: String?
    /// « engram://memory/<id> » : retrouvée avant toute nouvelle création (jamais de doublon).
    public let marker: String
    public let calendarIdentifier: String?

    public init(title: String, start: Date, hasTime: Bool, notes: String?, marker: String, calendarIdentifier: String?) {
        self.title = title
        self.start = start
        self.hasTime = hasTime
        self.notes = notes
        self.marker = marker
        self.calendarIdentifier = calendarIdentifier
    }
}

/// F18 — un événement tel que le calendrier le connaît (sa dernière modification dit si quelqu'un y a touché).
public struct CalendarEventSnapshot: Sendable, Equatable {
    public let identifier: String
    public let calendarIdentifier: String?
    public let title: String
    public let start: Date
    public let lastModified: Date?

    public init(identifier: String, calendarIdentifier: String?, title: String, start: Date, lastModified: Date?) {
        self.identifier = identifier
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.start = start
        self.lastModified = lastModified
    }
}

public enum CalendarEffectError: Error, Equatable, Sendable {
    case noAccess, noCalendar
}

/// F18 — les effets sur le calendrier (EventKit sur l'iPhone, un calendrier imité dans les tests).
public protocol CalendarEffects: Sendable {
    func findEvent(marker: String, around date: Date) async throws -> CalendarEventSnapshot?
    func createEvent(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func updateEvent(_ identifier: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot
    func deleteEvent(_ identifier: String) async throws
    func event(_ identifier: String) async throws -> CalendarEventSnapshot?
}

public enum CalendarMarker {
    public static func make(_ memoryID: UUID) -> String { "engram://memory/" + memoryID.uuidString }
}
