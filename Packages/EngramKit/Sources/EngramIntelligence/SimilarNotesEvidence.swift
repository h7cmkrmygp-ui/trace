import EngramCore
import Foundation

/// P34 — trouve, **sur l'iPhone**, les notes déjà rangées qui ressemblent le plus à une nouvelle note (par le sens), et
/// où elles sont rangées. Seuls les noms des dossiers sortent de ce calcul ; les notes elles-mêmes restent sur l'iPhone.
public final class SimilarNotesEvidence: FolderEvidenceSource, @unchecked Sendable {
    let embedder: any SentenceEmbedder
    let samples: @Sendable () throws -> [FilingSample]

    public init(embedder: any SentenceEmbedder, samples: @escaping @Sendable () throws -> [FilingSample]) {
        self.embedder = embedder
        self.samples = samples
    }

    public func evidence(for text: String) async -> [FolderEvidence] {
        []
    }
}
