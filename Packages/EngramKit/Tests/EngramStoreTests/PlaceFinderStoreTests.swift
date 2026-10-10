import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P30 — les adresses trouvées toutes seules : la plus proche, les autres succursales, et les lieux encore à chercher.
struct PlaceFinderStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, people: [String] = []) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: ["Achats"], mentionedDates: [], people: people)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    func store(_ env: StoreTestEnvironment) -> EntityStore { EntityStore(database: env.database, dates: env.dates) }

    func found(_ name: String, _ latitude: Double, _ longitude: Double) -> PlaceFinder.Result {
        PlaceFinder.Result(name: name, address: "\(name), adresse inventée", latitude: latitude, longitude: longitude)
    }

    @Test func theMigrationCreatesTheTables() throws {
        let env = try StoreTestEnvironment()
        let tables = try env.database.writer.read { db in try ["place_branch", "place_lookup"].map { try db.tableExists($0) } }
        #expect(tables == [true, true])
    }

    @Test func placesWaitingForAnAddressAreListed() throws {
        let env = try StoreTestEnvironment()
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        _ = try file(env, "Sortir les poubelles quand j'arrive à la maison")
        let costco = try #require(try store(env).placeTrigger(for: milk.id)?.place)
        // La maison ne se cherche pas ; Costco, oui.
        #expect(try store(env).placesNeedingLocation().map(\.id) == [costco.id])
        // Cherché sans rien trouver : pas recherché de nouveau tout de suite.
        try store(env).recordLookup(costco.id, found: [])
        #expect(try store(env).placesNeedingLocation().isEmpty)
        env.dates.advance(by: 8 * 86_400)
        #expect(try store(env).placesNeedingLocation().map(\.id) == [costco.id])
    }

    @Test func foundBranchesAreWatchedUntilTheOwnerChoosesOne() throws {
        let env = try StoreTestEnvironment()
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        let costco = try #require(try store(env).placeTrigger(for: milk.id)?.place)
        try store(env).recordLookup(costco.id, found: [found("Costco Marché Central", 45.535, -73.655),
                                                      found("Costco Boucherville", 45.59, -73.44)])
        #expect(try store(env).location(for: costco.id)?.label == "Costco Marché Central, adresse inventée")
        #expect(try store(env).branches(for: costco.id).map(\.label) == ["Costco Boucherville, adresse inventée"])
        #expect(try store(env).isAutoLocated(costco.id))
        #expect(try store(env).placesNeedingLocation().isEmpty)
        let item = try #require(try store(env).placeReminderItems().first { $0.memoryID == milk.id })
        #expect(item.location?.latitude == 45.535)
        #expect(item.branches.map(\.latitude) == [45.59])
        // Le propriétaire choisit une adresse : seulement celle-là.
        try store(env).setLocation(costco.id, latitude: 45.57, longitude: -73.75, radius: 200, label: "Costco Laval")
        #expect(try store(env).branches(for: costco.id).isEmpty)
        #expect(try store(env).isAutoLocated(costco.id) == false)
        #expect(try store(env).placeReminderItems().first { $0.memoryID == milk.id }?.branches.isEmpty == true)
    }

    @Test func theExportContainsTheBranches() throws {
        let env = try StoreTestEnvironment()
        let milk = try file(env, "Acheter du lait quand j'arrive chez Costco")
        let costco = try #require(try store(env).placeTrigger(for: milk.id)?.place)
        try store(env).recordLookup(costco.id, found: [found("Costco A", 45.5, -73.6), found("Costco B", 45.6, -73.5)])
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"place_branches\""))
    }
}
