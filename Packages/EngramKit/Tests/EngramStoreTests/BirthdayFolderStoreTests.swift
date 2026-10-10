import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P33 — les fêtes ont leur dossier : « Anniversaires » (ou celui que le propriétaire a déjà), sans échéance ni « À faire » ;
/// les anciennes notes de fête y sont rangées une fois, sauf celles que le propriétaire a touchées.
struct BirthdayFolderStoreTests {
    static let text = "Retiens l'anniversaire de Inès c'est le 13 octobre"

    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind = .task, path: [String], dates: [String] = [],
              birthdayOf: String? = nil) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                                   categoryPath: path, mentionedDates: dates,
                                   categoryReason: birthdayOf == nil ? nil : "Une fête à retenir.", birthdayOf: birthdayOf)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func aBirthdayIsFiledInAnniversairesWithoutADueDate() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, Self.text, kind: .info, path: ["Anniversaires"], dates: ["13 octobre"], birthdayOf: "Inès")
        #expect(memory.dueAt == nil)
        #expect(memory.kind == .info)
        #expect(try env.categories.categories(for: memory.id).map(\.name) == ["Anniversaires"])
    }

    @Test func theOwnersOwnBirthdayFolderIsReused() throws {
        let env = try StoreTestEnvironment()
        let family = try env.categories.createCategory(name: "Famille", parentID: nil, origin: .user).category
        let folder = try env.categories.createCategory(name: "Fêtes", parentID: family.id, origin: .user).category
        let memory = try file(env, Self.text, kind: .info, path: ["Anniversaires"], birthdayOf: "Inès")
        #expect(try env.categories.categories(for: memory.id).map(\.id) == [folder.id])
        #expect(try !env.categories.categoryPaths().contains("Anniversaires"))
    }

    @Test func oldBirthdayNotesAreFiledOnce() throws {
        let env = try StoreTestEnvironment()
        // Avant : la fête était une tâche datée, rangée dans Famille.
        let old = try file(env, Self.text, path: ["Famille"], dates: ["13 octobre"])
        #expect(old.dueAt != nil)
        // Une fête que le propriétaire a rangée lui-même, et une vraie tâche autour d'une fête : on n'y touche pas.
        let chosen = try file(env, "La fête de Marc, c'est le 5 avril", path: ["Famille"])
        let familyID = try #require(try env.categories.categories(for: chosen.id).first?.id)
        try env.categories.confirm(memoryID: chosen.id, categoryID: familyID)
        let gift = try file(env, "Acheter un cadeau pour la fête de Julie le 12 mars", path: ["Achats"], dates: ["12 mars"])

        #expect(try env.categories.refileBirthdayNotes() == 1)
        let refiled = try #require(try env.memories.memory(id: old.id))
        #expect(refiled.kind == .info)
        #expect(refiled.dueAt == nil)
        #expect(try env.categories.categories(for: old.id).map(\.name) == ["Anniversaires"])
        #expect(try env.categories.filingReasons(for: old.id).first?.path == "Anniversaires")
        #expect(try env.categories.categories(for: chosen.id).map(\.name) == ["Famille"])
        #expect(try env.memories.memory(id: gift.id)?.kind == .task)
        #expect(try env.categories.categories(for: gift.id).map(\.name) == ["Achats"])
        #expect(try env.categories.refileBirthdayNotes() == 0)
    }
}
