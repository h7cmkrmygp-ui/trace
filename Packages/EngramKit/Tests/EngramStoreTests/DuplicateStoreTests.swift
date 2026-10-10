import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P23 — les doublons possibles : proposés, réunis sans rien perdre, ou écartés pour de bon.
struct DuplicateStoreTests {
    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String], people: [String] = []) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task,
                                   tags: [], categoryPath: path, mentionedDates: [], people: people)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func theMigrationCreatesTheTable() throws {
        let env = try StoreTestEnvironment()
        #expect(try env.database.writer.read { db in try db.tableExists("duplicate_dismissal") })
    }

    @Test func aDuplicateIsProposedThenMergedWithoutLosingAnything() throws {
        let env = try StoreTestEnvironment()
        let first = try file(env, "Appeler l'assurance pour la voiture", path: ["Auto"])
        env.dates.advance(by: 3_600)
        let second = try file(env, "Il faut appeler l'assurance pour la voiture", path: ["Assurances"], people: ["Julie"])
        _ = try env.memories.updateMemory(second.id, with: MemoryEdit(summary: "Demander le numéro de police"), actor: .user)
        try file(env, "Acheter du lait", path: ["Achats"])

        let pairs = try env.memories.duplicatePairs()
        try #require(pairs.count == 1)
        #expect(pairs[0].keep.id == first.id)
        #expect(pairs[0].duplicate.id == second.id)

        try env.memories.mergeDuplicate(second.id, into: first.id)
        let kept = try #require(try env.memories.memory(id: first.id))
        #expect(kept.summary?.contains("Demander le numéro de police") == true)
        #expect(Set(try env.categories.categories(for: first.id).map(\.name)) == ["Auto", "Assurances"])
        #expect(try EntityStore(database: env.database, dates: env.dates).entities(for: first.id).map(\.name) == ["Julie"])
        // Le doublon va à la corbeille : il se récupère.
        #expect(try env.memories.memory(id: second.id)?.status == .trashed)
        #expect(try env.memories.duplicatePairs().isEmpty)
    }

    @Test func notADuplicateIsRemembered() throws {
        let env = try StoreTestEnvironment()
        let first = try file(env, "Réparer la poignée de la porte", path: ["Maison"])
        let second = try file(env, "Il faut réparer la poignée de la porte", path: ["Maison"])
        try #require(try env.memories.duplicatePairs().count == 1)
        try env.memories.dismissDuplicate(first.id, second.id)
        #expect(try env.memories.duplicatePairs().isEmpty)
        #expect(try env.memories.memory(id: second.id)?.status != .trashed)
    }
}
