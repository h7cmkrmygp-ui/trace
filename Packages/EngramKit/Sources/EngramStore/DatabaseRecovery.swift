import Foundation

/// Copie de secours quand la base ne s'ouvre plus (spec §5.2 et §10) : les fichiers bruts sont copiés
/// et compressés **sans ouvrir la base**, pour que le propriétaire puisse les sauvegarder ailleurs.
public enum DatabaseRecovery {
    public static let databaseFileName = "engram.sqlite"

    public struct Archive: Sendable, Equatable {
        public let archiveURL: URL
        /// Fichiers copiés (la base et, s'ils existent, ses journaux `-wal` et `-shm`).
        public let fileNames: [String]
    }

    /// Dossier qui contient la base de l'app.
    public static func storageDirectory(fileManager: FileManager = .default) throws -> URL {
        try StorageLocation.engramDirectory(fileManager: fileManager)
    }

    public static func archiveRawFiles(from directory: URL, into destination: URL, at date: Date = Date()) throws -> Archive {
        let fileManager = FileManager.default
        let names = [databaseFileName, databaseFileName + "-shm", databaseFileName + "-wal"]
            .filter { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
        guard names.contains(databaseFileName) else { throw StoreError.notFound }

        let folder = destination.appendingPathComponent("Engram-Recuperation-\(Exporter.stamp(date))", isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try fileManager.copyItem(at: directory.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        let archive = destination.appendingPathComponent(folder.lastPathComponent + ".zip")
        try Exporter.zip(folder, to: archive)
        return Archive(archiveURL: archive, fileNames: names)
    }
}
