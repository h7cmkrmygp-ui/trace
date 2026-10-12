import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P34 — les exemples de classement relus sur l'iPhone : les notes rangées, leurs dossiers, et si c'est le propriétaire
/// qui les y a mises ; la taille de chaque dossier.
struct FilingSamplesStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String]) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: path, mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func filedNotesAreTheExamples() throws {
        let env = try StoreTestEnvironment()
        let tires = try file(env, "Changer les pneus", path: ["Automobile", "Corolla"])
        let oil = try file(env, "Changement d'huile", path: ["Automobile", "Corolla"])
        let corolla = try #require(try env.categories.categories(for: oil.id).first)
        try env.categories.confirm(memoryID: oil.id, categoryID: corolla.id)
        // Une note « À classer » ou à la corbeille n'est pas un exemple.
        try env.saveNote("Une idée sans dossier")
        let trashed = try file(env, "Vieille note", path: ["Maison"])
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)

        let samples = try env.categories.filingSamples()
        #expect(samples.count == 2)
        let tiresSample = try #require(samples.first { $0.id == tires.id })
        #expect(tiresSample.paths == ["Automobile › Corolla"])
        #expect(tiresSample.text.contains("Changer les pneus"))
        #expect(tiresSample.byOwner == false)
        #expect(samples.first { $0.id == oil.id }?.byOwner == true)
    }

    @Test func eachFolderKnowsHowManyNotesItHolds() throws {
        let env = try StoreTestEnvironment()
        _ = try file(env, "Changer les pneus", path: ["Automobile", "Corolla"])
        _ = try file(env, "Laver l'auto", path: ["Automobile"])
        _ = try file(env, "Payer l'électricité", path: ["Finances"])
        #expect(try env.categories.categoryCounts() == ["Automobile": 2, "Automobile › Corolla": 1, "Finances": 1])
    }
}
