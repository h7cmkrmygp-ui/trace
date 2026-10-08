import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// Où une note a été classée, reclassement ultérieur, description des catégories créées par l'IA.
struct RoutingStoreTests {
    func valid(_ title: String, path: [String], description: String? = nil) -> ValidThought {
        ValidThought(title: title, summary: nil, excerpt: title, spanStart: nil, spanEnd: nil, kind: .task,
                     tags: [], categoryPath: path, mentionedDates: [], categoryDescription: description)
    }

    @Test func theRouteIsRecordedOnTheSource() throws {
        let env = try StoreTestEnvironment()
        let note = try env.saveNote("Acheter du lait")
        try env.memories.recordRoute(sourceID: note.sourceID,
                                     route: AnalysisRoute(level: .neutral, provider: "gemini", reason: "Aucune information personnelle détectée.",
                                                          needsCloudRetry: false))
        let source = try #require(try env.memories.source(id: note.sourceID))
        #expect(source.privacyLevel == .neutral)
        #expect(source.analysisProvider == "gemini")
        #expect(source.routeReason == "Aucune information personnelle détectée.")
        #expect(source.needsCloudRetry == false)
    }

    @Test func untouchedNotesFiledLocallyAreReopenedForTheCloud() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Je pèse 75 kg")
        let filed = try env.filer.file([valid("Je pèse 75 kg", path: ["Santé"])], sourceID: interim.sourceID)
        try env.memories.recordRoute(sourceID: interim.sourceID,
                                     route: AnalysisRoute(level: .personal, provider: "apple", reason: "Groq injoignable.", needsCloudRetry: true))
        #expect(try env.memories.sourcesNeedingCloudRetry().map(\.id) == [interim.sourceID])

        #expect(try env.memories.reopenForCloudRetry(sourceID: interim.sourceID))
        #expect(try env.memories.memory(id: filed.memories[0].id) == nil)
        #expect(try env.memories.sourcesAwaitingAnalysis() == [interim.sourceID])
        #expect(try env.memories.sourcesNeedingCloudRetry().isEmpty)
    }

    @Test func aNoteTheOwnerTouchedIsNeverReclassified() throws {
        let env = try StoreTestEnvironment()
        let interim = try env.saveNote("Je pèse 75 kg")
        let filed = try env.filer.file([valid("Je pèse 75 kg", path: ["Santé"])], sourceID: interim.sourceID)
        _ = try env.memories.updateMemory(filed.memories[0].id, with: MemoryEdit(title: "Mon poids"), actor: .user)
        try env.memories.recordRoute(sourceID: interim.sourceID,
                                     route: AnalysisRoute(level: .personal, provider: "apple", reason: "Groq injoignable.", needsCloudRetry: true))
        #expect(try env.memories.reopenForCloudRetry(sourceID: interim.sourceID) == false)
        #expect(try env.memories.memory(id: filed.memories[0].id)?.title == "Mon poids")
        #expect(try env.memories.sourcesNeedingCloudRetry().isEmpty)
        #expect(try env.memories.sourcesAwaitingAnalysis().isEmpty)
    }

    @Test func aNewCategoryGetsTheDescriptionProposedByTheAI() throws {
        let env = try StoreTestEnvironment()
        let first = try env.saveNote("Tailler la haie")
        _ = try env.filer.file([valid("Tailler la haie", path: ["Maison", "Jardin"], description: "Entretien et projets de la maison")],
                               sourceID: first.sourceID)
        let second = try env.saveNote("Réparer la porte")
        _ = try env.filer.file([valid("Réparer la porte", path: ["Maison"], description: "Autre description")],
                               sourceID: second.sourceID)
        let maison = try #require(try env.categories.activeCategories().first { $0.name == "Maison" })
        #expect(maison.descriptionText == "Entretien et projets de la maison")
    }
}
