import Foundation

/// P40 — un dossier tel que le ménage le voit.
public struct TidyFolder: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let parentID: UUID?
    /// Créé ou nommé par le propriétaire : jamais fusionné dans un autre, jamais renommé, jamais replié.
    public let createdByOwner: Bool
    /// Notes du dossier (sous-dossiers compris).
    public let noteCount: Int
    public let createdAt: Date
    /// Une note y a été rangée ou confirmée par le propriétaire.
    public let hasOwnerNotes: Bool
    public let hasChildren: Bool

    public init(id: UUID, name: String, parentID: UUID?, createdByOwner: Bool, noteCount: Int, createdAt: Date,
                hasOwnerNotes: Bool, hasChildren: Bool) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdByOwner = createdByOwner
        self.noteCount = noteCount
        self.createdAt = createdAt
        self.hasOwnerNotes = hasOwnerNotes
        self.hasChildren = hasChildren
    }
}

/// P40 — une note rangée par l'IA, avec ses dossiers et le vote de ses notes semblables (sans elle).
public struct TidyNote: Sendable, Equatable {
    public let id: UUID
    public let paths: [String]
    public let evidence: [FolderEvidence]

    public init(id: UUID, paths: [String], evidence: [FolderEvidence]) {
        self.id = id
        self.paths = paths
        self.evidence = evidence
    }
}

/// P40 — un changement du ménage.
public enum TidyAction: Sendable, Equatable {
    case merge(source: UUID, into: UUID)
    case rename(folder: UUID, to: String)
    case fold(folder: UUID, into: UUID)
    case move(memory: UUID, from: String, to: String)
}

/// P40 — le ménage automatique : il décide, sans toucher à rien ; le magasin applique et note chaque changement.
public enum TidyPlanner {
    public static func merges(_ folders: [TidyFolder]) -> [TidyAction] { [] }
    public static func renames(_ folders: [TidyFolder]) -> [TidyAction] { [] }
    public static func folds(_ folders: [TidyFolder], now: Date) -> [TidyAction] { [] }
    public static func moves(_ notes: [TidyNote]) -> [TidyAction] { [] }

    public static func summary(merged source: String, into target: String, notes: Int) -> String { "" }
    public static func summary(renamed old: String, to new: String) -> String { "" }
    public static func summary(folded folder: String, into parent: String, notes: Int) -> String { "" }
    public static func summary(moved title: String, from: String, to: String) -> String { "" }
}
