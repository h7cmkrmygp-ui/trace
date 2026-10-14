import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// P42 — la dictée classée juste avant celle-ci, il y a moins de 30 minutes : ses personnes, ses listes et ses
    /// dossiers. nil s'il n'y en a pas, ou si elle ne nomme rien.
    public func recentContext(before sourceID: UUID) throws -> RecentContext? {
        try database.writer.read { db in
            guard let source = try Source.fetchOne(db, key: sourceID) else { return nil }
            let since = source.capturedAt.addingTimeInterval(-RecentContext.window)
            guard let previous = try Source
                .filter(Column("id") != sourceID && Column("processing_status") == ProcessingStatus.done.rawValue
                        && Column("captured_at") <= source.capturedAt && Column("captured_at") >= since)
                .order(Column("captured_at").desc)
                .fetchOne(db) else { return nil }
            return try Self.context(db, of: previous,
                                    minutesAgo: Int((source.capturedAt.timeIntervalSince(previous.capturedAt) / 60).rounded()))
        }
    }

    /// Les personnes, les listes et les dossiers d'une dictée classée ; nil si elle ne nomme rien.
    static func context(_ db: Database, of previous: Source, minutesAgo: Int) throws -> RecentContext? {
        let memories = try Memory
            .filter(Column("source_id") == previous.id && Column("status") != MemoryStatus.trashed.rawValue)
            .order(Column("created_at"))
            .fetchAll(db)
        let listMemoryIDs = Set(try UUID.fetchAll(db, sql: "SELECT memory_id FROM memory_list"))

        var context = RecentContext(minutesAgo: minutesAgo)
        // Les personnes de toutes ses notes (une liste de cadeaux pour quelqu'un compte aussi).
        for memory in memories {
            for entity in try EntityStore.entities(db, for: memory.id)
            where entity.kind == .person && !context.people.contains(entity.name) {
                context.people.append(entity.name)
            }
        }
        // Les listes complétées par cette dictée (une clé « liste | passage » vient d'un passage compris par l'IA).
        let keys = try String.fetchAll(db, sql: """
            SELECT normalized_name FROM memory_list_addition WHERE source_id = ? ORDER BY added_at
            """, arguments: [previous.id])
        for key in keys {
            let listKey = key.components(separatedBy: " | ")[0]
            guard let record = try ListRecord.fetchOne(db, key: listKey),
                  let list = try Memory.fetchOne(db, key: record.memoryID), list.status != .trashed,
                  !context.lists.contains(record.name) else { continue }
            context.lists.append(record.name)
        }
        // Les dossiers de ses notes (pas celui des listes : une liste n'est pas un projet).
        let active = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        for memory in memories where !listMemoryIDs.contains(memory.id) {
            let categoryIDs = try UUID.fetchAll(db, sql: """
                SELECT category_id FROM memory_category WHERE memory_id = ? AND rejected = 0
                """, arguments: [memory.id])
            for id in categoryIDs {
                guard let category = byID[id] else { continue }
                let path = CategoryPaths.display(CategoryPaths.components(of: category, in: byID))
                if !context.folders.contains(path) { context.folders.append(path) }
            }
        }
        return context.isEmpty ? nil : context
    }
}
