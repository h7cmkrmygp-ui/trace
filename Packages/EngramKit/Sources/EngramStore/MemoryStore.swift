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
        /// F09 — les autres dictées supprimées avec une liste (elles n'existaient plus que par leurs ajouts), et leurs
        /// fichiers audio à effacer.
        public var orphanedSources: [UUID] = []
        public var orphanedAudioPaths: [String] = []
    }

    // MARK: - Sources

    public func insertTextSource(_ text: String) throws -> SourceInsertion {
        let now = dates.now()
        return try database.writer.write { db in try insertTextSource(db, text: text, now: now) }
    }

    func insertTextSource(_ db: Database, text: String, importID: String? = nil, now: Date) throws -> SourceInsertion {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyContent }
        let hash = ContentHasher.textHash(trimmed)
        // F19 : un élément importé se reconnaît à son identifiant (un rejeu ne le recrée pas) ; deux partages distincts
        // du même texte sont deux gestes du propriétaire.
        if let importID {
            if let existing = try Source.filter(Column("import_id") == importID).fetchOne(db) { return .duplicate(of: existing) }
            let source = Source(kind: .text, originalText: trimmed, contentHash: hash, capturedAt: now, createdAt: now,
                                updatedAt: now, importID: importID, capturedTimeZone: calendar.timeZone.identifier)
            try source.insert(db)
            return .created(source)
        }
        let windowStart = now.addingTimeInterval(-Self.technicalDuplicateWindow)
        if let existing = try Source
            .filter(Column("content_hash") == hash && Column("captured_at") >= windowStart)
            .order(Column("captured_at").desc)
            .fetchOne(db) {
            return .duplicate(of: existing)
        }
        let source = Source(kind: .text, originalText: trimmed, contentHash: hash,
                            capturedAt: now, createdAt: now, updatedAt: now, capturedTimeZone: calendar.timeZone.identifier)
        try source.insert(db)
        return .created(source)
    }

    public func source(id: UUID) throws -> Source? {
        try database.writer.read { db in try Source.fetchOne(db, key: id) }
    }

    // MARK: - Note texte sans analyse (en attendant le moteur IA du plan P2)

    /// Enregistre une note texte comme un souvenir « À classer », en une seule transaction.
    /// - Parameters:
    ///   - keepLocal: « Garder sur l'iPhone » : la note ne sera jamais envoyée à un service en ligne.
    ///   - importID: F19 — identifiant stable d'un élément importé (partage) : déjà enregistré, il n'est pas recréé.
    public func saveTextNoteWithoutAnalysis(_ text: String, keepLocal: Bool = false, importID: String? = nil) throws -> TextNoteSave {
        let now = dates.now()
        return try database.writer.write { db in
            switch try insertTextSource(db, text: text, importID: importID, now: now) {
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
            // F09 — une liste modifiée à la main : chaque case ajoutée, cochée ou retirée est notée au nom du propriétaire.
            try Self.syncListItems(db, memory, actor: actor, now: now)
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
            try Self.syncListItems(db, memory, actor: .user, now: now)
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
        // F09 — les dictées qui ont complété cette liste (ses choses, ses opérations, ses ajouts d'avant).
        let list = try ListRecord.filter(Column("memory_id") == memory.id).fetchOne(db)
        let contributors = try list.map { record in
            try UUID.fetchAll(db, sql: """
                SELECT c.source_id FROM list_item_contribution c JOIN list_item i ON i.id = c.item_id
                WHERE i.list_memory_id = ? AND c.source_id IS NOT NULL
                UNION SELECT source_id FROM list_operation WHERE list_key = ?
                UNION SELECT source_id FROM memory_list_addition WHERE normalized_name = ? OR normalized_name LIKE ?
                """, arguments: [memory.id, record.normalizedName, record.normalizedName, record.normalizedName + " | %"])
        } ?? []
        _ = try memory.delete(db)
        var deletion = PermanentDeletion(memoryID: memory.id, deletedSourceID: nil, audioPathToRemove: nil)
        if let list {
            for sourceID in contributors where sourceID != memory.sourceID {
                guard let source = try orphanedContributor(db, sourceID, deletedList: list.normalizedName) else { continue }
                _ = try source.delete(db)
                deletion.orphanedSources.append(source.id)
                if let path = source.audioPath { deletion.orphanedAudioPaths.append(path) }
            }
        }
        let remaining = try Memory.filter(Column("source_id") == memory.sourceID).fetchCount(db)
        guard remaining == 0, let source = try Source.fetchOne(db, key: memory.sourceID) else { return deletion }
        _ = try source.delete(db)
        return PermanentDeletion(memoryID: memory.id, deletedSourceID: source.id, audioPathToRemove: source.audioPath,
                                 orphanedSources: deletion.orphanedSources, orphanedAudioPaths: deletion.orphanedAudioPaths)
    }

    /// F09 — une dictée qui n'existait plus que par ses ajouts à la liste supprimée : aucune note, aucune contribution à
    /// une autre liste, aucun ajout à une autre liste encore là.
    static func orphanedContributor(_ db: Database, _ sourceID: UUID, deletedList: String) throws -> Source? {
        guard try Memory.filter(Column("source_id") == sourceID).fetchCount(db) == 0,
              !(try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM list_item_contribution WHERE source_id = ?)",
                                  arguments: [sourceID]) ?? true) else { return nil }
        let otherLists = try String.fetchAll(db, sql: "SELECT normalized_name FROM memory_list_addition WHERE source_id = ?",
                                             arguments: [sourceID])
            .map { $0.components(separatedBy: " | ")[0] }
            .filter { $0 != deletedList }
        for key in otherLists {
            if try ListRecord.fetchOne(db, key: key) != nil { return nil }
        }
        return try Source.fetchOne(db, key: sourceID)
    }

    /// F09 — si ce souvenir est une liste, ses choses suivent son texte.
    static func syncListItems(_ db: Database, _ memory: Memory, actor: ChangeActor, now: Date) throws {
        guard try ListRecord.filter(Column("memory_id") == memory.id).fetchCount(db) > 0 else { return }
        try ListStore.syncItems(db, listMemoryID: memory.id, body: memory.summary ?? "", actor: actor, sourceID: nil,
                                now: now)
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
