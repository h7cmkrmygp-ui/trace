import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// F02 — la provenance de chaque dossier et de chaque liste vient des notes qui les ont produits ; F13 — les reçus d'envoi
/// sont gardés ; F17 — le calendrier synchronisé ne reçoit que ce que la politique de la note permet.
struct OutboundProvenanceStoreTests {
    static let neutral = AnalysisRoute(level: .neutral, provider: "gemini", reason: "Neutre.", needsCloudRetry: false,
                                       basis: .judged)
    static let personal = AnalysisRoute(level: .personal, provider: "groq", reason: "Personnel.", needsCloudRetry: false,
                                        basis: .judged)
    static let local = AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.ownerKeepLocal,
                                     needsCloudRetry: false, basis: .ownerKeepLocal)
    static let judgedSecret = AnalysisRoute(level: .secret, provider: "apple", reason: "Un mot de passe.",
                                            needsCloudRetry: false, basis: .judged)
    static let everythingLocal = AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.keepEverythingLocal,
                                               needsCloudRetry: false, basis: .everythingLocal)
    static let offline = AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.noCloudService,
                                       needsCloudRetry: false, basis: .noCloudService)

    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String], kind: MemoryKind = .task, dates: [String] = [],
              keepLocal: Bool = false, route: AnalysisRoute?) throws -> Memory {
        guard case .saved(let interim) = try env.memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                                   categoryPath: path, mentionedDates: dates)
        let summary = try env.filer.file([thought], sourceID: interim.sourceID, route: route)
        env.dates.advance(by: 60)
        return try #require(summary.memories.first)
    }

    @Test func eachFolderCarriesWhatItsNotesForbid() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Préparer la réunion", path: ["Travail"], route: Self.neutral)
        try file(env, "Prendre les comprimés", path: ["Santé"], keepLocal: true, route: Self.local)
        try file(env, "Appeler Julie", path: ["Famille", "Julie"], route: Self.personal)
        _ = try env.categories.resolvePath(["Vide"], origin: .ai)
        _ = try env.categories.resolvePath(["Voyages"], origin: .user)
        let masks = try env.categories.provenanceMasks()
        #expect(masks["Travail"] == 0)
        #expect(masks["Santé"].map { !PrivacyPolicy.allows(mask: $0, .cloudPersonal) } == true)
        #expect(masks["Famille › Julie"].map { PrivacyPolicy.allows(mask: $0, .cloudPersonal) } == true)
        #expect(masks["Famille › Julie"].map { PrivacyPolicy.allows(mask: $0, .cloudNeutral) } == false)
        // Le dossier parent prend ce que ses sous-dossiers interdisent.
        #expect(masks["Famille"].map { PrivacyPolicy.allows(mask: $0, .cloudNeutral) } == false)
        // Un dossier de l'IA sans note : provenance inconnue ; un dossier créé par le propriétaire : son nom est à lui.
        #expect(masks["Vide"] == PrivacyPolicy.unknownMask)
        #expect(masks["Voyages"] == 0)
    }

    @Test func eachListCarriesWhatItsContributionsForbid() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Ajoute du lait à ma liste d'épicerie", path: ["Achats"], route: Self.neutral)
        try file(env, "Ajoute des pansements à ma liste de pharmacie", path: ["Achats"], keepLocal: true, route: Self.local)
        let masks = try ListStore(database: env.database, dates: env.dates).provenanceMasks()
        #expect(masks["épicerie"] == 0)
        #expect(masks["pharmacie"].map { !PrivacyPolicy.allows(mask: $0, .cloudPersonal) } == true)
    }

    @Test func aSendingReceiptIsKept() throws {
        let env = try StoreTestEnvironment()
        let note = try env.saveNote("Acheter du lait")
        let id = UUID()
        try env.memories.recordTransmission(TransmissionEvent(id: id, sourceID: note.sourceID, provider: "gemini", status: .sending))
        try env.memories.recordTransmission(TransmissionEvent(id: id, sourceID: note.sourceID, provider: "gemini", status: .failed,
                                                              detail: "réseau"))
        let receipts = try env.memories.transmissions(sourceID: note.sourceID)
        #expect(receipts.count == 1)
        #expect(receipts.first?.status == .failed)
        #expect(receipts.first?.detail == "réseau")
        #expect(try env.memories.forbiddenMask(sourceID: note.sourceID) == PrivacyPolicy.unknownMask)
    }

    @Test func aSyncedCalendarOnlyReceivesWhatThePolicyAllows() throws {
        let env = try StoreTestEnvironment()
        let calendar = CalendarLinkStore(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
        func appointment(_ title: String, keepLocal: Bool = false, route: AnalysisRoute?) throws -> Memory {
            try file(env, "\(title) demain à 15 h", path: ["Rendez-vous"], kind: .appointment, dates: ["demain à 15 h"],
                     keepLocal: keepLocal, route: route)
        }
        let neutral = try appointment("Dentiste", route: Self.neutral)
        let kept = try appointment("Psy", keepLocal: true, route: Self.local)
        let secret = try appointment("Avocat", route: Self.judgedSecret)
        let everything = try appointment("Coiffeur", route: Self.everythingLocal)
        let offline = try appointment("Garage", route: Self.offline)
        let unknown = try appointment("Banque", route: nil)

        #expect(Set(try calendar.unlinkedAppointments(for: .syncedCalendar).map(\.id)) == [neutral.id, offline.id])
        #expect(Set(try calendar.unlinkedAppointments(for: .localCalendar).map(\.id))
            == [neutral.id, kept.id, secret.id, everything.id, offline.id])
        #expect(Set(try calendar.blockedAppointments(for: .syncedCalendar).map(\.id))
            == [kept.id, secret.id, everything.id, unknown.id])
        // Une décision ciblée du propriétaire pour cette note et cette destination.
        try calendar.allowOutput(memoryID: kept.id, to: .syncedCalendar)
        #expect(try calendar.unlinkedAppointments(for: .syncedCalendar).map(\.id).contains(kept.id))
        #expect(try !calendar.blockedAppointments(for: .syncedCalendar).map(\.id).contains(kept.id))
    }
}
