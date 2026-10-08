import EngramCore
import Foundation
import Testing
@testable import EngramStore

struct ThoughtFilerTests {
    func valid(_ title: String, excerpt: String, path: [String], kind: MemoryKind = .task, tags: [String] = []) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: excerpt, spanStart: nil, spanEnd: nil, kind: kind,
                     tags: tags, categoryPath: path, mentionedDates: [])
    }

    @Test func replacesTheInterimMemoryWithAnalysedThoughts() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Low beams pour la Lexus. Appeler mon gestionnaire de portefeuille.")
        let summary = try env.filer.file([
            valid("Acheter des low beams", excerpt: "Low beams pour la Lexus", path: ["Automobile", "Lexus"], tags: ["Achat"]),
            valid("Appeler le gestionnaire", excerpt: "Appeler mon gestionnaire de portefeuille", path: ["Finance"]),
        ], sourceID: interim.sourceID)
        #expect(summary.memories.count == 2)
        #expect(summary.categoryPaths == ["Automobile › Lexus", "Finance"])
        #expect(try env.memories.memory(id: interim.id) == nil)
        let first = summary.memories[0]
        #expect(first.status == .active)
        #expect(first.analysisVersion == ThoughtFiler.analysisVersion)
        #expect(try env.categories.categories(for: first.id).map(\.name) == ["Lexus"])
        #expect(try env.categories.tags(for: first.id).map(\.name) == ["Achat"])
        #expect(try env.memories.source(id: interim.sourceID)?.processingStatus == .done)
    }

    @Test func aThoughtWithoutCategoryStaysUnsorted() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Une pensée floue")
        let summary = try env.filer.file([valid("Pensée floue", excerpt: "Une pensée floue", path: [], kind: .idea)],
                                         sourceID: interim.sourceID)
        #expect(summary.memories.first?.status == .unsorted)
        #expect(summary.categoryPaths == [])
    }

    @Test func aUserEditedInterimIsKeptAndOnlyCategorised() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Rappeler le garage")
        _ = try env.memories.updateMemory(interim.id, with: MemoryEdit(title: "Garage : rappeler"), actor: .user)
        let summary = try env.filer.file([valid("Rappeler le garage", excerpt: "Rappeler le garage", path: ["Automobile"])],
                                         sourceID: interim.sourceID)
        #expect(summary.memories.map(\.id) == [interim.id])
        let kept = try #require(try env.memories.memory(id: interim.id))
        #expect(kept.title == "Garage : rappeler")
        #expect(try env.categories.categories(for: interim.id).map(\.name) == ["Automobile"])
    }

    @Test func aCategoryTheOwnerRejectedIsNotRecreated() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Rappeler le garage")
        _ = try env.memories.updateMemory(interim.id, with: MemoryEdit(title: "Garage"), actor: .user)
        let automobile = try env.categories.resolvePath(["Automobile"], origin: .ai)
        _ = try env.categories.assign(memoryID: interim.id, categoryID: automobile.id, origin: .ai)
        try env.categories.removeAssignment(memoryID: interim.id, categoryID: automobile.id, by: .user)
        _ = try env.filer.file([valid("Garage", excerpt: "Rappeler le garage", path: ["Automobile"])], sourceID: interim.sourceID)
        #expect(try env.categories.categories(for: interim.id).isEmpty)
    }

    @Test func fallbackKeepsTheInterimAndClosesTheSource() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Texte que l'IA n'a pas compris")
        try env.filer.markFallback(sourceID: interim.sourceID)
        #expect(try env.memories.memory(id: interim.id)?.status == .unsorted)
        #expect(try env.memories.source(id: interim.sourceID)?.processingStatus == .done)
        #expect(try env.memories.sourcesAwaitingAnalysis().isEmpty)
    }

    @Test func savesAVoiceNoteWithAudioAndTranscript() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.memories.saveVoiceNote(audioPath: "audio/x.caf", duration: 12.5, transcript: "Appeler le garage",
                                                    languages: ["fr-CA"], engine: "apple-speech")
        let source = try #require(try env.memories.source(id: memory.sourceID))
        #expect(source.kind == .voice)
        #expect(source.audioPath == "audio/x.caf")
        #expect(source.audioDuration == 12.5)
        #expect(source.originalText == "Appeler le garage")
        #expect(source.processingStatus == .waiting)
        #expect(memory.status == .unsorted)
        #expect(memory.title == "Appeler le garage")
        #expect(try env.memories.sourcesAwaitingAnalysis() == [memory.sourceID])
    }

    @Test func anEmptyTranscriptStillKeepsTheAudio() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.memories.saveVoiceNote(audioPath: "audio/y.caf", duration: 3, transcript: "  ",
                                                    languages: [], engine: "apple-speech")
        #expect(memory.title == MemoryStore.emptyTranscriptTitle)
        #expect(try env.memories.source(id: memory.sourceID)?.audioPath == "audio/y.caf")
    }

    @Test func todoStreamListsOnlyActiveTasksAndAppointments() async throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Acheter du lait. Dentiste vendredi. Idée de jardin. Payer le loyer.")
        let summary = try env.filer.file([
            valid("Acheter du lait", excerpt: "Acheter du lait", path: ["Achats"], kind: .task),
            valid("Dentiste vendredi", excerpt: "Dentiste vendredi", path: ["Santé"], kind: .appointment),
            valid("Idée de jardin", excerpt: "Idée de jardin", path: ["Maison"], kind: .idea),
            valid("Payer le loyer", excerpt: "Payer le loyer", path: ["Finance"], kind: .task),
        ], sourceID: interim.sourceID)
        _ = try env.memories.setStatus(.archived, for: summary.memories[3].id, actor: .user)
        var iterator = env.memories.memoriesStream(kinds: [.task, .appointment], statuses: [.active, .unsorted]).makeAsyncIterator()
        let todo = try #require(try await iterator.next())
        #expect(Set(todo.map(\.title)) == ["Acheter du lait", "Dentiste vendredi"])
    }
}
