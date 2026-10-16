import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// Lot A — la confidentialité est enregistrée avec le classement (F13), une politique inconnue n'autorise aucune sortie,
/// une liste est aussi protégée que son ajout le plus protégé (F01), les partages ne se perdent pas (F19) et chaque passage
/// oublié reste à classer (F05).
struct PrivacyBoundaryStoreTests {
    static let neutralRoute = AnalysisRoute(level: .neutral, provider: "gemini", reason: "Aucune information personnelle.",
                                            needsCloudRetry: false, basis: .judged)
    static let localRoute = AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.ownerKeepLocal,
                                          needsCloudRetry: false, basis: .ownerKeepLocal)

    func thought(_ text: String, kind: MemoryKind = .task, path: [String] = ["Achats"], dates: [String] = []) -> ValidThought {
        ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                     categoryPath: path, mentionedDates: dates)
    }

    func dictate(_ env: StoreTestEnvironment, _ text: String, keepLocal: Bool = false, route: AnalysisRoute?) throws {
        guard case .saved(let interim) = try env.memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        _ = try env.filer.file([thought(text)], sourceID: interim.sourceID, route: route)
        env.dates.advance(by: 60)
    }

    // MARK: F13

    @Test func theRouteIsWrittenWithTheFiling() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Tailler la haie demain à 15 h")
        _ = try env.filer.file([thought("Tailler la haie demain à 15 h", path: ["Maison"], dates: ["demain à 15 h"])],
                               sourceID: interim.sourceID, route: Self.neutralRoute)
        let source = try #require(try env.memories.source(id: interim.sourceID))
        #expect(source.privacyLevel == .neutral)
        #expect(source.privacyBasis == .judged)
        #expect(source.analysisProvider == "gemini")
        #expect(try env.memories.reminderItems().first?.isPrivate == false)
    }

    @Test func aNoteFiledWithoutAKnownPolicyShowsNothingOutside() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Changer le code du casier demain à 15 h")
        _ = try env.filer.file([thought("Changer le code du casier demain à 15 h", path: ["Maison"], dates: ["demain à 15 h"])],
                               sourceID: interim.sourceID)
        #expect(try env.memories.reminderItems().first?.isPrivate == true)
        #expect(try env.memories.recallDocuments().first?.isPrivate == true)
    }

    // MARK: F01

    @Test func aListCompletedByALocalNoteBecomesPrivateEverywhere() throws {
        let env = try StoreTestEnvironment()
        try dictate(env, "Ajoute du lait à ma liste d'épicerie", route: Self.neutralRoute)
        let lists = ListStore(database: env.database, dates: env.dates)
        #expect(try lists.widgetSources().first?.isPrivate == false)
        try dictate(env, "Ajoute du sirop contre la toux à ma liste d'épicerie", keepLocal: true, route: Self.localRoute)
        let list = try #require(try lists.widgetSources().first)
        #expect(list.body.contains("Sirop"))
        #expect(list.isPrivate)
        // Le widget ne montre aucune case ; Retrouver et l'export pour un assistant non plus.
        #expect(ListsSnapshot.make([list], hideItems: false, now: env.dates.now()).lists.first?.open.isEmpty == true)
        let document = try #require(try env.memories.recallDocuments().first { $0.id == list.memoryID })
        #expect(document.isPrivate)
        let export = AssistantExport.text(question: "épicerie", hits: [RecallHit(document: document, score: 1)],
                                          calendar: Calendar(identifier: .gregorian), now: env.dates.now())
        #expect(!export.contains("Sirop"))
        #expect(!export.contains("Lait"))
        // Un ajout neutre plus tard ne rend pas la liste partageable.
        try dictate(env, "Ajoute du pain à ma liste d'épicerie", route: Self.neutralRoute)
        #expect(try lists.widgetSources().first?.isPrivate == true)
    }

    @Test func aLocalListStaysPrivateWhenANeutralNoteAddsToIt() throws {
        let env = try StoreTestEnvironment()
        try dictate(env, "Ajoute des pansements à ma liste de pharmacie", keepLocal: true, route: Self.localRoute)
        try dictate(env, "Ajoute du savon à ma liste de pharmacie", route: Self.neutralRoute)
        #expect(try ListStore(database: env.database, dates: env.dates).widgetSources().first?.isPrivate == true)
    }

    @Test func theMigrationProtectsExistingListsFromAllTheirContributions() throws {
        let env = try StoreTestEnvironment()
        try dictate(env, "Ajoute du lait à ma liste d'épicerie", route: Self.neutralRoute)
        try dictate(env, "Ajoute du sirop à ma liste d'épicerie", keepLocal: true, route: Self.localRoute)
        // Une base d'avant v19 : le masque n'existait pas.
        try env.database.writer.write { db in
            try db.execute(sql: "UPDATE memory_list SET forbidden_mask = 0")
            try Schema.backfillListPrivacy(db)
        }
        #expect(try ListStore(database: env.database, dates: env.dates).widgetSources().first?.isPrivate == true)
    }

    // MARK: F19

    @Test func aSharedItemIsSavedOnceEvenWhenReplayed() throws {
        let env = try StoreTestEnvironment()
        let box = SharedInbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)"))
        try box.add(SharedItem(text: "Lire cet article", link: "https://example.com/a", createdAt: env.dates.now()))
        try box.add(SharedItem(text: "Lire cet article", link: "https://example.com/a", createdAt: env.dates.now().addingTimeInterval(1)))
        let report = env.memories.importShares(from: box)
        // Deux partages distincts du même texte : deux captures (chacune est un geste du propriétaire).
        #expect(report.saved.count == 2)
        #expect(box.pending().items.isEmpty)
        let ids = try env.database.writer.read { db in try String.fetchAll(db, sql: "SELECT import_id FROM source") }
        #expect(Set(ids) == Set(report.saved))
        // Le même identifiant d'import ne recrée rien.
        let again = try env.memories.saveTextNoteWithoutAnalysis("Lire cet article", importID: report.saved[0])
        guard case .duplicate = again else {
            Issue.record("un import rejoué ne doit pas créer une deuxième capture")
            return
        }
    }

    // MARK: F05

    @Test func eachForgottenPassageStaysToFileOnItsOwn() throws {
        let env = try StoreTestEnvironment()
        let text = "Réparer la douche. Payer loyer. Je dois appeler Marc."
        let interim = try env.saveNote(text)
        let repair = ValidThought(title: "Réparer la douche", summary: nil, excerpt: "Réparer la douche", spanStart: 0,
                                  spanEnd: 17, kind: .task, tags: [], categoryPath: ["Maison"], mentionedDates: [])
        _ = try env.filer.file([repair], sourceID: interim.sourceID, route: Self.neutralRoute, keepInterimIfUncovered: true)
        let unsorted = try env.memories.memories(statuses: [.unsorted]).sorted { ($0.spanStart ?? 0) < ($1.spanStart ?? 0) }
        #expect(unsorted.map(\.content) == ["Payer loyer", "Je dois appeler Marc"])
        #expect(unsorted.first?.id == interim.id)
        #expect(unsorted.allSatisfy { $0.analysisVersion == ThoughtFiler.leftoverAnalysisVersion })
        for memory in unsorted {
            let range = NSRange(location: memory.spanStart ?? 0, length: (memory.spanEnd ?? 0) - (memory.spanStart ?? 0))
            #expect((text as NSString).substring(with: range) == memory.content)
        }
    }
}
