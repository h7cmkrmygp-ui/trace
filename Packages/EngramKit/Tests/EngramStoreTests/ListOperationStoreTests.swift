import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// F08 — chaque opération de liste a une identité stable (source, type, liste, chose) : deux ajouts distincts dans une même
/// dictée sont tous deux appliqués, un rejeu n'ajoute rien, et une retranscription légèrement différente ne refait pas une
/// opération déjà faite (une case cochée depuis reste cochée).
struct ListOperationStoreTests {
    static let route = AnalysisRoute(level: .neutral, provider: "gemini", reason: "Neutre.", needsCloudRetry: false,
                                     basis: .judged)

    func thoughts(_ excerpts: [String], in text: String) -> [ValidThought] {
        excerpts.map { excerpt in
            let range = (text as NSString).range(of: excerpt)
            return ValidThought(title: excerpt, summary: nil, excerpt: excerpt, spanStart: range.location,
                                spanEnd: range.location + range.length, kind: .task, tags: [], categoryPath: ["Achats"],
                                mentionedDates: [])
        }
    }

    func groceries(_ env: StoreTestEnvironment) throws -> String {
        let list = try #require(try ListStore(database: env.database, dates: env.dates).widgetSources().first)
        return list.body
    }

    func refile(_ env: StoreTestEnvironment, _ sourceID: UUID) throws {
        try env.database.writer.write { db in
            try db.execute(sql: "UPDATE source SET processing_status = 'waiting' WHERE id = ?", arguments: [sourceID])
        }
    }

    @Test func twoAdditionsToTheSameListInOneDictationAreBothApplied() throws {
        let env = try StoreTestEnvironment()
        let text = "Ajoute du lait à ma liste d'épicerie. Ajoute du pain à ma liste d'épicerie."
        let interim = try env.saveNote(text)
        _ = try env.filer.file(thoughts(["Ajoute du lait à ma liste d'épicerie", "Ajoute du pain à ma liste d'épicerie"],
                                        in: text), sourceID: interim.sourceID, route: Self.route)
        #expect(try groceries(env) == "☐ Lait\n☐ Pain")
    }

    @Test func replayingAFilingDoesNotRedoItsOperations() throws {
        let env = try StoreTestEnvironment()
        let text = "Ajoute du lait à ma liste d'épicerie"
        let interim = try env.saveNote(text)
        _ = try env.filer.file(thoughts([text], in: text), sourceID: interim.sourceID, route: Self.route)
        // Le lait est acheté entre-temps.
        let check = try env.saveNote("Coche le lait")
        _ = try env.filer.file(thoughts(["Coche le lait"], in: "Coche le lait"), sourceID: check.sourceID, route: Self.route)
        #expect(try groceries(env) == "☑ Lait")
        // Le même classement rejoué (reprise après un arrêt) : rien n'est refait, le lait reste coché.
        try refile(env, interim.sourceID)
        _ = try env.filer.file(thoughts([text], in: text), sourceID: interim.sourceID, route: Self.route)
        #expect(try groceries(env) == "☑ Lait")
    }

    @Test func aSlightlyDifferentRetranscriptionDoesNotRedoAnOperation() throws {
        let env = try StoreTestEnvironment()
        let voice = try env.memories.saveVoiceNote(audioPath: "audio/l.caf", duration: 2,
                                                   transcript: "Ajoute du lait à ma liste d'épicerie", languages: [], engine: nil)
        _ = try env.filer.file(thoughts(["Ajoute du lait à ma liste d'épicerie"], in: "Ajoute du lait à ma liste d'épicerie"),
                               sourceID: voice.sourceID, route: Self.route)
        let check = try env.saveNote("Coche le lait")
        _ = try env.filer.file(thoughts(["Coche le lait"], in: "Coche le lait"), sourceID: check.sourceID, route: Self.route)
        let retranscribed = "Euh, ajoute du lait à ma liste d'épicerie"
        try env.memories.retranscribe(sourceID: voice.sourceID, transcript: retranscribed, languages: [], engine: "whisperkit")
        _ = try env.filer.file(thoughts([retranscribed], in: retranscribed), sourceID: voice.sourceID, route: Self.route)
        #expect(try groceries(env) == "☑ Lait")
    }
}
