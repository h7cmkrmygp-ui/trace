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

    /// Une note gardée sur l'iPhone, ou jugée secrète, est marquée privée : elle ne sera jamais donnée à un assistant.
    /// Être classée sur l'iPhone faute de service ne la rend pas privée.
    @Test func privateNotesAreMarked() throws {
        let env = try StoreTestEnvironment()
        guard case .saved(let kept) = try env.memories.saveTextNoteWithoutAnalysis("Code du casier", keepLocal: true) else {
            Issue.record("Note en double")
            return
        }
        let secret = try env.saveNote("Mot de passe du wifi")
        try env.memories.recordRoute(sourceID: secret.sourceID, route: AnalysisRoute(
            level: .secret, provider: "apple", reason: "Contient un mot de passe.", needsCloudRetry: false))
        let offline = try env.saveNote("Acheter des piles")
        try env.memories.recordRoute(sourceID: offline.sourceID, route: AnalysisRoute(
            level: .secret, provider: "apple", reason: RouteReasons.noCloudService, needsCloudRetry: true))
        let plain = try env.saveNote("Idée de jardin")

        let documents = Dictionary(uniqueKeysWithValues: try env.memories.recallDocuments().map { ($0.id, $0) })
        #expect(documents[kept.id]?.isPrivate == true)
        #expect(documents[secret.id]?.isPrivate == true)
        #expect(documents[offline.id]?.isPrivate == false)
        #expect(documents[plain.id]?.isPrivate == false)
    }
}
