import Foundation

/// L'original d'une capture. Le texte original n'est jamais réécrit.
public struct Source: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: SourceKind
    public var audioPath: String?
    public var audioDuration: Double?
    public var originalText: String?
    public var correctedText: String?
    public var languages: [String]
    public var transcriptionEngine: String?
    public var contentHash: String
    public var capturedAt: Date
    public var processingStatus: ProcessingStatus
    public var createdAt: Date
    public var updatedAt: Date
    /// La transcription attend la vérification du propriétaire : aucune analyse avant sa confirmation.
    public var needsReview: Bool
    /// « Garder sur l'iPhone » : la note n'est jamais envoyée à un service en ligne.
    public var keepLocal: Bool
    /// Niveau de confidentialité décidé sur l'iPhone (nil tant que la note n'a pas été évaluée).
    public var privacyLevel: PrivacyLevel?
    /// Qui a classé la note : « gemini », « groq » ou « apple ».
    public var analysisProvider: String?
    /// Pourquoi elle a été classée là (affiché au propriétaire).
    public var routeReason: String?
    /// Classée sur l'iPhone faute de service en ligne : à reclasser plus tard si personne n'y touche.
    public var needsCloudRetry: Bool
    /// `correctedText` vient du propriétaire (« Vérifie ta note ») et non d'une retranscription :
    /// c'est une référence fiable, et aucune retranscription ne l'écrase.
    public var correctedByOwner: Bool

    public init(
        id: UUID = UUID(), kind: SourceKind, audioPath: String? = nil, audioDuration: Double? = nil,
        originalText: String? = nil, correctedText: String? = nil, languages: [String] = [],
        transcriptionEngine: String? = nil, contentHash: String, capturedAt: Date,
        processingStatus: ProcessingStatus = .pending, createdAt: Date, updatedAt: Date,
        needsReview: Bool = false, keepLocal: Bool = false, privacyLevel: PrivacyLevel? = nil,
        analysisProvider: String? = nil, routeReason: String? = nil, needsCloudRetry: Bool = false,
        correctedByOwner: Bool = false
    ) {
        self.correctedByOwner = correctedByOwner
        self.needsReview = needsReview
        self.keepLocal = keepLocal
        self.privacyLevel = privacyLevel
        self.analysisProvider = analysisProvider
        self.routeReason = routeReason
        self.needsCloudRetry = needsCloudRetry
        self.id = id
        self.kind = kind
        self.audioPath = audioPath
        self.audioDuration = audioDuration
        self.originalText = originalText
        self.correctedText = correctedText
        self.languages = languages
        self.transcriptionEngine = transcriptionEngine
        self.contentHash = contentHash
        self.capturedAt = capturedAt
        self.processingStatus = processingStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Texte à analyser : la correction du propriétaire si elle existe, sinon l'original.
    public var referenceText: String? { correctedText ?? originalText }

    enum CodingKeys: String, CodingKey {
        case id, kind, languages
        case audioPath = "audio_path"
        case audioDuration = "audio_duration"
        case originalText = "original_text"
        case correctedText = "corrected_text"
        case transcriptionEngine = "transcription_engine"
        case contentHash = "content_hash"
        case capturedAt = "captured_at"
        case processingStatus = "processing_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case needsReview = "needs_review"
        case keepLocal = "keep_local"
        case privacyLevel = "privacy_level"
        case analysisProvider = "analysis_provider"
        case routeReason = "route_reason"
        case needsCloudRetry = "needs_cloud_retry"
        case correctedByOwner = "corrected_by_owner"
    }
}

/// Données nécessaires pour créer un souvenir.
public struct MemoryDraft: Sendable, Hashable {
    public var sourceID: UUID
    public var excerpt: String
    public var spanStart: Int?
    public var spanEnd: Int?
    public var spanTextVersion: TextVersion
    public var title: String
    public var summary: String?
    public var content: String
    public var kind: MemoryKind?
    public var status: MemoryStatus
    public var confidence: Double?
    public var suggestedTopic: String?
    public var mentionedDates: [String]
    public var analysisVersion: String
    public var dueAt: Date?
    public var dueHasTime: Bool

    public init(
        sourceID: UUID, excerpt: String, spanStart: Int? = nil, spanEnd: Int? = nil,
        spanTextVersion: TextVersion = .original, title: String, summary: String? = nil,
        content: String, kind: MemoryKind? = nil, status: MemoryStatus = .unsorted,
        confidence: Double? = nil, suggestedTopic: String? = nil, mentionedDates: [String] = [],
        analysisVersion: String, dueAt: Date? = nil, dueHasTime: Bool = false
    ) {
        self.dueAt = dueAt
        self.dueHasTime = dueHasTime
        self.sourceID = sourceID
        self.excerpt = excerpt
        self.spanStart = spanStart
        self.spanEnd = spanEnd
        self.spanTextVersion = spanTextVersion
        self.title = title
        self.summary = summary
        self.content = content
        self.kind = kind
        self.status = status
        self.confidence = confidence
        self.suggestedTopic = suggestedTopic
        self.mentionedDates = mentionedDates
        self.analysisVersion = analysisVersion
    }
}

/// Un souvenir.
public struct Memory: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sourceID: UUID
    public var excerpt: String
    public var spanStart: Int?
    public var spanEnd: Int?
    public var spanTextVersion: TextVersion
    public var title: String
    public var summary: String?
    public var content: String
    public var kind: MemoryKind?
    public var memoryType: String?
    public var status: MemoryStatus
    public var confidence: Double?
    public var suggestedTopic: String?
    public var mentionedDates: [String]
    public var userEdited: Bool
    public var possibleDuplicateOf: UUID?
    public var analysisVersion: String
    public var capturedAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?
    public var version: Int
    /// Échéance calculée à partir des dates dites (jamais inventée).
    public var dueAt: Date?
    /// Vrai si une heure précise a été dite.
    public var dueHasTime: Bool

    public init(id: UUID = UUID(), draft: MemoryDraft, capturedAt: Date, now: Date) {
        self.id = id
        self.sourceID = draft.sourceID
        self.excerpt = draft.excerpt
        self.spanStart = draft.spanStart
        self.spanEnd = draft.spanEnd
        self.spanTextVersion = draft.spanTextVersion
        self.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = draft.summary
        self.content = draft.content
        self.kind = draft.kind
        self.memoryType = nil
        self.status = draft.status
        self.confidence = draft.confidence
        self.suggestedTopic = draft.suggestedTopic
        self.mentionedDates = draft.mentionedDates
        self.userEdited = false
        self.possibleDuplicateOf = nil
        self.analysisVersion = draft.analysisVersion
        self.capturedAt = capturedAt
        self.createdAt = now
        self.updatedAt = now
        self.trashedAt = nil
        self.version = 1
        self.dueAt = draft.dueAt
        self.dueHasTime = draft.dueHasTime
    }

    /// Ce qui est conservé dans l'historique des versions.
    public var snapshot: MemorySnapshot {
        MemorySnapshot(title: title, summary: summary, content: content, kind: kind, status: status)
    }

    enum CodingKeys: String, CodingKey {
        case id, excerpt, title, summary, content, kind, status, confidence, version
        case sourceID = "source_id"
        case spanStart = "span_start"
        case spanEnd = "span_end"
        case spanTextVersion = "span_text_version"
        case memoryType = "memory_type"
        case suggestedTopic = "suggested_topic"
        case mentionedDates = "mentioned_dates"
        case userEdited = "user_edited"
        case possibleDuplicateOf = "possible_duplicate_of"
        case analysisVersion = "analysis_version"
        case capturedAt = "captured_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case trashedAt = "trashed_at"
        case dueAt = "due_at"
        case dueHasTime = "due_has_time"
    }
}

/// Une modification demandée sur un souvenir. `nil` = ne pas toucher ; `summary: ""` efface le résumé.
public struct MemoryEdit: Sendable, Hashable {
    public var title: String?
    public var summary: String?
    public var content: String?
    public var kind: MemoryKind?

    public init(title: String? = nil, summary: String? = nil, content: String? = nil, kind: MemoryKind? = nil) {
        self.title = title
        self.summary = summary
        self.content = content
        self.kind = kind
    }

    /// Applique la modification. Renvoie `true` si quelque chose a changé.
    public func apply(to memory: inout Memory) -> Bool {
        var changed = false
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != memory.title { memory.title = trimmed; changed = true }
        }
        if let summary {
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue: String? = trimmed.isEmpty ? nil : trimmed
            if newValue != memory.summary { memory.summary = newValue; changed = true }
        }
        if let content, content != memory.content {
            memory.content = content
            changed = true
        }
        if let kind, kind != memory.kind {
            memory.kind = kind
            changed = true
        }
        return changed
    }
}

/// Copie des champs d'un souvenir à un instant donné.
public struct MemorySnapshot: Codable, Sendable, Hashable {
    public var title: String
    public var summary: String?
    public var content: String
    public var kind: MemoryKind?
    public var status: MemoryStatus

    public init(title: String, summary: String?, content: String, kind: MemoryKind?, status: MemoryStatus) {
        self.title = title
        self.summary = summary
        self.content = content
        self.kind = kind
        self.status = status
    }
}

/// Une version de l'historique d'un souvenir.
public struct MemoryVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var memoryID: UUID
    public var version: Int
    public var snapshot: MemorySnapshot
    public var changedBy: ChangeActor
    public var changeReason: String?
    public var createdAt: Date

    public init(memory: Memory, changedBy: ChangeActor, reason: String?, at date: Date) {
        self.id = UUID()
        self.memoryID = memory.id
        self.version = memory.version
        self.snapshot = memory.snapshot
        self.changedBy = changedBy
        self.changeReason = reason
        self.createdAt = date
    }

    enum CodingKeys: String, CodingKey {
        case id, version, snapshot
        case memoryID = "memory_id"
        case changedBy = "changed_by"
        case changeReason = "change_reason"
        case createdAt = "created_at"
    }
}

/// Une catégorie (dossier). « À classer » n'en est pas une : c'est le statut `unsorted` d'un souvenir.
public struct EngramCategory: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var normalizedName: String
    public var descriptionText: String?
    public var parentID: UUID?
    public var origin: Origin
    public var status: CategoryStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, descriptionText: String? = nil, parentID: UUID?,
                origin: Origin, status: CategoryStatus = .active, now: Date) {
        self.id = id
        self.name = name
        self.normalizedName = TextNormalizer.normalizedName(name)
        self.descriptionText = descriptionText
        self.parentID = parentID
        self.origin = origin
        self.status = status
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, name, origin, status
        case normalizedName = "normalized_name"
        case descriptionText = "description"
        case parentID = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Une étiquette (idée, décision, facture…).
public struct EngramTag: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var normalizedName: String
    public var origin: Origin
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, origin: Origin, now: Date) {
        self.id = id
        self.name = name
        self.normalizedName = TextNormalizer.normalizedName(name)
        self.origin = origin
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, name, origin
        case normalizedName = "normalized_name"
        case createdAt = "created_at"
    }
}

/// Lien souvenir ↔ catégorie. `rejected` = retiré par le propriétaire (l'IA ne le recréera jamais).
public struct CategoryAssignment: Codable, Sendable, Hashable {
    public var memoryID: UUID
    public var categoryID: UUID
    public var origin: AssignmentOrigin
    public var confidence: Double?
    public var confirmed: Bool
    public var rejected: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(memoryID: UUID, categoryID: UUID, origin: AssignmentOrigin, confidence: Double? = nil,
                confirmed: Bool, rejected: Bool = false, now: Date) {
        self.memoryID = memoryID
        self.categoryID = categoryID
        self.origin = origin
        self.confidence = confidence
        self.confirmed = confirmed
        self.rejected = rejected
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case origin, confidence, confirmed, rejected
        case memoryID = "memory_id"
        case categoryID = "category_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Lien souvenir ↔ tag. Mêmes règles que `CategoryAssignment`.
public struct TagAssignment: Codable, Sendable, Hashable {
    public var memoryID: UUID
    public var tagID: UUID
    public var origin: AssignmentOrigin
    public var confidence: Double?
    public var confirmed: Bool
    public var rejected: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(memoryID: UUID, tagID: UUID, origin: AssignmentOrigin, confidence: Double? = nil,
                confirmed: Bool, rejected: Bool = false, now: Date) {
        self.memoryID = memoryID
        self.tagID = tagID
        self.origin = origin
        self.confidence = confidence
        self.confirmed = confirmed
        self.rejected = rejected
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case origin, confidence, confirmed, rejected
        case memoryID = "memory_id"
        case tagID = "tag_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
