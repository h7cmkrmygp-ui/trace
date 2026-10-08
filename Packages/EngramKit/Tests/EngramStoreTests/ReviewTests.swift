import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// « Vérifie ta note » : la transcription attend la confirmation du propriétaire avant tout classement.
struct ReviewTests {
    func transcribedForReview(_ env: StoreTestEnvironment, _ text: String = "a pelé le gars rage demain") throws -> Memory {
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/r.caf", duration: 4)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: text, languages: ["fr"],
                                              engine: "whisperkit-large-v3-turbo", needsReview: true)
        return recording
    }

    @Test func aTranscriptAwaitingReviewIsNeverAnalyzed() throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env)
        #expect(try env.memories.sourcesAwaitingAnalysis().isEmpty)
        #expect(try env.memories.sourcesAwaitingReview().map(\.id) == [recording.sourceID])
        #expect(try env.memories.source(id: recording.sourceID)?.needsReview == true)
    }

    @Test func theReviewQueueIsObservable() async throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env)
        var iterator = env.memories.sourcesAwaitingReviewStream().makeAsyncIterator()
        #expect(try #require(try await iterator.next()).map(\.id) == [recording.sourceID])
    }

    @Test func confirmingKeepsTheOriginalAndStoresTheCorrection() throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env)
        let interim = try #require(try env.memories.confirmReview(sourceID: recording.sourceID,
                                                                  text: "  Appeler le garage demain ", keepLocal: true))
        let source = try #require(try env.memories.source(id: recording.sourceID))
        #expect(source.originalText == "a pelé le gars rage demain")
        #expect(source.correctedText == "Appeler le garage demain")
        #expect(source.needsReview == false)
        #expect(source.keepLocal == true)
        #expect(source.correctedByOwner == true)
        #expect(interim.content == "Appeler le garage demain")
        #expect(try env.memories.sourcesAwaitingAnalysis() == [recording.sourceID])
        #expect(try env.memories.sourcesAwaitingReview().isEmpty)
    }

    @Test func confirmingWithoutAChangeStoresNoCorrection() throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env, "Acheter du pain")
        _ = try env.memories.confirmReview(sourceID: recording.sourceID, text: "Acheter du pain", keepLocal: false)
        let source = try #require(try env.memories.source(id: recording.sourceID))
        #expect(source.correctedText == nil)
        #expect(source.keepLocal == false)
        #expect(source.correctedByOwner == false)
    }

    /// Une correction faite à la main est la vérité : une retranscription ne l'écrase jamais.
    @Test func retranscriptionNeverOverwritesTheOwnersCorrection() throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env)
        _ = try env.memories.confirmReview(sourceID: recording.sourceID, text: "Appeler le garage demain", keepLocal: false)
        #expect(throws: StoreError.protectedByUser) {
            try env.memories.retranscribe(sourceID: recording.sourceID, transcript: "Appeler le garage demain matin",
                                          languages: ["fr"], engine: "whisperkit-large-v3")
        }
        let source = try #require(try env.memories.source(id: recording.sourceID))
        #expect(source.correctedText == "Appeler le garage demain")
        #expect(source.correctedByOwner == true)
    }

    /// Une retranscription par Whisper n'est pas une correction du propriétaire (le banc d'essai ne doit pas la prendre pour référence).
    @Test func aRetranscriptionIsNotAnOwnerCorrection() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceNote(audioPath: "audio/u.caf", duration: 3, transcript: "texte approximatif",
                                                       languages: [], engine: "apple-speech")
        _ = try env.memories.retranscribe(sourceID: recording.sourceID, transcript: "Texte exact", languages: ["fr"],
                                          engine: "whisperkit-large-v3-turbo")
        let source = try #require(try env.memories.source(id: recording.sourceID))
        #expect(source.correctedText == "Texte exact")
        #expect(source.correctedByOwner == false)
    }

    @Test func confirmingAnEmptyTextIsRefused() throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env)
        #expect(throws: StoreError.emptyContent) {
            try env.memories.confirmReview(sourceID: recording.sourceID, text: "   ", keepLocal: false)
        }
    }

    @Test func discardingTrashesTheNoteAndNeverAnalyzesIt() throws {
        let env = try StoreTestEnvironment()
        let recording = try transcribedForReview(env)
        try env.memories.discardReview(sourceID: recording.sourceID)
        #expect(try env.status(of: recording) == .trashed)
        #expect(try env.memories.sourcesAwaitingAnalysis().isEmpty)
        #expect(try env.memories.sourcesAwaitingReview().isEmpty)
    }

    @Test func anEmptyTranscriptHasNothingToReview() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/s.caf", duration: 1)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: " ", languages: [],
                                              engine: nil, needsReview: true)
        #expect(try env.memories.sourcesAwaitingReview().isEmpty)
    }

    @Test func aNoteAwaitingReviewSurvivesReopeningTheDatabase() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("engram.sqlite").path
        let sourceID: UUID
        do {
            let database = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
            let memories = MemoryStore(database: database)
            let recording = try memories.saveVoiceRecording(audioPath: "audio/t.caf", duration: 2)
            _ = try memories.attachTranscript(sourceID: recording.sourceID, transcript: "Idée de cadeau", languages: [],
                                              engine: nil, needsReview: true)
            sourceID = recording.sourceID
        }
        let reopened = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
        #expect(try MemoryStore(database: reopened).sourcesAwaitingReview().map(\.id) == [sourceID])
    }

    @Test func aV2DatabaseMigratesToV3WithPrivateDefaults() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("engram.sqlite").path
        let sourceID = UUID()
        do {
            let queue = try DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration())
            try Schema.migrator.migrate(queue, upTo: "v2_due_dates_calendar")
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO source (id, kind, original_text, languages, content_hash, captured_at, processing_status, created_at, updated_at)
                    VALUES (?, 'text', 'Acheter du lait', '[]', 'h', ?, 'done', ?, ?)
                    """, arguments: [sourceID, Fixtures.date, Fixtures.date, Fixtures.date])
            }
        }
        let database = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
        let source = try #require(try MemoryStore(database: database).source(id: sourceID))
        #expect(source.originalText == "Acheter du lait")
        #expect(source.needsReview == false)
        #expect(source.keepLocal == false)
        #expect(source.privacyLevel == nil)
        #expect(source.analysisProvider == nil)
        #expect(source.routeReason == nil)
        #expect(source.needsCloudRetry == false)
        #expect(source.correctedByOwner == false)
    }
}
