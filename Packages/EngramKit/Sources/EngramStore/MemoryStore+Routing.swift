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

    /// Notes classées sur l'iPhone parce que le service en ligne ne répondait pas (quota, réseau).
    public func sourcesNeedingCloudRetry(limit: Int = 20) throws -> [Source] {
        try database.writer.read { db in
            try Source.filter(Column("needs_cloud_retry") == true && Column("processing_status") == ProcessingStatus.done)
                .order(Column("captured_at"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Remet la note en attente d'analyse pour le service en ligne : les notes que l'IA avait tirées sont remplacées
    /// par une note provisoire. Si le propriétaire a touché l'une d'elles, rien n'est remplacé et la note n'est plus
    /// reproposée. Renvoie `true` si la note a été rouverte.
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
            for memory in memories { _ = try memory.delete(db) }
            source.processingStatus = .waiting
            try source.update(db)
            let draft = MemoryDraft(sourceID: sourceID, excerpt: text, spanStart: 0, spanEnd: text.utf16.count,
                                    spanTextVersion: source.correctedText == nil ? .original : .corrected,
                                    title: TitleMaker.fallbackTitle(from: text), content: text,
                                    status: .unsorted, analysisVersion: Self.interimAnalysisVersion)
            _ = try createMemory(db, draft: draft, actor: .system, now: now)
            return true
        }
    }
}
