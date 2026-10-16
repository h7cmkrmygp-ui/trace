import EngramCore
import Foundation
import GRDB

/// Où une note a été classée (Gemini, Groq ou l'iPhone) et reclassement des notes classées sur l'iPhone faute de service.
extension MemoryStore {
    public func recordRoute(sourceID: UUID, route: AnalysisRoute) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            source.privacyLevel = route.level
            source.privacyBasis = source.keepLocal ? .ownerKeepLocal : route.effectiveBasis
            source.analysisProvider = route.provider
            source.routeReason = route.reason
            source.needsCloudRetry = route.needsCloudRetry
            source.updatedAt = now
            try source.update(db)
        }
    }

    /// Combien de notes dictées depuis `date` ont été classées par chaque service (« gemini », « groq », « apple »).
    public func routeCounts(since date: Date) throws -> [String: Int] {
        try database.writer.read { db in
            var counts: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT analysis_provider AS provider, count(*) AS n FROM source
                WHERE analysis_provider IS NOT NULL AND captured_at >= ?
                GROUP BY analysis_provider
                """, arguments: [date]) {
                let provider: String = row["provider"]
                let n: Int = row["n"]
                counts[provider] = n
            }
            return counts
        }
    }

    /// Notes classées sur l'iPhone parce que le service en ligne ne répondait pas (quota, réseau), dont le délai avant un
    /// nouvel essai est passé (F12).
    public func sourcesNeedingCloudRetry(limit: Int = 20) throws -> [Source] {
        let now = dates.now()
        return try database.writer.read { db in
            try Source.filter(Column("needs_cloud_retry") == true && Column("processing_status") == ProcessingStatus.done
                              && Column("analysis_attempts") < ThoughtFiler.maxAnalysisAttempts)
                .filter(Column("retry_after") == nil || Column("retry_after") <= now)
                .order(Column("captured_at"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// F12 — délai avant l'essai suivant : de plus en plus long (15 min, 2 h, 12 h).
    static func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
        let delays: [TimeInterval] = [15 * 60, 2 * 3600, 12 * 3600]
        return delays[min(max(attempt, 1), delays.count) - 1]
    }

    /// Remet la note en attente d'analyse pour un nouvel essai. F12 : rien n'est supprimé maintenant — les notes déjà
    /// tirées restent utilisables et ne seront remplacées, d'un coup, que par une nouvelle analyse réussie ; chaque essai
    /// compte et repousse le suivant. Si le propriétaire a touché l'une d'elles, la note n'est plus reproposée.
    /// Renvoie `true` si la note a été rouverte.
    @discardableResult
    public func reopenForCloudRetry(sourceID: UUID) throws -> Bool {
        let now = dates.now()
        return try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            source.needsCloudRetry = false
            source.updatedAt = now
            let memories = try Memory.filter(Column("source_id") == sourceID).fetchAll(db)
            let text = (source.referenceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let touched = try memories.contains { try ThoughtFiler.isTouchedByOwner(db, $0) }
            guard !touched, !text.isEmpty, source.processingStatus == .done else {
                try source.update(db)
                return false
            }
            source.analysisAttempts += 1
            source.retryAfter = now.addingTimeInterval(Self.retryDelay(afterAttempt: source.analysisAttempts))
            source.processingStatus = .waiting
            try source.update(db)
            return true
        }
    }
}
