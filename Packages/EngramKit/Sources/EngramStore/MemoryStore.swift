import EngramCore
import Foundation
import GRDB

/// Sources et souvenirs : création, modification versionnée, statuts, suppression contrôlée.
public struct MemoryStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider
    /// Fuseau des journées (la prochaine fois d'une tâche qui revient, P16).
    public let calendar: Calendar

    /// Deux captures identiques à moins de 10 minutes d'écart sont un doublon technique.
    public static let technicalDuplicateWindow: TimeInterval = 10 * 60
    /// Version d'analyse des souvenirs créés avant le moteur IA (plan P2), qui les ré-analysera.
    public static let interimAnalysisVersion = "interim-none"

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider(), calendar: Calendar = .current) {
        self.database = database
        self.dates = dates
        self.calendar = calendar
    }

    public enum SourceInsertion: Sendable, Equatable {
        case created(Source)
        case duplicate(of: Source)
    }

    public enum TextNoteSave: Sendable, Equatable {
        case saved(Memory)
        case duplicate(of: Source)
    }

    public struct PermanentDeletion: Sendable, Equatable {
        public let memoryID: UUID
        /// Renseigné si la source n'avait plus d'autre souvenir et a été supprimée.
        public let deletedSourceID: UUID?
        /// Fichier audio à effacer du disque (chemin relatif au dossier audio), le cas échéant.
        public let audioPathToRemove: String?
    }

    // MARK: - Sources

    public func insertTextSource(_ text: String) throws -> SourceInsertion {
        let now = dates.now()
        return try database.writer.write { db in try insertTextSource(db, text: text, now: now) }
    }

    func insertTextSource(_ db: Database, text: String, now: Date) throws -> SourceInsertion {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyContent }
        let hash = ContentHasher.textHash(trimmed)
        let windowStart = now.addingTimeInterval(-Self.technicalDuplicateWindow)
        if let existing = try Source
            .filter(Column("content_hash") == hash && Column("captured_at") >= windowStart)
            .order(Column("captured_at").desc)
            .fetchOne(db) {
            return .duplicate(of: existing)
        }
        let source = Source(kind: .text, originalText: trimmed, contentHash: hash,
                            capturedAt: now, createdAt: now, updatedAt: now)
        try source.insert(db)
        return .created(source)
    }

    public func source(id: UUID) throws -> Source? {
        try database.writer.read { db in try Source.fetchOne(db, key: id) }
    }

    // MARK: - Note texte sans analyse (en attendant le moteur IA du plan P2)

    /// Enregistre une note texte comme un souvenir « À classer », en une seule transaction.
    /// - Parameter keepLocal: « Garder sur l'iPhone » : la note ne sera jamais envoyée à un service en ligne.
    public func saveTextNoteWithoutAnalysis(_ text: String, keepLocal: Bool = false) throws -> TextNoteSave {
        let now = dates.now()
        return try database.writer.write { db in
            switch try insertTextSource(db, text: text, now: now) {
            case .duplicate(let existing):
                return .duplicate(of: existing)
            case .created(var source):
                let body = source.originalText ?? ""
                let draft = MemoryDraft(
                    sourceID: source.id, excerpt: body, spanStart: 0, spanEnd: body.utf16.count,
                    title: TitleMaker.fallbackTitle(from: body), content: body,
                    status: .unsorted, analysisVersion: Self.interimAnalysisVersion)
                let memory = try createMemory(db, draft: draft, actor: .system, now: now)
                source.processingStatus = .waiting
                source.keepLocal = keepLocal
                source.updatedAt = now
                try source.update(db)
                return .saved(memory)
            }
        }
    }

    // MARK: - Souvenirs

    public func createMemory(_ draft: MemoryDraft, actor: ChangeActor) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in try createMemory(db, draft: draft, actor: actor, now: now) }
    }

    func createMemory(_ db: Database, draft: MemoryDraft, actor: ChangeActor, now: Date) throws -> Memory {
        try draft.validate()
        guard let source = try Source.fetchOne(db, key: draft.sourceID) else { throw StoreError.notFound }
        let memory = Memory(draft: draft, capturedAt: source.capturedAt, now: now)
        try memory.insert(db)
        try MemoryVersion(memory: memory, changedBy: actor, reason: "création", at: now).insert(db)
        return memory
    }

    /// Modifie un souvenir et crée une version. L'IA ne peut pas modifier un souvenir édité à la main.
    public func updateMemory(_ id: UUID, with edit: MemoryEdit, actor: ChangeActor, reason: String? = nil) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            if actor == .ai && memory.userEdited { throw StoreError.protectedByUser }
            guard edit.apply(to: &memory) else { return memory }
            try MemoryValidation.validate(title: memory.title, content: memory.content)
            if actor == .user { memory.userEdited = true }
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: actor, reason: reason ?? "modification", at: now).insert(db)
            return memory
        }
    }

    /// Archive, met à la corbeille ou change le statut d'un souvenir. Chaque changement crée une version.
    public func setStatus(_ status: MemoryStatus, for id: UUID, actor: ChangeActor) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            try setStatus(db, status, for: id, actor: actor, now: now)
        }
    }

    func setStatus(_ db: Database, _ status: MemoryStatus, for id: UUID, actor: ChangeActor, now: Date) throws -> Memory {
        guard var memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
        guard memory.status != status else { return memory }
        // P16 : une tâche qui revient, faite, passe à la prochaine fois au lieu d'aller dans les Archives.
        if status == .archived, actor == .user, try advanceRecurrence(db, &memory, now: now) { return memory }
        memory.status = status
        memory.trashedAt = status == .trashed ? now : nil
        memory.version += 1
        memory.updatedAt = now
        try memory.update(db)
        try MemoryVersion(memory: memory, changedBy: actor, reason: "statut : \(status.rawValue)", at: now).insert(db)
        return memory
    }

    /// Sort un souvenir de la corbeille ou des archives : actif s'il a une catégorie, sinon « À classer ».
    public func restore(_ id: UUID, actor: ChangeActor = .user) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            guard memory.status == .trashed || memory.status == .archived else { return memory }
            memory.status = try SortingStatus.hasValidCategory(db, memoryID: id) ? .active : .unsorted
            memory.trashedAt = nil
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: actor, reason: "restauration", at: now).insert(db)
            return memory
        }
    }

    /// Restaure le texte d'une ancienne version (nouvelle version créée, souvenir marqué « modifié à la main »).
    public func restoreVersion(_ version: Int, of id: UUID) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var memory = try Memory.fetchOne(db, key: id),
                  let old = try MemoryVersion
                    .filter(Column("memory_id") == id && Column("version") == version)
                    .fetchOne(db)
            else { throw StoreError.notFound }
            memory.title = old.snapshot.title
            memory.summary = old.snapshot.summary
            memory.content = old.snapshot.content
            memory.kind = old.snapshot.kind
            memory.userEdited = true
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            try MemoryVersion(memory: memory, changedBy: .user, reason: "restauration de la version \(version)", at: now).insert(db)
            return memory
        }
    }

    /// Supprime définitivement un souvenir **qui est à la corbeille**, avec ses versions, liens, index et embedding.
    /// La source est supprimée si plus aucun souvenir ne l'utilise.
    public func deletePermanently(_ id: UUID) throws -> PermanentDeletion {
        try database.writer.write { db in
            guard let memory = try Memory.fetchOne(db, key: id) else { throw StoreError.notFound }
            return try Self.deletePermanently(db, memory)
        }
    }

    /// Vide la corbeille : supprime définitivement, en une seule transaction, toutes les notes qui y sont.
    @discardableResult
    public func emptyTrash() throws -> [PermanentDeletion] {
        try database.writer.write { db in
            try Memory.filter(Column("status") == MemoryStatus.trashed).fetchAll(db)
                .map { try Self.deletePermanently(db, $0) }
        }
    }

    static func deletePermanently(_ db: Database, _ memory: Memory) throws -> PermanentDeletion {
        guard memory.status == .trashed else {
            throw StoreError.invalidOperation("mettre le souvenir à la corbeille avant de le supprimer définitivement")
        }
        _ = try memory.delete(db)
        let remaining = try Memory.filter(Column("source_id") == memory.sourceID).fetchCount(db)
        guard remaining == 0, let source = try Source.fetchOne(db, key: memory.sourceID) else {
            return PermanentDeletion(memoryID: memory.id, deletedSourceID: nil, audioPathToRemove: nil)
        }
        _ = try source.delete(db)
        return PermanentDeletion(memoryID: memory.id, deletedSourceID: source.id, audioPathToRemove: source.audioPath)
    }

    // MARK: - Lecture

    public func memory(id: UUID) throws -> Memory? {
        try database.writer.read { db in try Memory.fetchOne(db, key: id) }
    }

    public func memories(statuses: Set<MemoryStatus>, limit: Int = 500) throws -> [Memory] {
        try database.writer.read { db in
            try Memory.filter(statuses.contains(Column("status")))
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Souvenirs correspondant aux identifiants, dans le même ordre (les absents sont ignorés).
    public func memories(ids: [UUID]) throws -> [Memory] {
        guard !ids.isEmpty else { return [] }
        let found = try database.writer.read { db in
            try Memory.filter(ids.contains(Column("id"))).fetchAll(db)
        }
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func versions(of id: UUID) throws -> [MemoryVersion] {
        try database.writer.read { db in
            try MemoryVersion.filter(Column("memory_id") == id).order(Column("version").desc).fetchAll(db)
        }
    }

    /// Liste observée : une nouvelle valeur à chaque modification.
    /// Les dictées qui attendent « Vérifie ta note » n'y figurent pas : elles ont leur propre carte « À vérifier ».
    public func memoriesStream(statuses: Set<MemoryStatus>, limit: Int = 500) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in
            try Memory.filter(statuses.contains(Column("status")))
                .filter(sql: "source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)")
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
