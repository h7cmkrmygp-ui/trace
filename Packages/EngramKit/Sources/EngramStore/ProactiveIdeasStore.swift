import EngramCore
import Foundation
import GRDB

extension EntityStore {
    /// P44 — pour chaque personne dont la fête est connue, la ligne d'idées à ajouter au rappel de la veille (personne → ligne).
    /// Aucun rappel de plus : seulement plus utile.
    public func birthdayIdeas() throws -> [UUID: String] {
        var ideas: [UUID: String] = [:]
        for birthday in try birthdays() {
            guard let line = PersonQuestion.reminderIdeas(person: birthday.name,
                                                          profile: try profile(of: birthday.personID)) else { continue }
            ideas[birthday.personID] = line
        }
        return ideas
    }
}
