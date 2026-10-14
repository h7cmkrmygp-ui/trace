import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// P42 — la dictée classée juste avant celle-ci, il y a moins de 30 minutes : ses personnes, ses listes et ses
    /// dossiers. nil s'il n'y en a pas, ou si elle ne nomme rien.
    public func recentContext(before sourceID: UUID) throws -> RecentContext? {
        nil
    }
}
