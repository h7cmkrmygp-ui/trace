import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// Notes et Cerveau n'affichent que les catégories qui contiennent quelque chose ; la corbeille se vide d'un coup.
struct NonEmptyCategoriesTests {
    struct Tree {
        let maison: EngramCategory
        let jardin: EngramCategory
        let note: Memory
    }

    /// Maison › Jardin (une note), Maison › Cuisine (vide), Voyages (vide).
    func makeTree(_ env: StoreTestEnvironment) throws -> Tree {
        let maison = try env.categories.createCategory(name: "Maison", parentID: nil, origin: .ai,
                                                       description: "Entretien et projets de la maison").category
        let jardin = try env.categories.createCategory(name: "Jardin", parentID: maison.id, origin: .ai).category
        _ = try env.categories.createCategory(name: "Cuisine", parentID: maison.id, origin: .ai)
        _ = try env.categories.createCategory(name: "Voyages", parentID: nil, origin: .ai)
        let note = try env.saveNote("Tailler la haie")
        _ = try env.categories.assign(memoryID: note.id, categoryID: jardin.id, origin: .user)
        return Tree(maison: maison, jardin: jardin, note: note)
    }

    @Test func librarySummaryHidesEmptyCategoriesButKeepsParentsOfFilledOnes() async throws {
        let env = try StoreTestEnvironment()
        _ = try makeTree(env)
        var iterator = env.categories.librarySummaryStream().makeAsyncIterator()
        let summary = try #require(try await iterator.next())
        #expect(summary.categories.map(\.category.name) == ["Maison", "Jardin"])
        #expect(summary.categories.map(\.memoryCount) == [0, 1])
        #expect(summary.categories.map(\.totalCount) == [1, 1])
        #expect(summary.categories.first?.category.descriptionText == "Entretien et projets de la maison")
    }

    @Test func aTrashedNoteNoLongerKeepsItsCategoryVisible() async throws {
        let env = try StoreTestEnvironment()
        let tree = try makeTree(env)
        _ = try env.memories.setStatus(.trashed, for: tree.note.id, actor: .user)
        var library = env.categories.librarySummaryStream().makeAsyncIterator()
        #expect(try #require(try await library.next()).categories.isEmpty)
        var brain = env.categories.brainSnapshotStream().makeAsyncIterator()
        let snapshot = try #require(try await brain.next())
        #expect(snapshot.categories.isEmpty)
        #expect(snapshot.items.isEmpty)
    }

    @Test func brainSnapshotKeepsOnlyFilledCategoriesAndTheirParents() async throws {
        let env = try StoreTestEnvironment()
        let tree = try makeTree(env)
        var iterator = env.categories.brainSnapshotStream().makeAsyncIterator()
        let snapshot = try #require(try await iterator.next())
        #expect(Set(snapshot.categories.map(\.name)) == ["Maison", "Jardin"])
        #expect(snapshot.items.map(\.categoryID) == [tree.jardin.id])
    }

    @Test func emptyTrashDeletesOnlyTrashedNotesAndReturnsTheirAudio() throws {
        let env = try StoreTestEnvironment()
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/a.caf", duration: 3, transcript: "Vieille idée",
                                                   languages: [], engine: "apple-speech")
        let text = try env.saveNote("Note à jeter")
        let kept = try env.saveNote("Note à garder")
        let archived = try env.saveNote("Note archivée")
        _ = try env.memories.setStatus(.trashed, for: voice.id, actor: .user)
        _ = try env.memories.setStatus(.trashed, for: text.id, actor: .user)
        _ = try env.memories.setStatus(.archived, for: archived.id, actor: .user)

        let deletions = try env.memories.emptyTrash()
        #expect(Set(deletions.map(\.memoryID)) == [voice.id, text.id])
        #expect(deletions.compactMap(\.audioPathToRemove) == ["audio/a.caf"])
        #expect(try env.memories.memories(statuses: [.trashed]).isEmpty)
        #expect(try env.memories.memory(id: kept.id) != nil)
        #expect(try env.memories.memory(id: archived.id) != nil)
    }
}
