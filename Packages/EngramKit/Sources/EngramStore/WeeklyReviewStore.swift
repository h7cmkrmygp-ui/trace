import EngramCore
import Foundation
import GRDB

/// P18 — « Ta semaine », lue dans la base, sur l'iPhone.
extension MemoryStore {
    /// Notes qui comptent : vivantes ou faites, jamais la corbeille ni les dictées qui attendent « Vérifie ta note ».
    static let livingNotes = """
        m.status IN ('active','unsorted','archived') AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
        """

    /// Une tâche qui revient, faite pendant [début, fin[ (P16) : chaque fois compte.
    static func repeatedCompletions(_ db: Database, from start: Date, to end: Date) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM memory_version WHERE change_reason LIKE 'fait — %' AND created_at >= ? AND created_at < ?
            """, arguments: [start, end]) ?? 0
    }

    /// La semaine du calendrier qui contient `date`.
    public func weeklyReview(containing date: Date) throws -> WeeklyReview {
        let calendar = self.calendar
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date),
              let previous = calendar.date(byAdding: .day, value: -7, to: week.start) else {
            throw StoreError.invalidOperation("Semaine introuvable.")
        }
        return try database.writer.read { db in
            let living = Self.livingNotes
            let range: StatementArguments = [week.start, week.end]
            let captured = try Date.fetchAll(db, sql: """
                SELECT m.captured_at FROM memory m WHERE \(living) AND m.captured_at >= ? AND m.captured_at < ?
                """, arguments: range)
            let lastWeek = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM memory m WHERE \(living) AND m.captured_at >= ? AND m.captured_at < ?
                """, arguments: [previous, week.start]) ?? 0
            var perDay = Array(repeating: 0, count: 7)
            for moment in captured {
                let index = calendar.dateComponents([.day], from: week.start, to: calendar.startOfDay(for: moment)).day ?? 0
                if (0..<7).contains(index) { perDay[index] += 1 }
            }
            let archived = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM memory WHERE status = 'archived' AND kind IN ('task','appointment')
                  AND updated_at >= ? AND updated_at < ?
                """, arguments: range) ?? 0
            let open = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM memory m WHERE m.status IN ('active','unsorted') AND m.kind IN ('task','appointment')
                  AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
                """) ?? 0

            // Dossiers : le dossier principal (la racine) de chaque note de la semaine.
            let categories = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            func root(of id: UUID) -> EngramCategory? {
                var current = byID[id]
                var steps = 0
                while let parentID = current?.parentID, let parent = byID[parentID], steps < 10 {
                    current = parent
                    steps += 1
                }
                return current
            }
            var notesByRoot: [UUID: Set<UUID>] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT mc.memory_id AS memory_id, mc.category_id AS category_id FROM memory_category mc
                JOIN memory m ON m.id = mc.memory_id
                WHERE mc.rejected = 0 AND \(living) AND m.captured_at >= ? AND m.captured_at < ?
                """, arguments: range) {
                let categoryID: UUID = row["category_id"]
                let memoryID: UUID = row["memory_id"]
                guard let top = root(of: categoryID) else { continue }
                notesByRoot[top.id, default: []].insert(memoryID)
            }
            let folders = notesByRoot.compactMap { id, notes in byID[id].map { WeeklyReview.Count(name: $0.name, count: notes.count) } }
                .sorted { ($0.count, $1.name) > ($1.count, $0.name) }

            // Personnes et lieux nommés dans les notes de la semaine.
            func named(_ kind: EntityKind) throws -> [WeeklyReview.Count] {
                try Row.fetchAll(db, sql: """
                    SELECT e.id AS id, e.name AS name, COUNT(DISTINCT m.id) AS n FROM memory_entity me
                    JOIN entity e ON e.id = me.entity_id
                    JOIN memory m ON m.id = me.memory_id
                    WHERE me.rejected = 0 AND e.status = 'active' AND e.kind = ? AND \(living)
                      AND m.captured_at >= ? AND m.captured_at < ?
                    GROUP BY e.id ORDER BY n DESC, e.name LIMIT 6
                    """, arguments: [kind.rawValue, week.start, week.end])
                    .map { WeeklyReview.Count(name: $0["name"], count: $0["n"], entityID: $0["id"]) }
            }

            // Habitudes : les jours où chacune a été faite.
            let entries = try HabitEntry.fetchAll(db, sql: """
                SELECT h.* FROM habit_entry h JOIN memory m ON m.id = h.memory_id
                WHERE m.status IN ('active','unsorted','archived') AND h.done_at >= ? AND h.done_at < ?
                """, arguments: range)
            let habits = Dictionary(grouping: entries, by: \.habit)
                .map { habit, list in
                    WeeklyReview.HabitCount(habit: habit, days: Set(list.map { calendar.startOfDay(for: $0.doneAt) }).count)
                }
                .sorted { ($0.days, $1.habit.rawValue) > ($1.days, $0.habit.rawValue) }

            return WeeklyReview(start: week.start, end: week.end, notes: captured.count, notesLastWeek: lastWeek,
                                done: archived + (try Self.repeatedCompletions(db, from: week.start, to: week.end)),
                                open: open, perDay: perDay, categories: Array(folders.prefix(5)),
                                people: try named(.person), places: try named(.place), habits: habits)
        }
    }
}

/// P28 — « Ton mois ».
extension MemoryStore {
    public func review(_ period: ReviewPeriod, containing date: Date) throws -> WeeklyReview {
        WeeklyReview(start: date, end: date, notes: 0, notesLastWeek: 0, done: 0, open: 0, perDay: [], categories: [],
                     people: [], places: [], habits: [])
    }
}
