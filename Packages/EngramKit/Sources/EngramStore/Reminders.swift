import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// Tâches et rendez-vous datés encore à faire, relus à chaque changement (fait, corbeille, date modifiée) :
    /// les rappels de l'iPhone suivent toujours la base.
    public func reminderItemsStream() -> AsyncThrowingStream<[ReminderPlanner.Item], any Error> {
        database.stream { db in try Self.reminderItems(db) }
    }

    public func reminderItems() throws -> [ReminderPlanner.Item] {
        try database.writer.read { db in try Self.reminderItems(db) }
    }

    /// Une note est privée (rien sur l'écran verrouillé) si le propriétaire l'a gardée sur l'iPhone, ou si le
    /// contrôleur de confidentialité l'a jugée secrète. Être classée sur l'iPhone faute de service ne la rend pas secrète.
    static func reminderItems(_ db: Database) throws -> [ReminderPlanner.Item] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT m.id AS id, m.title AS title, m.kind AS kind, m.status AS status, m.due_at AS due_at,
                   m.due_has_time AS due_has_time, s.keep_local AS keep_local, s.privacy_level AS privacy_level,
                   s.privacy_basis AS privacy_basis
            FROM memory m JOIN source s ON s.id = m.source_id
            WHERE m.due_at IS NOT NULL AND m.status IN ('active', 'unsorted') AND m.kind IN ('task', 'appointment')
              AND s.needs_review = 0
            """)
        return try rows.map { row in
            let kind: String? = row["kind"]
            let status: String = row["status"]
            let id: UUID = row["id"]
            let due: Date? = row["due_at"]
            // F16 — les rappels demandés en plus de l'échéance, à leur moment exact (pas celui de l'échéance).
            let reminders = try Date.fetchAll(db, sql: """
                SELECT resolved_at FROM memory_temporal
                WHERE memory_id = ? AND role = 'reminder' AND resolved_at IS NOT NULL ORDER BY position
                """, arguments: [id]).filter { $0 != due }
            return ReminderPlanner.Item(id: id, title: row["title"], kind: kind.flatMap(MemoryKind.init(rawValue:)),
                                        status: MemoryStatus(rawValue: status) ?? .active, dueAt: due,
                                        dueHasTime: row["due_has_time"] ?? false, isPrivate: isPrivate(row),
                                        reminders: reminders)
        }
    }

    /// F13 — ce qu'une ligne dit de la confidentialité de sa source (`keep_local`, `privacy_level`, `privacy_basis`).
    static func privacyFacts(_ row: Row) -> PrivacyFacts {
        let level: String? = row["privacy_level"]
        let basis: String? = row["privacy_basis"]
        let keepLocal: Bool = row["keep_local"] ?? false
        return PrivacyFacts(keepLocal: keepLocal, level: level.flatMap(PrivacyLevel.init(rawValue:)),
                            basis: basis.flatMap(PrivacyBasis.init(rawValue:)))
    }

    /// Rien sur l'écran verrouillé (F01, F13) : selon la politique commune de la source (`keep_local`, `privacy_level`,
    /// `privacy_basis` ; inconnue = privée) et, pour une liste, selon toutes ses contributions (`list_mask`, jamais abaissé).
    /// Aussi pour les rappels de lieu.
    static func isPrivate(_ row: Row) -> Bool {
        let mask: Int = row["list_mask"] ?? 0
        return !PrivacyPolicy.allows(privacyFacts(row), .lockScreen) || !PrivacyPolicy.allows(mask: mask, .lockScreen)
    }
}

extension MemoryStore {
    /// Chiffres d'une semaine pour son résumé : notes prises (sans la corbeille ni les dictées à vérifier), tâches et
    /// rendez-vous marqués faits pendant la semaine, et ceux qui restent à faire.
    public func weekStats(from start: Date, to end: Date) throws -> WeekStats {
        try database.writer.read { db in
            let notReview = "source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)"
            let todo = [MemoryKind.task, MemoryKind.appointment]
            let notes = try Memory
                .filter(Column("captured_at") >= start && Column("captured_at") < end)
                .filter([MemoryStatus.active, MemoryStatus.unsorted, MemoryStatus.archived].contains(Column("status")))
                .filter(sql: notReview)
                .fetchCount(db)
            // Une tâche qui revient (P16) compte chaque fois qu'elle est faite.
            let done = try Memory
                .filter(Column("status") == MemoryStatus.archived && todo.contains(Column("kind")))
                .filter(Column("updated_at") >= start && Column("updated_at") < end)
                .fetchCount(db) + Self.repeatedCompletions(db, from: start, to: end)
            let open = try Memory
                .filter([MemoryStatus.active, MemoryStatus.unsorted].contains(Column("status")) && todo.contains(Column("kind")))
                .filter(sql: notReview)
                .fetchCount(db)
            return WeekStats(notes: notes, done: done, open: open)
        }
    }
}

extension MemoryStore {
    /// F16 — les dates dites d'une note, avec leur rôle, dans l'ordre de la dictée.
    public func temporalMentions(of memoryID: UUID) throws -> [TemporalMention] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT role, phrase FROM memory_temporal WHERE memory_id = ? ORDER BY position",
                             arguments: [memoryID])
                .compactMap { row in
                    TemporalRole(rawValue: row["role"]).map { TemporalMention(role: $0, phrase: row["phrase"]) }
                }
        }
    }
}
