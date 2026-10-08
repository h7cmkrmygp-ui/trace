import Foundation

/// Emplacement des enregistrements : `<dossier Engram>/audio/<uuid>.caf`, référencés par un chemin relatif.
public enum AudioFiles {
    public struct Recording: Sendable, Equatable {
        public let url: URL
        /// Chemin relatif au dossier Engram (stocké dans `source.audio_path`).
        public let relativePath: String
    }

    public static func newRecording(in base: URL, fileManager: FileManager = .default) throws -> Recording {
        let directory = base.appendingPathComponent("audio", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased()).caf"
        return Recording(url: directory.appendingPathComponent(name), relativePath: "audio/\(name)")
    }

    public static func url(forRelativePath path: String, in base: URL) -> URL {
        base.appendingPathComponent(path)
    }

    /// Enregistrements présents sur le disque mais inconnus de la base (app fermée pendant l'enregistrement),
    /// plus anciens que `olderThan` pour ne jamais prendre un enregistrement en cours.
    public static func orphanedRecordings(in base: URL, referenced: Set<String>, olderThan limit: Date,
                                          fileManager: FileManager = .default) throws -> [String] {
        let directory = base.appendingPathComponent("audio", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        return try files
            .filter { $0.pathExtension == "caf" }
            .filter { url in
                let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
                return modified < limit
            }
            .map { "audio/\($0.lastPathComponent)" }
            .filter { !referenced.contains($0) }
            .sorted()
    }
}
