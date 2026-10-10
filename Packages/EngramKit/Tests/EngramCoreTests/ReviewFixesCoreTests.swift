import Foundation
import Testing
@testable import EngramCore

/// Corrections issues de la relecture finale P2 + P3 (dates et validation).
struct ReviewFixesCoreTests {
    let calendar = DateResolverTests.calendar
    let now = DateResolverTests.now

    func resolve(_ expression: String) -> ResolvedDate? {
        DateResolver.resolve(expression, relativeTo: now, calendar: calendar)
    }

    // Important 4 — heures de l'après-midi et du soir, durées, fractions, jour et heure séparés.

    @Test(arguments: [
        ("3 h de l'après-midi", 15),
        ("à 8 h ce soir", 20),
        ("vendredi à 7 h du soir", 19),
        ("10 h du matin", 10),
    ])
    func afternoonAndEveningShiftTheHour(expression: String, hour: Int) throws {
        let resolved = try #require(resolve(expression))
        #expect(calendar.component(.hour, from: resolved.date) == hour)
        #expect(resolved.hasTime)
    }

    // « dans 2 heures » n'est plus ici : c'est un moment (maintenant + 2 h), voir DateResolverTests.
    @Test(arguments: ["pendant 3 h", "2 heures de route", "for 2 h", "1/2 litre de lait", "ouvert 24/7"])
    func durationsAndFractionsAreNotDates(expression: String) {
        #expect(resolve(expression) == nil)
    }

    @Test func numericDatesStillWorkWithAContextWord() throws {
        let resolved = try #require(resolve("le 24/11"))
        #expect(resolved.date == DateResolverTests.day(2026, 11, 24))
    }

    @Test func dayAndTimeFromSeparateExpressionsAreCombined() {
        let expected = ResolvedDate(date: DateResolverTests.day(2026, 10, 9, 14, 0), hasTime: true)
        #expect(DateResolver.firstDate(in: ["14 h", "vendredi"], excerpt: "", relativeTo: now, calendar: calendar) == expected)
        #expect(DateResolver.firstDate(in: ["vendredi", "14 h"], excerpt: "", relativeTo: now, calendar: calendar) == expected)
    }

    // Important 5 — les dates relevées par l'IA doivent figurer dans le texte.

    @Test func mentionedDatesMustAppearInTheText() throws {
        let analysis = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Rapport", summary: nil, excerpt: "Remettre le rapport dans deux semaines", kind: .task,
                            tags: [], mentionedDates: ["dans deux semaines", "22/10"], category: "Travail", subcategory: nil),
        ])
        let valid = try AnalysisValidator.validate(analysis, against: "Remettre le rapport dans deux semaines")
        #expect(valid[0].mentionedDates == ["dans deux semaines"])
    }

    // Important 6 — une catégorie proposée sous forme de chemin est découpée.

    @Test(arguments: [
        ("Automobile › Corolla", nil as String?, ["Automobile", "Corolla"]),
        ("Automobile > Corolla", nil as String?, ["Automobile", "Corolla"]),
        ("Automobile", "Automobile › Corolla" as String?, ["Automobile", "Corolla"]),
        ("Automobile/Corolla", nil as String?, ["Automobile", "Corolla"]),
    ])
    func categoryPathsAreSplit(category: String, subcategory: String?, expected: [String]) throws {
        let analysis = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Wipers", summary: nil, excerpt: "wipers", kind: .task, tags: [],
                            mentionedDates: [], category: category, subcategory: subcategory),
        ])
        #expect(try AnalysisValidator.validate(analysis, against: "Acheter des wipers")[0].categoryPath == expected)
    }

    @Test func coverageMeasuresTheShareOfWordsTheExcerptsKeep() {
        let text = "Acheter des wipers pour la Corolla. Penser à rappeler le notaire au sujet de la maison."
        #expect(AnalysisValidator.coverage(of: ["Acheter des wipers pour la Corolla"], in: text) < 0.6)
        #expect(AnalysisValidator.coverage(of: [text], in: text) == 1)
    }
}
