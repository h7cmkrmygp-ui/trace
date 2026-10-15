import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// P29 — une liste qui porte le nom d'un lieu (« Liste de Costco ») t'attend à ce lieu, sans rien régler.
struct ListPlaceStoreTests {
    func dictate(_ env: StoreTestEnvironment, _ text: String, places: [String] = []) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: ["Achats"], mentionedDates: [], places: places)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    func store(_ env: StoreTestEnvironment) -> EntityStore { EntityStore(database: env.database, dates: env.dates) }

    @Test func aListNamedAfterAPlaceWaitsThere() throws {
        let env = try StoreTestEnvironment()
        let list = try dictate(env, "Ajoute des piles et du papier de toilette à ma liste de Costco")
        // Le lieu existe avec une adresse (posée depuis une autre note).
        let other = try dictate(env, "Rapporter les bouteilles au Costco", places: ["Costco"])
        let costco = try #require(try store(env).entities(for: other.id).first { $0.kind == .place })
        try store(env).setLocation(costco.id, latitude: 45.5, longitude: -73.6, radius: 200, label: nil)

        let item = try #require(try store(env).placeReminderItems().first { $0.memoryID == list.id })
        #expect(item.placeID == costco.id)
        #expect(item.event == .arrive)
        #expect(item.title == "Liste de Costco : piles et papier de toilette")
        #expect(item.location != nil)
    }

    @Test func aCheckedListOrAnUnknownPlaceWaitsNowhere() throws {
        let env = try StoreTestEnvironment()
        let list = try dictate(env, "Ajoute des piles à ma liste de Costco")
        // Pas encore de lieu « Costco » : rien.
        #expect(try store(env).placeReminderItems().contains { $0.memoryID == list.id } == false)
        let other = try dictate(env, "Rapporter les bouteilles au Costco", places: ["Costco"])
        let costco = try #require(try store(env).entities(for: other.id).first { $0.kind == .place })
        try store(env).setLocation(costco.id, latitude: 45.5, longitude: -73.6, radius: 200, label: nil)
        #expect(try store(env).placeReminderItems().contains { $0.memoryID == list.id })
        // Tout est coché : rien à prendre, plus de rappel.
        _ = try env.memories.updateMemory(list.id, with: MemoryEdit(summary: "☑ Piles"), actor: .user)
        #expect(try store(env).placeReminderItems().contains { $0.memoryID == list.id } == false)
    }

    @Test func aManualPlaceReminderIsNotDoubled() throws {
        let env = try StoreTestEnvironment()
        let list = try dictate(env, "Ajoute des piles à ma liste de Costco")
        let other = try dictate(env, "Rapporter les bouteilles au Costco", places: ["Costco"])
        let costco = try #require(try store(env).entities(for: other.id).first { $0.kind == .place })
        try store(env).setLocation(costco.id, latitude: 45.5, longitude: -73.6, radius: 200, label: nil)
        try store(env).setPlaceTrigger(for: list.id, placeID: costco.id, event: .leave)
        let items = try store(env).placeReminderItems().filter { $0.memoryID == list.id }
        #expect(items.count == 1)
        #expect(items.first?.event == .leave)
    }
}
