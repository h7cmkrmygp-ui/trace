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
    public func pending() -> InboxReading {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var reading = InboxReading()
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            do {
                let item = try decoder.decode(SharedItem.self, from: try Data(contentsOf: file))
                reading.items.append(PendingShare(id: id, item: item))
            } catch {
                // Jamais effacé : mis de côté avec l'erreur, pour que rien ne se perde en silence.
                if quarantine(file, error: error) { reading.quarantined.append(id) }
            }
        }
        reading.items.sort { ($0.item.createdAt, $0.id) < ($1.item.createdAt, $1.id) }
        return reading
    }

    /// F19 — retire un élément, seulement après son enregistrement durable.
    public func acknowledge(_ id: String) throws {
        let file = directory.appendingPathComponent(id + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// Déplace un fichier illisible en quarantaine, avec un petit fichier qui dit pourquoi.
    func quarantine(_ file: URL, error: any Error) -> Bool {
        let name = file.deletingPathExtension().lastPathComponent
        do {
            try FileManager.default.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
            let target = quarantineDirectory.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: file, to: target)
            let note = "Partage illisible (\(name)) : \(error.localizedDescription)\n"
            try Data(note.utf8).write(to: quarantineDirectory.appendingPathComponent(name + ".erreur.txt"), options: .atomic)
            return true
        } catch {
            return false
        }
    }
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
        let reading = inbox.pending()
        var report = ShareImportReport()
        report.quarantined = reading.quarantined
        for share in reading.items {
            do {
                switch try save(share) {
                case .saved: report.saved.append(share.id)
                case .duplicate: report.duplicates.append(share.id)
                }
            } catch {
                // Rien n'est acquitté : l'élément reste dans la boîte pour le prochain essai, les suivants continuent.
                report.failed.append(share.id)
                continue
            }
            // Enregistré durablement : il peut quitter la boîte. Un acquittement raté ne crée pas de doublon ensuite
            // (l'identifiant d'import est déjà connu).
            try? inbox.acknowledge(share.id)
        }
        return report
    }
}
