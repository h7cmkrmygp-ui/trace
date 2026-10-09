import EngramCore
import Foundation
import GRDB

public struct SearchFilters: Sendable, Equatable {
    /// Catégorie, sous-catégories comprises.
    public var categoryID: UUID?
    public var tagID: UUID?
    public var kinds: Set<MemoryKind>
    public var includeArchived: Bool
    public var capturedFrom: Date?
    public var capturedTo: Date?

    public init(categoryID: UUID? = nil, tagID: UUID? = nil, kinds: Set<MemoryKind> = [],
                includeArchived: Bool = false, capturedFrom: Date? = nil, capturedTo: Date? = nil) {
        self.categoryID = categoryID
        self.tagID = tagID
        self.kinds = kinds
        self.includeArchived = includeArchived
        self.capturedFrom = capturedFrom
        self.capturedTo = capturedTo
    }
}

public struct TextSearchHit: Sendable, Equatable {
    public let memoryID: UUID
    /// Score bm25 : plus il est petit (négatif), plus le résultat est pertinent.
    public let rank: Double
}

/// Transforme une saisie libre en requête FTS5 sûre.
public enum FTSQuery {
    /// Chaque mot devient un préfixe entre guillemets (jamais un opérateur), et tous les mots sont requis.
    /// Les mots d'une seule lettre (« l' », « a ») sont ignorés s'il y a d'autres mots.
    public static func make(from userInput: String) -> String? {
        let words = userInput
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let meaningful = words.filter { $0.count >= 2 }
        let kept = meaningful.isEmpty ? words : meaningful
        guard !kept.isEmpty else { return nil }
        return kept.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}

extension MemoryStore {
    /// Recherche par mots dans les souvenirs actifs et « À classer » (et archivés sur demande). La corbeille est exclue,
    /// comme les dictées qui attendent « Vérifie ta note » (elles n'apparaissent que dans « À vérifier »).
    public func searchText(_ input: String, filters: SearchFilters = SearchFilters(), limit: Int = 50) throws -> [TextSearchHit] {
        guard let match = FTSQuery.make(from: input) else { return [] }
        var statuses: [MemoryStatus] = [.active, .unsorted]
        if filters.includeArchived { statuses.append(.archived) }

        var sql = """
            SELECT m.id AS memory_id, bm25(memory_fts, 10.0, 4.0, 1.0, 2.0) AS rank
            FROM memory_fts
            JOIN memory_fts_map map ON map.fts_rowid = memory_fts.rowid
            JOIN memory m ON m.id = map.memory_id
            WHERE memory_fts MATCH ?
              AND m.status IN (\(Self.placeholders(statuses.count)))
              AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
            """
        var values: [(any DatabaseValueConvertible)?] = [match]
        values += statuses.map { $0 as (any DatabaseValueConvertible)? }

        if !filters.kinds.isEmpty {
            let kinds = filters.kinds.sorted { $0.rawValue < $1.rawValue }
            sql += "\n  AND m.kind IN (\(Self.placeholders(kinds.count)))"
            values += kinds.map { $0 as (any DatabaseValueConvertible)? }
        }
        if let from = filters.capturedFrom {
            sql += "\n  AND m.captured_at >= ?"
            values.append(from)
        }
        if let to = filters.capturedTo {
            sql += "\n  AND m.captured_at <= ?"
            values.append(to)
        }
        if let categoryID = filters.categoryID {
            sql += """

                  AND m.id IN (
                    SELECT mc.memory_id FROM memory_category mc
                    WHERE mc.rejected = 0 AND mc.category_id IN (
                      WITH RECURSIVE tree(id) AS (
                        SELECT ? UNION ALL
                        SELECT c.id FROM category c JOIN tree ON c.parent_id = tree.id WHERE c.status = 'active'
                      ) SELECT id FROM tree))
                """
            values.append(categoryID)
        }
        if let tagID = filters.tagID {
            sql += "\n  AND m.id IN (SELECT memory_id FROM memory_tag WHERE rejected = 0 AND tag_id = ?)"
            values.append(tagID)
        }
        sql += "\nORDER BY rank LIMIT ?"
        values.append(limit)

        let arguments = StatementArguments(values)
        return try database.writer.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                TextSearchHit(memoryID: row["memory_id"], rank: row["rank"])
            }
        }
    }

    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}

extension MemoryStore {
    /// Ce que « Retrouver » peut lire : les notes actives, « À classer » et archivées (« Fait »), avec leurs dossiers et
    /// étiquettes. Jamais la corbeille ni les dictées qui attendent « Vérifie ta note ». Rien ne quitte l'iPhone.
    public func recallDocuments(limit: Int = 5_000) throws -> [RecallDocument] {
        try database.writer.read { db in
            let memories = try Memory
                .filter([MemoryStatus.active, MemoryStatus.unsorted, MemoryStatus.archived].contains(Column("status")))
                .filter(sql: "source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)")
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
            let categories = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            var paths: [UUID: [String]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT memory_id, category_id FROM memory_category WHERE rejected = 0") {
                let categoryID: UUID = row["category_id"]
                guard let category = byID[categoryID] else { continue }
                let memoryID: UUID = row["memory_id"]
                paths[memoryID, default: []].append(CategoryPaths.display(CategoryPaths.components(of: category, in: byID)))
            }
            var tags: [UUID: [String]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT mt.memory_id AS memory_id, t.name AS name FROM memory_tag mt
                JOIN tag t ON t.id = mt.tag_id WHERE mt.rejected = 0
                """) {
                let memoryID: UUID = row["memory_id"]
                tags[memoryID, default: []].append(row["name"])
            }
            // Privées : « Garder sur l'iPhone », ou jugées secrètes (être classée sur l'iPhone faute de service ne compte pas).
            let privateSources = Set(try UUID.fetchAll(db, sql: """
                SELECT id FROM source
                WHERE keep_local = 1
                   OR (privacy_level = ? AND (route_reason IS NULL OR route_reason NOT IN (?, ?)))
                """, arguments: [PrivacyLevel.secret.rawValue, RouteReasons.noCloudService, RouteReasons.keepEverythingLocal]))
            return memories.map { memory in
                RecallDocument(id: memory.id, title: memory.title,
                               text: [memory.content, memory.summary].compactMap { $0 }.joined(separator: " "),
                               kind: memory.kind, status: memory.status, capturedAt: memory.capturedAt, dueAt: memory.dueAt,
                               categories: (paths[memory.id] ?? []).sorted(), tags: (tags[memory.id] ?? []).sorted(),
                               isPrivate: privateSources.contains(memory.sourceID))
            }
        }
    }
}
