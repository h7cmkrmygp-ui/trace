import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P35 — moins de « À classer » : plus de copie de toute la dictée, les classements ratés sont réessayés (3 fois au plus),
/// chaque note à classer dit pourquoi elle est là, et les anciennes copies sont rangées une fois (à la corbeille,
/// récupérables).
struct UnsortedFixesStoreTests {
    func valid(_ excerpt: String, path: [String] = ["Automobile"]) -> ValidThought {
        ValidThought(title: excerpt, summary: nil, excerpt: excerpt, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                     categoryPath: path, mentionedDates: [])
    }

    static let text = "Acheter des wipers pour la Corolla. Penser à rappeler le notaire au sujet de la maison."

    @Test func theMigrationCountsTheAttempts() throws {
        let env = try StoreTestEnvironment()
        let columns = try env.database.writer.read { db in try db.columns(in: "source").map(\.name) }
        #expect(columns.contains("analysis_attempts"))
    }

    @Test func onlyTheForgottenPartStaysToFile() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote(Self.text)
        _ = try env.filer.file([valid("Acheter des wipers pour la Corolla")], sourceID: interim.sourceID,
                               keepInterimIfUncovered: true)
        let unsorted = try env.memories.memories(statuses: [.unsorted])
        try #require(unsorted.count == 1)
        #expect(unsorted[0].content == "Penser à rappeler le notaire au sujet de la maison")
        #expect(try env.memories.unsortedReason(for: unsorted[0].id)?.contains("partie de ta dictée") == true)
        // Plus aucune copie de toute la dictée.
        #expect(try !env.memories.memories(statuses: [.active, .unsorted]).contains { $0.content == Self.text })
    }

    @Test func aFailedFilingIsRetriedThreeTimesAtMost() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Une note que l'IA n'arrive pas à classer")
        try env.filer.markFallback(sourceID: interim.sourceID)
        #expect(try env.memories.sourcesNeedingCloudRetry().map(\.id) == [interim.sourceID])
        #expect(try env.memories.unsortedReason(for: interim.id)?.contains("réessaiera") == true)
        for _ in 0..<2 {
            #expect(try env.memories.reopenForCloudRetry(sourceID: interim.sourceID))
            try env.filer.markFallback(sourceID: interim.sourceID)
        }
        // Trois échecs : Engram ne réessaie plus, et le dit.
        #expect(try env.memories.sourcesNeedingCloudRetry().isEmpty)
        let note = try #require(try env.memories.memories(statuses: [.unsorted]).first)
        #expect(try env.memories.unsortedReason(for: note.id)?.contains("toi-même") == true)
    }

    @Test func eachNoteToFileSaysWhy() throws {
        let env = try StoreTestEnvironment()
        // En attente d'un service.
        let waiting = try env.saveNote("Une note en attente")
        #expect(try env.memories.unsortedReason(for: waiting.id)?.contains("Pas encore classée") == true)
        // Classée par l'IA, mais sans dossier sûr.
        let interim = try env.saveNote("Une idée sans dossier")
        let filed = try #require(try env.filer.file([valid("Une idée sans dossier", path: [])], sourceID: interim.sourceID)
            .memories.first)
        #expect(try env.memories.unsortedReason(for: filed.id)?.contains("pas trouvé de dossier") == true)
        // Une note rangée n'a pas de raison à afficher.
        let other = try env.saveNote("Laver l'auto")
        let active = try #require(try env.filer.file([valid("Laver l'auto")], sourceID: other.sourceID).memories.first)
        #expect(try env.memories.unsortedReason(for: active.id) == nil)
    }

    @Test func oldCopiesAndOldFailuresAreHandledOnce() throws {
        let env = try StoreTestEnvironment()
        // Une ancienne copie entière, déjà couverte par la note rangée : à la corbeille (récupérable).
        let covered = try env.saveNote("Acheter des wipers pour la Corolla")
        _ = try env.filer.file([valid("Acheter des wipers pour la Corolla")], sourceID: covered.sourceID,
                               keepInterimIfUncovered: false, forceKeepInterim: true)
        #expect(try env.memories.memory(id: covered.id)?.status == .unsorted)
        // Une ancienne copie dont une partie n'est nulle part ailleurs : elle ne garde que cette partie.
        let partial = try env.saveNote(Self.text)
        _ = try env.filer.file([valid("Acheter des wipers pour la Corolla")], sourceID: partial.sourceID,
                               keepInterimIfUncovered: false, forceKeepInterim: true)
        #expect(try env.memories.memory(id: partial.id)?.content == Self.text)
        // Un ancien échec, d'avant les nouveaux essais.
        let failed = try env.saveNote("Une vieille note jamais classée")
        try env.database.writer.write { db in
            try db.execute(sql: "UPDATE source SET processing_status = 'done' WHERE id = ?", arguments: [failed.sourceID])
        }

        #expect(try env.memories.cleanUpWholeNoteCopies() == 2)
        #expect(try env.memories.memory(id: covered.id)?.status == .trashed)
        #expect(try env.memories.memory(id: partial.id)?.content == "Penser à rappeler le notaire au sujet de la maison")
        #expect(try env.memories.retryOldFailures() == 1)
        #expect(try env.memories.sourcesNeedingCloudRetry().map(\.id) == [failed.sourceID])
        #expect(try env.memories.cleanUpWholeNoteCopies() == 0)
        #expect(try env.memories.retryOldFailures() == 0)
    }
}
