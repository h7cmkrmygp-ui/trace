import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P20 — la fête d'une personne : dite dans une note ou posée à la main, gardée sur sa page.
struct BirthdayStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, people: [String] = []) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .info, tags: [],
                                   categoryPath: ["Famille"], mentionedDates: [], people: people)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    func people(_ env: StoreTestEnvironment) -> EntityStore { EntityStore(database: env.database, dates: env.dates) }

    @Test func theMigrationCreatesTheTable() throws {
        let env = try StoreTestEnvironment()
        #expect(try env.database.writer.read { db in try db.tableExists("person_birthday") })
    }

    @Test func aBirthdaySaidInANoteGoesOnThePersonsPage() throws {
        let env = try StoreTestEnvironment()
        // L'IA n'a pas vu Julie : la fête la crée quand même, et la relie à la note.
        let note = try file(env, "L'anniversaire de Julie est le 12 mars")
        let julie = try #require(try people(env).entities(for: note.id).first)
        #expect(julie.name == "Julie")
        #expect(julie.kind == .person)
        let birthday = try #require(try people(env).birthday(for: julie.id))
        #expect(birthday.month == 3 && birthday.day == 12 && birthday.year == nil)
        #expect(try people(env).birthdays().map(\.name) == ["Julie"])
        // Dite de nouveau avec l'année : la plus récente l'emporte.
        _ = try file(env, "Julie est née le 12 mars 1992", people: ["Julie"])
        #expect(try people(env).birthday(for: julie.id)?.year == 1992)
    }

    @Test func theOwnerSetsOrRemovesABirthday() throws {
        let env = try StoreTestEnvironment()
        let store = people(env)
        let note = try file(env, "Souper avec Marc", people: ["Marc"])
        let marc = try #require(try store.entities(for: note.id).first)
        try store.setBirthday(marc.id, month: 6, day: 3, year: nil)
        #expect(try store.birthday(for: marc.id)?.month == 6)
        #expect(throws: (any Error).self) { try store.setBirthday(marc.id, month: 2, day: 30, year: nil) }
        try store.removeBirthday(marc.id)
        #expect(try store.birthday(for: marc.id) == nil)
        // Un lieu n'a pas de fête.
        let costco = try store.addEntity(named: "Costco", kind: .place, to: note.id)
        #expect(throws: (any Error).self) { try store.setBirthday(costco.id, month: 1, day: 1, year: nil) }
    }

    @Test func mergingPeopleKeepsTheBirthday() throws {
        let env = try StoreTestEnvironment()
        let store = people(env)
        let note = try file(env, "L'anniversaire de Jules est le 5 avril")
        let jules = try #require(try store.entities(for: note.id).first)
        let other = try file(env, "Appeler Julien", people: ["Julien"])
        let julien = try #require(try store.entities(for: other.id).first)
        try store.merge(jules.id, into: julien.id)
        #expect(try store.birthday(for: julien.id)?.day == 5)
        // Une personne masquée n'a plus de rappel de fête.
        try store.hide(julien.id)
        #expect(try store.birthdays().isEmpty)
    }

    @Test func theExportContainsTheBirthdays() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "L'anniversaire de Julie est le 12 mars")
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"person_birthdays\""))
    }
}
