import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// F19 — enregistre chaque partage en attente (identifiant d'import stable), puis l'acquitte ; l'analyse vient après,
    /// indépendamment. Un rejeu ne crée pas de doublon, une erreur de stockage laisse l'élément dans la boîte.
    public func importShares(from inbox: SharedInbox) -> ShareImportReport {
        SharedImporter.run(inbox) { share in
            let text = share.item.noteText
            // Un élément vide n'a rien à garder : il peut quitter la boîte.
            guard !text.isEmpty else { return .duplicate }
            switch try saveTextNoteWithoutAnalysis(text, keepLocal: false, importID: share.id) {
            case .saved: return .saved
            case .duplicate: return .duplicate
            }
        }
    }
}
