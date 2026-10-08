import Testing
@testable import EngramCore

struct TitleMakerTests {
    @Test func keepsShortFirstLine() {
        #expect(TitleMaker.fallbackTitle(from: "Acheter du lait") == "Acheter du lait")
    }

    @Test func usesFirstNonBlankLineCollapsed() {
        #expect(TitleMaker.fallbackTitle(from: "\n   \n  Première   ligne  \nDeuxième") == "Première ligne")
    }

    @Test func blankTextGetsPlaceholderTitle() {
        #expect(TitleMaker.fallbackTitle(from: "  \n\t ") == "Note sans titre")
    }

    @Test func longSingleWordIsCutWithEllipsis() {
        let title = TitleMaker.fallbackTitle(from: String(repeating: "a", count: 200))
        #expect(title.count == 80)
        #expect(title.hasSuffix("…"))
    }

    @Test func longSentenceIsCutAtAWordBoundary() {
        let text = Array(repeating: "mot", count: 60).joined(separator: " ")
        let title = TitleMaker.fallbackTitle(from: text)
        #expect(title.count <= 80)
        #expect(title.hasSuffix("mot…"))
    }

    @Test func neverBreaksEmojiGraphemes() {
        let family = "👨‍👩‍👧"
        let title = TitleMaker.fallbackTitle(from: Array(repeating: family, count: 50).joined(separator: " "))
        #expect(title.count <= 80)
        #expect(title.allSatisfy { $0 == Character(family) || $0 == " " || $0 == "…" })
    }
}
