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
    /// En dessous, une note ne ressemble pas assez pour voter.
    public static let minimumSimilarity = 0.55
    /// Seules les notes les plus proches votent.
    public static let neighborCount = 8
    /// Une note rangée par le propriétaire montre comment il aime classer : elle compte triple.
    public static let ownerWeight = 3.0

    public static func vote(_ neighbors: [FolderNeighbor], limit: Int = 3) -> [FolderEvidence] {
        let closest = neighbors
            .filter { $0.similarity >= minimumSimilarity && !$0.paths.isEmpty }
            .sorted { $0.similarity > $1.similarity }
            .prefix(neighborCount)
        var weights: [String: Double] = [:]
        var notes: [String: Int] = [:]
        var byOwner: [String: Int] = [:]
        var order: [String] = []
        for neighbor in closest {
            for path in neighbor.paths {
                if weights[path] == nil { order.append(path) }
                weights[path, default: 0] += neighbor.similarity * (neighbor.byOwner ? ownerWeight : 1)
                notes[path, default: 0] += 1
                if neighbor.byOwner { byOwner[path, default: 0] += 1 }
            }
        }
        return order.enumerated()
            .sorted { (weights[$0.element] ?? 0, -$0.offset) > (weights[$1.element] ?? 0, -$1.offset) }
            .prefix(limit)
            .map { FolderEvidence(path: $0.element, notes: notes[$0.element] ?? 0, byOwner: byOwner[$0.element] ?? 0) }
    }

    /// Pour Gemini : seulement les grands dossiers, additionnés, dans l'ordre du vote.
    public static func roots(_ evidence: [FolderEvidence]) -> [FolderEvidence] {
        var order: [String] = []
        var notes: [String: Int] = [:]
        var byOwner: [String: Int] = [:]
        for item in evidence {
            let root = item.path.components(separatedBy: "›").first?.trimmingCharacters(in: .whitespaces) ?? item.path
            guard !root.isEmpty else { continue }
            if notes[root] == nil { order.append(root) }
            notes[root, default: 0] += item.notes
            byOwner[root, default: 0] += item.byOwner
        }
        return order.map { FolderEvidence(path: $0, notes: notes[$0] ?? 0, byOwner: byOwner[$0] ?? 0) }
    }

    /// « Automobile › Corolla (2 notes, dont 1 rangée par le propriétaire) ; Finances (1 note) ».
    public static func describe(_ evidence: [FolderEvidence]) -> String {
        evidence.map { item in
            let count = item.notes == 1 ? "1 note" : "\(item.notes) notes"
            guard item.byOwner > 0 else { return "\(item.path) (\(count))" }
            let owner = item.byOwner == 1 ? "1 rangée" : "\(item.byOwner) rangées"
            return "\(item.path) (\(count), dont \(owner) par le propriétaire)"
        }.joined(separator: " ; ")
    }
}
