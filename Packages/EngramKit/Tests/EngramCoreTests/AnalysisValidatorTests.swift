import Foundation
import Testing
@testable import EngramCore

struct AnalysisValidatorTests {
    let text = "Rappeler d'acheter des wipers pour ma Corolla. Appeler mon gestionnaire de placements."

    func thought(title: String = "Wipers Corolla", excerpt: String, category: String = "Automobile",
                 subcategory: String? = "Corolla", tags: [String] = [], kind: MemoryKind = .task) -> AnalyzedThought {
        AnalyzedThought(title: title, summary: nil, excerpt: excerpt, kind: kind, tags: tags,
                        mentionedDates: [], category: category, subcategory: subcategory)
    }

    @Test func acceptsVerbatimExcerptIgnoringCaseAccentsAndPunctuation() throws {
        let analysis = ThoughtAnalysis(thoughts: [thought(excerpt: "rappeler d’acheter des WIPERS pour ma corolla")])
        let valid = try AnalysisValidator.validate(analysis, against: text)
        #expect(valid.count == 1)
        #expect(valid[0].categoryPath == ["Automobile", "Corolla"])
        #expect(valid[0].kind == .task)
    }

    @Test func rejectsAnInventedExcerpt() {
        #expect(throws: AnalyzerError.invalidOutput) {
            try AnalysisValidator.validate(ThoughtAnalysis(thoughts: [thought(excerpt: "acheter des pneus d'hiver")]), against: text)
        }
    }

    @Test func keepsValidThoughtsAndDropsInventedOnes() throws {
        let analysis = ThoughtAnalysis(thoughts: [
            thought(excerpt: "acheter des wipers"),
            thought(title: "Pneus", excerpt: "changer les pneus"),
        ])
        #expect(try AnalysisValidator.validate(analysis, against: text).map(\.title) == ["Wipers Corolla"])
    }

    @Test func matchesOnWordBoundariesOnly() {
        #expect(TextNormalizer.containsPhrase("lait", in: "Acheter de la laitue") == false)
        #expect(TextNormalizer.containsPhrase("la laitue", in: "Acheter de la laitue") == true)
        #expect(TextNormalizer.containsPhrase("  ", in: "abc") == false)
    }

    @Test func shortensLongTitlesAndReplacesEmptyOnes() throws {
        let analysis = ThoughtAnalysis(thoughts: [
            thought(title: String(repeating: "très long titre ", count: 10), excerpt: "pour ma Corolla"),
            thought(title: "   ", excerpt: "Appeler mon gestionnaire de placements", category: "Finance", subcategory: nil),
        ])
        let valid = try AnalysisValidator.validate(analysis, against: text)
        #expect(valid[0].title.count <= 80)
        #expect(valid[1].title == "Appeler mon gestionnaire de placements")
    }

    @Test func cleansCategoriesAndIgnoresRedundantOrEmptySubcategories() throws {
        let analysis = ThoughtAnalysis(thoughts: [
            thought(excerpt: "pour ma Corolla", category: "  Automobile  ", subcategory: "automobile"),
            thought(excerpt: "Appeler mon gestionnaire", category: "Finance", subcategory: "  "),
            thought(excerpt: "de placements", category: "   ", subcategory: "Placements"),
        ])
        let valid = try AnalysisValidator.validate(analysis, against: text)
        #expect(valid.map(\.categoryPath) == [["Automobile"], ["Finance"], []])
    }

    @Test func capsCategoryNamesAt40Characters() throws {
        let analysis = ThoughtAnalysis(thoughts: [thought(excerpt: "pour ma Corolla", category: String(repeating: "a", count: 60), subcategory: nil)])
        #expect(try AnalysisValidator.validate(analysis, against: text)[0].categoryPath[0].count == 40)
    }

    @Test func deduplicatesAndCapsTags() throws {
        let analysis = ThoughtAnalysis(thoughts: [thought(excerpt: "pour ma Corolla", tags: ["Achat", "achat", "Voiture", " ", "Phares", "Garage"])])
        #expect(try AnalysisValidator.validate(analysis, against: text)[0].tags == ["Achat", "Voiture", "Phares"])
    }

    @Test func computesTheUTF16SpanWhenTheExcerptIsFoundAsIs() throws {
        let excerpt = "Appeler mon gestionnaire de placements"
        let analysis = ThoughtAnalysis(thoughts: [thought(excerpt: excerpt, category: "Finance", subcategory: nil)])
        let valid = try AnalysisValidator.validate(analysis, against: text)
        let location = (text as NSString).range(of: excerpt).location
        #expect(valid[0].spanStart == location)
        #expect(valid[0].spanEnd == location + (excerpt as NSString).length)
    }

    @Test func rejectsAnEmptyAnalysis() {
        #expect(throws: AnalyzerError.invalidOutput) {
            try AnalysisValidator.validate(ThoughtAnalysis(thoughts: []), against: text)
        }
    }
}
