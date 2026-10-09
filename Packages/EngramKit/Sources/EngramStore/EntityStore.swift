import EngramCore
import Foundation
import GRDB

/// P9 — les personnes et les lieux : pages, liens avec les notes, et décisions du propriétaire.
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

    public func summaries(kind: EntityKind) throws -> [Summary] { [] }

    public func entities(for memoryID: UUID) throws -> [EngramEntity] { [] }

    public func memories(for entityID: UUID) throws -> [Memory] { [] }

    public func entity(id: UUID) throws -> EngramEntity? { nil }

    @discardableResult
    public func addEntity(named name: String, kind: EntityKind, to memoryID: UUID) throws -> EngramEntity {
        throw StoreError.invalidOperation("à venir")
    }

    public func removeEntity(_ entityID: UUID, from memoryID: UUID) throws {}

    @discardableResult
    public func rename(_ entityID: UUID, to name: String) throws -> EngramEntity {
        throw StoreError.invalidOperation("à venir")
    }

    public func merge(_ sourceID: UUID, into targetID: UUID) throws {}

    public func hide(_ entityID: UUID) throws {}

    public func backfill(using recognizer: any EntityRecognizer) throws -> Int { 0 }

    func link(_ db: Database, memoryID: UUID, entityID: UUID, origin: AssignmentOrigin, now: Date) throws -> AssignmentOutcome {
        .assigned
    }
}
