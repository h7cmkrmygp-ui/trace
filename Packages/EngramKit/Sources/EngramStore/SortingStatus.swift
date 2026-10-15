import EngramCore
import Foundation
import GRDB

/// Règle « À classer » : un souvenir actif sans catégorie valable repasse « À classer »,
/// un souvenir « À classer » qui reçoit une catégorie devient actif.
/// Ces passages automatiques ne créent pas de version (ils restent tracés dans `change_log`).
enum SortingStatus {
    static func hasValidCategory(_ db: Database, memoryID: UUID) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS(
              SELECT 1 FROM memory_category mc JOIN category c ON c.id = mc.category_id
              WHERE mc.memory_id = ? AND mc.rejected = 0 AND c.status = 'active')
            """, arguments: [memoryID]) ?? false
    }

    static func refresh(_ db: Database, memoryID: UUID, now: Date) throws {
        let target: MemoryStatus = try hasValidCategory(db, memoryID: memoryID) ? .active : .unsorted
        try db.execute(sql: """
            UPDATE memory SET status = ?, updated_at = ?
            WHERE id = ? AND status IN ('active','unsorted') AND status <> ?
            """, arguments: [target, now, memoryID, target])
    }
}
