import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// P45 — ce que disait la dernière dictée classée, quelle que soit l'heure (pour « ce projet » dans Retrouver).
    public func latestContext() throws -> RecentContext? {
        try database.writer.read { db in
            guard let latest = try Source.filter(Column("processing_status") == ProcessingStatus.done.rawValue)
                .order(Column("captured_at").desc).fetchOne(db) else { return nil }
            return try Self.context(db, of: latest, minutesAgo: 0)
        }
    }
}

extension CategoryStore {
    /// P45 — « Qu'est-ce que j'avais prévu pour le chalet ? » : ce qui reste à faire dans ce dossier (et ses sous-dossiers),
    /// puis ce qui y est noté ; nil si la question porte sur autre chose ou si le dossier est vide.
    public func projectAnswer(to question: String, recent: RecentContext?) throws -> String? {
        try database.writer.read { db in
            let active = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
            let pathByID = byID.mapValues { CategoryPaths.display(CategoryPaths.components(of: $0, in: byID)) }
            guard let folder = ProjectQuestion.folder(in: question, among: Array(pathByID.values), recent: recent),
                  let id = pathByID.first(where: { $0.value == folder })?.key else { return nil }
            // Les notes vivantes du dossier et de ses sous-dossiers, de la plus ancienne à la plus récente ; pas les listes.
            let ids = try descendantIDs(db, of: id)
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let memories = try Memory.fetchAll(db, sql: """
                SELECT DISTINCT m.* FROM memory m JOIN memory_category mc ON mc.memory_id = m.id
                WHERE mc.category_id IN (\(placeholders)) AND mc.rejected = 0 AND m.status IN ('active','unsorted')
                  AND m.id NOT IN (SELECT memory_id FROM memory_list)
                ORDER BY m.captured_at
                """, arguments: StatementArguments(ids))
            guard !memories.isEmpty else { return nil }
            let open = memories.filter { $0.kind == .task || $0.kind == .appointment }.map(\.title)
            let notes = memories.filter { $0.kind != .task && $0.kind != .appointment }.map(\.title)
            return ProjectQuestion.answer(folder: folder, open: open, notes: notes)
        }
    }
}
