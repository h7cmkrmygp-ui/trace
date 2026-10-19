import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// F22, F26, F27 — « Retrouver » ne lit pas une note remplacée par une correction ; la confiance de la transcription est
/// gardée avec la dictée ; une recherche limitée aux notes les plus récentes le dit.
struct RecallLimitsStoreTests {
    @Test func aReplacedNoteIsNotAnAnswerAnymore() throws {
        let env = try StoreTestEnvironment()
        func file(_ text: String, intent: IntentType) throws -> Memory {
            let interim = try env.saveNote(text)
            let memory = try #require(try env.filer.file([
                ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .info, tags: [],
                             categoryPath: ["Maison"], mentionedDates: [], intent: intent),
            ], sourceID: interim.sourceID).memories.first)
            env.dates.advance(by: 3_600)
            return memory
        }
        let old = try file("Le loyer est de 1200 $", intent: .fact)
        let corrected = try file("Correction : le loyer est de 1250 $", intent: .correction)
        let ids = try env.memories.recallDocuments().map(\.id)
        #expect(ids.contains(corrected.id))
        #expect(!ids.contains(old.id))
    }

    @Test func theTranscriptConfidenceIsKeptWithTheDictation() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/c.caf", duration: 2)
        _ = try env.memories.attachTranscript(sourceID: recording.sourceID, transcript: "Payer 450 $ au plombier",
                                              languages: ["fr"], engine: "whisperkit", needsReview: true,
                                              confidence: -1.2)
        #expect(try env.memories.source(id: recording.sourceID)?.transcriptConfidence == -1.2)
    }

    @Test func aLimitedSearchSaysSo() throws {
        let env = try StoreTestEnvironment()
        for text in ["Note un", "Note deux", "Note trois"] {
            try env.saveNote(text)
            env.dates.advance(by: 60)
        }
        #expect(try env.memories.recallIsLimited(limit: 2))
        #expect(try !env.memories.recallIsLimited(limit: 5))
    }
}
