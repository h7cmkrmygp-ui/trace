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

    /// Un rappel demandé fait d'une idée ou d'une info une chose « À faire » ; un rendez-vous reste un rendez-vous.
    @Test func aReminderTurnsAnIdeaIntoATask() {
        let text = "Idée de cadeau : un livre de cuisine, rappelle-moi ça samedi"
        let idea = ThoughtAnalysis(thoughts: [
            thought("Cadeau : livre de cuisine", excerpt: "Idée de cadeau : un livre de cuisine", kind: .idea),
            thought("Rappel", excerpt: "rappelle-moi ça samedi", kind: .other, dates: ["samedi"]),
        ])
        #expect(ReminderMerger.merge(idea, in: text).thoughts.map(\.kind) == [.task])

        let appointment = ThoughtAnalysis(thoughts: [
            thought("Dentiste", excerpt: "Dentiste mardi à 10 h", kind: .appointment, dates: ["mardi à 10 h"]),
            thought("Rappel", excerpt: "rappelle-moi ça lundi", kind: .other, dates: ["lundi"]),
        ])
        let merged = ReminderMerger.merge(appointment, in: "Dentiste mardi à 10 h, rappelle-moi ça lundi").thoughts
        #expect(merged.map(\.kind) == [.appointment])
        // Le calendrier reçoit le rendez-vous à sa date (mardi à 10 h), pas à la date du rappel.
        #expect(merged.first?.mentionedDates == ["mardi à 10 h", "lundi"])
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
