import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// Retranscrire une note vocale avec un meilleur moteur (Whisper, OpenAI).
struct RetranscriptionTests {
    func valid(_ title: String, path: [String]) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: title, spanStart: nil, spanEnd: nil, kind: .task,
                     tags: [], categoryPath: path, mentionedDates: [])
    }

    @Test func replacesUntouchedAIMemoriesWithAFreshInterim() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceNote(audioPath: "audio/v.caf", duration: 5, transcript: "a pelé le gars rage",
                                                       languages: ["fr-CA"], engine: "apple-speech")
        let filed = try env.filer.file([valid("a pelé le gars rage", path: ["Divers"])], sourceID: recording.sourceID)
        let interim = try #require(try env.memories.retranscribe(sourceID: recording.sourceID, transcript: "Appeler le garage",
                                                                 languages: ["fr"], engine: "whisperkit-large-v3-turbo"))
        #expect(try env.memories.memory(id: filed.memories[0].id) == nil)
        #expect(interim.title == "Appeler le garage")
        #expect(interim.analysisVersion == MemoryStore.interimAnalysisVersion)
        let source = try #require(try env.memories.source(id: recording.sourceID))
        #expect(source.originalText == "a pelé le gars rage")
        #expect(source.correctedText == "Appeler le garage")
        #expect(source.referenceText == "Appeler le garage")
        #expect(source.transcriptionEngine == "whisperkit-large-v3-turbo")
        #expect(try env.memories.sourcesAwaitingAnalysis() == [recording.sourceID])
    }

    @Test func keepsMemoriesTheOwnerTouched() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceNote(audioPath: "audio/w.caf", duration: 5, transcript: "texte mal compris",
                                                       languages: [], engine: "apple-speech")
        let filed = try env.filer.file([valid("texte mal compris", path: ["Divers"])], sourceID: recording.sourceID)
        _ = try env.memories.updateMemory(filed.memories[0].id, with: MemoryEdit(title: "Corrigé à la main"), actor: .user)
        _ = try env.memories.retranscribe(sourceID: recording.sourceID, transcript: "Texte bien compris", languages: [], engine: nil)
        #expect(try env.memories.memory(id: filed.memories[0].id)?.title == "Corrigé à la main")
    }

    /// Un événement existe déjà dans le calendrier de l'iPhone : remplacer la note créerait un doublon.
    @Test func keepsMemoriesLinkedToACalendarEvent() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceNote(audioPath: "audio/z.caf", duration: 5, transcript: "dentiste vendredi",
                                                       languages: [], engine: "apple-speech")
        let filed = try env.filer.file([valid("dentiste vendredi", path: ["Santé"])], sourceID: recording.sourceID)
        try CalendarLinkStore(database: env.database, dates: env.dates)
            .link(memoryID: filed.memories[0].id, eventIdentifier: "event-1", calendarIdentifier: nil)
        let interim = try env.memories.retranscribe(sourceID: recording.sourceID, transcript: "Dentiste vendredi à 14 h",
                                                    languages: [], engine: nil)
        #expect(interim == nil)
        #expect(try env.memories.memory(id: filed.memories[0].id) != nil)
    }

    @Test func refusesAnEmptyTranscriptOrATextNote() throws {
        let env = try StoreTestEnvironment()
        let recording = try env.memories.saveVoiceRecording(audioPath: "audio/x.caf", duration: 1)
        #expect(throws: StoreError.emptyContent) {
            try env.memories.retranscribe(sourceID: recording.sourceID, transcript: "  ", languages: [], engine: nil)
        }
        let note = try env.saveNote("Une note écrite")
        #expect(throws: StoreError.self) {
            try env.memories.retranscribe(sourceID: note.sourceID, transcript: "Autre", languages: [], engine: nil)
        }
    }

    @Test func listsVoiceSourcesWithAudio() throws {
        let env = try StoreTestEnvironment()
        let voice = try env.memories.saveVoiceRecording(audioPath: "audio/y.caf", duration: 1)
        try env.saveNote("Une note écrite")
        #expect(try env.memories.voiceSources().map(\.id) == [voice.sourceID])
    }
}
