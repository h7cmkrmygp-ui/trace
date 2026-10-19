import EngramCore
import EngramTesting
import Foundation
import Synchronization
import Testing
@testable import EngramIntelligence

/// F02, F10, F13 — tout ce qui part vers un service en ligne est autorisé champ par champ, selon la provenance de chaque
/// métadonnée : un dérivé d'une note locale ne sort jamais ; la politique est revérifiée juste avant chaque envoi ; chaque
/// envoi laisse un reçu écrit avant de partir, même si la réponse échoue.
struct OutboundEnvelopeTests {
    static let thought = ThoughtAnalysis(thoughts: [
        AnalyzedThought(title: "Lait", summary: nil, excerpt: "Acheter du lait", kind: .task, tags: [], mentionedDates: [],
                        category: "Épicerie", subcategory: nil),
    ])
    static let localMask = PrivacyPolicy.forbiddenMask(PrivacyFacts(keepLocal: true, level: .secret, basis: .ownerKeepLocal))
    static let personalMask = PrivacyPolicy.forbiddenMask(PrivacyFacts(keepLocal: false, level: .personal, basis: .judged))

    final class Receipts: Sendable {
        let events = Mutex<[TransmissionEvent]>([])
        func record(_ event: TransmissionEvent) { events.withLock { $0.append(event) } }
        var all: [TransmissionEvent] { events.withLock { $0 } }
    }

    final class Switch: Sendable {
        let state = Mutex(false)
        var isOn: Bool { state.withLock { $0 } }
        func turnOn() { state.withLock { $0 = true } }
    }

    /// Un juge qui actionne un interrupteur pendant qu'il juge (le propriétaire change d'avis pendant l'attente).
    struct SwitchingJudge: PrivacyJudge {
        let toggle: Switch
        func judge(_ text: String) async throws -> PrivacyJudgement {
            toggle.turnOn()
            return PrivacyJudgement(verdict: .neutral, reason: "Neutre.")
        }
    }

    func router(gemini: FakeCloud, groq: FakeCloud, judge: any PrivacyJudge = FakeJudge(verdict: .neutral),
                keepEverythingLocal: @escaping @Sendable () -> Bool = { false },
                sourceAllowsCloud: (@Sendable (UUID) -> Bool)? = nil,
                receipts: Receipts? = nil) -> RoutedAnalyzer {
        RoutedAnalyzer(local: FakeAnalyzer([.success(Self.thought)]), judge: judge,
                       neutral: CloudProvider(name: "gemini", analyzer: gemini),
                       personal: CloudProvider(name: "groq", analyzer: groq),
                       keepEverythingLocal: keepEverythingLocal, quota: CloudQuota(defaults: nil),
                       sourceAllowsCloud: sourceAllowsCloud,
                       onTransmission: receipts.map { box in { @Sendable event in box.record(event) } })
    }

    static let metadata = AnalysisContext(
        capturedAt: Date(), categoryDescriptions: ["Travail": "Le boulot", "Santé": "Rendez-vous médicaux"],
        folderEvidence: [FolderEvidence(path: "Travail", notes: 2, byOwner: 0), FolderEvidence(path: "Santé", notes: 3, byOwner: 1)],
        categoryCounts: ["Travail": 3, "Santé": 4], lists: ["épicerie", "pharmacie"],
        recent: RecentContext(lists: ["épicerie"], folders: ["Travail"], minutesAgo: 3))

    @Test func withoutAKnownProvenanceNoDerivedMetadataLeaves() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        _ = try await router(gemini: gemini, groq: groq).analyze(text: "Acheter du lait", existingCategories: ["Santé", "Travail"],
                                                                 context: Self.metadata)
        let context = try #require(gemini.receivedContexts.first)
        #expect(gemini.receivedCategories.first == [])
        #expect(context.lists.isEmpty)
        #expect(context.folderEvidence.isEmpty)
        #expect(context.categoryCounts.isEmpty)
        #expect(context.categoryDescriptions.isEmpty)
        #expect(context.recent == nil)
    }

    @Test func whatALocalNoteProducedStaysOnThePhone() async throws {
        var context = Self.metadata
        context.provenance = ContextProvenance(categories: ["Travail": 0, "Santé": Self.localMask, "Famille": Self.personalMask],
                                               lists: ["épicerie": 0, "pharmacie": Self.localMask], recent: Self.localMask)
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        let routed = router(gemini: gemini, groq: groq)
        _ = try await routed.analyze(text: "Acheter du lait", existingCategories: ["Santé", "Travail", "Famille"], context: context)
        let neutral = try #require(gemini.receivedContexts.first)
        #expect(gemini.receivedCategories.first == ["Travail"])
        #expect(neutral.lists == ["épicerie"])
        #expect(neutral.folderEvidence.map(\.path) == ["Travail"])
        #expect(neutral.categoryCounts == ["Travail": 3])
        #expect(neutral.recent == nil)
        // Groq : les dérivés de notes personnelles peuvent y aller, jamais ceux d'une note locale.
        _ = try await routed.analyze(text: "Je pèse 75 kg ce matin", existingCategories: ["Santé", "Travail", "Famille"],
                                     context: context)
        let personal = try #require(groq.receivedContexts.first)
        #expect(groq.receivedCategories.first == ["Travail", "Famille"])
        #expect(personal.lists == ["épicerie"])
        #expect(personal.categoryDescriptions == ["Travail": "Le boulot"])
        #expect(personal.recent == nil)
    }

    @Test func aSourceKeptLocalWhileWaitingNeverLeaves() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        var context = Self.metadata
        context.sourceID = UUID()
        let analysis = try await router(gemini: gemini, groq: groq, sourceAllowsCloud: { _ in false })
            .analyze(text: "Acheter du lait", existingCategories: [], context: context)
        #expect(gemini.callCount == 0)
        #expect(groq.callCount == 0)
        #expect(analysis.route?.provider == "apple")
    }

    @Test func keepingEverythingLocalDuringTheJudgementStopsTheSending() async throws {
        let gemini = FakeCloud(.success(Self.thought))
        let groq = FakeCloud(.success(Self.thought))
        let toggle = Switch()
        let analysis = try await router(gemini: gemini, groq: groq, judge: SwitchingJudge(toggle: toggle),
                                        keepEverythingLocal: { toggle.isOn })
            .analyze(text: "Acheter du lait", existingCategories: [], context: Self.metadata)
        #expect(gemini.callCount == 0)
        #expect(groq.callCount == 0)
        #expect(analysis.route?.provider == "apple")
    }

    @Test func everySendingLeavesAReceiptWrittenBeforeItLeaves() async throws {
        let gemini = FakeCloud(.failure(.network))
        let groq = FakeCloud(.success(Self.thought))
        let receipts = Receipts()
        var context = Self.metadata
        let id = UUID()
        context.sourceID = id
        _ = try await router(gemini: gemini, groq: groq, receipts: receipts)
            .analyze(text: "Acheter du lait", existingCategories: [], context: context)
        #expect(receipts.all.map(\.provider) == ["gemini", "gemini", "groq", "groq"])
        #expect(receipts.all.map(\.status) == [.sending, .failed, .sending, .succeeded])
        #expect(receipts.all.allSatisfy { $0.sourceID == id })
        // Le reçu d'un envoi garde le même identifiant de l'envoi à son résultat.
        try #require(receipts.all.count == 4)
        #expect(receipts.all[0].id == receipts.all[1].id)
        #expect(receipts.all[0].id != receipts.all[2].id)
    }
}
