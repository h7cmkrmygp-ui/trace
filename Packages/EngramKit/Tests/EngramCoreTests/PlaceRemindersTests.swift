import Foundation
import Testing
@testable import EngramCore

/// P14 — « quand j'arrive chez Costco » : le rappel attend le lieu, pas une heure.
struct PlaceRemindersTests {
    func trigger(_ text: String) -> ParsedPlaceTrigger? { PlaceTriggerParser.parse(text) }

    @Test func arrivingSomewhereIsRecognized() {
        #expect(trigger("Rappelle-moi d'acheter du lait quand j'arrive chez Costco") == ParsedPlaceTrigger(place: "Costco", event: .arrive))
        #expect(trigger("Quand je passe au dépanneur, prendre des piles") == ParsedPlaceTrigger(place: "dépanneur", event: .arrive))
        #expect(trigger("Quand j'arrive à Laval, appeler Julie") == ParsedPlaceTrigger(place: "Laval", event: .arrive))
        #expect(trigger("Une fois rendu chez Canadian Tire, acheter de l'huile") == ParsedPlaceTrigger(place: "Canadian Tire", event: .arrive))
        #expect(trigger("La prochaine fois que je vais à la pharmacie, demander pour le vaccin")
            == ParsedPlaceTrigger(place: "pharmacie", event: .arrive))
        #expect(trigger("When I get to the pharmacy, pick up the prescription") == ParsedPlaceTrigger(place: "pharmacy", event: .arrive))
    }

    @Test func homeHasOneName() {
        #expect(trigger("En arrivant à la maison, sortir les poubelles") == ParsedPlaceTrigger(place: "Maison", event: .arrive))
        #expect(trigger("Quand j'arrive chez nous, arroser les plantes") == ParsedPlaceTrigger(place: "Maison", event: .arrive))
        #expect(trigger("Remind me to water the plants when I get home") == ParsedPlaceTrigger(place: "Maison", event: .arrive))
    }

    @Test func leavingSomewhereIsRecognized() {
        #expect(trigger("Quand je pars du bureau, appeler Marc") == ParsedPlaceTrigger(place: "bureau", event: .leave))
        #expect(trigger("En sortant du gym, boire de l'eau") == ParsedPlaceTrigger(place: "gym", event: .leave))
        #expect(trigger("Quand je quitte le travail, passer prendre du pain") == ParsedPlaceTrigger(place: "travail", event: .leave))
        #expect(trigger("When I leave work, call the garage") == ParsedPlaceTrigger(place: "work", event: .leave))
    }

    @Test func ordinarySentencesAreNotPlaceReminders() {
        #expect(trigger("Quand j'arrive à dormir, je me sens mieux") == nil)
        #expect(trigger("Je suis à l'aise avec le projet") == nil)
        #expect(trigger("Quand je suis à l'aise, je parle plus") == nil)
        #expect(trigger("Acheter du lait chez Costco") == nil)
        #expect(trigger("Quand j'arrive au bout du livre, je le prête à Marc") == nil)
        #expect(trigger("Quand je passe à travers mes courriels, je fais le ménage") == nil)
        #expect(trigger("Quand j'arrive demain, on ira au resto") == nil)
    }

    // MARK: - Ce qui est surveillé

    static let created = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ title: String, place: String = "Costco", event: PlaceEvent = .arrive, status: MemoryStatus = .active,
              located: Bool = true, isPrivate: Bool = false, minutesAgo: Double = 0) -> PlaceReminderPlanner.Item {
        PlaceReminderPlanner.Item(memoryID: UUID(), title: title, status: status, isPrivate: isPrivate, placeID: UUID(),
                                  placeName: place, event: event,
                                  location: located ? PlaceReminderPlanner.Coordinates(latitude: 45.5, longitude: -73.6, radius: 200) : nil,
                                  createdAt: Self.created.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func aPlaceReminderSaysThePlaceAndTheThingToDo() throws {
        let milk = item("Acheter du lait")
        let planned = try #require(PlaceReminderPlanner.plan([milk]).first)
        #expect(planned.identifier == PlaceReminderPlanner.identifierPrefix + milk.memoryID.uuidString)
        #expect(planned.memoryID == milk.memoryID)
        #expect(planned.title == "Costco")
        #expect(planned.body == "Acheter du lait")
        #expect(planned.event == .arrive)
        #expect(planned.latitude == 45.5 && planned.longitude == -73.6 && planned.radius == 200)
        let leaving = try #require(PlaceReminderPlanner.plan([item("Appeler Marc", place: "Bureau", event: .leave)]).first)
        #expect(leaving.event == .leave)
    }

    @Test func onlyLivingNotesWithAnAddressAreWatched() {
        let items = [item("Faite", status: .archived), item("Corbeille", status: .trashed), item("Sans adresse", located: false),
                     item("À classer", status: .unsorted)]
        #expect(PlaceReminderPlanner.plan(items).map(\.body) == ["À classer"])
    }

    @Test func aPrivateNoteShowsNothingOnTheLockScreen() throws {
        let planned = try #require(PlaceReminderPlanner.plan([item("Code du casier", isPrivate: true)]).first)
        #expect(planned.title == "Rappel Engram")
        #expect(planned.body == "Ouvre Engram pour le voir.")
    }

    @Test func iOSWatchesAtMostTwentyPlacesTheNewestFirst() {
        let items = (0..<25).map { item("Note \($0)", minutesAgo: Double($0)) }
        let planned = PlaceReminderPlanner.plan(items)
        #expect(planned.count == 20)
        #expect(planned.first?.body == "Note 0")
        #expect(!planned.contains { $0.body == "Note 24" })
    }
}
