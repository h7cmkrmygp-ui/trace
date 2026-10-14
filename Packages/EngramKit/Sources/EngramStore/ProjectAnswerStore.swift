import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// P45 — ce que disait la dernière dictée classée, quelle que soit l'heure (pour « ce projet » dans Retrouver).
    public func latestContext() throws -> RecentContext? {
        nil
    }
}

extension CategoryStore {
    /// P45 — « Qu'est-ce que j'avais prévu pour le chalet ? » : ce qui reste à faire dans ce dossier (et ses sous-dossiers),
    /// puis ce qui y est noté ; nil si la question porte sur autre chose ou si le dossier est vide.
    public func projectAnswer(to question: String, recent: RecentContext?) throws -> String? {
        nil
    }
}
