import EngramCore
import Foundation
import GRDB

extension CategoryStore {
    /// F02 — pour chaque dossier actif (chemin complet), les destinations interdites par les notes qui y sont rangées
    /// (sous-dossiers compris). Un dossier créé par l'IA sans aucune note a une provenance inconnue : rien ne sort ; le nom
    /// d'un dossier créé par le propriétaire (ou d'origine) lui appartient.
    public func provenanceMasks() throws -> [String: Int] {
        try database.writer.read { db in
            let active = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
            let sourceMasks = try MemoryStore.sourceMasks(db)
            var direct: [UUID: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT mc.category_id AS category_id, m.source_id AS source_id
                FROM memory_category mc JOIN memory m ON m.id = mc.memory_id
                WHERE mc.rejected = 0 AND m.status <> 'trashed'
                """) {
                let category: UUID = row["category_id"]
                let source: UUID = row["source_id"]
                direct[category, default: 0] |= sourceMasks[source] ?? PrivacyPolicy.unknownMask
            }
            var children: [UUID: [UUID]] = [:]
            for category in active { if let parent = category.parentID { children[parent, default: []].append(category.id) } }
            // Le masque d'un dossier : ses notes et celles de ses sous-dossiers ; sans aucune note, selon qui l'a créé.
            func subtree(_ id: UUID, depth: Int) -> (mask: Int, hasNotes: Bool) {
                var mask = direct[id] ?? 0
                var hasNotes = direct[id] != nil
                if depth < 32 {
                    for child in children[id] ?? [] {
                        let below = subtree(child, depth: depth + 1)
                        mask |= below.mask
                        hasNotes = hasNotes || below.hasNotes
                    }
                }
                return (mask, hasNotes)
            }
            var masks: [String: Int] = [:]
            for category in active {
                let found = subtree(category.id, depth: 0)
                let mask = found.hasNotes ? found.mask : (category.origin == .ai ? PrivacyPolicy.unknownMask : 0)
                masks[CategoryPaths.display(CategoryPaths.components(of: category, in: byID))] = mask
            }
            return masks
        }
    }
}

extension ListStore {
    /// F02 — pour chaque liste (son nom, comme le donne `names()`), les destinations interdites par toutes ses
    /// contributions (jamais abaissées).
    public func provenanceMasks() throws -> [String: Int] {
        try database.writer.read { db in
            let sourceMasks = try MemoryStore.sourceMasks(db)
            var masks: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT l.name AS name, l.forbidden_mask AS forbidden_mask, m.source_id AS source_id
                FROM memory_list l JOIN memory m ON m.id = l.memory_id WHERE m.status <> 'trashed'
                """) {
                let name: String = row["name"]
                let stored: Int = row["forbidden_mask"]
                let source: UUID = row["source_id"]
                masks[name, default: 0] |= stored | (sourceMasks[source] ?? PrivacyPolicy.unknownMask)
            }
            return masks
        }
    }
}

extension MemoryStore {
    /// Les destinations interdites par chaque source.
    static func sourceMasks(_ db: Database) throws -> [UUID: Int] {
        var masks: [UUID: Int] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, keep_local, privacy_level, privacy_basis FROM source") {
            let id: UUID = row["id"]
            masks[id] = PrivacyPolicy.forbiddenMask(privacyFacts(row))
        }
        return masks
    }

    /// F02 — les destinations interdites par une source (inconnue : toutes).
    public func forbiddenMask(sourceID: UUID) throws -> Int {
        try database.writer.read { db in try ListStore.forbiddenMask(db, sourceID: sourceID) }
    }

    /// F13 — écrit ou complète un reçu d'envoi (même identifiant : l'envoi, puis son résultat).
    public func recordTransmission(_ event: TransmissionEvent) throws {
        let now = dates.now()
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO transmission_receipt (id, source_id, provider, status, detail, started_at, finished_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET status = excluded.status, detail = excluded.detail,
                  finished_at = excluded.finished_at
                """, arguments: [event.id, event.sourceID, event.provider, event.status.rawValue, event.detail, now,
                                 event.status == .sending ? nil : now])
        }
    }

    /// Les reçus d'envoi d'une source, du plus ancien au plus récent.
    public func transmissions(sourceID: UUID) throws -> [TransmissionEvent] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, source_id, provider, status, detail FROM transmission_receipt
                WHERE source_id = ? ORDER BY started_at
                """, arguments: [sourceID]).map { row in
                let status: String = row["status"]
                return TransmissionEvent(id: row["id"], sourceID: row["source_id"], provider: row["provider"],
                                         status: TransmissionEvent.Status(rawValue: status) ?? .failed, detail: row["detail"])
            }
        }
    }

    /// F02 — les destinations interdites par la dictée classée juste avant celle-ci (dans la fenêtre du contexte récent) ;
    /// sans dictée récente, toutes.
    public func recentProvenance(before sourceID: UUID) throws -> Int {
        try database.writer.read { db in
            guard let source = try Source.fetchOne(db, key: sourceID) else { return PrivacyPolicy.unknownMask }
            let since = source.capturedAt.addingTimeInterval(-RecentContext.window)
            guard let previous = try UUID.fetchOne(db, sql: """
                SELECT id FROM source WHERE id <> ? AND processing_status = 'done' AND captured_at <= ? AND captured_at >= ?
                ORDER BY captured_at DESC LIMIT 1
                """, arguments: [sourceID, source.capturedAt, since]) else { return PrivacyPolicy.unknownMask }
            return try ListStore.forbiddenMask(db, sourceID: previous)
        }
    }
}
