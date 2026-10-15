import Foundation
import Testing
@testable import EngramCore

/// Cerveau vivant : chaque catégorie garde sa couleur, les notes tournent autour d'elle sans s'en éloigner.
struct BrainLookTests {
    @Test func aCategoryAlwaysHasTheSameColor() {
        #expect(CategoryPalette.index(for: "Santé") == CategoryPalette.index(for: "santé"))
        #expect(CategoryPalette.index(for: "Santé") == CategoryPalette.index(for: "SANTE"))
        #expect((0..<CategoryPalette.count).contains(CategoryPalette.index(for: "Maison")))
        // Une sous-catégorie prend la couleur de sa grande catégorie.
        #expect(CategoryPalette.index(forPath: "Maison › Réparations") == CategoryPalette.index(for: "Maison"))
        // Les grandes catégories courantes ne se ressemblent pas toutes.
        let names = ["Santé", "Travail", "Finance", "Maison", "Famille", "Automobile", "Achats", "Loisirs"]
        #expect(Set(names.map(CategoryPalette.index(for:))).count >= 5)
    }

    @Test func notesOrbitAroundTheirCategoryAtAConstantDistance() {
        let anchor = (x: 100.0, y: -40.0)
        let start = (x: 130.0, y: -40.0)
        for time in [0.0, 1.5, 7.25, 60] {
            let moved = BrainMotion.orbit(start, around: anchor, seed: 7, time: time)
            let distance = ((moved.x - anchor.x) * (moved.x - anchor.x) + (moved.y - anchor.y) * (moved.y - anchor.y)).squareRoot()
            #expect(abs(distance - 30) < 1e-9)
        }
        let still = BrainMotion.orbit(start, around: anchor, seed: 7, time: 0)
        #expect(abs(still.x - start.x) < 1e-9 && abs(still.y - start.y) < 1e-9)
        #expect(BrainMotion.orbit(start, around: anchor, seed: 7, time: 3).x != start.x)
    }

    @Test func pulsesAndSignalsStayGentle() {
        for time in stride(from: 0.0, through: 20, by: 0.37) {
            let pulse = BrainMotion.pulse(seed: 3, time: time)
            #expect(pulse >= 0.94 && pulse <= 1.06)
            if let progress = BrainMotion.signal(seed: 3, time: time) { #expect(progress >= 0 && progress <= 1) }
        }
        // Un signal finit par passer sur chaque connexion.
        #expect(stride(from: 0.0, through: 10, by: 0.1).contains { BrainMotion.signal(seed: 11, time: $0) != nil })
    }
}
