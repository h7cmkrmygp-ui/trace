import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// Mots proches factices.
struct FakeNeighbors: WordNeighbors {
    let words: [String: [String]]

    func neighbors(of word: String) -> [String] { words[word] ?? [] }
}

/// « Retrouver » avec le sens des phrases et les mots proches, calculés sur l'iPhone (faux modèles ici).
struct RecallEngineTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Jeudi 8 octobre 2026, 10 h.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 10))!

    func doc(_ title: String, daysAgo: Double = 2, kind: MemoryKind = .task, categories: [String] = []) -> RecallDocument {
        RecallDocument(id: UUID(), title: title, text: title, kind: kind, status: .active,
                       capturedAt: Self.now.addingTimeInterval(-daysAgo * 86_400), dueAt: nil, categories: categories, tags: [])
    }

    @Test func meaningFindsANoteWithoutTheSameWords() {
        let gearbox = doc("La transmission grince en reculant")
        let milk = doc("Acheter du lait")
        let question = "Le souci mécanique avec mon véhicule"
        let embedder = FakeEmbedder(vectors: [question: [1, 0], gearbox.meaningText: [0.95, 0.1], milk.meaningText: [0, 1]])
        let result = RecallEngine(embedder: embedder, neighbors: nil)
            .search(question, in: [gearbox, milk], now: Self.now, calendar: Self.calendar)
        #expect(result.hits.map(\.document.id) == [gearbox.id])
    }

    @Test func nearbyWordsFromTheLanguageModelAreUsed() {
        let bike = doc("Réparer le vélo de route")
        let engine = RecallEngine(embedder: FakeEmbedder(vectors: [:]), neighbors: FakeNeighbors(words: ["bicyclette": ["vélo"]]))
        let result = engine.search("Ma bicyclette", in: [bike, doc("Acheter du lait")], now: Self.now, calendar: Self.calendar)
        #expect(result.hits.map(\.document.id) == [bike.id])
    }

    @Test func relatedNotesShareTheirSubject() {
        let tires = doc("Changer les pneus de la Corolla", categories: ["Automobile"])
        let garage = doc("Appeler le garage pour la Corolla", categories: ["Automobile"])
        let milk = doc("Acheter du lait", categories: ["Achats"])
        let engine = RecallEngine(embedder: FakeEmbedder(vectors: [:]), neighbors: nil)
        #expect(engine.related(to: tires, in: [tires, garage, milk], now: Self.now).map(\.document.id) == [garage.id])
    }

    @Test func theAnswerPromptOnlyContainsTheNotesFound() {
        let hits = (1...12).map { RecallHit(document: doc("Note numéro \($0)"), score: 1) }
        let prompt = RecallAnswerPrompt.prompt(question: "Mes tâches ?", hits: hits, now: Self.now, calendar: Self.calendar)
        #expect(prompt.contains("Mes tâches ?"))
        #expect(prompt.contains("« Note numéro 1 »"))
        #expect(prompt.contains("« Note numéro 8 »"))
        #expect(!prompt.contains("« Note numéro 9 »"))
        #expect(RecallAnswerPrompt.instructions.contains("Never invent"))
    }
}
