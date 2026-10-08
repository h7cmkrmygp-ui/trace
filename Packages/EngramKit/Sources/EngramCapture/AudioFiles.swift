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
}
