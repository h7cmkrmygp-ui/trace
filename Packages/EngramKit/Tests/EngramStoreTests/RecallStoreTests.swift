import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// Ce que « Retrouver » peut lire : les notes vivantes et archivées, avec leurs dossiers et étiquettes ; jamais la
/// corbeille ni les dictées qui attendent « Vérifie ta note ».
struct RecallStoreTests {
    func valid(_ title: String, path: [String], tags: [String] = []) -> ValidThought {
        ValidThought(title: title, summary: "Bruit en tournant à gauche", excerpt: title, spanStart: nil, spanEnd: nil,
                     kind: .task, tags: tags, categoryPath: path, mentionedDates: [])
    }

    @Test func recallReadsLivingAndArchivedNotesWithTheirFolders() throws {
        let env = try StoreTestEnvironment()
        let car = try env.saveNote("Le char fait un bruit bizarre")
        let filed = try env.filer.file([valid("Le char fait un bruit bizarre", path: ["Automobile", "Corolla"], tags: ["garage"])],
                                       sourceID: car.sourceID)
        let done = try env.saveNote("Ancienne tâche terminée")
        _ = try env.memories.setStatus(.archived, for: done.id, actor: .user)
        let thrown = try env.saveNote("Vieille idée à jeter")
        _ = try env.memories.setStatus(.trashed, for: thrown.id, actor: .user)
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/r.caf", duration: 2)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: "Acheter des piles", languages: [],
                                              engine: nil, needsReview: true)

        let documents = try env.memories.recallDocuments()
        #expect(Set(documents.map(\.title)) == ["Le char fait un bruit bizarre", "Ancienne tâche terminée"])
        let carDocument = try #require(documents.first { $0.id == filed.memories.first?.id })
        #expect(carDocument.categories == ["Automobile › Corolla"])
        #expect(carDocument.tags == ["garage"])
        #expect(carDocument.text.contains("Bruit en tournant à gauche"))
        #expect(documents.first { $0.title == "Ancienne tâche terminée" }?.status == .archived)
    }
}
