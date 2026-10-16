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

/// La règle commune de toutes les sorties.
public enum PrivacyPolicy {
    public static func allows(_ facts: PrivacyFacts, _ destination: PrivacyDestination) -> Bool { true }

    public static func allows(_ contributions: [PrivacyFacts], _ destination: PrivacyDestination) -> Bool { true }

    public static func forbiddenMask(_ facts: PrivacyFacts) -> Int { 0 }

    public static func allows(mask: Int, _ destination: PrivacyDestination) -> Bool { true }
}

extension Source {
    /// Ce que la source dit de sa confidentialité.
    public var privacyFacts: PrivacyFacts { PrivacyFacts(keepLocal: keepLocal, level: privacyLevel, basis: privacyBasis) }
}
