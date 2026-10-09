import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P9 — les personnes et les lieux de la mémoire : reconnus au classement, reliés d'une note à l'autre, et toujours
/// sous le contrôle du propriétaire (retirer, renommer, fusionner, « ce n'est pas une personne »).
struct EntityStoreTests {
    func thought(_ text: String, kind: MemoryKind = .task, people: [String] = [], places: [String] = []) -> ValidThought {
        ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                     categoryPath: ["Famille"], mentionedDates: [], people: people, places: places)
    }

    /// Classe une note inventée ; renvoie la note classée.
    @discardableResult
    func file(_ env: StoreTestEnvironment, _ valid: ValidThought) throws -> Memory {
        let interim = try env.saveNote(valid.excerpt)
        return try #require(try env.filer.file([valid], sourceID: interim.sourceID).memories.first)
    }

    func entities(_ env: StoreTestEnvironment) -> EntityStore {
        EntityStore(database: env.database, dates: env.dates)
    }

    @Test func theMigrationCreatesTheTables() throws {
        let env = try StoreTestEnvironment()
        let tables = try env.database.writer.read { db in
            try ["entity", "entity_alias", "memory_entity"].map { try db.tableExists($0) }
        }
        #expect(tables == [true, true, true])
    }

    @Test func filingLinksThePeopleAndPlacesOfANote() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, thought("Appeler Julie avant d'aller au Costco", people: ["Julie"], places: ["au Costco"]))
        let found = try entities(env).entities(for: memory.id)
        #expect(Set(found.map(\.name)) == ["Julie", "Costco"])
        #expect(found.first { $0.name == "Julie" }?.kind == .person)
        #expect(found.first { $0.name == "Costco" }?.kind == .place)
    }

    @Test func theSamePersonIsOnePageWithItsNotesAndTasks() throws {
        let env = try StoreTestEnvironment()
        try file(env, thought("Appeler mon manager pour le quart", people: ["mon manager"]))
        env.dates.advance(by: 3_600)
        try file(env, thought("Le manager a dit oui pour vendredi", kind: .info, people: ["le manager"]))
        let summaries = try entities(env).summaries(kind: .person)
        let manager = try #require(summaries.first)
        #expect(summaries.count == 1)
        #expect(manager.entity.name == "Mon manager")
        #expect(manager.noteCount == 2)
        #expect(manager.openTaskCount == 1)
        #expect(manager.lastMentionedAt == env.dates.now())
        #expect(try entities(env).memories(for: manager.entity.id).map(\.title)
            == ["Le manager a dit oui pour vendredi", "Appeler mon manager pour le quart"])
    }

    @Test func aNameRemovedByTheOwnerIsNeverPutBackByTheAI() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, thought("Souper avec Julie", people: ["Julie"]))
        let store = entities(env)
        let julie = try #require(try store.entities(for: memory.id).first)
        try store.removeEntity(julie.id, from: memory.id)
        #expect(try store.entities(for: memory.id).isEmpty)
        let outcome = try env.database.writer.write { db in
            try store.link(db, memoryID: memory.id, entityID: julie.id, origin: .ai, now: env.dates.now())
        }
        #expect(outcome == .skippedRejectedByUser)
        #expect(try store.summaries(kind: .person).isEmpty)
    }

    @Test func theOwnerCanAddANameToANote() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, thought("Préparer le cadeau"))
        let added = try entities(env).addEntity(named: "chez Grand-maman", kind: .place, to: memory.id)
        #expect(added.name == "Grand-maman")
        #expect(try entities(env).entities(for: memory.id).map(\.id) == [added.id])
        #expect(throws: StoreError.invalidName) { try entities(env).addEntity(named: "  ", kind: .person, to: memory.id) }
    }

    @Test func aHiddenNameDisappearsAndIsNotRecreated() throws {
        let env = try StoreTestEnvironment()
        let first = try file(env, thought("Acheter du Tylenol", people: ["Tylenol"]))
        let store = entities(env)
        let wrong = try #require(try store.entities(for: first.id).first)
        try store.hide(wrong.id)
        #expect(try store.summaries(kind: .person).isEmpty)
        #expect(try store.entities(for: first.id).isEmpty)
        let second = try file(env, thought("Encore du Tylenol", people: ["Tylenol"]))
        #expect(try store.entities(for: second.id).isEmpty)
    }

    @Test func mergingMovesTheNotesAndRemembersTheOldName() throws {
        let env = try StoreTestEnvironment()
        let a = try file(env, thought("Appeler Julie", people: ["Julie"]))
        let b = try file(env, thought("Cadeau pour Julie T.", people: ["Julie T."]))
        let store = entities(env)
        let julie = try #require(try store.entities(for: a.id).first)
        let other = try #require(try store.entities(for: b.id).first)
        try store.merge(other.id, into: julie.id)
        #expect(try store.entity(id: other.id) == nil)
        #expect(try store.entities(for: b.id).map(\.id) == [julie.id])
        #expect(try store.summaries(kind: .person).map(\.noteCount) == [2])
        // Plus tard, « Julie T. » va directement à Julie.
        let c = try file(env, thought("Julie T. arrive samedi", people: ["Julie T."]))
        #expect(try store.entities(for: c.id).map(\.id) == [julie.id])
    }

    @Test func renamingToAnExistingNameMerges() throws {
        let env = try StoreTestEnvironment()
        let a = try file(env, thought("Voir Marc", people: ["Marc"]))
        let b = try file(env, thought("Voir Marco", people: ["Marco"]))
        let store = entities(env)
        let marco = try #require(try store.entities(for: b.id).first)
        let kept = try store.rename(marco.id, to: "marc")
        #expect(kept.id == (try store.entities(for: a.id).first?.id))
        #expect(try store.summaries(kind: .person).count == 1)
        let renamed = try store.rename(kept.id, to: "Marc-André")
        #expect(renamed.name == "Marc-André")
    }

    @Test func recallSeesTheNamesOfANote() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, thought("Lui rapporter son livre", people: ["Lui"], places: []))
        _ = try entities(env).addEntity(named: "Julie", kind: .person, to: memory.id)
        let document = try #require(try env.memories.recallDocuments().first { $0.id == memory.id })
        #expect(document.tags.contains("Julie"))
    }

    @Test func theExportContainsPeopleAndPlaces() throws {
        let env = try StoreTestEnvironment()
        try file(env, thought("Appeler Julie", people: ["Julie"]))
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"entities\""))
        #expect(json.contains("\"entity_assignments\""))
        #expect(json.contains("Julie"))
    }

    /// Les anciennes notes : la reconnaissance des noms de l'iPhone les relit, sans rien envoyer.
    struct FakeRecognizer: EntityRecognizer {
        func names(in text: String) -> [RecognizedName] {
            var found: [RecognizedName] = []
            if text.contains("Julie") { found.append(RecognizedName(name: "Julie", kind: .person)) }
            if text.contains("Costco") { found.append(RecognizedName(name: "Costco", kind: .place)) }
            found.append(RecognizedName(name: "Inventé", kind: .person))
            return found
        }
    }

    @Test func oldNotesAreReadAgainOnTheIPhone() throws {
        let env = try StoreTestEnvironment()
        let old = try env.saveNote("Appeler Julie en revenant du Costco")
        let named = try file(env, thought("Souper avec Marc", people: ["Marc"]))
        let store = entities(env)
        #expect(try store.backfill(using: FakeRecognizer()) == 2)
        #expect(Set(try store.entities(for: old.id).map(\.name)) == ["Julie", "Costco"])
        // Une note qui a déjà ses noms n'est pas relue ; une deuxième relecture ne refait rien.
        #expect(try store.entities(for: named.id).map(\.name) == ["Marc"])
        #expect(try store.backfill(using: FakeRecognizer()) == 0)
    }
}
