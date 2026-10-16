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
    /// n'est jamais remplacée quand une dictée est reclassée. P41 : une liste existante est retrouvée même dite autrement
    /// (« anniversaire » pour « souhaits d'anniversaire ») ; `added` dit les choses ajoutées (pour le résumé).
    /// - Parameter perExcerpt: chaque passage de la dictée compte à part (l'IA peut ranger deux passages dans une liste).
    func add(_ db: Database, _ command: ListCommand, sourceID: UUID, excerpt: String, memoryStore: MemoryStore,
             now: Date, perExcerpt: Bool = false) throws -> (memory: Memory, created: Bool, added: [String]) {
        let name = try Self.resolvedName(db, command.listName)
        let key = ListCommandParser.key(name)
        let additionKey = perExcerpt ? key + " | " + TextNormalizer.matchingForm(excerpt) : key
        let alreadyAdded = try ListAddition.exists(db, key: ["source_id": sourceID, "normalized_name": additionKey])
        if let record = try ListRecord.fetchOne(db, key: key), var memory = try Memory.fetchOne(db, key: record.memoryID),
           memory.status != .trashed {
            guard !alreadyAdded else { return (memory, false, []) }
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
            try ListAddition(sourceID: sourceID, normalizedName: additionKey, addedAt: now).insert(db, onConflict: .ignore)
            try Self.restrict(db, key: key, by: sourceID)
            return (memory, false, merged.added)
        }
        let body = ListMerge.adding(command.items, to: "")
        let draft = MemoryDraft(sourceID: sourceID, excerpt: excerpt, title: ListCommandParser.title(for: name),
                                summary: body.body, content: excerpt, kind: .other,
                                status: .active, analysisVersion: ThoughtFiler.analysisVersion)
        var memory = try memoryStore.createMemory(db, draft: draft, actor: .user, now: now)
        memory.userEdited = true
        try memory.update(db)
        try ListRecord(normalizedName: key, name: name, memoryID: memory.id, createdAt: now).save(db)
        try ListAddition(sourceID: sourceID, normalizedName: additionKey, addedAt: now).insert(db, onConflict: .ignore)
        try Self.restrict(db, key: key, by: sourceID)
        return (memory, true, body.added)
    }

    /// P41 — le nom de la liste dont on parle : une liste existante (pas jetée) dite autrement, sinon le nom dit.
    static func resolvedName(_ db: Database, _ name: String) throws -> String {
        let existing = try String.fetchAll(db, sql: """
            SELECT l.name FROM memory_list l JOIN memory m ON m.id = l.memory_id
            WHERE m.status != 'trashed' ORDER BY m.updated_at DESC
            """)
        return ListResolver.resolve(name, existing: existing)
    }

    /// P41 — les noms des listes, pour que l'IA y ajoute plutôt que d'en créer d'autres.
    public func names() throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT l.name FROM memory_list l JOIN memory m ON m.id = l.memory_id
                WHERE m.status != 'trashed' ORDER BY m.updated_at DESC
                """)
        }
    }
}

/// P25 — ce que lit le widget « Liste ».
extension ListStore {
    /// Les listes vivantes, la plus récemment complétée d'abord, avec leur texte et leur discrétion (comme les rappels).
    public func widgetSources() throws -> [ListsSnapshot.Source] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT l.name AS name, m.id AS memory_id, m.title AS title, m.summary AS summary,
                       s.keep_local AS keep_local, s.privacy_level AS privacy_level, s.privacy_basis AS privacy_basis,
                       l.forbidden_mask AS list_mask
                FROM memory_list l JOIN memory m ON m.id = l.memory_id JOIN source s ON s.id = m.source_id
                WHERE m.status IN ('active','unsorted')
                ORDER BY m.updated_at DESC
                """).map { row in
                let body: String? = row["summary"]
                return ListsSnapshot.Source(memoryID: row["memory_id"], name: ListCommandParser.displayName(row["name"]),
                                            title: row["title"], body: body ?? "", isPrivate: MemoryStore.isPrivate(row))
            }
        }
    }
}

extension ListStore {
    /// F01 — les destinations interdites par toutes les dictées qui ont complété cette liste, sa première comprise.
    static func contributionMask(_ db: Database, key: String, memoryID: UUID) throws -> Int {
        var sourceIDs = Set<UUID>()
        if let first = try UUID.fetchOne(db, sql: "SELECT source_id FROM memory WHERE id = ?", arguments: [memoryID]) {
            sourceIDs.insert(first)
        }
        for row in try Row.fetchAll(db, sql: "SELECT source_id, normalized_name FROM memory_list_addition") {
            let name: String = row["normalized_name"]
            guard name.components(separatedBy: " | ")[0] == key else { continue }
            let id: UUID = row["source_id"]
            sourceIDs.insert(id)
        }
        var mask = 0
        for id in sourceIDs { mask |= try forbiddenMask(db, sourceID: id) }
        return mask
    }

    /// Les destinations interdites par une source (lue colonne par colonne : utilisable dans une migration).
    static func forbiddenMask(_ db: Database, sourceID: UUID) throws -> Int {
        guard let row = try Row.fetchOne(db, sql: "SELECT keep_local, privacy_level, privacy_basis FROM source WHERE id = ?",
                                         arguments: [sourceID]) else {
            return PrivacyPolicy.forbiddenMask(PrivacyFacts(keepLocal: false, level: nil, basis: nil))
        }
        return PrivacyPolicy.forbiddenMask(MemoryStore.privacyFacts(row))
    }
}

extension ListStore {
    /// F01 — la liste prend les interdictions de cette dictée (jamais retirées ensuite).
    static func restrict(_ db: Database, key: String, by sourceID: UUID) throws {
        let mask = try forbiddenMask(db, sourceID: sourceID)
        guard mask != 0 else { return }
        try db.execute(sql: "UPDATE memory_list SET forbidden_mask = forbidden_mask | ? WHERE normalized_name = ?",
                       arguments: [mask, key])
    }
}
