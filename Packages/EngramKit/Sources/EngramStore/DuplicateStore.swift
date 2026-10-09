import EngramCore
import Foundation
import GRDB

/// Deux notes qui se ressemblent, pour « Doublons possibles ».
public struct DuplicatePair: Sendable, Equatable, Identifiable {
    public let keep: Memory
    public let duplicate: Memory
    public let score: Double
    public var id: String { DuplicateFinder.key(keep.id, duplicate.id) }
}

/// P23 — les doublons possibles : proposés, réunis sans rien perdre (le doublon va à la corbeille), ou écartés.
extension MemoryStore {
    /// Les notes vivantes des 90 derniers jours (400 au plus, sans les listes) qui se ressemblent.
    public func duplicatePairs() throws -> [DuplicatePair] {
        let since = dates.now().addingTimeInterval(-90 * 86_400)
        return try database.writer.read { db in
            let notes = try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m
                WHERE m.status IN ('active','unsorted') AND m.captured_at >= ?
                  AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
                  AND m.id NOT IN (SELECT memory_id FROM memory_list)
                ORDER BY m.captured_at DESC LIMIT 400
                """, arguments: [since])
            let dismissed = Set(try Row.fetchAll(db, sql: "SELECT first_id, second_id FROM duplicate_dismissal").map { row in
                DuplicateFinder.key(row["first_id"], row["second_id"])
            })
            let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
            let candidates = notes.map {
                DuplicateFinder.Note(id: $0.id, text: $0.title + " " + $0.content, kind: $0.kind, capturedAt: $0.capturedAt)
            }
            return DuplicateFinder.pairs(candidates, dismissed: dismissed).compactMap { pair in
                guard let keep = byID[pair.keep], let duplicate = byID[pair.duplicate] else { return nil }
                return DuplicatePair(keep: keep, duplicate: duplicate, score: pair.score)
            }
        }
    }

    /// Réunit le doublon dans la note gardée : son texte s'ajoute s'il dit quelque chose de plus ; ses dossiers, tags,
    /// personnes et lieux, son épingle, son rappel de lieu et son rythme passent à la note gardée (si elle n'en a pas).
    /// Le doublon va à la corbeille, d'où il se récupère.
    public func mergeDuplicate(_ duplicateID: UUID, into keepID: UUID) throws {
        guard duplicateID != keepID else { throw StoreError.invalidOperation("Une note ne se réunit pas avec elle-même.") }
        let now = dates.now()
        try database.writer.write { db in
            guard var keep = try Memory.fetchOne(db, key: keepID), let duplicate = try Memory.fetchOne(db, key: duplicateID) else {
                throw StoreError.notFound
            }
            let moves: [(String, StatementArguments)] = [
                ("""
                 INSERT OR IGNORE INTO memory_category (memory_id, category_id, origin, confidence, confirmed, rejected, created_at, updated_at)
                 SELECT ?, category_id, 'user', NULL, 1, 0, ?, ? FROM memory_category WHERE memory_id = ? AND rejected = 0
                 """, [keepID, now, now, duplicateID]),
                ("""
                 INSERT OR IGNORE INTO memory_tag (memory_id, tag_id, origin, confidence, confirmed, rejected, created_at, updated_at)
                 SELECT ?, tag_id, 'user', NULL, 1, 0, ?, ? FROM memory_tag WHERE memory_id = ? AND rejected = 0
                 """, [keepID, now, now, duplicateID]),
                ("""
                 INSERT OR IGNORE INTO memory_entity (memory_id, entity_id, origin, confirmed, rejected, created_at, updated_at)
                 SELECT ?, entity_id, 'user', 1, 0, ?, ? FROM memory_entity WHERE memory_id = ? AND rejected = 0
                 """, [keepID, now, now, duplicateID]),
                ("INSERT OR IGNORE INTO memory_pin (memory_id, pinned_at) SELECT ?, pinned_at FROM memory_pin WHERE memory_id = ?",
                 [keepID, duplicateID]),
                ("""
                 INSERT OR IGNORE INTO place_trigger (memory_id, entity_id, event, origin, created_at)
                 SELECT ?, entity_id, event, origin, created_at FROM place_trigger WHERE memory_id = ?
                 """, [keepID, duplicateID]),
                ("""
                 INSERT OR IGNORE INTO memory_recurrence (memory_id, rule, anchor_at, done_count, last_done_at, created_at)
                 SELECT ?, rule, anchor_at, done_count, last_done_at, created_at FROM memory_recurrence WHERE memory_id = ?
                 """, [keepID, duplicateID]),
            ]
            for (sql, arguments) in moves { try db.execute(sql: sql, arguments: arguments) }

            let merged = DuplicateFinder.mergedBody(keep: keep.summary ?? "", duplicate: duplicate.summary ?? "")
            if !merged.isEmpty { keep.summary = merged }
            if keep.dueAt == nil, let due = duplicate.dueAt {
                keep.dueAt = due
                keep.dueHasTime = duplicate.dueHasTime
            }
            // Une note « À classer » qui reçoit un dossier est classée.
            let filed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory_category WHERE memory_id = ? AND rejected = 0",
                                         arguments: [keepID]) ?? 0
            if keep.status == .unsorted && filed > 0 { keep.status = .active }
            keep.userEdited = true
            keep.version += 1
            keep.updatedAt = now
            try keep.update(db)
            try MemoryVersion(memory: keep, changedBy: .user, reason: "réunie avec « \(duplicate.title) »", at: now).insert(db)
            _ = try setStatus(db, .trashed, for: duplicateID, actor: .user, now: now)
            try Self.dismiss(db, keepID, duplicateID, now: now)
        }
    }

    /// « Ce n'est pas un doublon » : la paire n'est plus proposée.
    public func dismissDuplicate(_ first: UUID, _ second: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in try Self.dismiss(db, first, second, now: now) }
    }

    static func dismiss(_ db: Database, _ first: UUID, _ second: UUID, now: Date) throws {
        let ordered = [first, second].sorted { $0.uuidString < $1.uuidString }
        try db.execute(sql: "INSERT OR IGNORE INTO duplicate_dismissal (first_id, second_id, dismissed_at) VALUES (?, ?, ?)",
                       arguments: [ordered[0], ordered[1], now])
    }
}
