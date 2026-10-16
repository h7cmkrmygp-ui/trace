import Foundation

/// Un élément partagé vers Engram depuis une autre app (texte, lien).
public struct SharedItem: Codable, Sendable, Equatable {
    public let text: String
    public let link: String?
    public let createdAt: Date

    public init(text: String, link: String?, createdAt: Date) {
        self.text = text
        self.link = link
        self.createdAt = createdAt
    }

    /// Le texte de la note : le texte partagé, puis le lien.
    public var noteText: String {
        [text, link ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Boîte de dépôt du dossier partagé : l'extension de partage y dépose, l'app reprend chaque élément une seule fois.
public struct SharedInbox: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func add(_ item: SharedItem) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = String(format: "%015.0f", item.createdAt.timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent("\(stamp)-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(item).write(to: url, options: .atomic)
    }

    /// Les éléments déposés, du plus ancien au plus récent ; ils sont retirés de la boîte.
    public func drain() -> [SharedItem] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var items: [SharedItem] = []
        for file in files {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file), let item = try? decoder.decode(SharedItem.self, from: data) else { continue }
            items.append(item)
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }
}

/// F19 — un élément de la boîte, avec son identifiant d'import stable (le nom de son fichier).
public struct PendingShare: Sendable, Equatable {
    public let id: String
    public let item: SharedItem

    public init(id: String, item: SharedItem) {
        self.id = id
        self.item = item
    }
}

/// F19 — ce que la boîte contient : les éléments lisibles, et les fichiers illisibles mis en quarantaine.
public struct InboxReading: Sendable, Equatable {
    public var items: [PendingShare]
    public var quarantined: [String]

    public init(items: [PendingShare] = [], quarantined: [String] = []) {
        self.items = items
        self.quarantined = quarantined
    }
}

extension SharedInbox {
    /// Les fichiers illisibles, gardés avec leur erreur (jamais effacés automatiquement).
    public var quarantineDirectory: URL { directory.appendingPathComponent("quarantine", isDirectory: true) }

    /// F19 — les éléments déposés, du plus ancien au plus récent, **sans les retirer** ; un fichier illisible part en
    /// quarantaine avec son erreur.
    public func pending() -> InboxReading { InboxReading() }

    /// F19 — retire un élément, seulement après son enregistrement durable.
    public func acknowledge(_ id: String) throws {}
}

/// F19 — ce qu'a donné un import.
public struct ShareImportReport: Sendable, Equatable {
    /// Identifiants d'import enregistrés pour la première fois.
    public var saved: [String] = []
    /// Déjà enregistrés (rejeu) : acquittés sans doublon.
    public var duplicates: [String] = []
    /// Non enregistrés (erreur de stockage) : restés dans la boîte pour le prochain essai.
    public var failed: [String] = []
    public var quarantined: [String] = []

    public init() {}
}

/// F19 — l'import des partages : chaque élément est enregistré, puis acquitté ; une erreur ne fait rien perdre.
public enum SharedImporter {
    public enum Outcome: Sendable, Equatable { case saved, duplicate }

    public static func run(_ inbox: SharedInbox, save: (PendingShare) throws -> Outcome) -> ShareImportReport {
        ShareImportReport()
    }
}
