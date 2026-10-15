import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P18 — « Ta semaine », lue dans la base : notes, choses faites (les tâches qui reviennent comprises), jours, dossiers,
/// personnes et habitudes.
struct WeeklyReviewStoreTests {
    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind = .task, path: [String],
              people: [String] = []) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind,
                                   tags: [], categoryPath: path, mentionedDates: [], people: people)
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func theWeekIsCounted() throws {
        let env = try StoreTestEnvironment()
        // La semaine d'avant (lundi 4 janvier 2027) : une note.
        env.dates.advance(by: -11 * 86_400)
        try file(env, "Appeler le garage", path: ["Maison"])
        // Cette semaine (vendredi 15 janvier) : cinq notes.
        env.dates.advance(by: 11 * 86_400)
        try file(env, "Souper chez Julie samedi", kind: .appointment, path: ["Famille"], people: ["Julie"])
        try file(env, "Rapporter le livre de Julie", path: ["Famille"], people: ["Julie"])
        let fence = try file(env, "Réparer la clôture", path: ["Maison", "Réparations"])
        let trash = try file(env, "Sortir les poubelles tous les lundis", path: ["Maison"])
        try file(env, "J'ai médité 10 minutes", kind: .info, path: ["Santé"])
        _ = try env.memories.setStatus(.archived, for: fence.id, actor: .user)
        // Une tâche qui revient, faite : elle compte aussi.
        _ = try env.memories.setStatus(.archived, for: trash.id, actor: .user)

        let review = try env.memories.weeklyReview(containing: Fixtures.date)
        #expect(review.start == Fixtures.calendar.dateInterval(of: .weekOfYear, for: Fixtures.date)?.start)
        #expect(review.notes == 5)
        #expect(review.notesLastWeek == 1)
        #expect(review.done == 2)
        #expect(review.open == 4)
        #expect(review.perDay == [0, 0, 0, 0, 0, 5, 0])
        #expect(review.categories.map(\.name) == ["Famille", "Maison", "Santé"])
        #expect(review.categories.map(\.count) == [2, 2, 1])
        #expect(review.people.map(\.name) == ["Julie"])
        #expect(review.people.first?.count == 2)
        #expect(review.habits == [WeeklyReview.HabitCount(habit: .meditation, days: 1)])
        // Le résumé du dimanche compte pareil.
        #expect(try env.memories.weekStats(from: review.start, to: review.end).done == 2)
        // La semaine d'avant, vue à son tour.
        let before = try env.memories.weeklyReview(containing: Fixtures.date.addingTimeInterval(-7 * 86_400))
        #expect(before.notes == 1)
        #expect(before.categories.map(\.name) == ["Maison"])
    }
}
