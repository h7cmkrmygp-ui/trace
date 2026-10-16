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
    public func analysisJob(sourceID: UUID) throws -> AnalysisJob? { nil }

    /// F14 — prend le travail d'analyse d'une source pour `lease` secondes ; false si un autre traitement le tient encore.
    public func beginAnalysis(sourceID: UUID, revision: Int, lease: TimeInterval) throws -> Bool { true }

    /// F14 — termine le travail : réussi, en attente (avec un délai) ou en échec, avec le type d'erreur.
    public func finishAnalysis(sourceID: UUID, status: AnalysisJob.Status, errorKind: AnalysisJob.ErrorKind? = nil,
                               detail: String? = nil, retryAfter: TimeInterval? = nil) throws {}

    /// F10 — « Garder sur l'iPhone » changé après la capture : la version de la politique augmente (une analyse en cours
    /// sur l'ancienne version n'est jamais écrite).
    public func setKeepLocal(sourceID: UUID, keepLocal: Bool) throws {}

    /// F12 — les sources à réessayer maintenant : les analyses ratées (même sans service en ligne) et, si un service est
    /// disponible, celles classées sur l'iPhone faute de service ; jamais avant leur délai, jamais au-delà de la limite.
    public func sourcesToRetry(cloudAvailable: Bool, limit: Int = 10) throws -> [Source] {
        cloudAvailable ? try sourcesNeedingCloudRetry(limit: limit) : []
    }
}
