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
            let reason: String? = row["route_reason"]
            let level: String? = row["privacy_level"]
            let judgedSecret = level == PrivacyLevel.secret.rawValue
                && reason != RouteReasons.noCloudService && reason != RouteReasons.keepEverythingLocal
            let keepLocal: Bool = row["keep_local"] ?? false
            let kind: String? = row["kind"]
            let status: String = row["status"]
            return ReminderPlanner.Item(id: row["id"], title: row["title"], kind: kind.flatMap(MemoryKind.init(rawValue:)),
                                        status: MemoryStatus(rawValue: status) ?? .active, dueAt: row["due_at"],
                                        dueHasTime: row["due_has_time"] ?? false, isPrivate: keepLocal || judgedSecret)
        }
    }
}
