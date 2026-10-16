import EngramCore
import Foundation
import GRDB

/// F14 — le travail d'analyse d'une source, durable (table `processing_job`, étape « analyze ») : bail d'exécution,
/// révision, tentatives, prochain essai et type d'erreur.
public struct AnalysisJob: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable { case queued, running, succeeded, waiting, failed }
    public enum ErrorKind: String, Sendable, Equatable {
        /// Le service ou le modèle ne répond pas pour l'instant.
        case providerWait = "provider_wait"
        /// Un garde-fou a refusé la note.
        case policy
        /// La réponse ne respectait pas le contrat (extraits inventés…).
        case quality
        /// La source a changé pendant l'analyse.
        case stale
        /// Une erreur de l'iPhone (base, fichier…).
        case technical
    }

    public let sourceID: UUID
    public let revision: Int?
    public let status: Status
    public let attempts: Int
    public let nextAttemptAt: Date?
    public let leasedUntil: Date?
    public let errorKind: ErrorKind?
    public let lastError: String?
}

extension MemoryStore {
    static func analysisJobKey(_ sourceID: UUID) -> String { "analyze:" + sourceID.uuidString }

    public func analysisJob(sourceID: UUID) throws -> AnalysisJob? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT source_id, revision, status, attempts, next_attempt_at, leased_until, error_kind, last_error
                FROM processing_job WHERE idempotency_key = ?
                """, arguments: [Self.analysisJobKey(sourceID)]) else { return nil }
            let status: String = row["status"]
            let kind: String? = row["error_kind"]
            return AnalysisJob(sourceID: row["source_id"], revision: row["revision"],
                               status: AnalysisJob.Status(rawValue: status) ?? .queued, attempts: row["attempts"],
                               nextAttemptAt: row["next_attempt_at"], leasedUntil: row["leased_until"],
                               errorKind: kind.flatMap(AnalysisJob.ErrorKind.init(rawValue:)), lastError: row["last_error"])
        }
    }

    /// F14 — prend le travail d'analyse d'une source pour `lease` secondes ; false si un autre traitement le tient encore
    /// (son bail n'a pas expiré). Chaque prise compte comme une tentative.
    public func beginAnalysis(sourceID: UUID, revision: Int, lease: TimeInterval) throws -> Bool {
        let now = dates.now()
        return try database.writer.write { db in
            let key = Self.analysisJobKey(sourceID)
            if let row = try Row.fetchOne(db, sql: "SELECT status, leased_until FROM processing_job WHERE idempotency_key = ?",
                                          arguments: [key]) {
                let status: String = row["status"]
                let leased: Date? = row["leased_until"]
                if status == AnalysisJob.Status.running.rawValue, let leased, leased > now { return false }
                try db.execute(sql: """
                    UPDATE processing_job SET status = 'running', revision = ?, leased_until = ?, attempts = attempts + 1,
                      updated_at = ? WHERE idempotency_key = ?
                    """, arguments: [revision, now.addingTimeInterval(lease), now, key])
            } else {
                try db.execute(sql: """
                    INSERT INTO processing_job (id, source_id, step, status, attempts, max_attempts, idempotency_key,
                      created_at, updated_at, revision, leased_until)
                    VALUES (?, ?, 'analyze', 'running', 1, ?, ?, ?, ?, ?, ?)
                    """, arguments: [UUID(), sourceID, ThoughtFiler.maxAnalysisAttempts, key, now, now, revision,
                                     now.addingTimeInterval(lease)])
            }
            return true
        }
    }

    /// F14 — termine le travail : réussi, en attente (avec un délai) ou en échec, avec le type d'erreur ; le bail est rendu.
    public func finishAnalysis(sourceID: UUID, status: AnalysisJob.Status, errorKind: AnalysisJob.ErrorKind? = nil,
                               detail: String? = nil, retryAfter: TimeInterval? = nil) throws {
        let now = dates.now()
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE processing_job SET status = ?, error_kind = ?, last_error = ?, leased_until = NULL,
                  next_attempt_at = ?, updated_at = ? WHERE idempotency_key = ?
                """, arguments: [status.rawValue, errorKind?.rawValue, detail.map { String($0.prefix(300)) },
                                 retryAfter.map { now.addingTimeInterval($0) }, now, Self.analysisJobKey(sourceID)])
        }
    }

    /// F10 — « Garder sur l'iPhone » changé après la capture : la version de la politique augmente (une analyse en cours
    /// sur l'ancienne version n'est jamais écrite), et les listes que la note a complétées en prennent les interdictions
    /// (F01, jamais abaissées).
    public func setKeepLocal(sourceID: UUID, keepLocal: Bool) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            guard source.keepLocal != keepLocal else { return }
            source.keepLocal = keepLocal
            if keepLocal { source.privacyBasis = .ownerKeepLocal }
            source.policyVersion += 1
            source.updatedAt = now
            try source.update(db)
            for key in try String.fetchAll(db, sql: "SELECT normalized_name FROM memory_list_addition WHERE source_id = ?",
                                           arguments: [sourceID]) {
                try ListStore.restrict(db, key: key.components(separatedBy: " | ")[0], by: sourceID)
            }
        }
    }

    /// F12 — les sources à réessayer maintenant : les analyses ratées (même sans service en ligne : le modèle de l'iPhone
    /// réessaie) et, si un service est disponible, celles classées sur l'iPhone faute de service ; jamais avant leur délai,
    /// jamais au-delà de la limite d'essais.
    public func sourcesToRetry(cloudAvailable: Bool, limit: Int = 10) throws -> [Source] {
        let now = dates.now()
        return try database.writer.read { db in
            try Source.fetchAll(db, sql: """
                SELECT s.* FROM source s
                WHERE s.processing_status = 'done' AND s.analysis_attempts < ?
                  AND (s.retry_after IS NULL OR s.retry_after <= ?)
                  AND (
                    -- Une analyse ratée : seule la note provisoire existe.
                    (EXISTS (SELECT 1 FROM memory m WHERE m.source_id = s.id AND m.analysis_version = ? AND m.status <> 'trashed')
                     AND NOT EXISTS (SELECT 1 FROM memory m WHERE m.source_id = s.id AND m.analysis_version <> ?
                                     AND m.status <> 'trashed')
                     AND s.analysis_attempts > 0)
                    OR (s.needs_cloud_retry = 1 AND ?)
                  )
                ORDER BY s.captured_at LIMIT ?
                """, arguments: [ThoughtFiler.maxAnalysisAttempts, now, Self.interimAnalysisVersion,
                                 Self.interimAnalysisVersion, cloudAvailable, limit])
        }
    }

    /// F23 — une dictée dite juste avant celle-ci (dans la fenêtre du contexte) est en ce moment en cours de classement :
    /// celle-ci attend son tour pour en recevoir le contexte (« elle », « cette liste »).
    public func earlierDictationInProgress(before sourceID: UUID) throws -> Bool {
        let now = dates.now()
        return try database.writer.read { db in
            guard let source = try Source.fetchOne(db, key: sourceID) else { return false }
            return try Bool.fetchOne(db, sql: """
                SELECT EXISTS(
                  SELECT 1 FROM source s JOIN processing_job j ON j.source_id = s.id
                  WHERE s.id != ? AND s.captured_at <= ? AND s.captured_at >= ? AND s.processing_status != 'done'
                    AND s.needs_review = 0 AND j.step = 'analyze' AND j.status = 'running'
                    AND j.leased_until > ?)
                """, arguments: [sourceID, source.capturedAt, source.capturedAt.addingTimeInterval(-RecentContext.window),
                                 now]) ?? false
        }
    }
}
