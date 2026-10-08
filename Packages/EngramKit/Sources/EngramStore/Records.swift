import EngramCore
import GRDB

// Persistance GRDB des types du domaine (encodage Codable, clés snake_case définies dans EngramCore).

extension Source: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "source" }
}

extension Memory: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory" }
}

extension MemoryVersion: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory_version" }
}

extension EngramCategory: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "category" }
}

extension EngramTag: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "tag" }
}

extension CategoryAssignment: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory_category" }
}

extension TagAssignment: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "memory_tag" }
}

extension SourceKind: @retroactive DatabaseValueConvertible {}
extension ProcessingStatus: @retroactive DatabaseValueConvertible {}
extension MemoryStatus: @retroactive DatabaseValueConvertible {}
extension MemoryKind: @retroactive DatabaseValueConvertible {}
extension TextVersion: @retroactive DatabaseValueConvertible {}
extension Origin: @retroactive DatabaseValueConvertible {}
extension AssignmentOrigin: @retroactive DatabaseValueConvertible {}
extension ChangeActor: @retroactive DatabaseValueConvertible {}
extension CategoryStatus: @retroactive DatabaseValueConvertible {}
