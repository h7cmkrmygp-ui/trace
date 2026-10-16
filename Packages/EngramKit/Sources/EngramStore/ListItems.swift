import EngramCore
import Foundation
import GRDB

/// F09 — une chose d'une liste, avec la provenance de ses contributions.
public struct ListItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let done: Bool
    /// Les dictées qui l'ont ajoutée, cochée ou retirée, dans l'ordre (vide : aucune dictée connue).
    public let sources: [UUID]
    /// Le propriétaire l'a écrite, cochée ou changée à la main.
    public let touchedByOwner: Bool
    /// false : chose d'une liste d'avant le suivi des contributions, dont l'origine n'est pas connue (rien n'est inventé).
    public let provenanceKnown: Bool

    public init(id: UUID, text: String, done: Bool, sources: [UUID], touchedByOwner: Bool, provenanceKnown: Bool) {
        self.id = id
        self.text = text
        self.done = done
        self.sources = sources
        self.touchedByOwner = touchedByOwner
        self.provenanceKnown = provenanceKnown
    }
}

extension ListStore {
    /// F09 — ce qu'une contribution a fait à une chose.
    enum ContributionKind: String { case add, check, uncheck, remove, retract }

    /// Les choses présentes d'une liste, dans l'ordre de la note.
    public func items(of listMemoryID: UUID) throws -> [ListItem] {
        try database.writer.read { db in try Self.items(db, of: listMemoryID) }
    }

    static func items(_ db: Database, of listMemoryID: UUID) throws -> [ListItem] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, text, done, provenance_known FROM list_item
            WHERE list_memory_id = ? AND removed_at IS NULL ORDER BY position, created_at
            """, arguments: [listMemoryID])
        return try rows.map { row in
            let id: UUID = row["id"]
            let contributions = try Row.fetchAll(db, sql: """
                SELECT source_id, actor FROM list_item_contribution WHERE item_id = ? ORDER BY at, id
                """, arguments: [id])
            var sources: [UUID] = []
            for contribution in contributions {
                if let source: UUID = contribution["source_id"], !sources.contains(source) { sources.append(source) }
            }
            let owner = contributions.contains { ($0["actor"] as String?) == ChangeActor.user.rawValue }
            return ListItem(id: id, text: row["text"], done: row["done"], sources: sources, touchedByOwner: owner,
                            provenanceKnown: row["provenance_known"])
        }
    }

    /// F09 — rapproche les choses de la liste de son texte : une case nouvelle est ajoutée, une case cochée, décochée ou
    /// disparue est notée, chacune avec l'acteur réel (IA, propriétaire, Engram) et la dictée qui l'a demandé.
    static func syncItems(_ db: Database, listMemoryID: UUID, body: String, actor: ChangeActor, sourceID: UUID?,
                          people: [String] = [], now: Date) throws {
        let live = try Row.fetchAll(db, sql: """
            SELECT id, item_key, text, done, position FROM list_item
            WHERE list_memory_id = ? AND removed_at IS NULL ORDER BY position, created_at
            """, arguments: [listMemoryID])
        var matched = Set<UUID>()
        var position = 0
        for block in NoteBody.blocks(from: body) {
            guard case .check(let done) = block.kind else { continue }
            defer { position += 1 }
            let key = ListCommandParser.key(block.text)
            if let row = live.first(where: { !matched.contains($0["id"]) && ($0["item_key"] as String) == key }) {
                let id: UUID = row["id"]
                matched.insert(id)
                let wasDone: Bool = row["done"]
                if (row["position"] as Int) != position || (row["text"] as String) != block.text || wasDone != done {
                    try db.execute(sql: """
                        UPDATE list_item SET position = ?, text = ?, done = ?, updated_at = ? WHERE id = ?
                        """, arguments: [position, block.text, done, now, id])
                }
                if wasDone != done {
                    try contribute(db, itemID: id, kind: done ? .check : .uncheck, actor: actor, sourceID: sourceID, now: now)
                }
            } else {
                let id = UUID()
                try db.execute(sql: """
                    INSERT INTO list_item (id, list_memory_id, text, item_key, done, position, provenance_known, created_at,
                      updated_at) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
                    """, arguments: [id, listMemoryID, block.text, key, done, position, now, now])
                try contribute(db, itemID: id, kind: .add, actor: actor, sourceID: sourceID, people: people, now: now)
            }
        }
        for row in live where !matched.contains(row["id"]) {
            let id: UUID = row["id"]
            try db.execute(sql: "UPDATE list_item SET removed_at = ?, updated_at = ? WHERE id = ?", arguments: [now, now, id])
            try contribute(db, itemID: id, kind: .remove, actor: actor, sourceID: sourceID, now: now)
        }
    }

    /// F09 — une dictée a aussi demandé des choses déjà dans la liste : elle en devient une source.
    static func recordRequested(_ db: Database, listMemoryID: UUID, items: [String], sourceID: UUID, people: [String],
                                now: Date) throws {
        for item in items {
            let key = ListCommandParser.key(item)
            guard let id = try UUID.fetchOne(db, sql: """
                SELECT id FROM list_item WHERE list_memory_id = ? AND removed_at IS NULL AND item_key = ?
                ORDER BY position LIMIT 1
                """, arguments: [listMemoryID, key]) else { continue }
            let already = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM list_item_contribution WHERE item_id = ? AND source_id = ? AND kind = 'add')
                """, arguments: [id, sourceID]) ?? false
            if !already { try contribute(db, itemID: id, kind: .add, actor: .ai, sourceID: sourceID, people: people, now: now) }
        }
    }

    static func contribute(_ db: Database, itemID: UUID, kind: ContributionKind, actor: ChangeActor, sourceID: UUID?,
                           people: [String] = [], now: Date) throws {
        try db.execute(sql: """
            INSERT INTO list_item_contribution (item_id, source_id, actor, kind, people, at) VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [itemID, sourceID, actor.rawValue, kind.rawValue, people.joined(separator: "\n"), now])
    }

    /// Retire les choses que cette seule dictée a ajoutées et que personne n'a touchées depuis (ni le propriétaire, ni
    /// une autre dictée) ; rend leurs textes. Le retrait est une action d'Engram, gardée dans l'historique de la note.
    @discardableResult
    public func retract(sourceID: UUID) throws -> [String] {
        let now = dates.now()
        return try database.writer.write { db in try Self.retract(db, sourceID: sourceID, keeping: nil, now: now) }
    }

    /// - Parameter keeping: les choses que la nouvelle analyse de cette dictée redemande, par liste (clés) : elles restent.
    static func retract(_ db: Database, sourceID: UUID, keeping: [UUID: Set<String>]?, now: Date) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT i.id AS id, i.item_key AS item_key, i.list_memory_id AS list_id FROM list_item i
            JOIN list_item_contribution c ON c.item_id = i.id
            WHERE c.source_id = ? AND c.kind = 'add' AND i.removed_at IS NULL
            ORDER BY i.position
            """, arguments: [sourceID])
        var byList: [UUID: [(id: UUID, key: String)]] = [:]
        var order: [UUID] = []
        for row in rows {
            let id: UUID = row["id"]
            let listID: UUID = row["list_id"]
            let key: String = row["item_key"]
            if keeping?[listID]?.contains(key) == true { continue }
            let shared = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM list_item_contribution
                              WHERE item_id = ? AND (source_id IS NULL OR source_id != ? OR actor != 'ai'))
                """, arguments: [id, sourceID]) ?? true
            guard !shared else { continue }
            if byList[listID] == nil { order.append(listID) }
            byList[listID, default: []].append((id, key))
        }
        var retracted: [String] = []
        for listID in order {
            guard var memory = try Memory.fetchOne(db, key: listID), memory.status != .trashed,
                  let record = try ListRecord.filter(Column("memory_id") == listID).fetchOne(db) else { continue }
            var blocks = NoteBody.blocks(from: memory.summary ?? "")
            var removed: [String] = []
            for item in byList[listID] ?? [] {
                guard let index = blocks.firstIndex(where: { block in
                    if case .check = block.kind { return ListCommandParser.key(block.text) == item.key }
                    return false
                }) else { continue }
                let text = blocks[index].text
                removed.append(text)
                blocks.remove(at: index)
                try db.execute(sql: "UPDATE list_item SET removed_at = ?, updated_at = ? WHERE id = ?",
                               arguments: [now, now, item.id])
                try contribute(db, itemID: item.id, kind: .retract, actor: .system, sourceID: sourceID, now: now)
                // La même dictée pourra le redemander plus tard (F08 : l'opération n'est plus « faite »).
                try db.execute(sql: "DELETE FROM list_operation WHERE op_key = ?",
                               arguments: [operationKey(.add, item: text, listKey: record.normalizedName, sourceID: sourceID)])
            }
            guard !removed.isEmpty else { continue }
            memory.summary = NoteBody.text(from: blocks)
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: .system,
                              reason: "retiré : ajout annulé (\(removed.joined(separator: ", ")))", at: now).insert(db)
            retracted += removed
        }
        return retracted
    }

    /// F09 (migration v21) — les cases des listes existantes deviennent des choses ; une opération notée (F08) donne sa
    /// dictée, sinon la provenance reste inconnue (rien n'est inventé).
    static func backfillItems(_ db: Database) throws {
        let lists = try Row.fetchAll(db, sql: """
            SELECT l.normalized_name AS list_key, m.id AS id, m.summary AS summary, m.updated_at AS at
            FROM memory_list l JOIN memory m ON m.id = l.memory_id
            """)
        for list in lists {
            let listID: UUID = list["id"]
            let listKey: String = list["list_key"]
            let at: Date = list["at"]
            let summary: String? = list["summary"]
            let operations = try Row.fetchAll(db, sql: """
                SELECT source_id, item, applied_at FROM list_operation WHERE list_key = ? AND kind = 'add'
                ORDER BY applied_at
                """, arguments: [listKey])
            var position = 0
            for block in NoteBody.blocks(from: summary ?? "") {
                guard case .check(let done) = block.kind else { continue }
                let key = ListCommandParser.key(block.text)
                let known = operations.filter { ListCommandParser.key($0["item"]) == key }
                let id = UUID()
                try db.execute(sql: """
                    INSERT INTO list_item (id, list_memory_id, text, item_key, done, position, provenance_known, created_at,
                      updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [id, listID, block.text, key, done, position, !known.isEmpty, at, at])
                for operation in known {
                    try db.execute(sql: """
                        INSERT INTO list_item_contribution (item_id, source_id, actor, kind, people, at)
                        VALUES (?, ?, 'ai', 'add', '', ?)
                        """, arguments: [id, operation["source_id"] as UUID, operation["applied_at"] as Date])
                }
                position += 1
            }
        }
    }
}
