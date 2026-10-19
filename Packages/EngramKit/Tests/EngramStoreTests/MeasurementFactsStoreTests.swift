import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// F15 — le graphique du poids ne montre que les mesures du propriétaire, pas celles d'un tiers, d'une négation ou d'un
/// ancien poids ; une négation classée ne crée pas de mesure.
struct MeasurementFactsStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, polarity: Polarity = .affirmative) throws {
        let interim = try env.saveNote(text)
        _ = try env.filer.file([ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil,
                                             kind: .info, tags: [], categoryPath: ["Santé"], mentionedDates: [],
                                             intent: .fact, polarity: polarity)],
                               sourceID: interim.sourceID)
        env.dates.advance(by: 3_600)
    }

    @Test func theWeightChartOnlyShowsTheOwnersWeight() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Je pèse 162 livres")
        try file(env, "Mon frère pèse 180 livres")
        try file(env, "Je ne pèse pas 200 livres")
        try file(env, "Je pesais 190 livres l'an passé")
        let store = MeasurementStore(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
        #expect(try store.points(metric: .weight, weightUnit: "lb").map(\.value) == [162])
        // Le relevé de fond (au lancement) suit la même règle.
        _ = try store.backfill()
        #expect(try store.points(metric: .weight, weightUnit: "lb").map(\.value) == [162])
    }
}
