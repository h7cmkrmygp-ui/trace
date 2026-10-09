import EngramCore
import GRDB

// Persistance GRDB des types du domaine (encodage Codable, clés snake_case définies dans EngramCore).

extension Source: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "source" }
}

extension Memory: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory" }
}

extension MemoryVersion: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_version" }
}

extension EngramCategory: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "category" }
}

extension EngramTag: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "tag" }
}

extension CategoryAssignment: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_category" }
}

extension TagAssignment: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_tag" }
}

extension SourceKind: DatabaseValueConvertible {}
extension ProcessingStatus: DatabaseValueConvertible {}
extension MemoryStatus: DatabaseValueConvertible {}
extension MemoryKind: DatabaseValueConvertible {}
extension TextVersion: DatabaseValueConvertible {}
extension Origin: DatabaseValueConvertible {}
extension AssignmentOrigin: DatabaseValueConvertible {}
extension ChangeActor: DatabaseValueConvertible {}
extension CategoryStatus: DatabaseValueConvertible {}

// P9 — personnes et lieux.

extension EngramEntity: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "entity" }
}

extension EntityAlias: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "entity_alias" }
}

extension EntityAssignment: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "memory_entity" }
}

extension EntityKind: DatabaseValueConvertible {}
extension EntityStatus: DatabaseValueConvertible {}
