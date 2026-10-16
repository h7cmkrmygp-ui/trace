import EngramCore
import Foundation
import GRDB

/// F09 — une chose d'une liste, avec la provenance de ses contributions.
public struct ListItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let done: Bool
    /// Les dictées qui l'ont ajoutée, cochée ou retirée, dans l'ordre (vide : aucune dictée connue).
    public let sources: [UUID]
    /// Le propriétaire l'a écrite, cochée ou changée à la main.
    public let touchedByOwner: Bool
    /// false : chose d'une liste d'avant le suivi des contributions, dont l'origine n'est pas connue (rien n'est inventé).
    public let provenanceKnown: Bool

    public init(id: UUID, text: String, done: Bool, sources: [UUID], touchedByOwner: Bool, provenanceKnown: Bool) {
        self.id = id
        self.text = text
        self.done = done
        self.sources = sources
        self.touchedByOwner = touchedByOwner
        self.provenanceKnown = provenanceKnown
    }
}

extension ListStore {
    /// Les choses présentes d'une liste, dans l'ordre de la note.
    public func items(of listMemoryID: UUID) throws -> [ListItem] {
        try database.writer.read { db in try Self.items(db, of: listMemoryID) }
    }

    static func items(_ db: Database, of listMemoryID: UUID) throws -> [ListItem] { [] }

    /// Retire les choses que cette seule dictée a ajoutées et que personne n'a touchées depuis ; rend leurs textes.
    @discardableResult
    public func retract(sourceID: UUID) throws -> [String] { [] }
}
