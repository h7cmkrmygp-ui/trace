import EngramCore
import Foundation
import GRDB

/// P9 — les personnes et les lieux : pages, liens avec les notes, et décisions du propriétaire. Comme pour les
/// catégories, l'IA n'écrase jamais un choix du propriétaire (un nom retiré d'une note n'y revient pas).
public struct EntityStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    /// Une ligne de la liste « Personnes » ou « Lieux ».
    public struct Summary: Sendable, Equatable, Identifiable {
        public let entity: EngramEntity
        /// Notes vivantes ou faites (jamais la corbeille).
        public let noteCount: Int
        /// Tâches et rendez-vous pas encore faits.
        public let openTaskCount: Int
        public let lastMentionedAt: Date?
        public var id: UUID { entity.id }
    }

    /// Notes qui comptent : vivantes ou faites, jamais la corbeille ni les dictées qui attendent « Vérifie ta note ».
    static let countedNotes = """
        m.status IN ('active','unsorted','archived')
        AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
        """

    // MARK: - Lecture

    public func summaries(kind: EntityKind) throws -> [Summary] {
        try database.writer.read { db in try Self.summaries(db, kind: kind) }
    }

    public func summariesStream(kind: EntityKind) -> AsyncThrowingStream<[Summary], any Error> {
        database.stream { db in try Self.summaries(db, kind: kind) }
    }

    /// Les personnes (ou les lieux) dont parle au moins une note, la plus récemment nommée d'abord.
    static func summaries(_ db: Database, kind: EntityKind) throws -> [Summary] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.*, COUNT(m.id) AS note_count,
                   SUM(CASE WHEN m.kind IN ('task','appointment') AND m.status IN ('active','unsorted') THEN 1 ELSE 0 END)
                       AS open_count,
                   MAX(m.captured_at) AS last_at
            FROM entity e
            JOIN memory_entity me ON me.entity_id = e.id AND me.rejected = 0
            JOIN memory m ON m.id = me.memory_id
            WHERE e.kind = ? AND e.status = 'active' AND \(countedNotes)
            GROUP BY e.id
            ORDER BY last_at DESC, e.name
            """, arguments: [kind.rawValue])
        return try rows.map { row in
            Summary(entity: try EngramEntity(row: row), noteCount: row["note_count"], openTaskCount: row["open_count"] ?? 0,
                    lastMentionedAt: row["last_at"])
        }
    }

    /// Les personnes et les lieux d'une note (ni retirés par le propriétaire, ni masqués).
    public func entities(for memoryID: UUID) throws -> [EngramEntity] {
        try database.writer.read { db in try Self.entities(db, for: memoryID) }
    }

    public func entitiesStream(for memoryID: UUID) -> AsyncThrowingStream<[EngramEntity], any Error> {
        database.stream { db in try Self.entities(db, for: memoryID) }
    }

    static func entities(_ db: Database, for memoryID: UUID) throws -> [EngramEntity] {
        try EngramEntity.fetchAll(db, sql: """
            SELECT e.* FROM entity e JOIN memory_entity me ON me.entity_id = e.id
            WHERE me.memory_id = ? AND me.rejected = 0 AND e.status = 'active'
            ORDER BY e.kind, e.name
            """, arguments: [memoryID])
    }

    /// Les notes d'une personne ou d'un lieu, de la plus récente à la plus ancienne.
    public func memories(for entityID: UUID) throws -> [Memory] {
        try database.writer.read { db in try Self.memories(db, for: entityID) }
    }

    public func memoriesStream(for entityID: UUID) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in try Self.memories(db, for: entityID) }
    }

    static func memories(_ db: Database, for entityID: UUID) throws -> [Memory] {
        try Memory.fetchAll(db, sql: """
            SELECT m.* FROM memory m JOIN memory_entity me ON me.memory_id = m.id
            WHERE me.entity_id = ? AND me.rejected = 0 AND \(countedNotes)
            ORDER BY m.captured_at DESC
            """, arguments: [entityID])
    }

    /// Une personne (ou un lieu) et ses notes vivantes, pour le Cerveau.
    public struct Links: Sendable, Equatable, Identifiable {
        public let entity: EngramEntity
        public let memoryIDs: [UUID]
        public var id: UUID { entity.id }
    }

    public func links(kind: EntityKind) throws -> [Links] {
        try database.writer.read { db in try Self.links(db, kind: kind) }
    }

    public func linksStream(kind: EntityKind) -> AsyncThrowingStream<[Links], any Error> {
        database.stream { db in try Self.links(db, kind: kind) }
    }

    /// Les mêmes notes que le Cerveau : vivantes, jamais faites ni à la corbeille, jamais en attente de vérification.
    static func links(_ db: Database, kind: EntityKind) throws -> [Links] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT me.entity_id AS entity_id, me.memory_id AS memory_id FROM memory_entity me
            JOIN entity e ON e.id = me.entity_id
            JOIN memory m ON m.id = me.memory_id
            WHERE me.rejected = 0 AND e.kind = ? AND e.status = 'active' AND m.status IN ('active','unsorted')
              AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
            ORDER BY m.captured_at
            """, arguments: [kind.rawValue])
        var notes: [UUID: [UUID]] = [:]
        for row in rows {
            let entityID: UUID = row["entity_id"]
            let memoryID: UUID = row["memory_id"]
            notes[entityID, default: []].append(memoryID)
        }
        return try EngramEntity.filter(keys: Array(notes.keys)).order(Column("name")).fetchAll(db)
            .map { Links(entity: $0, memoryIDs: notes[$0.id] ?? []) }
    }

    public func entity(id: UUID) throws -> EngramEntity? {
        try database.writer.read { db in try EngramEntity.fetchOne(db, key: id) }
    }

    /// Toutes les personnes (ou tous les lieux) actifs, par nom : pour fusionner ou proposer un nom.
    public func allEntities(kind: EntityKind) throws -> [EngramEntity] {
        try database.writer.read { db in
            try EngramEntity.filter(Column("kind") == kind.rawValue && Column("status") == EntityStatus.active.rawValue)
                .order(Column("name")).fetchAll(db)
        }
    }

    // MARK: - Décisions du propriétaire

    /// Ajoute un nom à une note (et le réactive s'il avait été masqué : le propriétaire l'a voulu).
    @discardableResult
    public func addEntity(named name: String, kind: EntityKind, to memoryID: UUID) throws -> EngramEntity {
        guard EntityName.isAcceptable(name) else { throw StoreError.invalidName }
        let now = dates.now()
        return try database.writer.write { db in
            guard try Memory.exists(db, key: memoryID) else { throw StoreError.notFound }
            var entity = try existing(db, name: name, kind: kind) ?? create(db, name: name, kind: kind, now: now)
            if entity.status == .hidden {
                entity.status = .active
                entity.updatedAt = now
                try entity.update(db)
            }
            _ = try link(db, memoryID: memoryID, entityID: entity.id, origin: .user, now: now)
            return entity
        }
    }

    /// Retire un nom d'une note : le lien est gardé « rejeté », l'IA ne le remettra pas.
    public func removeEntity(_ entityID: UUID, from memoryID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try EntityAssignment.fetchOne(db, key: ["memory_id": memoryID, "entity_id": entityID]) else { return }
            try AssignmentRules.remove(db, row: row, by: .user, now: now)
        }
    }

    /// Renomme ; vers un nom qui existe déjà, c'est une fusion. Renvoie la personne (ou le lieu) gardée.
    @discardableResult
    public func rename(_ entityID: UUID, to name: String) throws -> EngramEntity {
        guard EntityName.isAcceptable(name) else { throw StoreError.invalidName }
        let now = dates.now()
        return try database.writer.write { db in
            guard var entity = try EngramEntity.fetchOne(db, key: entityID) else { throw StoreError.notFound }
            let key = EntityName.key(name)
            if key != entity.normalizedName, let other = try existing(db, name: name, kind: entity.kind), other.id != entityID {
                try merge(db, entityID, into: other.id, now: now)
                guard let kept = try EngramEntity.fetchOne(db, key: other.id) else { throw StoreError.notFound }
                return kept
            }
            if key != entity.normalizedName {
                // L'ancien nom mène toujours ici ; le nouveau n'est plus l'alias de personne.
                try EntityAlias(kind: entity.kind, normalizedName: entity.normalizedName, entityID: entity.id).save(db)
                try EntityAlias.filter(Column("kind") == entity.kind.rawValue && Column("normalized_name") == key).deleteAll(db)
                entity.normalizedName = key
            }
            entity.name = EntityName.display(name, kind: entity.kind)
            entity.updatedAt = now
            try entity.update(db)
            return entity
        }
    }

    /// Fusionne `sourceID` dans `targetID` : les notes passent à la personne gardée, l'ancien nom en devient un alias.
    public func merge(_ sourceID: UUID, into targetID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in try merge(db, sourceID, into: targetID, now: now) }
    }

    func merge(_ db: Database, _ sourceID: UUID, into targetID: UUID, now: Date) throws {
        guard sourceID != targetID, let source = try EngramEntity.fetchOne(db, key: sourceID),
              var target = try EngramEntity.fetchOne(db, key: targetID), source.kind == target.kind else {
            throw StoreError.invalidOperation("Fusion impossible.")
        }
        for row in try EntityAssignment.filter(Column("entity_id") == sourceID).fetchAll(db) {
            if var kept = try EntityAssignment.fetchOne(db, key: ["memory_id": row.memoryID, "entity_id": targetID]) {
                // Une décision du propriétaire l'emporte sur un lien posé par l'IA.
                if row.origin == .user && kept.origin != .user {
                    kept.origin = .user
                    kept.confirmed = row.confirmed
                    kept.rejected = row.rejected
                    kept.updatedAt = now
                    try kept.update(db)
                }
            } else {
                var moved = EntityAssignment(memoryID: row.memoryID, entityID: targetID, origin: row.origin,
                                             confirmed: row.confirmed, rejected: row.rejected, now: now)
                moved.createdAt = row.createdAt
                try moved.insert(db)
            }
        }
        try db.execute(sql: "UPDATE entity_alias SET entity_id = ? WHERE entity_id = ?", arguments: [targetID, sourceID])
        _ = try source.delete(db)
        try EntityAlias(kind: source.kind, normalizedName: source.normalizedName, entityID: targetID).save(db)
        target.updatedAt = now
        try target.update(db)
    }

    /// « Ce n'est pas une personne / un lieu » : la page disparaît, et l'IA ne recrée plus ce nom.
    public func hide(_ entityID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var entity = try EngramEntity.fetchOne(db, key: entityID) else { throw StoreError.notFound }
            entity.status = .hidden
            entity.updatedAt = now
            try entity.update(db)
        }
    }

    // MARK: - Anciennes notes

    /// Relit, sur l'iPhone, les notes qui n'ont encore aucun nom. Renvoie le nombre de liens posés.
    public func backfill(using recognizer: any EntityRecognizer) throws -> Int {
        let now = dates.now()
        let candidates = try database.writer.read { db in
            try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m
                WHERE \(Self.countedNotes) AND NOT EXISTS (SELECT 1 FROM memory_entity me WHERE me.memory_id = m.id)
                """)
        }
        var linked = 0
        for memory in candidates {
            let text = memory.title == memory.content ? memory.content : memory.title + ". " + memory.content
            let found = recognizer.names(in: text)
            let people = EntityName.clean(found.filter { $0.kind == .person }.map(\.name), in: text,
                                          limit: AnalysisValidator.maxNames)
            let places = EntityName.clean(found.filter { $0.kind == .place }.map(\.name), in: text,
                                          limit: AnalysisValidator.maxNames)
            guard !people.isEmpty || !places.isEmpty else { continue }
            linked += try database.writer.write { db -> Int in
                try linkNames(db, people: people, places: places, to: memory.id, now: now)
            }
        }
        return linked
    }

    // MARK: - Au classement

    /// Relie les noms d'une pensée à sa note (origine IA). Un nom masqué ou inutilisable est ignoré.
    @discardableResult
    func linkNames(_ db: Database, people: [String], places: [String], to memoryID: UUID, now: Date) throws -> Int {
        var linked = 0
        for (names, kind) in [(people, EntityKind.person), (places, EntityKind.place)] {
            for name in names {
                guard let entity = try resolve(db, name: name, kind: kind, now: now) else { continue }
                if try link(db, memoryID: memoryID, entityID: entity.id, origin: .ai, now: now) == .assigned { linked += 1 }
            }
        }
        return linked
    }

    /// La personne (ou le lieu) de ce nom, par son alias ou sa clé ; créée si elle n'existe pas. nil si elle est masquée.
    func resolve(_ db: Database, name: String, kind: EntityKind, now: Date) throws -> EngramEntity? {
        guard EntityName.isAcceptable(name) else { return nil }
        if let found = try existing(db, name: name, kind: kind) { return found.status == .active ? found : nil }
        return try create(db, name: name, kind: kind, now: now)
    }

    func existing(_ db: Database, name: String, kind: EntityKind) throws -> EngramEntity? {
        let key = EntityName.key(name)
        if let alias = try EntityAlias.fetchOne(db, key: ["kind": kind.rawValue, "normalized_name": key]),
           let entity = try EngramEntity.fetchOne(db, key: alias.entityID) {
            return entity
        }
        return try EngramEntity.filter(Column("kind") == kind.rawValue && Column("normalized_name") == key).fetchOne(db)
    }

    func create(_ db: Database, name: String, kind: EntityKind, now: Date) throws -> EngramEntity {
        var entity = EngramEntity(kind: kind, name: EntityName.display(name, kind: kind), now: now)
        entity.normalizedName = EntityName.key(name)
        try entity.insert(db)
        return entity
    }

    func link(_ db: Database, memoryID: UUID, entityID: UUID, origin: AssignmentOrigin, now: Date) throws -> AssignmentOutcome {
        let existing = try EntityAssignment.fetchOne(db, key: ["memory_id": memoryID, "entity_id": entityID])
        return try AssignmentRules.assign(db, existing: existing, makeNew: {
            EntityAssignment(memoryID: memoryID, entityID: entityID, origin: origin, confirmed: origin == .user, now: now)
        }, origin: origin, now: now)
    }
}
