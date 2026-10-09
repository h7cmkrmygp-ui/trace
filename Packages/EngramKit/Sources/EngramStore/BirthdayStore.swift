import EngramCore
import Foundation
import GRDB

/// La fête d'une personne (table `person_birthday`).
public struct PersonBirthday: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "person_birthday" }
    public var entityID: UUID
    public var month: Int
    public var day: Int
    public var year: Int?
    /// La note où elle a été dite (nil si posée à la main).
    public var memoryID: UUID?
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case month, day, year
        case entityID = "entity_id"
        case memoryID = "memory_id"
        case updatedAt = "updated_at"
    }
}

/// P20 — les fêtes des personnes.
extension EntityStore {
    public func birthday(for entityID: UUID) throws -> PersonBirthday? { nil }

    public func setBirthday(_ entityID: UUID, month: Int, day: Int, year: Int?) throws {}

    public func removeBirthday(_ entityID: UUID) throws {}

    public func birthdays() throws -> [Birthday] { [] }
}
