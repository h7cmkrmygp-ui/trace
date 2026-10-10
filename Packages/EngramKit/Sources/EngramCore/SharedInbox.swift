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
