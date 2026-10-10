import EngramCore
import Foundation
import GRDB

/// Une autre succursale d'un lieu, trouvée toute seule (table `place_branch`).
public struct PlaceBranch: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "place_branch" }
    public var id: UUID
    public var entityID: UUID
    public var latitude: Double
    public var longitude: Double
    public var radius: Double
    public var label: String?
    public var foundAt: Date

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, radius, label
        case entityID = "entity_id"
        case foundAt = "found_at"
    }
}

/// La dernière recherche automatique d'un lieu (table `place_lookup`) ; `manual` : le propriétaire a choisi (ou
/// retiré) l'adresse lui-même, Engram ne cherche plus jamais pour lui.
struct PlaceLookup: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "place_lookup" }
    var entityID: UUID
    var triedAt: Date
    var found: Int
    var manual: Bool

    enum CodingKeys: String, CodingKey {
        case found, manual
        case entityID = "entity_id"
        case triedAt = "tried_at"
    }
}

/// P30 — les adresses trouvées toutes seules : la succursale la plus proche devient l'adresse du lieu, les autres sont
/// surveillées aussi ; une recherche sans résultat n'est refaite qu'une semaine plus tard.
extension EntityStore {
    /// Un lieu sans résultat est recherché de nouveau après ce délai.
    public static let lookupRetry: TimeInterval = 7 * 86_400
    /// Le rayon d'une adresse trouvée toute seule.
    public static let foundRadius: Double = 200

    /// Les lieux qui attendent une adresse (un rappel de lieu, ou une liste à leur nom) et qu'on peut chercher.
    public func placesNeedingLocation() throws -> [EngramEntity] {
        let now = dates.now()
        return try database.writer.read { db in
            let people = try String.fetchAll(db, sql: "SELECT name FROM entity WHERE kind = 'person' AND status = 'active'")
            let places = try EngramEntity.fetchAll(db, sql: """
                SELECT e.* FROM entity e
                WHERE e.kind = 'place' AND e.status = 'active'
                  AND NOT EXISTS (SELECT 1 FROM place_location l WHERE l.entity_id = e.id)
                ORDER BY e.name
                """)
            guard !places.isEmpty else { return [] }
            let triggered = Set(try UUID.fetchAll(db, sql: """
                SELECT DISTINCT t.entity_id FROM place_trigger t JOIN memory m ON m.id = t.memory_id
                WHERE m.status IN ('active','unsorted')
                """))
            let listKeys = Set(try String.fetchAll(db, sql: """
                SELECT l.name FROM memory_list l JOIN memory m ON m.id = l.memory_id WHERE m.status IN ('active','unsorted')
                """).map(EntityName.key))
            let lookups = Dictionary(try PlaceLookup.fetchAll(db).map { ($0.entityID, $0) }, uniquingKeysWith: { first, _ in first })
            return places.filter { place in
                guard triggered.contains(place.id) || listKeys.contains(place.normalizedName),
                      PlaceFinder.canSearch(place.name, people: people) else { return false }
                guard let lookup = lookups[place.id] else { return true }
                return !lookup.manual && now.timeIntervalSince(lookup.triedAt) >= Self.lookupRetry
            }
        }
    }

    /// Enregistre une recherche : le premier résultat devient l'adresse, les autres des succursales. Sans résultat,
    /// rien ne change (et la recherche attend une semaine). Une adresse choisie par le propriétaire n'est pas touchée.
    public func recordLookup(_ placeID: UUID, found: [PlaceFinder.Result]) throws {
        let now = dates.now()
        try database.writer.write { db in
            if let lookup = try PlaceLookup.fetchOne(db, key: placeID), lookup.manual { return }
            if let first = found.first {
                try PlaceLocation(entityID: placeID, latitude: first.latitude, longitude: first.longitude,
                                  radius: Self.foundRadius, label: first.address ?? first.name, updatedAt: now).save(db)
                try PlaceBranch.filter(Column("entity_id") == placeID).deleteAll(db)
                for other in found.dropFirst() {
                    try PlaceBranch(id: UUID(), entityID: placeID, latitude: other.latitude, longitude: other.longitude,
                                    radius: Self.foundRadius, label: other.address ?? other.name, foundAt: now).insert(db)
                }
            }
            try PlaceLookup(entityID: placeID, triedAt: now, found: found.count, manual: false).save(db)
        }
    }

    public func branches(for placeID: UUID) throws -> [PlaceBranch] {
        try database.writer.read { db in try Self.branches(db, placeID) }
    }

    static func branches(_ db: Database, _ placeID: UUID) throws -> [PlaceBranch] {
        try PlaceBranch.fetchAll(db, sql: "SELECT * FROM place_branch WHERE entity_id = ? ORDER BY rowid", arguments: [placeID])
    }

    /// L'adresse a-t-elle été trouvée toute seule (et pas choisie par le propriétaire) ?
    public func isAutoLocated(_ placeID: UUID) throws -> Bool {
        try database.writer.read { db in
            guard let lookup = try PlaceLookup.fetchOne(db, key: placeID), !lookup.manual, lookup.found > 0 else { return false }
            return try PlaceLocation.exists(db, key: placeID)
        }
    }

    /// Le propriétaire choisit ou retire l'adresse : les succursales trouvées s'effacent, Engram ne cherche plus.
    static func markManual(_ db: Database, _ placeID: UUID, now: Date) throws {
        try PlaceBranch.filter(Column("entity_id") == placeID).deleteAll(db)
        try PlaceLookup(entityID: placeID, triedAt: now, found: 0, manual: true).save(db)
    }

    /// Les succursales d'un lieu, pour la surveillance.
    static func branchCoordinates(_ db: Database) throws -> [UUID: [PlaceReminderPlanner.Coordinates]] {
        Dictionary(grouping: try PlaceBranch.fetchAll(db, sql: "SELECT * FROM place_branch ORDER BY rowid"), by: \.entityID)
            .mapValues { branches in
                branches.map { PlaceReminderPlanner.Coordinates(latitude: $0.latitude, longitude: $0.longitude, radius: $0.radius) }
            }
    }
}
