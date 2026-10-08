import Foundation
import Testing
@testable import EngramCore

/// Filet de sécurité : « rappelle-moi ça demain » après une demande n'est pas une deuxième note,
/// c'est la date de rappel de la note précédente.
struct ReminderMergerTests {
    func thought(_ title: String, excerpt: String, kind: MemoryKind = .task, dates: [String] = []) -> AnalyzedThought {
        AnalyzedThought(title: title, summary: nil, excerpt: excerpt, kind: kind, tags: [], mentionedDates: dates,
                        category: "Travail", subcategory: nil)
    }

    @Test func aBareReminderIsMergedIntoThePreviousNote() {
        let text = "Rappelle-moi de demander congé pour le 24 novembre, rappelle-moi ça demain"
        let analysis = ThoughtAnalysis(thoughts: [
            thought("Demander congé", excerpt: "demander congé pour le 24 novembre", dates: ["24 novembre"]),
            thought("Se rappeler demain", excerpt: "rappelle-moi ça demain", kind: .other, dates: ["demain"]),
        ])
        let merged = ReminderMerger.merge(analysis, in: text)
        #expect(merged.thoughts.count == 1)
        let only = merged.thoughts[0]
        #expect(only.title == "Demander congé")
        // La date de rappel passe en premier : c'est elle qui donne l'échéance.
        #expect(only.mentionedDates == ["demain", "24 novembre"])
        // L'extrait couvre les deux morceaux, mot pour mot.
        #expect(only.excerpt == "demander congé pour le 24 novembre, rappelle-moi ça demain")
        #expect(text.contains(only.excerpt))
    }

    @Test func aReminderEvenWithoutDetectedDatesIsMerged() {
        let text = "Acheter des piles. Fais-moi penser à ça demain matin"
        let analysis = ThoughtAnalysis(thoughts: [
            thought("Acheter des piles", excerpt: "Acheter des piles"),
            thought("Penser demain", excerpt: "Fais-moi penser à ça demain matin", kind: .other),
        ])
        #expect(ReminderMerger.merge(analysis, in: text).thoughts.count == 1)
    }

    @Test func englishRemindersAreMergedToo() {
        let text = "Book the dentist, remind me about it tomorrow"
        let analysis = ThoughtAnalysis(thoughts: [
            thought("Book the dentist", excerpt: "Book the dentist"),
            thought("Reminder", excerpt: "remind me about it tomorrow", kind: .other, dates: ["tomorrow"]),
        ])
        let merged = ReminderMerger.merge(analysis, in: text)
        #expect(merged.thoughts.count == 1)
        #expect(merged.thoughts[0].mentionedDates == ["tomorrow"])
    }

    @Test func aReminderWithItsOwnSubjectStaysSeparate() {
        let text = "Demander congé pour le 24 novembre, rappelle-moi d'appeler le garage demain"
        let analysis = ThoughtAnalysis(thoughts: [
            thought("Demander congé", excerpt: "Demander congé pour le 24 novembre", dates: ["24 novembre"]),
            thought("Appeler le garage", excerpt: "rappelle-moi d'appeler le garage demain", dates: ["demain"]),
        ])
        #expect(ReminderMerger.merge(analysis, in: text).thoughts.count == 2)
    }

    @Test func aReminderWithNothingBeforeItIsKept() {
        let text = "Rappelle-moi ça demain"
        let analysis = ThoughtAnalysis(thoughts: [thought("Rappel", excerpt: "Rappelle-moi ça demain", dates: ["demain"])])
        #expect(ReminderMerger.merge(analysis, in: text) == analysis)
    }

    @Test func theRouteIsKept() {
        let route = AnalysisRoute(level: .personal, provider: "groq", reason: "Travail.", needsCloudRetry: false)
        let analysis = ThoughtAnalysis(thoughts: [
            thought("Demander congé", excerpt: "demander congé"),
            thought("Rappel", excerpt: "rappelle-moi ça demain", dates: ["demain"]),
        ], route: route)
        #expect(ReminderMerger.merge(analysis, in: "demander congé, rappelle-moi ça demain").route == route)
    }
}
