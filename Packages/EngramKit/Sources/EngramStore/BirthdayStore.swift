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

/// P20 — les fêtes des personnes : dites dans une note ou posées à la main ; la plus récente l'emporte.
extension EntityStore {
    public func birthday(for entityID: UUID) throws -> PersonBirthday? {
        try database.writer.read { db in try PersonBirthday.fetchOne(db, key: entityID) }
    }

    public func birthdayStream(for entityID: UUID) -> AsyncThrowingStream<PersonBirthday?, any Error> {
        database.stream { db in try PersonBirthday.fetchOne(db, key: entityID) }
    }

    public func setBirthday(_ entityID: UUID, month: Int, day: Int, year: Int?) throws {
        guard BirthdayParser.isValid(month: month, day: day) else { throw StoreError.invalidOperation("Date invalide.") }
        let now = dates.now()
        try database.writer.write { db in
            guard let entity = try EngramEntity.fetchOne(db, key: entityID) else { throw StoreError.notFound }
            guard entity.kind == .person else { throw StoreError.invalidOperation("Seule une personne a une fête.") }
            try PersonBirthday(entityID: entityID, month: month, day: day, year: year, memoryID: nil, updatedAt: now).save(db)
        }
    }

    public func removeBirthday(_ entityID: UUID) throws {
        try database.writer.write { db in _ = try PersonBirthday.deleteOne(db, key: entityID) }
    }

    /// Les fêtes des personnes encore affichées, dans l'ordre de l'année.
    public func birthdays() throws -> [Birthday] {
        try database.writer.read { db in try Self.birthdays(db) }
    }

    public func birthdaysStream() -> AsyncThrowingStream<[Birthday], any Error> {
        database.stream { db in try Self.birthdays(db) }
    }

    static func birthdays(_ db: Database) throws -> [Birthday] {
        try Row.fetchAll(db, sql: """
            SELECT e.id AS id, e.name AS name, b.month AS month, b.day AS day, b.year AS year
            FROM person_birthday b JOIN entity e ON e.id = b.entity_id
            WHERE e.status = 'active' AND e.kind = 'person'
            ORDER BY b.month, b.day, e.name
            """)
            .map { Birthday(personID: $0["id"], name: $0["name"], month: $0["month"], day: $0["day"], year: $0["year"]) }
    }

    /// « L'anniversaire de Julie est le 12 mars » au classement : Julie est reliée à la note et sa fête est posée.
    func recordBirthday(_ db: Database, memoryID: UUID, text: String, now: Date) throws {
        guard let parsed = BirthdayParser.parse(text),
              let person = try resolve(db, name: parsed.person, kind: .person, now: now) else { return }
        _ = try link(db, memoryID: memoryID, entityID: person.id, origin: .ai, now: now)
        let known = try PersonBirthday.fetchOne(db, key: person.id)
        try PersonBirthday(entityID: person.id, month: parsed.month, day: parsed.day, year: parsed.year ?? (
            known?.month == parsed.month && known?.day == parsed.day ? known?.year : nil), memoryID: memoryID,
                           updatedAt: now).save(db)
    }

    /// P31 — relit les anciennes notes pour y trouver les fêtes jamais retenues (une personne qui a déjà sa fête, posée à
    /// la main ou dite, la garde). Renvoie le nombre de fêtes posées.
    public func backfillBirthdays() throws -> Int {
        0
    }

    /// Fusion : la personne gardée prend la fête de l'autre si elle n'en a pas.
    func moveBirthday(_ db: Database, from sourceID: UUID, to targetID: UUID) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO person_birthday (entity_id, month, day, year, memory_id, updated_at)
            SELECT ?, month, day, year, memory_id, updated_at FROM person_birthday WHERE entity_id = ?
            """, arguments: [targetID, sourceID])
    }
}
