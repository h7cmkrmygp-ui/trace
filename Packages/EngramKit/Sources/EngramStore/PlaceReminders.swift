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

    public func setLocation(_ entityID: UUID, latitude: Double, longitude: Double, radius: Double, label: String?) throws {
        throw StoreError.notFound
    }

    public func removeLocation(_ entityID: UUID) throws {}

    public func location(for entityID: UUID) throws -> PlaceLocation? { nil }

    // MARK: - Rappels

    public func placeTrigger(for memoryID: UUID) throws -> PlaceTriggerInfo? { nil }

    @discardableResult
    public func setPlaceTrigger(for memoryID: UUID, placeNamed name: String, event: PlaceEvent) throws -> EngramEntity {
        throw StoreError.notFound
    }

    public func setPlaceTrigger(for memoryID: UUID, placeID: UUID, event: PlaceEvent) throws {
        throw StoreError.notFound
    }

    public func removePlaceTrigger(for memoryID: UUID) throws {}

    public func waitingReminders(at placeID: UUID) throws -> [Memory] { [] }

    public func placeReminderItems() throws -> [PlaceReminderPlanner.Item] { [] }
}
