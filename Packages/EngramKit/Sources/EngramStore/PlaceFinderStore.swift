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

/// P30 — les adresses trouvées toutes seules.
extension EntityStore {
    public func placesNeedingLocation() throws -> [EngramEntity] { [] }

    public func recordLookup(_ placeID: UUID, found: [PlaceFinder.Result]) throws {}

    public func branches(for placeID: UUID) throws -> [PlaceBranch] { [] }

    public func isAutoLocated(_ placeID: UUID) throws -> Bool { false }
}
