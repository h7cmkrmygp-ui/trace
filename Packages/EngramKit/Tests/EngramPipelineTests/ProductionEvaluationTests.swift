import EngramCore
import EngramStore
import EngramTesting
import Foundation
import Testing
@testable import EngramPipeline

/// F20 — l'évaluation traverse le vrai chemin (validation, plan, rangement, stockage) sur un corpus de dictées inventées,
/// avec un jeu de développement et un jeu de contrôle. Bloquants : aucune opération issue d'une négation, d'une
/// condition, d'une question ou d'une citation, aucun achat non demandé, aucune dictée perdue, aucun doublon, aucune
/// fuite d'une note gardée sur l'iPhone.
struct ProductionEvaluationTests {
    static let fictionalNames: Set<String> = ["Inès", "Léo", "Maëlle", "Noé"]

    @Test func theCorpusIsLargeFictionalAndSplit() {
        let cases = EvaluationCorpus.cases
        #expect((300...600).contains(cases.count))
        #expect(Set(cases.map(\.id)).count == cases.count)
        let heldout = cases.filter { $0.split == .heldout }
        #expect(heldout.count * 5 >= cases.count)
        for family in Set(cases.map(\.family)) {
            #expect(cases.contains { $0.family == family && $0.split == .dev }, "\(family)")
            #expect(cases.contains { $0.family == family && $0.split == .heldout }, "\(family)")
        }
        // Seuls des prénoms inventés, et au moins des paires minimales sur l'action et l'achat.
        let people = Set(cases.flatMap { $0.oracle.thoughts.flatMap(\.people) })
        #expect(people.isSubset(of: Self.fictionalNames))
        #expect(cases.contains { $0.family == "obligation" } && cases.contains { $0.family == "achat" })
        #expect(cases.filter { $0.expected.forbidsListOperation }.count >= 40)
        #expect(cases.contains { $0.keepLocal })
    }

    @Test func theCorrectReadingGivesTheExpectedEffectsEverywhere() async {
        var failures: [String] = []
        for item in EvaluationCorpus.cases {
            let result = await ProductionEvaluator.evaluate(item)
            if !result.passed { failures.append("\(item.id) « \(item.text) » : \(result.mismatches) \(result.blocking)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    @Test func aWrongReadingNeverProducesABlockingEffect() async {
        var blocked: [String] = []
        for item in EvaluationCorpus.cases {
            guard let adversary = item.adversary else { continue }
            let result = await ProductionEvaluator.evaluate(item, reading: adversary)
            if !result.blocking.isEmpty { blocked.append("\(item.id) « \(item.text) » : \(result.blocking)") }
        }
        #expect(EvaluationCorpus.cases.filter { $0.adversary != nil }.count >= 100)
        #expect(blocked.isEmpty, "\(blocked.prefix(10))")
    }

    // MARK: L'évaluateur lui-même

    static func thought(_ excerpt: String, kind: MemoryKind, intent: IntentType, list: String? = nil, items: [String] = [],
                        dates: [String] = []) -> AnalyzedThought {
        AnalyzedThought(title: excerpt, summary: nil, excerpt: excerpt, kind: kind, tags: [], mentionedDates: dates,
                        category: "Divers", subcategory: nil, listName: list, listItems: items, intent: intent)
    }

    @Test func aWrongSecondThoughtFailsTheCase() async {
        let text = "Lundi, je dois laver l'auto. Il me faut aussi du café."
        let first = Self.thought("Lundi, je dois laver l'auto", kind: .task, intent: .obligation, dates: ["Lundi"])
        let item = ProductionCase(id: "deux-pensees", split: .dev, family: "deux-intentions", text: text,
                                  expected: ExpectedEffects(listAdds: ["epicerie|cafe"], noteKinds: [.task], dueCount: 1),
                                  oracle: ThoughtAnalysis(thoughts: [
                                      first,
                                      Self.thought("Il me faut aussi du café", kind: .other, intent: .purchase,
                                                   list: "épicerie", items: ["Café"]),
                                  ]))
        #expect(await ProductionEvaluator.evaluate(item).passed)
        // La deuxième pensée lue comme une préférence : le cas échoue.
        let wrong = ThoughtAnalysis(thoughts: [
            first, Self.thought("Il me faut aussi du café", kind: .preference, intent: .preference),
        ])
        #expect(await !ProductionEvaluator.evaluate(item, reading: wrong).passed)
    }

    @Test func anUnrequestedPurchaseBlocks() async {
        let text = "Je dois laver l'auto"
        let item = ProductionCase(id: "achat-non-demande", split: .dev, family: "obligation", text: text,
                                  expected: ExpectedEffects(noteKinds: [.task], dueCount: 0),
                                  oracle: ThoughtAnalysis(thoughts: [Self.thought(text, kind: .task, intent: .obligation)]))
        // Une lecture qui ajoute vraiment quelque chose à une liste (la phrase le permet) alors que la dictée ne le demandait pas.
        let shopping = "Il me faut du café"
        let pushed = ProductionCase(id: "achat-impose", split: .dev, family: "achat", text: shopping,
                                    expected: ExpectedEffects(noteKinds: [.task]),
                                    oracle: ThoughtAnalysis(thoughts: [
                                        Self.thought(shopping, kind: .other, intent: .purchase, list: "épicerie",
                                                     items: ["Café"]),
                                    ]))
        #expect(await ProductionEvaluator.evaluate(item).blocking.isEmpty)
        #expect(await ProductionEvaluator.evaluate(pushed).blocking.contains(.unrequestedOperation))
    }

    @Test func aLocalNoteSentOnlineBlocks() async {
        let text = "Je dois laver l'auto"
        let item = ProductionCase(id: "fuite", split: .dev, family: "obligation", text: text, keepLocal: true,
                                  expected: ExpectedEffects(noteKinds: [.task], dueCount: 0),
                                  oracle: ThoughtAnalysis(thoughts: [Self.thought(text, kind: .task, intent: .obligation)]))
        let leaking: @Sendable (MemoryStore) -> any MemoryAnalyzer = { store in LeakingAnalyzer(store: store, reading: item.oracle) }
        #expect(await ProductionEvaluator.evaluate(item, makeAnalyzer: leaking).blocking.contains(.localLeak))
        #expect(await ProductionEvaluator.evaluate(item).blocking.isEmpty)
    }
}

/// Un analyseur qui « envoie » la note en ligne (il écrit un reçu d'envoi) : sert à vérifier que l'évaluateur le voit.
struct LeakingAnalyzer: MemoryAnalyzer {
    let store: MemoryStore
    let reading: ThoughtAnalysis

    func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis { reading }

    func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        try store.recordTransmission(TransmissionEvent(id: UUID(), sourceID: context.sourceID, provider: "gemini",
                                                       status: .succeeded))
        return reading
    }
}
