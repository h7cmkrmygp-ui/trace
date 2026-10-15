import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P19 — les cases cochées ou retirées à la voix, sans nouvelle note.
struct ListActionStoreTests {
    func dictate(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind = .task) throws -> [Memory] {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                                   categoryPath: ["Achats"], mentionedDates: [])
        return try env.filer.file([thought], sourceID: interim.sourceID).memories
    }

    func groceries(_ env: StoreTestEnvironment) throws -> Memory {
        try #require(try dictate(env, "Ajoute du lait, du pain et des bananes à ma liste d'épicerie").first)
    }

    @Test func boughtThingsAreCheckedWithoutANewNote() throws {
        let env = try StoreTestEnvironment()
        let list = try groceries(env)
        let filed = try dictate(env, "J'ai acheté le lait pis les bananes", kind: .info)
        #expect(filed.map(\.id) == [list.id])
        #expect(try env.memories.memory(id: list.id)?.summary == "☑ Lait\n☐ Pain\n☑ Bananes")
        #expect(try env.memories.versions(of: list.id).first?.changeReason?.hasPrefix("coché") == true)
    }

    @Test func somethingBoughtThatIsNotOnAListIsANote() throws {
        let env = try StoreTestEnvironment()
        let list = try groceries(env)
        let filed = try dictate(env, "J'ai acheté une nouvelle tondeuse", kind: .info)
        #expect(filed.count == 1)
        #expect(filed.first?.id != list.id)
        #expect(try env.memories.memory(id: list.id)?.summary == "☐ Lait\n☐ Pain\n☐ Bananes")
    }

    @Test func aBoxCanBeRemoved() throws {
        let env = try StoreTestEnvironment()
        let list = try groceries(env)
        #expect(try dictate(env, "Enlève le pain de ma liste d'épicerie").map(\.id) == [list.id])
        #expect(try env.memories.memory(id: list.id)?.summary == "☐ Lait\n☐ Bananes")
    }

    @Test func aClearCommandNeverBecomesANote() throws {
        let env = try StoreTestEnvironment()
        let list = try groceries(env)
        // Rien à cocher (le café n'y est pas) : la demande reste une demande, pas une note.
        #expect(try dictate(env, "Coche le café").map(\.id) == [list.id])
        #expect(try env.memories.memory(id: list.id)?.summary == "☐ Lait\n☐ Pain\n☐ Bananes")
    }
}
