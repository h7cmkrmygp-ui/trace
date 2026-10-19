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
    /// - Parameters:
    ///   - fallback: texte relu si `text` ne dit pas la fête (l'extrait de l'IA a pu perdre le début de la phrase, P31).
    ///   - saidOn: jour de la note (« fête ses 30 ans » donne l'année de naissance).
    ///   - keepKnown: une personne qui a déjà sa fête la garde (relecture des anciennes notes).
    /// - Returns: vrai si une fête a été posée.
    @discardableResult
    func recordBirthday(_ db: Database, memoryID: UUID, text: String, fallback: String? = nil, saidOn: Date? = nil,
                        calendar: Calendar = .current, keepKnown: Bool = false, now: Date) throws -> Bool {
        guard let parsed = BirthdayParser.parse(text) ?? fallback.flatMap(BirthdayParser.parse),
              let person = try resolve(db, name: parsed.person, kind: .person, now: now) else { return false }
        let known = try PersonBirthday.fetchOne(db, key: person.id)
        if keepKnown, known != nil { return false }
        _ = try link(db, memoryID: memoryID, entityID: person.id, origin: .ai, now: now)
        let year = parsed.birthYear(saidOn: saidOn ?? now, calendar: calendar)
            ?? (known?.month == parsed.month && known?.day == parsed.day ? known?.year : nil)
        try PersonBirthday(entityID: person.id, month: parsed.month, day: parsed.day, year: year, memoryID: memoryID,
                           updatedAt: now).save(db)
        return true
    }

    /// P31 — relit les anciennes notes pour y trouver les fêtes jamais retenues (une personne qui a déjà sa fête, posée à
    /// la main ou dite, la garde). Des plus récentes aux plus anciennes : la dernière fête dite l'emporte.
    /// Renvoie le nombre de fêtes posées.
    public func backfillBirthdays() throws -> Int {
        let now = dates.now()
        return try database.writer.write { db -> Int in
            let notes = try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m WHERE \(Self.countedNotes) ORDER BY m.captured_at DESC
                """)
            var posed = 0
            for memory in notes {
                // Le texte de la note, sa version rédigée, son titre ; puis la dictée entière si elle n'a donné qu'une note.
                var texts = [memory.content, memory.summary, memory.title].compactMap { $0 }
                let siblings = try Memory.filter(Column("source_id") == memory.sourceID).fetchCount(db)
                if siblings == 1, let whole = try Source.fetchOne(db, key: memory.sourceID)?.referenceText { texts.append(whole) }
                guard let text = texts.first(where: { BirthdayParser.parse($0) != nil }) else { continue }
                if try recordBirthday(db, memoryID: memory.id, text: text, saidOn: memory.capturedAt, keepKnown: true, now: now) {
                    posed += 1
                }
            }
            return posed
        }
    }

    /// Fusion : la personne gardée prend la fête de l'autre si elle n'en a pas.
    func moveBirthday(_ db: Database, from sourceID: UUID, to targetID: UUID) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO person_birthday (entity_id, month, day, year, memory_id, updated_at)
            SELECT ?, month, day, year, memory_id, updated_at FROM person_birthday WHERE entity_id = ?
            """, arguments: [targetID, sourceID])
    }
}
