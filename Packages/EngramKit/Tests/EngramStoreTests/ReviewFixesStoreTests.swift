import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// Corrections issues de la relecture finale P2 + P3.
struct ReviewFixesStoreTests {
    func valid(_ title: String, excerpt: String? = nil, path: [String] = ["Automobile"], kind: MemoryKind = .task) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: excerpt ?? title, spanStart: nil, spanEnd: nil, kind: kind,
                     tags: [], categoryPath: path, mentionedDates: [])
    }

    // Critique 1 — les notes interim que le propriétaire a touchées ne sont jamais remplacées.

    @Test func aTrashedInterimStaysTrashedAndCreatesNothing() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Rappeler le garage")
        _ = try env.memories.setStatus(.trashed, for: interim.id, actor: .user)
        let summary = try env.filer.file([valid("Rappeler le garage")], sourceID: interim.sourceID)
        #expect(try env.memories.memory(id: interim.id)?.status == .trashed)
        #expect(summary.memories.map(\.id) == [interim.id])
        #expect(try env.memories.memories(statuses: [.active, .unsorted]).isEmpty)
        #expect(try env.categories.categories(for: interim.id).isEmpty)
    }

    @Test func anArchivedInterimStaysArchived() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Idée ancienne")
        _ = try env.memories.setStatus(.archived, for: interim.id, actor: .user)
        _ = try env.filer.file([valid("Idée ancienne", kind: .idea)], sourceID: interim.sourceID)
        #expect(try env.memories.memory(id: interim.id)?.status == .archived)
        #expect(try env.memories.memories(statuses: [.active, .unsorted]).isEmpty)
    }

    @Test func aManuallyFiledInterimKeepsItsCategoryAndHistory() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Rappeler le garage")
        let personnel = try env.categories.createCategory(name: "Personnel", parentID: nil, origin: .user).category
        _ = try env.categories.assign(memoryID: interim.id, categoryID: personnel.id, origin: .user)
        _ = try env.filer.file([valid("Rappeler le garage")], sourceID: interim.sourceID)
        let kept = try #require(try env.memories.memory(id: interim.id))
        #expect(kept.analysisVersion == MemoryStore.interimAnalysisVersion)
        #expect(Set(try env.categories.categories(for: interim.id).map(\.name)) == ["Personnel", "Automobile"])
        #expect(try env.memories.memories(statuses: [.active, .unsorted]).count == 1)
    }

    // Important 2 — un même source ne peut pas être classé deux fois.

    @Test func filingAnAlreadyFiledSourceChangesNothing() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Dentiste demain")
        let first = try env.filer.file([valid("Dentiste demain", path: ["Santé"], kind: .appointment)], sourceID: interim.sourceID)
        let second = try env.filer.file([valid("Dentiste demain", path: ["Santé"], kind: .appointment)], sourceID: interim.sourceID)
        #expect(second.memories.map(\.id) == first.memories.map(\.id))
        #expect(try env.memories.memories(statuses: [.active, .unsorted]).count == 1)
    }

    @Test func aLateTranscriptDoesNotReopenAFinishedSource() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.memories.saveVoiceNote(audioPath: "audio/a.caf", duration: 2, transcript: "Appeler le garage",
                                                    languages: ["fr-CA"], engine: "apple-speech")
        try env.filer.markFallback(sourceID: memory.sourceID)
        try env.memories.attachTranscript(sourceID: memory.sourceID, transcript: "Autre texte", languages: [], engine: nil)
        #expect(try env.memories.source(id: memory.sourceID)?.processingStatus == .done)
        #expect(try env.memories.source(id: memory.sourceID)?.originalText == "Appeler le garage")
    }

    // Important 8 — une analyse partielle ne fait pas disparaître le texte non couvert.

    @Test func aPartialAnalysisKeepsTheFullTextInUnsorted() throws {
        let env = try StoreTestEnvironment()
        let text = "Acheter des low beams pour la Lexus. Penser à rappeler le notaire au sujet de la maison."
        let interim = try env.saveNote(text)
        _ = try env.filer.file([valid("Low beams", excerpt: "Acheter des low beams pour la Lexus")],
                               sourceID: interim.sourceID, keepInterimIfUncovered: true)
        let kept = try #require(try env.memories.memory(id: interim.id))
        #expect(kept.status == .unsorted)
        #expect(kept.content == text)
        #expect(try env.memories.memories(statuses: [.active, .unsorted]).count == 2)
    }

    @Test func aCompleteAnalysisStillReplacesTheInterim() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Acheter des low beams pour la Lexus")
        _ = try env.filer.file([valid("Low beams", excerpt: "Acheter des low beams pour la Lexus")],
                               sourceID: interim.sourceID, keepInterimIfUncovered: true)
        #expect(try env.memories.memory(id: interim.id) == nil)
    }

    // Important 7 — enregistrements orphelins (app tuée pendant l'enregistrement).

    @Test func listsTheAudioPathsAlreadyReferenced() throws {
        let env = try StoreTestEnvironment()
        _ = try env.memories.saveVoiceRecording(audioPath: "audio/a.caf", duration: 1)
        #expect(try env.memories.referencedAudioPaths() == ["audio/a.caf"])
    }
}
