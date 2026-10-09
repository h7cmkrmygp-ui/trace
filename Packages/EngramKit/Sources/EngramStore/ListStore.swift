import EngramCore
import Foundation
import GRDB

/// Une liste et sa note (table `memory_list`) : une par nom (« épicerie », « cadeaux »).
public struct ListRecord: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_list" }
    public var normalizedName: String
    /// Le nom tel qu'il a été dit (« épicerie », « Costco »).
    public var name: String
    public var memoryID: UUID
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case normalizedName = "normalized_name"
        case memoryID = "memory_id"
        case createdAt = "created_at"
    }
}

/// Une dictée déjà ajoutée à une liste (table `memory_list_addition`) : reclassée, elle n'y est pas remise.
public struct ListAddition: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_list_addition" }
    public var sourceID: UUID
    public var normalizedName: String
    public var addedAt: Date

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case normalizedName = "normalized_name"
        case addedAt = "added_at"
    }
}

/// P15 — les listes (épicerie, cadeaux…) : une note par liste, complétée à chaque « ajoute … à ma liste ».
public struct ListStore: Sendable {
    /// Une liste, pour la carte « Listes » des Notes.
    public struct Summary: Sendable, Equatable, Identifiable {
        public let memoryID: UUID
        /// « Épicerie ».
        public let name: String
        /// « Liste d'épicerie » (le titre de la note, qui peut avoir été renommée).
        public let title: String
        public let open: Int
        public let done: Int
        public let updatedAt: Date
        public var id: UUID { memoryID }
    }

    public let database: AppDatabase
    public let dates: any DateProvider

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    // MARK: - Lecture

    /// Les listes vivantes, la plus récemment complétée d'abord.
    public func lists() throws -> [Summary] {
        try database.writer.read { db in try Self.lists(db) }
    }

    public func listsStream() -> AsyncThrowingStream<[Summary], any Error> {
        database.stream { db in try Self.lists(db) }
    }

    static func lists(_ db: Database) throws -> [Summary] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT l.name AS name, m.id AS memory_id, m.title AS title, m.summary AS summary, m.updated_at AS updated_at
            FROM memory_list l JOIN memory m ON m.id = l.memory_id
            WHERE m.status IN ('active','unsorted')
            ORDER BY m.updated_at DESC
            """)
        return rows.map { row in
            let summary: String? = row["summary"]
            let progress = NoteBody.progress(of: summary) ?? (done: 0, total: 0)
            return Summary(memoryID: row["memory_id"], name: ListCommandParser.displayName(row["name"]), title: row["title"],
                           open: progress.total - progress.done, done: progress.done, updatedAt: row["updated_at"])
        }
    }

    // MARK: - Au classement

    /// Ajoute les choses dites à la liste (créée si elle n'existe pas, ou si elle a été jetée). Une dictée déjà ajoutée
    /// à cette liste n'y est pas remise (une case cochée depuis le reste). La liste appartient au propriétaire : elle
    /// n'est jamais remplacée quand une dictée est reclassée.
    func add(_ db: Database, _ command: ListCommand, sourceID: UUID, excerpt: String, memoryStore: MemoryStore,
             now: Date) throws -> (memory: Memory, created: Bool) {
        let key = ListCommandParser.key(command.listName)
        let alreadyAdded = try ListAddition.exists(db, key: ["source_id": sourceID, "normalized_name": key])
        if let record = try ListRecord.fetchOne(db, key: key), var memory = try Memory.fetchOne(db, key: record.memoryID),
           memory.status != .trashed {
            guard !alreadyAdded else { return (memory, false) }
            let merged = ListMerge.adding(command.items, to: memory.summary ?? "")
            if merged.body != (memory.summary ?? "") || memory.status == .archived {
                memory.summary = merged.body
                // Une liste archivée qu'on complète redevient active.
                if memory.status == .archived { memory.status = .active }
                memory.userEdited = true
                memory.version += 1
                memory.updatedAt = now
                try memory.update(db)
                try MemoryVersion(memory: memory, changedBy: .user, reason: "ajouté à la liste", at: now).insert(db)
            }
            try ListAddition(sourceID: sourceID, normalizedName: key, addedAt: now).insert(db, onConflict: .ignore)
            return (memory, false)
        }
        let draft = MemoryDraft(sourceID: sourceID, excerpt: excerpt, title: ListCommandParser.title(for: command.listName),
                                summary: ListMerge.adding(command.items, to: "").body, content: excerpt, kind: .other,
                                status: .active, analysisVersion: ThoughtFiler.analysisVersion)
        var memory = try memoryStore.createMemory(db, draft: draft, actor: .user, now: now)
        memory.userEdited = true
        try memory.update(db)
        try ListRecord(normalizedName: key, name: command.listName, memoryID: memory.id, createdAt: now).save(db)
        try ListAddition(sourceID: sourceID, normalizedName: key, addedAt: now).insert(db, onConflict: .ignore)
        return (memory, true)
    }
}
