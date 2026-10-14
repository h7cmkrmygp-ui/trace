import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramIntelligence

/// P34 — le classement réfléchi : l'IA voit où sont rangées les notes semblables (noms des dossiers seulement, sans les
/// sous-dossiers pour Gemini), la taille de chaque dossier, les règles du propriétaire, et Groq réfléchit davantage.
struct FolderEvidencePromptTests {
    static let toronto = TimeZone(identifier: "America/Toronto")!
    static let thought = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                        category: "Épicerie", subcategory: nil),
    ])

    @Test func theIPhoneFindsWhereSimilarNotesAreFiled() async {
        let embedder = FakeEmbedder(vectors: [
            "Faire l'alignement des roues": [1, 0, 0],
            "Changer les pneus": [0.95, 0.05, 0],
            "Changement d'huile": [0.9, 0.1, 0],
            "Payer l'électricité": [0, 1, 0],
        ])
        let samples = [
            FilingSample(id: UUID(), text: "Changer les pneus", paths: ["Automobile › Corolla"], byOwner: false),
            FilingSample(id: UUID(), text: "Changement d'huile", paths: ["Automobile › Corolla"], byOwner: true),
            FilingSample(id: UUID(), text: "Payer l'électricité", paths: ["Finances"], byOwner: false),
        ]
        let source = SimilarNotesEvidence(embedder: embedder, samples: { samples })
        #expect(await source.evidence(for: "Faire l'alignement des roues")
            == [FolderEvidence(path: "Automobile › Corolla", notes: 2, byOwner: 1)])
        // Sans le sens de la note, aucun indice.
        #expect(await source.evidence(for: "Texte inconnu").isEmpty)
    }

    @Test func theAISeesTheSizeOfEachFolderAndWhereSimilarNotesAre() {
        let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200), timeZone: Self.toronto,
                                   categoryDescriptions: ["Automobile": "Entretien de la voiture"],
                                   folderEvidence: [FolderEvidence(path: "Automobile › Corolla", notes: 2, byOwner: 1)],
                                   categoryCounts: ["Automobile": 12, "Automobile › Corolla": 5])
        let prompt = CloudPrompt.user(text: "Faire l'alignement des roues", categories: ["Automobile", "Automobile › Corolla"],
                                      context: context)
        #expect(prompt.contains("- Automobile (12) : Entretien de la voiture"))
        #expect(prompt.contains("- Automobile › Corolla (5)"))
        #expect(prompt.contains("Automobile › Corolla (2 notes, dont 1 rangée par le propriétaire)"))
        let plain = CloudPrompt.user(text: "x", categories: ["Automobile"], context: CloudContext(now: Date(), timeZone: Self.toronto))
        #expect(!plain.contains("notes les plus semblables"))
    }

    @Test func theInstructionsFollowTheOwnersWayOfFiling() {
        let system = CloudPrompt.system
        #expect(system.contains("at least 3 notes"))
        #expect(system.localizedCaseInsensitiveContains("most similar"))
        #expect(system.localizedCaseInsensitiveContains("few broad categories"))
        #expect(CloudPrompt.version == "p41-cloud-v1")
    }

    func router(gemini: FakeCloud, groq: FakeCloud) -> RoutedAnalyzer {
        RoutedAnalyzer(local: FakeAnalyzer([.success(Self.thought)]), judge: FakeJudge(verdict: .neutral),
                       neutral: CloudProvider(name: "gemini", analyzer: gemini),
                       personal: CloudProvider(name: "groq", analyzer: groq), quota: CloudQuota(defaults: nil))
    }

    static let evidence = [FolderEvidence(path: "Famille › Julie", notes: 2, byOwner: 1),
                           FolderEvidence(path: "Automobile", notes: 1, byOwner: 0)]
    static let counts = ["Famille": 5, "Famille › Julie": 2, "Automobile": 3]
    static let categories = ["Automobile", "Famille", "Famille › Julie"]

    @Test func geminiOnlyGetsTheMainFolders() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(
            text: "Acheter du lait", existingCategories: Self.categories,
            context: AnalysisContext(capturedAt: Date(), folderEvidence: Self.evidence, categoryCounts: Self.counts))
        let context = try #require(gemini.receivedContexts.first)
        #expect(context.folderEvidence == [FolderEvidence(path: "Famille", notes: 2, byOwner: 1),
                                           FolderEvidence(path: "Automobile", notes: 1, byOwner: 0)])
        #expect(context.categoryCounts == ["Famille": 5, "Automobile": 3])
    }

    @Test func groqGetsTheFullFolders() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(
            text: "Je pèse 75 kg ce matin", existingCategories: Self.categories,
            context: AnalysisContext(capturedAt: Date(), folderEvidence: Self.evidence, categoryCounts: Self.counts))
        let context = try #require(groq.receivedContexts.first)
        #expect(context.folderEvidence == Self.evidence)
        #expect(context.categoryCounts == Self.counts)
    }

    static let groqAnswer: Data = {
        let content = #"{"notes":[{"title":"Lait","summary":"","excerpt":"acheter du lait","kind":"task","categoryReason":"","category":"Épicerie","categoryDescription":"","subcategory":"","tags":[],"dates":[],"people":[],"places":[]}]}"#
        return try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": content]]]])
    }()

    @Test func groqThinksHarderAndStillWorksIfItRefusesTo() async throws {
        let request = try GroqClient.makeRequest(apiKey: "CLE-TEST", system: "s", user: "u")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("\"reasoning_effort\":\"high\""))
        // Le service refuse le réglage (400) : un second essai sans lui.
        let transport = FakeTransport([(400, Data(#"{"error":{"message":"reasoning_effort"}}"#.utf8)), (200, Self.groqAnswer)])
        let text = try await GroqClient(apiKey: "CLE-TEST", transport: transport).generate(system: "s", user: "u")
        #expect(text.contains("Épicerie"))
        #expect(transport.bodies.count == 2)
        #expect(!transport.bodies[1].contains("reasoning_effort"))
    }

    #if canImport(FoundationModels)
    @Test func theAppleModelGetsTheSameEvidence() {
        #expect(AnalysisPrompt.version == "p41-v1")
        #expect(AnalysisPrompt.instructions.contains("at least 3 notes"))
        let prompt = AnalysisPrompt.prompt(text: "x", categories: ["Automobile"], likely: [],
                                           evidence: [FolderEvidence(path: "Automobile", notes: 2, byOwner: 0)],
                                           counts: ["Automobile": 7])
        #expect(prompt.contains("- Automobile (7)"))
        #expect(prompt.contains("Automobile (2 notes)"))
    }
    #endif
}
