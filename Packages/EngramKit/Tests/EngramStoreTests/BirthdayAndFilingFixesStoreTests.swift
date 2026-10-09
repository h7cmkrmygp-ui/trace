import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P31 — les anciennes notes : les fêtes jamais retenues sont relues, et un suivi (« Poids ») rend les notes qui
/// n'y ont rien à faire.
struct BirthdayAndFilingFixesStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String], people: [String] = []) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .info, tags: [],
                                   categoryPath: path, mentionedDates: [], people: people)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func oldNotesGiveTheirBirthdaysToThePeople() throws {
        let env = try StoreTestEnvironment()
        let people = EntityStore(database: env.database, dates: env.dates)
        _ = try file(env, "Retiens la fête à Amina, c'est le 13 octobre", path: ["Famille"])
        _ = try file(env, "L'anniversaire de Marc est le 5 avril", path: ["Famille"])
        // Des notes d'avant ce correctif : la fête n'avait pas été retenue.
        try env.database.writer.write { db in try db.execute(sql: "DELETE FROM person_birthday") }
        // Une fête posée à la main n'est jamais remplacée par la relecture.
        let marc = try #require(try people.allEntities(kind: .person).first { $0.name == "Marc" })
        try people.setBirthday(marc.id, month: 6, day: 3, year: nil)
        #expect(try people.backfillBirthdays() == 1)
        #expect(try people.birthdays().map { "\($0.name) \($0.day)/\($0.month)" }.sorted() == ["Amina 13/10", "Marc 3/6"])
        // Relancée : rien de plus.
        #expect(try people.backfillBirthdays() == 0)
    }

    @Test func aTrackerKeepsOnlyItsMeasurements() throws {
        let env = try StoreTestEnvironment()
        let categories = env.categories
        let birthday = try file(env, "Retiens l'anniversaire de Amina c'est le 13 octobre", path: ["Santé", "Poids"])
        let weight = try file(env, "Je pèse 162,5 livres", path: ["Santé", "Poids"])
        let chosen = try file(env, "Souper chez Amina", path: ["Santé", "Poids"])
        // Rangée là par le propriétaire lui-même : on n'y touche pas.
        let poids = try #require(try categories.categories(for: chosen.id).first)
        try categories.confirm(memoryID: chosen.id, categoryID: poids.id)

        #expect(try categories.removeMisfiledFromTrackers() == 1)
        #expect(try categories.categories(for: birthday.id).isEmpty)
        #expect(try env.status(of: birthday) == .unsorted)
        #expect(try categories.categories(for: weight.id).map(\.name) == ["Poids"])
        #expect(try categories.categories(for: chosen.id).map(\.name) == ["Poids"])
        #expect(try categories.removeMisfiledFromTrackers() == 0)
    }
}
