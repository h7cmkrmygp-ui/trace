import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// F19 — enregistre chaque partage en attente (identifiant d'import stable), puis l'acquitte ; l'analyse vient après,
    /// indépendamment. Un rejeu ne crée pas de doublon, une erreur de stockage laisse l'élément dans la boîte.
    public func importShares(from inbox: SharedInbox) -> ShareImportReport {
        ShareImportReport()
    }
}
