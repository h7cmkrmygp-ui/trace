import EngramCore
import Foundation
import GRDB

/// P33 — les fêtes ont leur dossier : « Anniversaires », ou celui que le propriétaire a déjà (« Fêtes »…).
extension CategoryStore {
    /// Une seule fois : les anciennes notes qui disent seulement une fête vont dans le dossier des fêtes, comme des choses
    /// à retenir (sans échéance ni « À faire »). Une note que le propriétaire a modifiée ou rangée lui-même n'est jamais
    /// touchée. Renvoie le nombre de notes rangées.
    public func refileBirthdayNotes() throws -> Int {
        0
    }
}
