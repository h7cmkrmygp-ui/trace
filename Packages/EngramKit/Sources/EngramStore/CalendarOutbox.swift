import EngramCore
import Foundation
import GRDB

/// F18 — une opération sur le calendrier, écrite avant l'effet.
public struct CalendarOperation: Sendable, Equatable {
    public enum Kind: String, Sendable { case create, update, delete }
    public enum State: String, Sendable { case pending, applied, failed, conflict }

    public let memoryID: UUID
    public let kind: Kind
    public let state: State
    public let eventIdentifier: String?
    public let error: String?
    public let attempts: Int
}

/// F18 — ce qu'une synchronisation a fait.
public struct CalendarSyncReport: Sendable, Equatable {
    public var created = 0
    public var linkedExisting = 0
    public var updated = 0
    public var deleted = 0
    public var conflicts = 0
    public var failed = 0

    public init() {}
}

/// F18 — la boîte d'envoi du calendrier : chaque création, modification ou suppression passe par une opération durable.
public struct CalendarOutbox: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider
    public let calendar: Calendar

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider(), calendar: Calendar = .current) {
        self.database = database
        self.dates = dates
        self.calendar = calendar
    }

    public func sync(destination: PrivacyDestination, calendarIdentifier: String?,
                     effects: some CalendarEffects) async -> CalendarSyncReport {
        CalendarSyncReport()
    }

    public func operation(for memoryID: UUID) throws -> CalendarOperation? { nil }
}
