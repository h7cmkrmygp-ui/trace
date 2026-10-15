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
                   s.route_reason AS route_reason
            FROM memory m JOIN source s ON s.id = m.source_id
            WHERE m.due_at IS NOT NULL AND m.status IN ('active', 'unsorted') AND m.kind IN ('task', 'appointment')
              AND s.needs_review = 0
            """)
        return rows.map { row in
            let kind: String? = row["kind"]
            let status: String = row["status"]
            return ReminderPlanner.Item(id: row["id"], title: row["title"], kind: kind.flatMap(MemoryKind.init(rawValue:)),
                                        status: MemoryStatus(rawValue: status) ?? .active, dueAt: row["due_at"],
                                        dueHasTime: row["due_has_time"] ?? false, isPrivate: isPrivate(row))
        }
    }

    /// Lit `keep_local`, `privacy_level` et `route_reason` de la source (voir `reminderItems`). Aussi pour les rappels de lieu.
    static func isPrivate(_ row: Row) -> Bool {
        let reason: String? = row["route_reason"]
        let level: String? = row["privacy_level"]
        let judgedSecret = level == PrivacyLevel.secret.rawValue
            && reason != RouteReasons.noCloudService && reason != RouteReasons.keepEverythingLocal
        let keepLocal: Bool = row["keep_local"] ?? false
        return keepLocal || judgedSecret
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
