import Foundation

/// F29 — la version du contrat d'analyse (intention, polarité, arguments, dates avec rôle).
public enum AnalysisContract {
    public static let version = "intention-p50"
}

/// F29 — la trace d'une tentative de classement, gardée sur l'iPhone.
public struct AnalysisRun: Sendable, Equatable {
    public enum Outcome: String, Sendable, Codable {
        case filed, refused, waiting, failed, stale
    }

    public struct Proposal: Sendable, Equatable, Codable {
        public let title: String
        public let intent: String?
        public let kind: String
        public let folder: String
        public let list: String?

        public init(title: String, intent: String?, kind: String, folder: String, list: String?) {
            self.title = title
            self.intent = intent
            self.kind = kind
            self.folder = folder
            self.list = list
        }
    }

    public let id: UUID
    public let sourceID: UUID
    public let attempt: Int
    public let revision: Int
    public let textHash: String
    public let provider: String?
    public let model: String?
    public let promptVersion: String?
    public let contractVersion: String
    public let privacyLevel: String?
    public let privacyBasis: String?
    public let proposals: [Proposal]
    public let problems: [String]
    public let operations: [String]
    public let outcome: Outcome
    public let errorKind: String?
    public let startedAt: Date
    public let finishedAt: Date

    public init(id: UUID = UUID(), sourceID: UUID, attempt: Int, revision: Int, textHash: String, provider: String?,
                model: String?, promptVersion: String?, contractVersion: String = AnalysisContract.version,
                privacyLevel: String?, privacyBasis: String?, proposals: [Proposal], problems: [String],
                operations: [String], outcome: Outcome, errorKind: String?, startedAt: Date, finishedAt: Date) {
        self.id = id
        self.sourceID = sourceID
        self.attempt = attempt
        self.revision = revision
        self.textHash = textHash
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
        self.contractVersion = contractVersion
        self.privacyLevel = privacyLevel
        self.privacyBasis = privacyBasis
        self.proposals = proposals
        self.problems = problems
        self.operations = operations
        self.outcome = outcome
        self.errorKind = errorKind
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
