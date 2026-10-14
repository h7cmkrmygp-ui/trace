import EngramCore
import Foundation
import GRDB

extension ListStore {
    /// P43 — « Qu'est-ce que je voulais pour mon anniversaire ? » : ce qui reste dans la liste ; nil si la question porte
    /// sur autre chose.
    public func listAnswer(to question: String) throws -> String? {
        nil
    }
}

extension EntityStore {
    /// P43 — « Qu'est-ce que Julie aime ? » : ses goûts (d'après ses notes), ses idées de cadeaux et sa fête ; nil si la
    /// question porte sur autre chose ou si rien n'est noté.
    public func personAnswer(to question: String, now: Date, calendar: Calendar) throws -> String? {
        nil
    }
}
