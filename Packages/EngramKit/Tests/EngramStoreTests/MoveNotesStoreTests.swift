import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P38 — déplacer d'un coup les notes semblables : celles que l'IA avait rangées dans le dossier quitté vont dans le dossier
/// choisi par le propriétaire (son choix, que l'IA ne défera pas) ; une note qu'il avait rangée lui-même ne bouge pas.
struct MoveNotesStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String]) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: path, mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func similarNotesFollowTheOwnersChoice() throws {
        let env = try StoreTestEnvironment()
        let categories = env.categories
        let misfiled = try file(env, "Renouveler l'assurance habitation", path: ["Automobile", "Pièces"])
        let chosen = try file(env, "Assurance de l'auto", path: ["Automobile", "Pièces"])
        let pieces = try #require(try categories.categories(for: chosen.id).first)
        try categories.confirm(memoryID: chosen.id, categoryID: pieces.id)
        let insurance = try categories.resolvePath(["Finances", "Assurances"], origin: .user)

        #expect(try categories.moveNotes([misfiled.id, chosen.id], from: [pieces.id], to: insurance.id) == 1)
        #expect(try categories.categories(for: misfiled.id).map(\.name) == ["Assurances"])
        #expect(try categories.categories(for: chosen.id).map(\.name) == ["Pièces"])
        // C'est le choix du propriétaire : confirmé, l'IA ne le défera pas.
        let link = try env.database.writer.read { db in
            try CategoryAssignment.fetchOne(db, key: ["memory_id": misfiled.id, "category_id": insurance.id])
        }
        #expect(link?.origin == .user && link?.confirmed == true)
    }
}
