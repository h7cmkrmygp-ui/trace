import Testing
@testable import EngramIntelligence

struct TextChunkerTests {
    @Test func shortTextIsASingleChunk() {
        #expect(TextChunker.chunks(of: "Acheter du lait.", maxLength: 100) == ["Acheter du lait."])
    }

    @Test func longTextIsCutAtSentenceBoundaries() {
        let sentence = "Ceci est une phrase de test assez longue. "
        let text = String(repeating: sentence, count: 10)
        let chunks = TextChunker.chunks(of: text, maxLength: 120)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 120 })
        #expect(chunks.joined(separator: " ").split(separator: ".").count == 10)
    }

    @Test func halvesSplitBySentencesThenByWords() {
        #expect(TextChunker.halves(of: "Une phrase. Une autre.").count == 2)
        #expect(TextChunker.halves(of: "un seul long morceau sans point") == ["un seul long", "morceau sans point"])
        #expect(TextChunker.halves(of: "mot") == ["mot"])
    }
}
