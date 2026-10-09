import Foundation
import Testing
@testable import EngramCore

/// Les personnes et les lieux : le même nom dit autrement est reconnu, et chaque nom s'affiche proprement.
struct EntityNameTests {
    @Test(arguments: [
        ("Mon manager", "le manager"), ("mon Manager", "manager"), ("au gym", "le gym"), ("chez le dentiste", "dentiste"),
        ("l'épicerie", "épicerie"), ("L’Épicerie", "epicerie"), ("Julie", "julie"), ("à Québec", "Quebec"),
    ])
    func theSameNameSaidDifferentlyHasTheSameKey(first: String, second: String) {
        #expect(EntityName.key(first) == EntityName.key(second))
        #expect(!EntityName.key(first).isEmpty)
    }

    @Test func differentNamesStayDifferent() {
        #expect(EntityName.key("Julie") != EntityName.key("Julien"))
        #expect(EntityName.key("Marc Tremblay") == "marc tremblay")
    }

    @Test(arguments: [
        ("le gym", EntityKind.place, "Gym"), ("chez le dentiste", .place, "Dentiste"), ("mon gym", .place, "Gym"),
        ("l'épicerie", .place, "Épicerie"), ("Costco", .place, "Costco"),
        ("mon manager", .person, "Mon manager"), ("maman", .person, "Maman"), ("julie", .person, "Julie"),
        ("le dentiste", .person, "Dentiste"), ("ma sœur", .person, "Ma sœur"),
    ])
    func namesAreShownCleanly(raw: String, kind: EntityKind, shown: String) {
        #expect(EntityName.display(raw, kind: kind) == shown)
    }

    @Test func onlyNamesFromTheNoteAreKeptOnceAndWithinLimits() {
        let text = "Appeler Julie et maman avant d'aller au Costco avec Marc, puis voir mon manager"
        let people = EntityName.clean(["Julie", "julie", "Pierre", "  ", "moi", "quelqu'un", "maman", "Marc",
                                       String(repeating: "a", count: 41), "mon manager"], in: text, limit: 4)
        #expect(people == ["Julie", "maman", "Marc", "mon manager"])
        #expect(EntityName.clean(["Costco", "Walmart"], in: text, limit: 4) == ["Costco"])
        #expect(EntityName.clean(["Julie", "maman", "Marc", "mon manager"], in: text, limit: 2) == ["Julie", "maman"])
    }
}
