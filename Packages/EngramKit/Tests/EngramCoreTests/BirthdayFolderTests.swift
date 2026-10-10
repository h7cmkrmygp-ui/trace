import Foundation
import Testing
@testable import EngramCore

/// P33 — une note qui dit seulement une fête va dans « Anniversaires », comme une chose à retenir (pas une tâche) ;
/// une tâche autour d'une fête (« acheter un cadeau ») reste une tâche.
struct BirthdayFolderTests {
    func validate(_ text: String, _ thoughts: [AnalyzedThought]) throws -> [ValidThought] {
        try AnalysisValidator.validate(ThoughtAnalysis(thoughts: thoughts), against: text)
    }

    func thought(_ excerpt: String, kind: MemoryKind = .task, category: String = "Famille", dates: [String] = []) -> AnalyzedThought {
        AnalyzedThought(title: excerpt, summary: nil, excerpt: excerpt, kind: kind, tags: [], mentionedDates: dates,
                        category: category, subcategory: nil, categoryReason: "Une personne de la famille.")
    }

    @Test func aNoteThatOnlySaysABirthdayIsSomethingToRemember() {
        #expect(BirthdayParser.isOnlyABirthday("Retiens l'anniversaire de Inès c'est le 13 octobre"))
        #expect(BirthdayParser.isOnlyABirthday("C'est la fête de Marc le premier mars"))
        #expect(BirthdayParser.isOnlyABirthday("Sophie Tremblay est née le 24 décembre 1990"))
        #expect(BirthdayParser.isOnlyABirthday("N'oublie pas que la fête à Léa, c'est le 2 juin"))
        #expect(!BirthdayParser.isOnlyABirthday("Acheter un cadeau pour la fête de Julie le 12 mars"))
        #expect(!BirthdayParser.isOnlyABirthday("Inès fête ses 30 ans le 13 octobre, faut organiser un party"))
        #expect(!BirthdayParser.isOnlyABirthday("Appeler le garage pour les pneus"))
    }

    @Test func aBirthdayGoesInAnniversairesAndIsNotATask() throws {
        let text = "Retiens l'anniversaire de Inès c'est le 13 octobre"
        let valid = try #require(try validate(text, [thought(text, dates: ["13 octobre"])]).first)
        #expect(valid.kind == .info)
        #expect(valid.categoryPath == ["Anniversaires"])
        #expect(valid.birthdayOf == "Inès")
        #expect(valid.categoryReason?.contains("anniversaires") == true)
        // La date reste dans la note ; c'est la page d'Inès qui rappelle la fête, chaque année.
        #expect(valid.mentionedDates == ["13 octobre"])
    }

    @Test func anIncompleteExcerptIsReadWithTheWholeNote() throws {
        let text = "Retiens l'anniversaire de Inès c'est le 13 octobre"
        let valid = try #require(try validate(text, [thought("Inès c'est le 13 octobre")]).first)
        #expect(valid.birthdayOf == "Inès")
        #expect(valid.categoryPath == ["Anniversaires"])
    }

    @Test func aTaskAroundABirthdayStaysATask() throws {
        let text = "Acheter un cadeau pour la fête de Julie le 12 mars"
        let valid = try #require(try validate(text, [thought(text, category: "Achats", dates: ["12 mars"])]).first)
        #expect(valid.kind == .task)
        #expect(valid.categoryPath == ["Achats"])
        #expect(valid.birthdayOf == nil)
    }

    @Test func onlyTheBirthdayPartOfANoteChanges() throws {
        let text = "Retiens la fête à Inès, c'est le 13 octobre, pis acheter du lait"
        let valid = try validate(text, [thought("Retiens la fête à Inès, c'est le 13 octobre"),
                                         thought("acheter du lait", category: "Épicerie")])
        try #require(valid.count == 2)
        #expect(valid[0].categoryPath == ["Anniversaires"])
        #expect(valid[0].kind == .info)
        #expect(valid[1].categoryPath == ["Épicerie"])
        #expect(valid[1].kind == .task)
        #expect(valid[1].birthdayOf == nil)
    }
}
