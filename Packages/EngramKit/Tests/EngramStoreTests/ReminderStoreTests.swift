import EngramCore
import Foundation
import Testing
@testable import EngramStore

/// Les notes à rappeler, lues dans la base, avec ce qui doit rester discret sur l'écran verrouillé.
struct ReminderStoreTests {
    func dated(_ title: String, kind: MemoryKind = .task) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: title, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                     categoryPath: ["Maison"], mentionedDates: ["demain à 15 h"])
    }

    @Test func datedTasksAreRemindedAndPrivateOnesStayDiscreet() throws {
        let env = try StoreTestEnvironment()
        let plain = try env.saveNote("Tailler la haie demain à 15 h")
        _ = try env.filer.file([dated("Tailler la haie demain à 15 h")], sourceID: plain.sourceID)
        try env.memories.recordRoute(sourceID: plain.sourceID, route: AnalysisRoute(
            level: .secret, provider: "apple", reason: RouteReasons.noCloudService, needsCloudRetry: false))

        guard case .saved(let code) = try env.memories.saveTextNoteWithoutAnalysis("Changer le code du casier demain à 15 h",
                                                                                 keepLocal: true) else {
            Issue.record("Note en double")
            return
        }
        _ = try env.filer.file([dated("Changer le code du casier demain à 15 h")], sourceID: code.sourceID)

        let done = try env.saveNote("Laver l'auto demain à 15 h")
        let filedDone = try env.filer.file([dated("Laver l'auto demain à 15 h")], sourceID: done.sourceID)
        _ = try env.memories.setStatus(.archived, for: try #require(filedDone.memories.first?.id), actor: .user)

        let items = try env.memories.reminderItems()
        #expect(Set(items.map(\.title)) == ["Tailler la haie demain à 15 h", "Changer le code du casier demain à 15 h"])
        #expect(items.first { $0.title.hasPrefix("Tailler") }?.isPrivate == false)
        #expect(items.first { $0.title.hasPrefix("Changer") }?.isPrivate == true)
        #expect(items.allSatisfy { $0.dueHasTime && $0.dueAt != nil })
    }

    /// Le résumé de la semaine : notes de la semaine, choses faites, choses encore à faire (la corbeille ne compte pas).
    @Test func weekStatsCountNotesDoneAndOpen() throws {
        let env = try StoreTestEnvironment()
        let start = env.dates.now().addingTimeInterval(-3_600)
        let end = env.dates.now().addingTimeInterval(7 * 86_400)
        let open = try env.saveNote("Tailler la haie demain à 15 h")
        _ = try env.filer.file([dated("Tailler la haie demain à 15 h")], sourceID: open.sourceID)
        let done = try env.saveNote("Laver l'auto demain à 15 h")
        let filedDone = try env.filer.file([dated("Laver l'auto demain à 15 h")], sourceID: done.sourceID)
        _ = try env.memories.setStatus(.archived, for: try #require(filedDone.memories.first?.id), actor: .user)
        _ = try env.saveNote("Une idée en vrac")
        let thrown = try env.saveNote("Vieille idée à jeter")
        _ = try env.memories.setStatus(.trashed, for: thrown.id, actor: .user)

        #expect(try env.memories.weekStats(from: start, to: end) == WeekStats(notes: 3, done: 1, open: 1))
    }
}
