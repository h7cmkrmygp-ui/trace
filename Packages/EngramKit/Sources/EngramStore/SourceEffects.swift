import EngramCore
import Foundation
import GRDB

/// F20 — ce qu'une dictée a réellement produit dans la base : notes (type, échéance), ajouts à des listes, mesures,
/// envois en ligne. Sert à l'évaluation de bout en bout (rien n'est envoyé nulle part).
public struct SourceEffects: Sendable, Equatable {
    /// Les types des notes tirées de la dictée (ni listes, ni passages à classer), triés.
    public let noteKinds: [MemoryKind]
    /// Combien de ces notes ont une échéance.
    public let dueCount: Int
    /// Les ajouts à des listes faits par cette dictée : « clé de liste|clé de chose ».
    public let listAdds: Set<String>
    /// Des choses présentes deux fois dans une même liste après cette dictée.
    public let duplicatedItems: [String]
    /// Les mesures enregistrées depuis ces notes.
    public let measurements: Int
    /// Toutes les notes de la dictée, passages à classer compris (zéro avec aucun ajout : la dictée est perdue).
    public let anyNote: Int
    /// Les envois en ligne de cette dictée (reçus).
    public let transmissions: Int
}

extension MemoryStore {
    public func effects(of sourceID: UUID) throws -> SourceEffects {
        try database.writer.read { db in
            let listIDs = Set(try UUID.fetchAll(db, sql: "SELECT memory_id FROM memory_list"))
            let memories = try Memory
                .filter(Column("source_id") == sourceID && Column("status") != MemoryStatus.trashed.rawValue)
                .fetchAll(db)
            let notes = memories.filter {
                !listIDs.contains($0.id) && $0.analysisVersion == ThoughtFiler.analysisVersion
            }
            let adds = try Row.fetchAll(db, sql: """
                SELECT l.normalized_name AS list_key, i.item_key AS item_key FROM list_item_contribution c
                JOIN list_item i ON i.id = c.item_id JOIN memory_list l ON l.memory_id = i.list_memory_id
                WHERE c.source_id = ? AND c.kind = 'add'
                """, arguments: [sourceID])
            let duplicates = try String.fetchAll(db, sql: """
                SELECT l.normalized_name || '|' || i.item_key FROM list_item i
                JOIN memory_list l ON l.memory_id = i.list_memory_id
                WHERE i.removed_at IS NULL GROUP BY i.list_memory_id, i.item_key HAVING COUNT(*) > 1
                """)
            let ids = notes.map(\.id)
            let measurements = ids.isEmpty ? 0
                : try MetricMeasurement.filter(ids.contains(Column("memory_id"))).fetchCount(db)
            let transmissions = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM transmission_receipt WHERE source_id = ? AND status IN ('sending', 'succeeded')
                """, arguments: [sourceID]) ?? 0
            return SourceEffects(
                noteKinds: notes.map { $0.kind ?? .other }.sorted { $0.rawValue < $1.rawValue },
                dueCount: notes.filter { $0.dueAt != nil }.count,
                listAdds: Set(adds.map { ($0["list_key"] as String) + "|" + ($0["item_key"] as String) }),
                duplicatedItems: duplicates, measurements: measurements, anyNote: memories.count,
                transmissions: transmissions)
        }
    }
}
