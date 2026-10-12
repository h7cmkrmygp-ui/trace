import EngramCore
import Foundation

/// P34 — trouve, **sur l'iPhone**, les notes déjà rangées qui ressemblent le plus à une nouvelle note (par le sens), et
/// où elles sont rangées. Seuls les noms des dossiers sortent de ce calcul ; les notes elles-mêmes restent sur l'iPhone.
public final class SimilarNotesEvidence: FolderEvidenceSource, @unchecked Sendable {
    let embedder: any SentenceEmbedder
    let samples: @Sendable () throws -> [FilingSample]
    private let lock = NSLock()
    /// Vecteurs déjà calculés (recalculés si le texte de la note change).
    private var vectors: [UUID: (text: String, vector: [Double]?)] = [:]

    public init(embedder: any SentenceEmbedder, samples: @escaping @Sendable () throws -> [FilingSample]) {
        self.embedder = embedder
        self.samples = samples
    }

    public func evidence(for text: String) async -> [FolderEvidence] {
        guard let target = embedder.vector(for: text), let notes = try? samples(), !notes.isEmpty else { return [] }
        let neighbors = notes.compactMap { sample -> FolderNeighbor? in
            guard let vector = vector(for: sample) else { return nil }
            return FolderNeighbor(paths: sample.paths, similarity: CategoryHints.cosine(target, vector), byOwner: sample.byOwner)
        }
        return SimilarFolders.vote(neighbors)
    }

    private func vector(for sample: FilingSample) -> [Double]? {
        if let known = lock.withLock({ vectors[sample.id] }), known.text == sample.text { return known.vector }
        let vector = embedder.vector(for: sample.text)
        lock.withLock { vectors[sample.id] = (sample.text, vector) }
        return vector
    }
}
