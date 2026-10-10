import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct MemoryStoreTests {
    @Test func savesTextNoteAsUnsortedMemory() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("  Acheter du lait\net du pain  ")
        #expect(memory.title == "Acheter du lait")
        #expect(memory.content == "Acheter du lait\net du pain")
        #expect(memory.excerpt == memory.content)
        #expect(memory.status == .unsorted)
        #expect(memory.version == 1)
        #expect(memory.analysisVersion == MemoryStore.interimAnalysisVersion)
        let source = try #require(try env.memories.source(id: memory.sourceID))
        #expect(source.kind == .text)
        #expect(source.originalText == "Acheter du lait\net du pain")
        #expect(source.processingStatus == .waiting)
        #expect(try env.memories.versions(of: memory.id).map(\.version) == [1])
    }

    @Test(arguments: ["", "   ", "\n\n\t "])
    func rejectsEmptyNotes(text: String) throws {
        let env = try StoreTestEnvironment()
        #expect(throws: StoreError.emptyContent) { try env.memories.saveTextNoteWithoutAnalysis(text) }
        #expect(try env.memories.memories(statuses: Set(MemoryStatus.allCases)).isEmpty)
        #expect(try env.database.writer.read { db in try Source.fetchCount(db) } == 0)
    }

    @Test func sameTextWithinTenMinutesIsATechnicalDuplicate() throws {
        let env = try StoreTestEnvironment()
        let first = try env.saveNote("Appeler le garage")
        env.dates.advance(by: 9 * 60)
        guard case .duplicate(let existing) = try env.memories.saveTextNoteWithoutAnalysis("Appeler   le garage ") else {
            Issue.record("un doublon technique était attendu")
            return
        }
        #expect(existing.id == first.sourceID)
        env.dates.advance(by: 2 * 60)
        guard case .saved = try env.memories.saveTextNoteWithoutAnalysis("Appeler le garage") else {
            Issue.record("après 11 minutes, une nouvelle note était attendue")
            return
        }
        #expect(try env.memories.memories(statuses: [.unsorted]).count == 2)
    }

    @Test func userEditCreatesAVersionAndProtectsFromAI() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Idée app")
        env.dates.advance(by: 60)
        let edited = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Idée : app de mémoire"), actor: .user)
        #expect(edited.version == 2)
        #expect(edited.userEdited)
        #expect(try env.memories.versions(of: memory.id).map(\.version) == [2, 1])
        #expect(throws: StoreError.protectedByUser) {
            try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Titre proposé par l'IA"), actor: .ai)
        }
    }

    @Test func editWithoutChangeKeepsTheVersion() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Rien ne change")
        let same = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Rien ne change"), actor: .user)
        #expect(same.version == 1)
        #expect(try env.memories.versions(of: memory.id).count == 1)
    }

    @Test func invalidEditIsRolledBack() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Titre valide")
        #expect(throws: MemoryValidationError.emptyTitle) {
            try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "   "), actor: .user)
        }
        let stored = try #require(try env.memories.memory(id: memory.id))
        #expect(stored.title == "Titre valide")
        #expect(stored.version == 1)
    }

    @Test func trashThenRestoreReturnsToUnsorted() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Note à jeter")
        let trashed = try env.memories.setStatus(.trashed, for: memory.id, actor: .user)
        #expect(trashed.status == .trashed)
        #expect(trashed.trashedAt == env.dates.now())
        let restored = try env.memories.restore(memory.id)
        #expect(restored.status == .unsorted)
        #expect(restored.trashedAt == nil)
        #expect(try env.memories.versions(of: memory.id).count == 3)
    }

    @Test func restoringAnOldVersionCreatesANewOne() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Version un")
        _ = try env.memories.updateMemory(memory.id, with: MemoryEdit(title: "Version deux", content: "Version deux"), actor: .user)
        let restored = try env.memories.restoreVersion(1, of: memory.id)
        #expect(restored.title == "Version un")
        #expect(restored.content == "Version un")
        #expect(restored.version == 3)
    }

    @Test func permanentDeletionRequiresTheTrash() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("À garder")
        #expect(throws: StoreError.self) { try env.memories.deletePermanently(memory.id) }
        #expect(try env.memories.memory(id: memory.id) != nil)
    }

    @Test func sharedSourceSurvivesUntilItsLastMemoryIsDeleted() throws {
        let env = try StoreTestEnvironment()
        let first = try env.saveNote("Rendez-vous vendredi, acheter un ordinateur")
        let second = try env.memories.createMemory(
            MemoryDraft(sourceID: first.sourceID, excerpt: "acheter un ordinateur", title: "Acheter un ordinateur",
                        content: "Acheter un ordinateur", analysisVersion: "test"),
            actor: .ai)
        try env.database.writer.write { db in
            try db.execute(sql: "UPDATE source SET audio_path = ? WHERE id = ?", arguments: ["note.caf", first.sourceID])
        }
        _ = try env.memories.setStatus(.trashed, for: first.id, actor: .user)
        let firstDeletion = try env.memories.deletePermanently(first.id)
        #expect(firstDeletion.deletedSourceID == nil)
        #expect(firstDeletion.audioPathToRemove == nil)
        #expect(try env.memories.source(id: first.sourceID) != nil)

        _ = try env.memories.setStatus(.trashed, for: second.id, actor: .user)
        let secondDeletion = try env.memories.deletePermanently(second.id)
        #expect(secondDeletion.deletedSourceID == first.sourceID)
        #expect(secondDeletion.audioPathToRemove == "note.caf")
        #expect(try env.memories.source(id: first.sourceID) == nil)
        #expect(try env.memories.versions(of: second.id).isEmpty)
    }

    @Test func memoriesByIDsKeepTheRequestedOrder() throws {
        let env = try StoreTestEnvironment()
        let a = try env.saveNote("Alpha")
        let b = try env.saveNote("Bravo")
        let c = try env.saveNote("Charlie")
        #expect(try env.memories.memories(ids: [c.id, a.id, b.id]).map(\.id) == [c.id, a.id, b.id])
    }

    @Test func streamEmitsAfterEachChange() async throws {
        let env = try StoreTestEnvironment()
        var iterator = env.memories.memoriesStream(statuses: [.unsorted]).makeAsyncIterator()
        #expect(try await iterator.next()?.count == 0)
        try env.saveNote("Première pensée")
        #expect(try await iterator.next()?.count == 1)
    }
}
