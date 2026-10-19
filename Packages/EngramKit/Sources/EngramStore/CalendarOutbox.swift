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
    /// Un événement déjà créé par Engram (retrouvé par sa marque) a été relié au lieu d'être recréé.
    public var linkedExisting = 0
    public var updated = 0
    public var deleted = 0
    /// Une modification faite dans le calendrier (ou un événement supprimé là) : Engram n'y touche pas.
    public var conflicts = 0
    public var failed = 0

    public init() {}
}

/// F18 — la boîte d'envoi du calendrier : chaque création, modification ou suppression passe par une opération durable,
/// écrite avant l'effet ; l'événement porte la marque Engram de sa note, cherchée avant toute création (une interruption
/// entre la création et le lien ne crée jamais de doublon). Une erreur est gardée avec l'opération, jamais un succès
/// silencieux. Une note modifiée ou mise à la corbeille met à jour ou retire son événement seulement si personne n'y a
/// touché dans le calendrier depuis ; sinon c'est un conflit, et l'événement reste tel quel.
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
        var report = CalendarSyncReport()
        let links = CalendarLinkStore(database: database, dates: dates, calendar: calendar)
        // Les rendez-vous sans événement, que la politique de chaque note permet d'envoyer vers ce calendrier.
        for memory in (try? links.unlinkedAppointments(for: destination)) ?? [] {
            guard let start = memory.dueAt else { continue }
            let draft = Self.draft(for: memory, start: start, calendarIdentifier: calendarIdentifier)
            do {
                try begin(memory.id, .create)
                if let existing = try await effects.findEvent(marker: draft.marker, around: start) {
                    try complete(memory, .create, event: existing, draft: draft)
                    report.linkedExisting += 1
                } else {
                    let created = try await effects.createEvent(draft)
                    try complete(memory, .create, event: created, draft: draft)
                    report.created += 1
                }
            } catch {
                record(memory.id, .create, state: .failed, error: error)
                report.failed += 1
            }
        }
        // Les événements déjà reliés dont on sait ce qui y a été écrit (les liens d'avant v24 n'y sont pas).
        for link in (try? syncedLinks()) ?? [] {
            guard let memory = self.memory(link.memoryID) else {
                continue
            }
            let trashed = memory.status == .trashed
            guard let start = memory.dueAt else { continue }
            let changed = memory.title != link.syncedTitle || start != link.syncedStart
            guard trashed || changed else { continue }
            let kind: CalendarOperation.Kind = trashed ? .delete : .update
            do {
                guard let event = try await effects.event(link.eventIdentifier) else {
                    // Supprimé dans le calendrier : le choix du propriétaire tient (rien n'est recréé).
                    record(memory.id, kind, state: .conflict, error: nil)
                    report.conflicts += 1
                    continue
                }
                guard !Self.modifiedOutside(event, link) else {
                    record(memory.id, kind, state: .conflict, error: nil)
                    report.conflicts += 1
                    continue
                }
                try begin(memory.id, kind)
                if trashed {
                    try await effects.deleteEvent(link.eventIdentifier)
                    try removeLink(memory.id)
                    report.deleted += 1
                } else {
                    let draft = Self.draft(for: memory, start: start, calendarIdentifier: link.calendarIdentifier)
                    let updated = try await effects.updateEvent(link.eventIdentifier, with: draft)
                    try complete(memory, .update, event: updated, draft: draft)
                    report.updated += 1
                }
            } catch {
                record(memory.id, kind, state: .failed, error: error)
                report.failed += 1
            }
        }
        return report
    }

    /// La dernière opération d'une note.
    public func operation(for memoryID: UUID) throws -> CalendarOperation? {
        try database.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT memory_id, kind, state, event_identifier, error, attempts FROM calendar_operation
                WHERE memory_id = ? ORDER BY updated_at DESC, rowid DESC LIMIT 1
                """, arguments: [memoryID])
                .flatMap { row -> CalendarOperation? in
                    guard let kind = CalendarOperation.Kind(rawValue: row["kind"]),
                          let state = CalendarOperation.State(rawValue: row["state"]) else { return nil }
                    return CalendarOperation(memoryID: row["memory_id"], kind: kind, state: state,
                                             eventIdentifier: row["event_identifier"], error: row["error"],
                                             attempts: row["attempts"])
                }
        }
    }

    static func draft(for memory: Memory, start: Date, calendarIdentifier: String?) -> CalendarEventDraft {
        CalendarEventDraft(title: memory.title, start: start, hasTime: memory.dueHasTime, notes: memory.summary,
                           marker: CalendarMarker.make(memory.id), calendarIdentifier: calendarIdentifier)
    }

    /// Quelqu'un a touché à l'événement depuis qu'Engram l'a écrit : sa date de modification est plus récente, ou son
    /// titre ou son heure ne sont plus ceux écrits.
    static func modifiedOutside(_ event: CalendarEventSnapshot, _ link: CalendarLink) -> Bool {
        if let modified = event.lastModified, let synced = link.syncedAt, modified > synced.addingTimeInterval(1) {
            return true
        }
        return event.title != link.syncedTitle || event.start != link.syncedStart
    }

    static func opID(_ memoryID: UUID, _ kind: CalendarOperation.Kind) -> String { kind.rawValue + ":" + memoryID.uuidString }

    /// L'opération est écrite (ou reprise) avant l'effet.
    func begin(_ memoryID: UUID, _ kind: CalendarOperation.Kind) throws {
        let now = dates.now()
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO calendar_operation (op_id, memory_id, kind, state, attempts, created_at, updated_at)
                VALUES (?, ?, ?, 'pending', 1, ?, ?)
                ON CONFLICT(op_id) DO UPDATE SET state = 'pending', error = NULL, attempts = attempts + 1, updated_at = ?
                """, arguments: [Self.opID(memoryID, kind), memoryID, kind.rawValue, now, now, now])
        }
    }

    /// Le lien et ce qui a été écrit, avec l'opération terminée, dans une seule transaction.
    func complete(_ memory: Memory, _ kind: CalendarOperation.Kind, event: CalendarEventSnapshot,
                  draft: CalendarEventDraft) throws {
        let now = dates.now()
        try database.writer.write { db in
            let created = try Date.fetchOne(db, sql: "SELECT created_at FROM calendar_link WHERE memory_id = ?",
                                            arguments: [memory.id]) ?? now
            try db.execute(sql: """
                INSERT OR REPLACE INTO calendar_link (memory_id, event_identifier, calendar_identifier, created_at,
                  synced_title, synced_start, synced_at) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [memory.id, event.identifier, event.calendarIdentifier ?? draft.calendarIdentifier, created,
                                 event.title, event.start, now])
            try db.execute(sql: """
                UPDATE calendar_operation SET state = 'applied', event_identifier = ?, error = NULL, updated_at = ?
                WHERE op_id = ?
                """, arguments: [event.identifier, now, Self.opID(memory.id, kind)])
        }
    }

    func removeLink(_ memoryID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM calendar_link WHERE memory_id = ?", arguments: [memoryID])
            try db.execute(sql: "UPDATE calendar_operation SET state = 'applied', updated_at = ? WHERE op_id = ?",
                           arguments: [now, Self.opID(memoryID, .delete)])
        }
    }

    /// Une erreur ou un conflit reste avec l'opération (jamais un succès silencieux).
    func record(_ memoryID: UUID, _ kind: CalendarOperation.Kind, state: CalendarOperation.State, error: (any Error)?) {
        let now = dates.now()
        try? database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO calendar_operation (op_id, memory_id, kind, state, error, attempts, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 1, ?, ?)
                ON CONFLICT(op_id) DO UPDATE SET state = excluded.state, error = excluded.error, updated_at = excluded.updated_at
                """, arguments: [Self.opID(memoryID, kind), memoryID, kind.rawValue, state.rawValue,
                                 error.map { String(describing: $0) }, now, now])
        }
    }

    func memory(_ id: UUID) -> Memory? {
        (try? database.writer.read { db in try Memory.fetchOne(db, key: id) }) ?? nil
    }

    func syncedLinks() throws -> [CalendarLink] {
        try database.writer.read { db in
            try CalendarLink.filter(Column("synced_at") != nil).fetchAll(db)
        }
    }
}
