import Foundation

/// P34 — une note déjà rangée, telle que l'iPhone la compare à une nouvelle note (rien de cela ne quitte l'iPhone).
public struct FilingSample: Sendable, Equatable {
    public let id: UUID
    /// Titre et texte de la note.
    public let text: String
    /// Ses dossiers (« Automobile › Corolla »).
    public let paths: [String]
    /// Rangée ou confirmée par le propriétaire lui-même.
    public let byOwner: Bool

    public init(id: UUID, text: String, paths: [String], byOwner: Bool) {
        self.id = id
        self.text = text
        self.paths = paths
        self.byOwner = byOwner
    }
}

/// Une note semblable à la nouvelle : ses dossiers et sa ressemblance (cosinus, −1 à 1).
public struct FolderNeighbor: Sendable, Equatable {
    public let paths: [String]
    public let similarity: Double
    public let byOwner: Bool

    public init(paths: [String], similarity: Double, byOwner: Bool) {
        self.paths = paths
        self.similarity = similarity
        self.byOwner = byOwner
    }
}

/// Un dossier où sont rangées des notes semblables : combien, dont combien par le propriétaire.
public struct FolderEvidence: Sendable, Equatable, Hashable {
    public let path: String
    public let notes: Int
    public let byOwner: Int

    public init(path: String, notes: Int, byOwner: Int) {
        self.path = path
        self.notes = notes
        self.byOwner = byOwner
    }
}

/// Où sont rangées les notes semblables à un texte (calculé sur l'iPhone).
public protocol FolderEvidenceSource: Sendable {
    func evidence(for text: String) async -> [FolderEvidence]
}

/// Le vote des notes semblables : les plus proches seulement, celles du propriétaire comptent triple.
public enum SimilarFolders {
    public static func vote(_ neighbors: [FolderNeighbor], limit: Int = 3) -> [FolderEvidence] {
        []
    }

    /// Pour Gemini : seulement les grands dossiers, additionnés.
    public static func roots(_ evidence: [FolderEvidence]) -> [FolderEvidence] {
        evidence
    }

    /// « Automobile › Corolla (2 notes, dont 1 rangée par le propriétaire) ; Finances (1 note) ».
    public static func describe(_ evidence: [FolderEvidence]) -> String {
        ""
    }
}
