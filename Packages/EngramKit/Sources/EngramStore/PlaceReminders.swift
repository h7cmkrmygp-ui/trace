import EngramCore
import Foundation
import GRDB

extension PlaceLocation: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "place_location" }
}

extension PlaceTrigger: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "place_trigger" }
}

/// Le rappel de lieu d'une note : le rappel, le lieu, et son adresse si elle est connue.
public struct PlaceTriggerInfo: Sendable, Equatable {
    public let trigger: PlaceTrigger
    public let place: EngramEntity
    public let location: PlaceLocation?
}

/// P14 — les adresses des lieux et les notes qui les attendent.
extension EntityStore {
    // MARK: - Adresse d'un lieu

    /// Pose (ou remplace) l'adresse d'un lieu. Une personne n'a pas d'adresse.
    public func setLocation(_ entityID: UUID, latitude: Double, longitude: Double, radius: Double, label: String?) throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude), radius > 0 else {
            throw StoreError.invalidOperation("Adresse invalide.")
        }
        let now = dates.now()
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.writer.write { db in
            guard let entity = try EngramEntity.fetchOne(db, key: entityID) else { throw StoreError.notFound }
            guard entity.kind == .place else { throw StoreError.invalidOperation("Seul un lieu a une adresse.") }
            try PlaceLocation(entityID: entityID, latitude: latitude, longitude: longitude, radius: radius,
                              label: trimmed?.isEmpty == false ? trimmed : nil, updatedAt: now).save(db)
        }
    }

    public func removeLocation(_ entityID: UUID) throws {
        try database.writer.write { db in _ = try PlaceLocation.deleteOne(db, key: entityID) }
    }

    public func location(for entityID: UUID) throws -> PlaceLocation? {
        try database.writer.read { db in try PlaceLocation.fetchOne(db, key: entityID) }
    }

    public func locationStream(for entityID: UUID) -> AsyncThrowingStream<PlaceLocation?, any Error> {
        database.stream { db in try PlaceLocation.fetchOne(db, key: entityID) }
    }

    // MARK: - Rappels

    public func placeTrigger(for memoryID: UUID) throws -> PlaceTriggerInfo? {
        try database.writer.read { db in try Self.placeTrigger(db, memoryID) }
    }

    public func placeTriggerStream(for memoryID: UUID) -> AsyncThrowingStream<PlaceTriggerInfo?, any Error> {
        database.stream { db in try Self.placeTrigger(db, memoryID) }
    }

    static func placeTrigger(_ db: Database, _ memoryID: UUID) throws -> PlaceTriggerInfo? {
        guard let trigger = try PlaceTrigger.fetchOne(db, key: memoryID),
              let place = try EngramEntity.fetchOne(db, key: trigger.entityID) else { return nil }
        return PlaceTriggerInfo(trigger: trigger, place: place, location: try PlaceLocation.fetchOne(db, key: place.id))
    }

    /// Le propriétaire pose un rappel vers un lieu nommé (créé s'il n'existe pas, réactivé s'il était masqué).
    @discardableResult
    public func setPlaceTrigger(for memoryID: UUID, placeNamed name: String, event: PlaceEvent) throws -> EngramEntity {
        guard EntityName.isAcceptable(name) else { throw StoreError.invalidName }
        let now = dates.now()
        return try database.writer.write { db in
            guard try Memory.exists(db, key: memoryID) else { throw StoreError.notFound }
            var entity = try existing(db, name: name, kind: .place) ?? create(db, name: name, kind: .place, now: now)
            if entity.status == .hidden {
                entity.status = .active
                entity.updatedAt = now
                try entity.update(db)
            }
            try setTrigger(db, memoryID: memoryID, place: entity, event: event, origin: .user, now: now)
            return entity
        }
    }

    /// Le propriétaire pose un rappel vers un lieu connu (ou change « en arrivant » pour « en partant »).
    public func setPlaceTrigger(for memoryID: UUID, placeID: UUID, event: PlaceEvent) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard try Memory.exists(db, key: memoryID), let place = try EngramEntity.fetchOne(db, key: placeID) else {
                throw StoreError.notFound
            }
            guard place.kind == .place else { throw StoreError.invalidOperation("Un rappel attend un lieu.") }
            try setTrigger(db, memoryID: memoryID, place: place, event: event, origin: .user, now: now)
        }
    }

    public func removePlaceTrigger(for memoryID: UUID) throws {
        try database.writer.write { db in _ = try PlaceTrigger.deleteOne(db, key: memoryID) }
    }

    /// Les notes vivantes qui attendent ce lieu, la plus récente d'abord.
    public func waitingReminders(at placeID: UUID) throws -> [Memory] {
        try database.writer.read { db in try Self.waitingReminders(db, at: placeID) }
    }

    public func waitingRemindersStream(at placeID: UUID) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in try Self.waitingReminders(db, at: placeID) }
    }

    static func waitingReminders(_ db: Database, at placeID: UUID) throws -> [Memory] {
        try Memory.fetchAll(db, sql: """
            SELECT m.* FROM memory m JOIN place_trigger t ON t.memory_id = m.id
            WHERE t.entity_id = ? AND m.status IN ('active','unsorted')
            ORDER BY t.created_at DESC, m.captured_at DESC
            """, arguments: [placeID])
    }

    /// Ce que l'iPhone peut surveiller : les notes vivantes, vérifiées, dont le lieu est actif (avec ou sans adresse :
    /// `PlaceReminderPlanner` ne garde que celles qui en ont une).
    public func placeReminderItems() throws -> [PlaceReminderPlanner.Item] {
        try database.writer.read { db in try Self.placeReminderItems(db) }
    }

    public func placeReminderItemsStream() -> AsyncThrowingStream<[PlaceReminderPlanner.Item], any Error> {
        database.stream { db in try Self.placeReminderItems(db) }
    }

    static func placeReminderItems(_ db: Database) throws -> [PlaceReminderPlanner.Item] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT m.id AS memory_id, m.title AS title, m.status AS status, t.event AS event, t.created_at AS created_at,
                   e.id AS place_id, e.name AS place_name, l.latitude AS latitude, l.longitude AS longitude,
                   l.radius AS radius, s.keep_local AS keep_local, s.privacy_level AS privacy_level,
                   s.route_reason AS route_reason
            FROM place_trigger t
            JOIN memory m ON m.id = t.memory_id
            JOIN source s ON s.id = m.source_id
            JOIN entity e ON e.id = t.entity_id
            LEFT JOIN place_location l ON l.entity_id = e.id
            WHERE m.status IN ('active','unsorted') AND e.status = 'active' AND s.needs_review = 0
            ORDER BY t.created_at DESC
            """)
        return rows.map { row in
            let status: String = row["status"]
            let event: String = row["event"]
            let latitude: Double? = row["latitude"]
            let longitude: Double? = row["longitude"]
            let radius: Double? = row["radius"]
            var location: PlaceReminderPlanner.Coordinates?
            if let latitude, let longitude, let radius {
                location = PlaceReminderPlanner.Coordinates(latitude: latitude, longitude: longitude, radius: radius)
            }
            return PlaceReminderPlanner.Item(
                memoryID: row["memory_id"], title: row["title"], status: MemoryStatus(rawValue: status) ?? .active,
                isPrivate: MemoryStore.isPrivate(row), placeID: row["place_id"], placeName: row["place_name"],
                event: PlaceEvent(rawValue: event) ?? .arrive, location: location, createdAt: row["created_at"])
        }
    }

    // MARK: - Au classement

    /// « quand j'arrive chez Costco » dans une pensée : le lieu est relié à la note et le rappel posé. Un rappel posé
    /// par le propriétaire n'est pas remplacé ; un lieu masqué n'est pas recréé.
    func recordPlaceTrigger(_ db: Database, memoryID: UUID, text: String, now: Date) throws {
        guard let parsed = PlaceTriggerParser.parse(text),
              try PlaceTrigger.fetchOne(db, key: memoryID)?.origin != .user,
              let place = try resolve(db, name: parsed.place, kind: .place, now: now) else { return }
        try setTrigger(db, memoryID: memoryID, place: place, event: parsed.event, origin: .ai, now: now)
    }

    func setTrigger(_ db: Database, memoryID: UUID, place: EngramEntity, event: PlaceEvent, origin: AssignmentOrigin,
                    now: Date) throws {
        _ = try link(db, memoryID: memoryID, entityID: place.id, origin: origin, now: now)
        try PlaceTrigger(memoryID: memoryID, entityID: place.id, event: event, origin: origin, createdAt: now).save(db)
    }

    /// Fusion de deux lieux : les rappels suivent le lieu gardé, et il prend l'adresse de l'autre s'il n'en a pas.
    func movePlaceReminders(_ db: Database, from sourceID: UUID, to targetID: UUID) throws {
        try db.execute(sql: "UPDATE place_trigger SET entity_id = ? WHERE entity_id = ?", arguments: [targetID, sourceID])
        try db.execute(sql: """
            INSERT OR IGNORE INTO place_location (entity_id, latitude, longitude, radius, label, updated_at)
            SELECT ?, latitude, longitude, radius, label, updated_at FROM place_location WHERE entity_id = ?
            """, arguments: [targetID, sourceID])
    }
}
