import Foundation
import Testing
@testable import EngramCore

/// Un titre relu plus tard ne dit plus « aujourd'hui » ni « demain », mais la vraie date de la dictée.
struct RelativeDateWordingTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    /// Vendredi 15 janvier 2027, 10 h, à Toronto.
    static let friday = Date(timeIntervalSince1970: 1_800_025_200)

    @Test(arguments: [
        ("Je pèse 162,5 livres aujourd'hui", "Je pèse 162,5 livres le 15 janvier"),
        ("Je pèse 162,5 livres aujourd’hui", "Je pèse 162,5 livres le 15 janvier"),
        ("Appeler l'assurance demain", "Appeler l'assurance le 16 janvier"),
        ("Demain, appeler le garage", "Le 16 janvier, appeler le garage"),
        ("Rapport pour après-demain", "Rapport pour le 17 janvier"),
        ("Souper d'hier soir avec l'équipe", "Souper du 14 janvier au soir avec l'équipe"),
        ("Réunion de demain matin", "Réunion du 16 janvier au matin"),
        ("Pesée de ce matin", "Pesée du 15 janvier au matin"),
        ("Gym ce soir", "Gym le 15 janvier au soir"),
        ("Attendre jusqu'à demain", "Attendre jusqu'au 16 janvier"),
        ("Le colis arrivé avant-hier", "Le colis arrivé le 13 janvier"),
    ])
    func relativeDaysBecomeRealDates(title: String, expected: String) {
        #expect(RelativeDateWording.anchored(title, on: Self.friday, calendar: Self.calendar) == expected)
    }

    @Test(arguments: [
        "Appeler mon gestionnaire",
        "Acheter des demi-lunes",
        "La hiérarchie du projet",
        "Le 24 novembre, réserver la salle",
    ])
    func otherWordsAreLeftAlone(title: String) {
        #expect(RelativeDateWording.anchored(title, on: Self.friday, calendar: Self.calendar) == title)
    }

    @Test func theYearIsWrittenWhenItChanges() {
        let newYearsEve = Date(timeIntervalSince1970: 1_798_725_600) // jeudi 31 décembre 2026, 9 h à Toronto
        #expect(RelativeDateWording.anchored("Souper demain", on: newYearsEve, calendar: Self.calendar)
            == "Souper le 1er janvier 2027")
    }
}
