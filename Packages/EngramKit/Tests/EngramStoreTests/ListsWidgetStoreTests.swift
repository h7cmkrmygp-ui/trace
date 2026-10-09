import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// P25 — ce que le widget « Liste » lit : chaque liste, son texte, et si elle est privée.
struct ListsWidgetStoreTests {
    func dictate(_ env: StoreTestEnvironment, _ text: String, keepLocal: Bool = false) throws {
        guard case .saved(let interim) = try env.memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: ["Achats"], mentionedDates: [])
        _ = try env.filer.file([thought], sourceID: interim.sourceID)
    }

    @Test func widgetSourcesCarryTheTextAndThePrivacy() throws {
        let env = try StoreTestEnvironment()
        try dictate(env, "Ajoute du lait à ma liste d'épicerie")
        env.dates.advance(by: 60)
        try dictate(env, "Ajoute un médicament à ma liste de pharmacie", keepLocal: true)
        let sources = try ListStore(database: env.database, dates: env.dates).widgetSources()
        #expect(sources.map(\.name) == ["Pharmacie", "Épicerie"])
        #expect(sources.first { $0.name == "Épicerie" }?.body == "☐ Lait")
        #expect(sources.first { $0.name == "Épicerie" }?.isPrivate == false)
        #expect(sources.first { $0.name == "Pharmacie" }?.isPrivate == true)
    }
}
