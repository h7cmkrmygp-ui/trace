import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// P42, F23 — ce qui vient d'être dit, dans les 30 minutes avant cette dictée : les personnes de la dernière dictée
    /// classée qui en a nommé, les listes de la dernière qui en a complété, les dossiers de la dernière qui en a eu. Une
    /// dictée qui ne nomme rien n'interrompt pas le fil. nil s'il n'y a rien.
    public func recentContext(before sourceID: UUID) throws -> RecentContext? {
        try database.writer.read { db in
            guard let source = try Source.fetchOne(db, key: sourceID) else { return nil }
            let since = source.capturedAt.addingTimeInterval(-RecentContext.window)
            let previous = try Source
                .filter(Column("id") != sourceID && Column("processing_status") == ProcessingStatus.done.rawValue
                        && Column("captured_at") <= source.capturedAt && Column("captured_at") >= since)
                .order(Column("captured_at").desc)
                .limit(Self.recentDictations)
                .fetchAll(db)
            var merged: RecentContext?
            for dictation in previous {
                let minutes = Int((source.capturedAt.timeIntervalSince(dictation.capturedAt) / 60).rounded())
                guard let context = try Self.context(db, of: dictation, minutesAgo: minutes) else { continue }
                guard var current = merged else {
                    merged = context
                    continue
                }
                if current.people.isEmpty { current.people = context.people }
                if current.lists.isEmpty { current.lists = context.lists }
                if current.folders.isEmpty { current.folders = context.folders }
                merged = current
            }
            return merged
        }
    }

    /// F23 — les dictées lues au plus pour retrouver le fil.
    static let recentDictations = 10

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
        // F09 — les personnes nommées par ses ajouts à une liste qui appartient à une autre dictée.
        let named = try String.fetchAll(db, sql: """
            SELECT people FROM list_item_contribution WHERE source_id = ? AND kind = 'add' AND people != '' ORDER BY at, id
            """, arguments: [previous.id])
        for name in named.flatMap({ $0.components(separatedBy: "\n") }) where !context.people.contains(name) {
            context.people.append(name)
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
