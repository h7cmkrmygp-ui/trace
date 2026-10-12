import EngramCore
import Foundation
import GRDB

/// P35 — moins de « À classer » : pourquoi une note y est, et le ménage unique des anciennes copies et des anciens échecs.
extension MemoryStore {
    /// Pourquoi cette note est « À classer », en une phrase pour le propriétaire ; nil si elle est rangée.
    public func unsortedReason(for memoryID: UUID) throws -> String? {
        try database.writer.read { db in
            guard let memory = try Memory.fetchOne(db, key: memoryID), memory.status == .unsorted,
                  let source = try Source.fetchOne(db, key: memory.sourceID) else { return nil }
            if memory.analysisVersion == ThoughtFiler.leftoverAnalysisVersion {
                return "Une partie de ta dictée que l'IA n'a reprise dans aucune autre note : range-la, ou laisse-la ici."
            }
            if memory.analysisVersion == Self.interimAnalysisVersion {
                if source.needsReview { return "Elle attend que tu vérifies le texte." }
                if source.processingStatus != .done {
                    return "Pas encore classée : Engram la classe dès qu'un service d'IA répond."
                }
                if source.needsCloudRetry { return "L'IA n'a pas réussi à la classer : Engram réessaiera tout seul." }
                return "L'IA n'a pas réussi à la classer après plusieurs essais : range-la toi-même."
            }
            let removedByOwner = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM memory_category WHERE memory_id = ? AND rejected = 1)
                """, arguments: [memoryID]) ?? false
            if removedByOwner { return "Tu l'as retirée de son dossier." }
            return "L'IA n'a pas trouvé de dossier qui convienne vraiment : choisis-en un."
        }
    }

    /// Une seule fois : les anciennes copies de toute une dictée, déjà rangée en morceaux, vont à la corbeille
    /// (récupérables) si rien ne manque ailleurs, sinon ne gardent que la partie qui n'est nulle part ailleurs.
    /// Une copie que le propriétaire a touchée n'est jamais modifiée. Renvoie le nombre de copies traitées.
    public func cleanUpWholeNoteCopies() throws -> Int {
        let now = dates.now()
        return try database.writer.write { db -> Int in
            let copies = try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m
                WHERE m.analysis_version = ? AND m.status = 'unsorted'
                  AND EXISTS (SELECT 1 FROM memory other
                              WHERE other.source_id = m.source_id AND other.id <> m.id AND other.analysis_version <> ?
                                AND other.status <> 'trashed')
                """, arguments: [Self.interimAnalysisVersion, Self.interimAnalysisVersion])
            var handled = 0
            for var copy in copies {
                guard try !ThoughtFiler.isTouchedByOwner(db, copy) else { continue }
                let others = try Memory
                    .filter(Column("source_id") == copy.sourceID && Column("id") != copy.id
                            && Column("status") != MemoryStatus.trashed.rawValue)
                    .fetchAll(db)
                if let rest = AnalysisValidator.leftover(of: copy.content, excerpts: others.map(\.content)) {
                    copy.content = rest
                    copy.excerpt = rest
                    copy.title = TitleMaker.fallbackTitle(from: rest)
                    copy.spanStart = nil
                    copy.spanEnd = nil
                    copy.analysisVersion = ThoughtFiler.leftoverAnalysisVersion
                    copy.updatedAt = now
                    try copy.update(db)
                } else {
                    _ = try setStatus(db, .trashed, for: copy.id, actor: .system, now: now)
                }
                handled += 1
            }
            return handled
        }
    }

    /// Une seule fois : les anciennes notes jamais classées (échecs d'avant P35) sont proposées à un nouvel essai.
    /// Renvoie le nombre de notes proposées.
    public func retryOldFailures() throws -> Int {
        let now = dates.now()
        return try database.writer.write { db -> Int in
            let sources = try Source.fetchAll(db, sql: """
                SELECT s.* FROM source s
                WHERE s.processing_status = 'done' AND s.needs_cloud_retry = 0 AND s.analysis_attempts = 0
                  AND s.needs_review = 0
                  AND EXISTS (SELECT 1 FROM memory m WHERE m.source_id = s.id)
                  AND NOT EXISTS (SELECT 1 FROM memory m WHERE m.source_id = s.id AND m.analysis_version <> ?)
                """, arguments: [Self.interimAnalysisVersion])
            var proposed = 0
            for var source in sources {
                let notes = try Memory.filter(Column("source_id") == source.id).fetchAll(db)
                guard try !notes.contains(where: { try ThoughtFiler.isTouchedByOwner(db, $0) }) else { continue }
                source.needsCloudRetry = true
                source.updatedAt = now
                try source.update(db)
                proposed += 1
            }
            return proposed
        }
    }
}
