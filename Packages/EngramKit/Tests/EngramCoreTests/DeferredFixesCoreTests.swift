import Foundation
import Testing
@testable import EngramCore

/// Petits défauts relevés aux relectures : heure seule déjà passée, pensées en double.
struct DeferredFixesCoreTests {
    func resolve(_ expression: String) -> ResolvedDate? {
        DateResolver.resolve(expression, relativeTo: DateResolverTests.now, calendar: DateResolverTests.calendar)
    }

    @Test func anHourAlreadyPassedWithoutADayMeansTomorrow() {
        #expect(resolve("à 9 h")?.date == DateResolverTests.day(2026, 10, 9, 9, 0))
        // Une heure encore à venir reste aujourd'hui.
        #expect(resolve("à 14 h")?.date == DateResolverTests.day(2026, 10, 8, 14, 0))
        // Un jour dit explicitement est respecté, même si l'heure est passée.
        #expect(resolve("aujourd'hui à 9 h")?.date == DateResolverTests.day(2026, 10, 8, 9, 0))
    }

    @Test func identicalExcerptsBecomeOneThought() {
        let first = AnalyzedThought(title: "Garage", summary: nil, excerpt: "Appeler le garage", kind: .task, tags: ["auto"],
                                    mentionedDates: ["demain"], category: "Automobile", subcategory: nil)
        let copy = AnalyzedThought(title: "Appel garage", summary: nil, excerpt: "appeler le  garage", kind: .task,
                                   tags: ["appel"], mentionedDates: ["vendredi"], category: "Automobile", subcategory: nil)
        let other = AnalyzedThought(title: "Lait", summary: nil, excerpt: "acheter du lait", kind: .task, tags: [],
                                    mentionedDates: [], category: "Achats", subcategory: nil)
        let merged = DuplicateThoughts.merge(ThoughtAnalysis(thoughts: [first, copy, other]))
        #expect(merged.thoughts.count == 2)
        #expect(merged.thoughts[0].title == "Garage")
        #expect(merged.thoughts[0].mentionedDates == ["demain", "vendredi"])
        #expect(merged.thoughts[0].tags == ["auto", "appel"])
        #expect(merged.thoughts[1].title == "Lait")
    }
}
