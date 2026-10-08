import EngramCore
import Foundation

/// Dossier partagé entre l'app et ses extensions (widgets, partage). La base de notes reste dans l'app : ici ne passent
/// que le petit résumé des widgets (sans note secrète en clair) et les éléments partagés en attente.
enum SharedContainer {
    static let defaultGroup = "group.io.github.h7cmkrmygpui.engram"

    /// Avec un compte gratuit, AltStore renomme le groupe et écrit le vrai nom dans `ALTAppGroups`.
    static var groupIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? defaultGroup
    }

    /// Nil si le dossier partagé n'existe pas (installation sans extensions) : l'app fonctionne alors normalement.
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static var snapshotURL: URL? { directory?.appendingPathComponent("widget-today.json") }

    static var inbox: SharedInbox? {
        directory.map { SharedInbox(directory: $0.appendingPathComponent("Inbox", isDirectory: true)) }
    }

    /// Écrit le résumé des widgets ; renvoie vrai s'il a changé (les widgets sont alors rafraîchis).
    @discardableResult
    static func writeSnapshot(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        var comparable = snapshot
        comparable.generatedAt = .distantPast
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        if let previous = readSnapshot() {
            var old = previous
            old.generatedAt = .distantPast
            if old == comparable { return false }
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
