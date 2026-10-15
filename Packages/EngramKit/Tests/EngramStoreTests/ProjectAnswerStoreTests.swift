import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// P45 — la réponse vient des notes du dossier du projet.
struct ProjectAnswerStoreTests {
    func file(_ env: StoreTestEnvironment, _ title: String, kind: MemoryKind) throws {
        let interim = try env.saveNote(title)
        _ = try env.filer.file([ValidThought(title: title, summary: nil, excerpt: title, spanStart: nil, spanEnd: nil, kind: kind,
                                             tags: [], categoryPath: ["Projets", "Chalet"], mentionedDates: [])],
                               sourceID: interim.sourceID)
        env.dates.advance(by: 60 * 60)
    }

    @Test func whatIPlannedForTheCottage() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Réparer le quai", kind: .task)
        try file(env, "Acheter du bois", kind: .task)
        try file(env, "Budget du chalet", kind: .info)
        #expect(try env.categories.projectAnswer(to: "Qu'est-ce que j'avais prévu pour le chalet?", recent: nil)
            == "Pour « Projets › Chalet », à faire : Réparer le quai et Acheter du bois. Aussi noté : Budget du chalet.")
        // « Ce projet » : celui de la dernière dictée, même des heures plus tard.
        let latest = try env.memories.latestContext()
        #expect(latest?.folders == ["Projets › Chalet"])
        #expect(try env.categories.projectAnswer(to: "Qu'est-ce qu'il reste à faire pour ce projet?", recent: latest)?
            .hasPrefix("Pour « Projets › Chalet », à faire :") == true)
        #expect(try env.categories.projectAnswer(to: "C'est quoi le numéro du garage?", recent: latest) == nil)
    }
}
