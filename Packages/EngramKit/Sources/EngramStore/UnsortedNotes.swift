import EngramCore
import Foundation
import GRDB

/// P35 — moins de « À classer » : pourquoi une note y est, et le ménage unique des anciennes copies et des anciens échecs.
extension MemoryStore {
    /// Pourquoi cette note est « À classer », en une phrase pour le propriétaire ; nil si elle est rangée.
    public func unsortedReason(for memoryID: UUID) throws -> String? {
        nil
    }

    /// Une seule fois : les anciennes copies de toute une dictée, déjà rangée en morceaux, vont à la corbeille
    /// (récupérables) si rien ne manque ailleurs, sinon ne gardent que la partie qui n'est nulle part ailleurs.
    /// Renvoie le nombre de copies traitées.
    public func cleanUpWholeNoteCopies() throws -> Int {
        0
    }

    /// Une seule fois : les anciennes notes jamais classées (échecs d'avant P35) sont proposées à un nouvel essai.
    public func retryOldFailures() throws -> Int {
        0
    }
}
