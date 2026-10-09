import EngramCore
import Foundation
import GRDB

/// Le rythme d'une tâche (table `memory_recurrence`).
public struct MemoryRecurrence: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_recurrence" }
    public var memoryID: UUID
    public var rule: RecurrenceRule
    /// La première fois (pour « aux deux semaines » et l'heure).
    public var anchorAt: Date
    /// Combien de fois la tâche a été faite.
    public var doneCount: Int
    public var lastDoneAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case rule
        case memoryID = "memory_id"
        case anchorAt = "anchor_at"
        case doneCount = "done_count"
        case lastDoneAt = "last_done_at"
        case createdAt = "created_at"
    }
}

/// P16 — les tâches qui reviennent : « Fait » les passe à la prochaine fois (les rappels suivent l'échéance).
extension MemoryStore {
    public func recurrence(for memoryID: UUID) throws -> MemoryRecurrence? {
        try database.writer.read { db in try MemoryRecurrence.fetchOne(db, key: memoryID) }
    }

    public func recurrenceStream(for memoryID: UUID) -> AsyncThrowingStream<MemoryRecurrence?, any Error> {
        database.stream { db in try MemoryRecurrence.fetchOne(db, key: memoryID) }
    }

    /// Pose, change ou (nil) retire le rythme d'une tâche. Sans échéance, la tâche prend la prochaine fois. C'est une
    /// décision du propriétaire : la note ne sera plus remplacée par un nouveau classement.
    public func setRecurrence(_ rule: RecurrenceRule?, for memoryID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: memoryID) else { throw StoreError.notFound }
            guard let rule else {
                _ = try MemoryRecurrence.deleteOne(db, key: memoryID)
                return
            }
            try startRecurrence(db, memory: &memory, rule: rule, from: now, now: now, actor: .user)
        }
    }

    /// « tous les lundis » dans une tâche ou un rendez-vous classé : le rythme est posé (P16).
    func recordRecurrence(_ db: Database, memoryID: UUID, text: String, capturedAt: Date, now: Date) throws {
        guard var memory = try Memory.fetchOne(db, key: memoryID), memory.kind == .task || memory.kind == .appointment,
              let rule = RecurrenceParser.parse(text) else { return }
        try startRecurrence(db, memory: &memory, rule: rule, from: capturedAt, now: now, actor: .ai)
    }

    func startRecurrence(_ db: Database, memory: inout Memory, rule: RecurrenceRule, from: Date, now: Date,
                         actor: ChangeActor) throws {
        var changed = false
        if memory.dueAt == nil {
            // Sans heure, aujourd'hui compte (« tous les jours », dit le matin, c'est pour aujourd'hui).
            let anchor = rule.hour == nil ? calendar.startOfDay(for: from) : from
            let after = rule.hour == nil ? anchor.addingTimeInterval(-1) : from
            if let first = Recurrence.next(after: after, rule: rule, anchor: anchor, calendar: calendar) {
                memory.dueAt = first
                memory.dueHasTime = rule.hour != nil
                changed = true
            }
        }
        if actor == .user && !memory.userEdited {
            memory.userEdited = true
            changed = true
        }
        if changed {
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: actor, reason: "répétition : \(Recurrence.describe(rule))", at: now)
                .insert(db)
        }
        let existing = try MemoryRecurrence.fetchOne(db, key: memory.id)
        try MemoryRecurrence(memoryID: memory.id, rule: rule, anchorAt: memory.dueAt ?? from,
                             doneCount: existing?.doneCount ?? 0, lastDoneAt: existing?.lastDoneAt,
                             createdAt: existing?.createdAt ?? now).save(db)
    }

    /// Une tâche qui revient, faite : son échéance passe à la prochaine fois. Faux si ce n'en est pas une.
    func advanceRecurrence(_ db: Database, _ memory: inout Memory, now: Date) throws -> Bool {
        guard memory.kind == .task || memory.kind == .appointment, memory.status == .active || memory.status == .unsorted,
              var recurrence = try MemoryRecurrence.fetchOne(db, key: memory.id),
              let next = Recurrence.next(after: max(now, memory.dueAt ?? now), rule: recurrence.rule,
                                         anchor: recurrence.anchorAt, calendar: calendar) else { return false }
        memory.dueAt = next
        memory.version += 1
        memory.updatedAt = now
        try memory.update(db)
        let when = next.formatted(Date.FormatStyle(date: .complete, time: memory.dueHasTime ? .shortened : .omitted,
                                                   locale: Locale(identifier: "fr_CA"), calendar: calendar,
                                                   timeZone: calendar.timeZone))
        try MemoryVersion(memory: memory, changedBy: .user, reason: "fait — prochaine fois : \(when)", at: now).insert(db)
        recurrence.doneCount += 1
        recurrence.lastDoneAt = now
        try recurrence.update(db)
        return true
    }
}

/// P22 — les tâches qui reviennent, pour le Calendrier.
extension MemoryStore {
    public func recurringTasks() throws -> [CalendarProjection.Recurring] { [] }
}
