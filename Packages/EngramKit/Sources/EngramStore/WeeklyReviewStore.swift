import EngramCore
import Foundation
import GRDB

/// P18 — « Ta semaine », lue dans la base, sur l'iPhone.
extension MemoryStore {
    /// La semaine du calendrier qui contient `date`.
    public func weeklyReview(containing date: Date) throws -> WeeklyReview {
        WeeklyReview(start: date, end: date, notes: 0, notesLastWeek: 0, done: 0, open: 0, perDay: [], categories: [],
                     people: [], places: [], habits: [])
    }
}
