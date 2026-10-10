import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P32 — la raison du choix de l'IA est gardée avec la note ; l'IA sait ce que contient chaque catégorie ;
/// « Assurance » retrouve « Assurances » (déjà vrai : accents, majuscules et pluriel sont ignorés).
struct FilingReasonStoreTests {
    static let text = "Retiens la fête à Léa, c'est le 13 mars"

    @Test func theMigrationAddsTheReason() throws {
        let env = try StoreTestEnvironment()
        let columns = try env.database.writer.read { db in try db.columns(in: "memory_category").map(\.name) }
        #expect(columns.contains("reason"))
    }

    @Test func theReasonIsShownUntilTheOwnerChangesTheFolder() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote(Self.text)
        let thought = ValidThought(title: "Fête de Léa", summary: nil, excerpt: Self.text, spanStart: nil, spanEnd: nil,
                                   kind: .info, tags: [], categoryPath: ["Famille", "Anniversaires"], mentionedDates: [],
                                   categoryReason: "Une date à retenir pour Léa.")
        let memory = try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
        #expect(try env.categories.filingReasons(for: memory.id)
            == [FilingReason(path: "Famille › Anniversaires", reason: "Une date à retenir pour Léa.")])
        // Le propriétaire retire ce dossier : la raison de l'IA ne s'affiche plus.
        let folder = try #require(try env.categories.categories(for: memory.id).first)
        try env.categories.removeAssignment(memoryID: memory.id, categoryID: folder.id, by: .user)
        #expect(try env.categories.filingReasons(for: memory.id).isEmpty)
    }

    @Test func anExistingCategoryIsFoundInTheSingularOrThePlural() throws {
        let env = try StoreTestEnvironment()
        let finance = try env.categories.createCategory(name: "Finance", parentID: nil, origin: .ai).category
        let insurance = try env.categories.createCategory(name: "Assurances", parentID: finance.id, origin: .ai).category
        #expect(try env.categories.createCategory(name: "assurance", parentID: finance.id, origin: .ai).category.id == insurance.id)
        #expect(try env.categories.createCategory(name: "Finances", parentID: nil, origin: .ai).category.id == finance.id)
        #expect(try env.categories.categoryPaths() == ["Finance", "Finance › Assurances"])
    }

    @Test func theAIIsToldWhatEachCategoryContains() throws {
        let env = try StoreTestEnvironment()
        let car = try env.categories.createCategory(name: "Automobile", parentID: nil, origin: .ai,
                                                    description: "Entretien et réparations de la voiture").category
        _ = try env.categories.createCategory(name: "Corolla", parentID: car.id, origin: .ai)
        #expect(try env.categories.categoryDescriptions() == ["Automobile": "Entretien et réparations de la voiture"])
    }
}
