import Foundation
import Testing
@testable import EngramCore

/// « Retrouver » : comprendre une question floue, puis trouver les vraies notes (jamais en inventer).
/// Les questions sont celles du propriétaire ; les notes sont inventées.
struct RecallQueryTests {
    static let calendar: Calendar = {
        var calendar = DateResolverTests.calendar
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Jeudi 8 octobre 2026, 10 h, à Toronto.
    static let now = DateResolverTests.now

    static func day(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date { DateResolverTests.day(2026, month, day, hour, 0) }

    func parse(_ question: String) -> RecallQuery { RecallQuery.parse(question, now: Self.now, calendar: Self.calendar) }

    @Test func aForgottenTaskThisWeekListsTasks() {
        let query = parse("Je me rappelle que j'avais quelque chose à faire cette semaine, mais je ne sais plus quoi.")
        #expect(query.intent == .list)
        #expect(query.kinds == [.task, .appointment])
        #expect(query.keywords.isEmpty)
        #expect(query.period == DateInterval(start: Self.day(10, 5), end: Self.day(10, 12)))
        #expect(query.periodMeansDue)
    }

    @Test func anIdeaFromAFewDaysAgo() {
        let query = parse("Il me semble que j'avais eu une idée pour améliorer mon application il y a quelques jours. C'était quoi ?")
        #expect(query.intent == .find)
        #expect(query.kinds == [.idea])
        #expect(query.keywords == ["ameliorer", "application"])
        #expect(query.period == DateInterval(start: Self.now.addingTimeInterval(-10 * 86_400), end: Self.now))
        #expect(!query.periodMeansDue)
    }

    @Test func aRestaurantName() {
        let query = parse("C'était quoi déjà le nom du restaurant que j'avais dit vouloir essayer ?")
        #expect(query.intent == .find)
        #expect(query.keywords == ["restaurant", "essayer"])
        #expect(query.kinds.isEmpty)
        #expect(query.period == nil)
    }

    @Test func aCarProblemSomeTimeAgo() {
        let query = parse("J'avais parlé d'un problème avec ma voiture il y a quelque temps. Retrouve-moi ça.")
        #expect(query.intent == .find)
        #expect(query.keywords == ["probleme", "voiture"])
        #expect(query.period == nil)
    }

    @Test func todaysPlansSummariesAndRecentTasks() {
        let today = parse("Qu'est-ce que j'avais prévu de faire aujourd'hui ?")
        #expect(today.intent == .list)
        #expect(today.periodMeansDue)
        #expect(today.period == DateInterval(start: Self.day(10, 8), end: Self.day(10, 9)))

        let summary = parse("Résume-moi les idées que j'ai enregistrées cette semaine.")
        #expect(summary.intent == .summarize)
        #expect(summary.kinds == [.idea])
        #expect(!summary.periodMeansDue)

        let recent = parse("Quelles tâches ai-je mentionnées récemment ?")
        #expect(recent.intent == .list)
        #expect(recent.kinds == [.task, .appointment])
        #expect(recent.period == DateInterval(start: Self.now.addingTimeInterval(-14 * 86_400), end: Self.now))

        let project = parse("Retrouve-moi ce que j'avais dit concernant mon projet.")
        #expect(project.intent == .find)
        #expect(project.keywords == ["projet"])
    }

    @Test func englishQuestionsToo() {
        let query = parse("What did I have to do tomorrow?")
        #expect(query.intent == .list)
        #expect(query.period == DateInterval(start: Self.day(10, 9), end: Self.day(10, 10)))
        #expect(query.periodMeansDue)
    }
}

struct RecallRankerTests {
    static let now = RecallQueryTests.now

    func parse(_ question: String) -> RecallQuery { RecallQuery.parse(question, now: Self.now, calendar: RecallQueryTests.calendar) }

    func doc(_ title: String, text: String? = nil, kind: MemoryKind = .task, status: MemoryStatus = .active,
             daysAgo: Double = 1, due: Date? = nil, categories: [String] = []) -> RecallDocument {
        RecallDocument(id: UUID(), title: title, text: text ?? title, kind: kind, status: status,
                       capturedAt: Self.now.addingTimeInterval(-daysAgo * 86_400), dueAt: due, categories: categories, tags: [])
    }

    @Test func aCarProblemIsFoundThroughRelatedWordsAndItsFolder() {
        let car = doc("Le char fait un bruit bizarre", daysAgo: 40, categories: ["Automobile"])
        let docs = [car, doc("Acheter du lait", categories: ["Achats"]),
                    doc("Une app de recettes", kind: .idea, categories: ["Projets"])]
        let hits = RecallRanker.rank(docs, for: parse("J'avais parlé d'un problème avec ma voiture il y a quelque temps"), now: Self.now)
        #expect(hits.map(\.document.id) == [car.id])
    }

    @Test func theRestaurantIsFoundWithTheWordResto() {
        let resto = doc("Essayer le resto Chez Gérard", kind: .idea, daysAgo: 12, categories: ["Loisirs"])
        let docs = [resto, doc("Réserver le garage pour les pneus", categories: ["Automobile"])]
        let hits = RecallRanker.rank(docs, for: parse("C'était quoi déjà le nom du restaurant que j'avais dit vouloir essayer ?"),
                                     now: Self.now)
        #expect(hits.first?.document.id == resto.id)
        #expect(hits.count == 1)
    }

    @Test func aForgottenTaskThisWeekListsOnlyThisWeeksOpenTasks() {
        let insurance = doc("Appeler l'assurance pour une réévaluation", daysAgo: 2, categories: ["Finance"])
        let bill = doc("Payer la facture d'Hydro", daysAgo: 30, due: RecallQueryTests.day(10, 9), categories: ["Finance"])
        let docs = [insurance, bill,
                    doc("Laver l'auto", status: .archived, daysAgo: 1),
                    doc("Renouveler le passeport", daysAgo: 21, due: RecallQueryTests.day(11, 20)),
                    doc("Une app de recettes", kind: .idea, daysAgo: 1)]
        let hits = RecallRanker.rank(docs, for: parse("Je me rappelle que j'avais quelque chose à faire cette semaine, mais je ne sais plus quoi."),
                                     now: Self.now)
        #expect(Set(hits.map(\.document.id)) == [insurance.id, bill.id])
    }

    @Test func nothingRelatedMeansNothingFound() {
        let docs = [doc("Réserver le garage pour les pneus", categories: ["Automobile"]), doc("Acheter du lait", categories: ["Achats"])]
        #expect(RecallRanker.rank(docs, for: parse("C'était quoi le nom du restaurant ?"), now: Self.now).isEmpty)
    }

    @Test func ideasOfTheWeekAreListedNewestFirst() {
        let older = doc("Idée : un jardin sur le balcon", kind: .idea, daysAgo: 3)
        let newer = doc("Idée : une page d'accueil plus simple", kind: .idea, daysAgo: 1)
        let docs = [older, newer, doc("Acheter du lait", daysAgo: 1), doc("Idée : vieux projet", kind: .idea, daysAgo: 40)]
        let hits = RecallRanker.rank(docs, for: parse("Résume-moi les idées que j'ai enregistrées cette semaine."), now: Self.now)
        #expect(hits.map(\.document.id) == [newer.id, older.id])
    }

    @Test func meaningAloneCanFindANoteWithoutCommonWords() {
        let gearbox = doc("La transmission grince en reculant", daysAgo: 20)
        let milk = doc("Acheter du lait", daysAgo: 1)
        let hits = RecallRanker.rank([gearbox, milk], for: parse("Le souci mécanique de l'autre jour"), now: Self.now,
                                     semanticScores: [gearbox.id: 0.82, milk.id: 0.12])
        #expect(hits.map(\.document.id) == [gearbox.id])
    }

    @Test func theAnswerWithoutAModelOnlyTellsWhatWasFound() {
        let insurance = doc("Appeler l'assurance pour une réévaluation", daysAgo: 2)
        let one = RecallAnswer.fallback(for: parse("C'était quoi déjà l'affaire de l'assurance ?"),
                                        hits: [RecallHit(document: insurance, score: 1)])
        #expect(one.contains("Appeler l'assurance pour une réévaluation"))
        #expect(RecallAnswer.fallback(for: parse("Le restaurant ?"), hits: []) == RecallAnswer.nothingFound)
    }
}
