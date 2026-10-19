import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P40 — le ménage appliqué et noté : chaque changement a sa phrase dans l'historique et s'annule ; rien ne se perd.
struct TidyStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String]) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: path, mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    func folderNames(_ env: StoreTestEnvironment, _ memory: Memory) throws -> [String] {
        try env.categories.categories(for: memory.id).map(\.name)
    }

    @Test func theMigrationCreatesTheHistory() throws {
        let env = try StoreTestEnvironment()
        #expect(try env.database.writer.read { db in try db.tableExists("tidy_action") })
    }

    @Test func foldersAreReadForThePlanner() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "Laver l'auto", path: ["Automobile"])
        _ = try file(env, "Changer les wipers", path: ["Automobile", "Wipers"])
        let folders = try env.categories.tidyFolders()
        let car = try #require(folders.first { $0.name == "Automobile" })
        let wipers = try #require(folders.first { $0.name == "Wipers" })
        #expect(car.noteCount == 2 && car.hasChildren && !car.createdByOwner)
        #expect(wipers.noteCount == 1 && wipers.parentID == car.id && !wipers.hasOwnerNotes)
    }

    @Test func aMergeIsAppliedNotedAndUndone() throws {
        let env = try StoreTestEnvironment()
        let a = try file(env, "Laver l'auto", path: ["Auto"])
        let b = try file(env, "Changer les pneus", path: ["Automobile"])
        let auto = try #require(try env.categories.categories(for: a.id).first)
        let automobile = try #require(try env.categories.categories(for: b.id).first)

        let records = try env.categories.applyTidy([.merge(source: auto.id, into: automobile.id)])
        #expect(records.map(\.summary) == ["« Auto » fusionné dans « Automobile » (1 note)."])
        #expect(try folderNames(env, a) == ["Automobile"])
        #expect(try !env.categories.categoryPaths().contains("Auto"))
        #expect(try env.categories.tidyHistory().map(\.summary) == records.map(\.summary))

        try env.categories.undoTidy(try #require(records.first).id)
        #expect(try folderNames(env, a) == ["Auto"])
        #expect(try folderNames(env, b) == ["Automobile"])
        #expect(try env.categories.tidyHistory().first?.undone == true)
    }

    @Test func aFoldARenameAndAMoveAreUndoneToo() throws {
        let env = try StoreTestEnvironment()
        let wiper = try file(env, "Changer les wipers", path: ["Automobile", "Wipers"])
        let part = try file(env, "Réévaluer l'assurance", path: ["Automobile", "car part"])
        let wipers = try #require(try env.categories.categories(for: wiper.id).first)
        let car = try #require(wipers.parentID)
        let carPart = try #require(try env.categories.categories(for: part.id).first)

        let records = try env.categories.applyTidy([
            .fold(folder: wipers.id, into: car),
            .rename(folder: carPart.id, to: "Pièces auto"),
            .move(memory: part.id, from: "Automobile › Pièces auto", to: "Finances › Assurances"),
        ])
        #expect(records.count == 3)
        #expect(try folderNames(env, wiper) == ["Automobile"])
        #expect(try folderNames(env, part) == ["Assurances"])
        #expect(try env.categories.filingReasons(for: part.id).first?.reason.contains("notes semblables") == true)

        for record in records.reversed() { try env.categories.undoTidy(record.id) }
        #expect(try folderNames(env, wiper) == ["Wipers"])
        #expect(try folderNames(env, part) == ["car part"])
    }

    @Test func theOwnersChoicesAreNeverTouched() throws {
        let env = try StoreTestEnvironment()
        let mine = try file(env, "Laver l'auto", path: ["Auto"])
        let auto = try #require(try env.categories.categories(for: mine.id).first)
        try env.categories.confirm(memoryID: mine.id, categoryID: auto.id)
        let other = try file(env, "Changer les pneus", path: ["Automobile"])
        let automobile = try #require(try env.categories.categories(for: other.id).first)
        // Même si on le lui demande, le ménage ne sort pas une note rangée par le propriétaire.
        let records = try env.categories.applyTidy([.move(memory: mine.id, from: "Auto", to: "Automobile"),
                                                    .fold(folder: auto.id, into: automobile.id)])
        #expect(records.isEmpty)
        #expect(try folderNames(env, mine) == ["Auto"])
    }
}
