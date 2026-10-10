import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P14 — les rappels de lieu : posés à la dictée ou à la main, l'adresse du lieu, ce que l'iPhone doit surveiller.
struct PlaceRemindersStoreTests {
    func thought(_ text: String, kind: MemoryKind = .task, places: [String] = []) -> ValidThought {
        ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                     categoryPath: ["Courses"], mentionedDates: [], places: places)
    }

    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String, places: [String] = [], keepLocal: Bool = false) throws -> Memory {
        guard case .saved(let interim) = try env.memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        return try #require(try env.filer.file([thought(text, places: places)], sourceID: interim.sourceID).memories.first)
    }

    func places(_ env: StoreTestEnvironment) -> EntityStore { EntityStore(database: env.database, dates: env.dates) }

    @Test func theMigrationCreatesTheTables() throws {
        let env = try StoreTestEnvironment()
        let tables = try env.database.writer.read { db in try ["place_location", "place_trigger"].map { try db.tableExists($0) } }
        #expect(tables == [true, true])
    }

    @Test func aDictatedPlaceReminderIsKept() throws {
        let env = try StoreTestEnvironment()
        // L'IA n'a pas vu le lieu : le rappel le crée quand même, et le relie à la note.
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        let info = try #require(try places(env).placeTrigger(for: milk.id))
        #expect(info.place.name == "Costco")
        #expect(info.place.kind == .place)
        #expect(info.trigger.event == .arrive)
        #expect(info.trigger.origin == .ai)
        #expect(info.location == nil)
        #expect(try places(env).entities(for: milk.id).map(\.name) == ["Costco"])
        // Le même lieu, nommé par l'IA : une seule page.
        env.dates.advance(by: 60)
        let bread = try file(env, "En sortant du Costco, acheter du pain", places: ["Costco"])
        #expect(try places(env).placeTrigger(for: bread.id)?.place.id == info.place.id)
        #expect(try places(env).placeTrigger(for: bread.id)?.trigger.event == .leave)
        #expect(try places(env).waitingReminders(at: info.place.id).map(\.id) == [bread.id, milk.id])
        // Une note sans lieu n'a pas de rappel.
        #expect(try places(env).placeTrigger(for: try file(env, "Appeler le garage").id) == nil)
    }

    @Test func onlyPlacesWithAnAddressAreWatched() throws {
        let env = try StoreTestEnvironment()
        let store = places(env)
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        let costco = try #require(try store.placeTrigger(for: milk.id)?.place)
        #expect(try store.placeReminderItems().first?.location == nil)
        try store.setLocation(costco.id, latitude: 45.5, longitude: -73.6, radius: 200, label: "Rue Inventée")
        let location = try #require(try store.location(for: costco.id))
        #expect(location.latitude == 45.5 && location.longitude == -73.6 && location.radius == 200)
        #expect(location.label == "Rue Inventée")
        let item = try #require(try store.placeReminderItems().first)
        #expect(item.memoryID == milk.id)
        #expect(item.placeName == "Costco")
        #expect(item.location == PlaceReminderPlanner.Coordinates(latitude: 45.5, longitude: -73.6, radius: 200))
        #expect(PlaceReminderPlanner.plan(try store.placeReminderItems()).count == 1)
        // Faite, à la corbeille, ou lieu masqué : plus surveillée.
        _ = try env.memories.setStatus(.archived, for: milk.id, actor: .user)
        #expect(try store.placeReminderItems().isEmpty)
        _ = try env.memories.setStatus(.active, for: milk.id, actor: .user)
        try store.hide(costco.id)
        #expect(try store.placeReminderItems().isEmpty)
        // Une personne n'a pas d'adresse.
        let julie = try store.addEntity(named: "Julie", kind: .person, to: milk.id)
        #expect(throws: (any Error).self) { try store.setLocation(julie.id, latitude: 1, longitude: 1, radius: 200, label: nil) }
        try store.removeLocation(costco.id)
        #expect(try store.location(for: costco.id) == nil)
    }

    @Test func aPrivateNoteStaysDiscreet() throws {
        let env = try StoreTestEnvironment()
        let secret = try file(env, "Changer le code du casier quand j'arrive au gym", keepLocal: true)
        let item = try #require(try places(env).placeReminderItems().first { $0.memoryID == secret.id })
        #expect(item.isPrivate)
    }

    @Test func theOwnerDecides() throws {
        let env = try StoreTestEnvironment()
        let store = places(env)
        let call = try file(env, "Appeler Marc")
        let pharmacy = try store.setPlaceTrigger(for: call.id, placeNamed: "la pharmacie", event: .leave)
        #expect(pharmacy.name == "Pharmacie")
        let info = try #require(try store.placeTrigger(for: call.id))
        #expect(info.trigger.origin == .user)
        #expect(info.trigger.event == .leave)
        #expect(try store.entities(for: call.id).map(\.name) == ["Pharmacie"])
        try store.setPlaceTrigger(for: call.id, placeID: pharmacy.id, event: .arrive)
        #expect(try store.placeTrigger(for: call.id)?.trigger.event == .arrive)
        try store.removePlaceTrigger(for: call.id)
        #expect(try store.placeTrigger(for: call.id) == nil)
        // Une personne n'est pas un lieu.
        let julie = try store.addEntity(named: "Julie", kind: .person, to: call.id)
        #expect(throws: (any Error).self) { try store.setPlaceTrigger(for: call.id, placeID: julie.id, event: .arrive) }
    }

    @Test func mergingPlacesKeepsTheRemindersAndTheAddress() throws {
        let env = try StoreTestEnvironment()
        let store = places(env)
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        let oil = try file(env, "Quand je passe au Costco Laval, acheter de l'huile")
        let costco = try #require(try store.placeTrigger(for: milk.id)?.place)
        let laval = try #require(try store.placeTrigger(for: oil.id)?.place)
        #expect(costco.id != laval.id)
        try store.setLocation(laval.id, latitude: 45.57, longitude: -73.75, radius: 500, label: nil)
        try store.merge(laval.id, into: costco.id)
        #expect(try store.placeTrigger(for: oil.id)?.place.id == costco.id)
        #expect(try store.location(for: costco.id)?.radius == 500)
        #expect(try store.placeReminderItems().count == 2)
    }

    @Test func remindersLeaveWithTheNoteAndAreExported() throws {
        let env = try StoreTestEnvironment()
        let store = places(env)
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        let costco = try #require(try store.placeTrigger(for: milk.id)?.place)
        try store.setLocation(costco.id, latitude: 45.5, longitude: -73.6, radius: 200, label: nil)
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"place_locations\""))
        #expect(json.contains("\"place_triggers\""))
        _ = try env.memories.setStatus(.trashed, for: milk.id, actor: .user)
        _ = try env.memories.deletePermanently(milk.id)
        let left = try env.database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM place_trigger") }
        #expect(left == 0)
    }
}
