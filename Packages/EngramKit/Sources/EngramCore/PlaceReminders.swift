import Foundation

/// P14 — arriver à un lieu, ou en partir.
public enum PlaceEvent: String, Codable, Sendable, CaseIterable {
    case arrive, leave
}

/// « quand j'arrive chez Costco » : le lieu dit (tel quel, sans article) et le moment.
public struct ParsedPlaceTrigger: Sendable, Equatable {
    public let place: String
    public let event: PlaceEvent

    public init(place: String, event: PlaceEvent) {
        self.place = place
        self.event = event
    }
}

/// Reconnaît, sur l'iPhone et sans IA, un rappel qui attend un lieu.
public enum PlaceTriggerParser {
    public static func parse(_ text: String) -> ParsedPlaceTrigger? {
        nil
    }
}

/// L'adresse d'un lieu : un cercle autour d'un point (table `place_location`).
public struct PlaceLocation: Codable, Sendable, Equatable {
    public var entityID: UUID
    public var latitude: Double
    public var longitude: Double
    /// Rayon en mètres.
    public var radius: Double
    /// L'adresse lisible (« 123, rue Inventée »), si elle est connue.
    public var label: String?
    public var updatedAt: Date

    public init(entityID: UUID, latitude: Double, longitude: Double, radius: Double, label: String?, updatedAt: Date) {
        self.entityID = entityID
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.label = label
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, radius, label
        case entityID = "entity_id"
        case updatedAt = "updated_at"
    }
}

/// Une note qui attend un lieu (table `place_trigger`, une par note).
public struct PlaceTrigger: Codable, Sendable, Equatable {
    public var memoryID: UUID
    public var entityID: UUID
    public var event: PlaceEvent
    public var origin: AssignmentOrigin
    public var createdAt: Date

    public init(memoryID: UUID, entityID: UUID, event: PlaceEvent, origin: AssignmentOrigin, createdAt: Date) {
        self.memoryID = memoryID
        self.entityID = entityID
        self.event = event
        self.origin = origin
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case event, origin
        case memoryID = "memory_id"
        case entityID = "entity_id"
        case createdAt = "created_at"
    }
}

/// Ce que l'iPhone surveille : les notes vivantes dont le lieu a une adresse.
public enum PlaceReminderPlanner {
    public static let identifierPrefix = "engram.place."
    /// iOS surveille au plus 20 régions par app.
    public static let maximum = 20

    public struct Coordinates: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double
        public let radius: Double

        public init(latitude: Double, longitude: Double, radius: Double) {
            self.latitude = latitude
            self.longitude = longitude
            self.radius = radius
        }
    }

    public struct Item: Sendable, Equatable {
        public let memoryID: UUID
        public let title: String
        public let status: MemoryStatus
        /// Note gardée sur l'iPhone (secrète), ou Engram verrouillé : rien sur l'écran verrouillé.
        public let isPrivate: Bool
        public let placeID: UUID
        public let placeName: String
        public let event: PlaceEvent
        public let location: Coordinates?
        public let createdAt: Date

        public init(memoryID: UUID, title: String, status: MemoryStatus, isPrivate: Bool, placeID: UUID, placeName: String,
                    event: PlaceEvent, location: Coordinates?, createdAt: Date) {
            self.memoryID = memoryID
            self.title = title
            self.status = status
            self.isPrivate = isPrivate
            self.placeID = placeID
            self.placeName = placeName
            self.event = event
            self.location = location
            self.createdAt = createdAt
        }
    }

    public struct Planned: Sendable, Equatable {
        public let identifier: String
        public let memoryID: UUID
        public let title: String
        public let body: String
        public let event: PlaceEvent
        public let latitude: Double
        public let longitude: Double
        public let radius: Double
    }

    public static func plan(_ items: [Item], limit: Int = maximum) -> [Planned] {
        []
    }
}
