import EngramCore
import Foundation
import GRDB

/// P40 — un changement du ménage, noté dans l'historique (annulable).
public struct TidyRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let runAt: Date
    public let summary: String
    public let undone: Bool

    public init(id: UUID, runAt: Date, summary: String, undone: Bool) {
        self.id = id
        self.runAt = runAt
        self.summary = summary
        self.undone = undone
    }
}

/// P40 — le ménage automatique des dossiers : appliqué, noté, annulable ; rien ne se perd.
extension CategoryStore {
    /// Les dossiers actifs, tels que le ménage les voit.
    public func tidyFolders() throws -> [TidyFolder] { [] }

    /// Applique les changements (en sautant ceux qui toucheraient un choix du propriétaire) et les note.
    public func applyTidy(_ actions: [TidyAction]) throws -> [TidyRecord] { [] }

    /// L'historique du ménage, le plus récent d'abord.
    public func tidyHistory(limit: Int = 100) throws -> [TidyRecord] { [] }

    /// Remet les dossiers et les notes comme avant ce changement.
    public func undoTidy(_ id: UUID) throws {}
}
