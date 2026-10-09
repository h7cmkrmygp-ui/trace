import Foundation
import Testing
@testable import EngramCore

/// P30 — l'adresse d'un lieu trouvée toute seule : les succursales les plus proches (« n'importe quel Costco »).
struct PlaceFinderTests {
    /// Un point quelconque du centre-ville de Montréal (données inventées).
    static let here = PlaceFinder.Point(latitude: 45.5017, longitude: -73.5673)

    func result(_ name: String, _ latitude: Double, _ longitude: Double) -> PlaceFinder.Result {
        PlaceFinder.Result(name: name, address: "Adresse inventée", latitude: latitude, longitude: longitude)
    }

    @Test func theThreeNearestBranchesAreKept() {
        let results = [result("Costco Laval", 45.57, -73.75), result("Costco Québec", 46.80, -71.30),
                       result("Costco Marché Central", 45.535, -73.655), result("Costco Boucherville", 45.59, -73.44),
                       result("Costco Saint-Jérôme", 45.78, -74.0)]
        let chosen = PlaceFinder.choose(results, near: Self.here, placeName: "Costco")
        #expect(chosen.map(\.name) == ["Costco Marché Central", "Costco Boucherville", "Costco Laval"])
    }

    @Test func farAwayPlacesAreLeftOut() {
        #expect(PlaceFinder.choose([result("Costco Québec", 46.80, -71.30)], near: Self.here, placeName: "Costco").isEmpty)
    }

    @Test func namesThatMatchWinWhenThereAreAny() {
        let results = [result("Walmart", 45.51, -73.57), result("Costco Wholesale", 45.535, -73.655)]
        #expect(PlaceFinder.choose(results, near: Self.here, placeName: "Costco").map(\.name) == ["Costco Wholesale"])
        // Un mot général (« pharmacie ») garde ce que la recherche a trouvé.
        let pharmacies = [result("Pharmaprix", 45.52, -73.58), result("Jean Coutu", 45.505, -73.57)]
        #expect(PlaceFinder.choose(pharmacies, near: Self.here, placeName: "Pharmacie").map(\.name) == ["Jean Coutu", "Pharmaprix"])
    }

    @Test func personalPlacesAreNeverSearched() {
        #expect(PlaceFinder.canSearch("Costco", people: []))
        #expect(PlaceFinder.canSearch("Pharmacie", people: []))
        #expect(!PlaceFinder.canSearch("Maison", people: []))
        #expect(!PlaceFinder.canSearch("bureau", people: []))
        #expect(!PlaceFinder.canSearch("Travail", people: []))
        // « chez Julie » : c'est chez quelqu'un, pas un commerce.
        #expect(!PlaceFinder.canSearch("Julie", people: ["Julie"]))
    }

    @Test func distancesAreRight() {
        let quebec = PlaceFinder.Point(latitude: 46.8139, longitude: -71.2080)
        let kilometres = PlaceFinder.distance(Self.here, quebec) / 1_000
        #expect(kilometres > 225 && kilometres < 240)
    }

    @Test func everyBranchIsWatched() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let main = PlaceReminderPlanner.Coordinates(latitude: 45.535, longitude: -73.655, radius: 200)
        let branches = [PlaceReminderPlanner.Coordinates(latitude: 45.59, longitude: -73.44, radius: 200),
                        PlaceReminderPlanner.Coordinates(latitude: 45.57, longitude: -73.75, radius: 200)]
        let item = PlaceReminderPlanner.Item(memoryID: UUID(), title: "Acheter des piles", status: .active, isPrivate: false,
                                             placeID: UUID(), placeName: "Costco", event: .arrive, location: main,
                                             branches: branches, createdAt: created)
        let planned = PlaceReminderPlanner.plan([item])
        try #require(planned.count == 3)
        #expect(Set(planned.map(\.identifier)).count == 3)
        #expect(planned.allSatisfy { $0.identifier.hasPrefix(PlaceReminderPlanner.identifierPrefix + item.memoryID.uuidString) })
        #expect(planned.allSatisfy { $0.body == "Acheter des piles" && $0.memoryID == item.memoryID })
        #expect(planned.map(\.latitude) == [45.535, 45.59, 45.57])
        // Au plus 20 régions en tout : les rappels les plus récents d'abord.
        let others = (1...19).map { index in
            PlaceReminderPlanner.Item(memoryID: UUID(), title: "Note \(index)", status: .active, isPrivate: false, placeID: UUID(),
                                      placeName: "Lieu", event: .arrive, location: main,
                                      createdAt: created.addingTimeInterval(-Double(index) * 60))
        }
        let all = PlaceReminderPlanner.plan([item] + others)
        #expect(all.count == 20)
        #expect(all.filter { $0.memoryID == item.memoryID }.count == 3)
    }
}
