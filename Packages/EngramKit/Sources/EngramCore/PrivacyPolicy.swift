import Foundation

/// F01/F13/F17 — sur quoi repose la confidentialité enregistrée d'une source.
public enum PrivacyBasis: String, Codable, Sendable, CaseIterable {
    /// Le contenu a été jugé sur l'iPhone (indices et modèle d'Apple).
    case judged
    /// Le propriétaire a choisi « Garder sur l'iPhone » pour cette note.
    case ownerKeepLocal = "owner_local"
    /// Réglage « Tout garder sur l'iPhone ».
    case everythingLocal = "everything_local"
    /// Aucun service en ligne : le contenu n'a pas été jugé.
    case noCloudService = "no_cloud"
}

/// Où un contenu peut aller. Chaque destination a son bit (masque des destinations interdites d'une liste).
public enum PrivacyDestination: Int, CaseIterable, Sendable {
    /// Écran verrouillé, widgets, notifications, Siri.
    case lockScreen = 0
    /// Raccourci « Exporter pour un assistant ».
    case assistantExport = 1
    /// Calendrier synchronisé (iCloud, Google…).
    case syncedCalendar = 2
    /// Calendrier « Sur mon iPhone ».
    case localCalendar = 3
    /// Gemini (palier gratuit) : métadonnées dérivées.
    case cloudNeutral = 4
    /// Groq : métadonnées dérivées.
    case cloudPersonal = 5

    public var bit: Int { 1 << rawValue }
}

/// Ce que la base sait de la confidentialité d'une source.
public struct PrivacyFacts: Sendable, Equatable {
    public var keepLocal: Bool
    public var level: PrivacyLevel?
    public var basis: PrivacyBasis?

    public init(keepLocal: Bool, level: PrivacyLevel?, basis: PrivacyBasis?) {
        self.keepLocal = keepLocal
        self.level = level
        self.basis = basis
    }
}

/// La règle commune de toutes les sorties. Une politique inconnue n'autorise aucune sortie automatique ; « Garder sur
/// l'iPhone » n'autorise que le calendrier de l'iPhone ; un contenu non jugé (faute de service) peut s'afficher et aller
/// dans les calendriers, mais ses dérivés ne partent vers aucun service en ligne.
public enum PrivacyPolicy {
    public static func allows(_ facts: PrivacyFacts, _ destination: PrivacyDestination) -> Bool {
        if facts.keepLocal || facts.basis == .ownerKeepLocal { return destination == .localCalendar }
        guard let level = facts.level, let basis = facts.basis else { return false }
        let judgedSecret = basis == .judged && level == .secret
        switch destination {
        case .localCalendar:
            return true
        case .lockScreen:
            return !judgedSecret
        case .assistantExport, .syncedCalendar:
            return !judgedSecret && basis != .everythingLocal
        case .cloudPersonal:
            return basis == .judged && (level == .neutral || level == .personal)
        case .cloudNeutral:
            return basis == .judged && level == .neutral
        }
    }

    /// Un ensemble (une liste) n'autorise que ce que toutes ses contributions autorisent ; sans contribution, rien.
    public static func allows(_ contributions: [PrivacyFacts], _ destination: PrivacyDestination) -> Bool {
        !contributions.isEmpty && contributions.allSatisfy { allows($0, destination) }
    }

    /// Les destinations interdites, en bits (voir `PrivacyDestination.bit`).
    public static func forbiddenMask(_ facts: PrivacyFacts) -> Int {
        PrivacyDestination.allCases.filter { !allows(facts, $0) }.reduce(0) { $0 | $1.bit }
    }

    public static func allows(mask: Int, _ destination: PrivacyDestination) -> Bool {
        mask & destination.bit == 0
    }
}

extension Source {
    /// Ce que la source dit de sa confidentialité.
    public var privacyFacts: PrivacyFacts { PrivacyFacts(keepLocal: keepLocal, level: privacyLevel, basis: privacyBasis) }
}

extension PrivacyDestination {
    /// Le nom enregistré (décision ciblée du propriétaire).
    public var key: String {
        switch self {
        case .lockScreen: "lock_screen"
        case .assistantExport: "assistant_export"
        case .syncedCalendar: "synced_calendar"
        case .localCalendar: "local_calendar"
        case .cloudNeutral: "cloud_neutral"
        case .cloudPersonal: "cloud_personal"
        }
    }
}

/// F02 — d'où vient chaque métadonnée jointe à une note : les destinations interdites par les notes qui l'ont produite.
/// Une métadonnée absente d'ici ne sort pas.
public struct ContextProvenance: Sendable, Equatable {
    /// Chemin de dossier → destinations interdites (toutes les notes du dossier et de ses sous-dossiers).
    public var categories: [String: Int]
    /// Nom de liste → destinations interdites (toutes ses contributions).
    public var lists: [String: Int]
    /// La dictée précédente (contexte récent).
    public var recent: Int

    public init(categories: [String: Int] = [:], lists: [String: Int] = [:], recent: Int = PrivacyPolicy.unknownMask) {
        self.categories = categories
        self.lists = lists
        self.recent = recent
    }

    public func allowsCategory(_ path: String, _ destination: PrivacyDestination) -> Bool {
        categories[path].map { PrivacyPolicy.allows(mask: $0, destination) } ?? false
    }

    public func allowsList(_ name: String, _ destination: PrivacyDestination) -> Bool {
        lists[name].map { PrivacyPolicy.allows(mask: $0, destination) } ?? false
    }

    public func allowsRecent(_ destination: PrivacyDestination) -> Bool { PrivacyPolicy.allows(mask: recent, destination) }
}

extension PrivacyPolicy {
    /// Toutes les destinations interdites (une provenance inconnue).
    public static var unknownMask: Int { PrivacyDestination.allCases.reduce(0) { $0 | $1.bit } }
}

/// F13 — un reçu d'envoi vers un service en ligne : écrit **avant** l'envoi, puis complété ; un envoi dont la réponse a
/// échoué reste connu (le texte a pu partir).
public struct TransmissionEvent: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable { case sending, succeeded, failed }

    public let id: UUID
    public let sourceID: UUID?
    public let provider: String
    public let status: Status
    public let detail: String?

    public init(id: UUID, sourceID: UUID?, provider: String, status: Status, detail: String? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.provider = provider
        self.status = status
        self.detail = detail
    }
}
