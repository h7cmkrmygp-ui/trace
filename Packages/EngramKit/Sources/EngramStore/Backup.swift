import EngramCore
import Foundation
import GRDB

extension AppDatabase {
    /// Copie cohérente de la base dans un seul fichier (sauvegarde SQLite, même pendant que l'app écrit).
    public func backup(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let target = try DatabaseQueue(path: url.path)
        try writer.backup(to: target)
        try target.close()
    }
}

/// Restauration d'une sauvegarde : préparée tout de suite, appliquée au lancement suivant, avant d'ouvrir la base.
/// Les données actuelles ne sont jamais effacées : elles sont rangées dans « Avant-restauration-… ».
public enum BackupRestore {
    static let pendingFolder = "RestorePending"

    /// Range la sauvegarde ouverte (base et audio) en attente de restauration.
    public static func stage(_ restored: URL, in storage: URL) throws {
        let pending = storage.appendingPathComponent(pendingFolder, isDirectory: true)
        if FileManager.default.fileExists(atPath: pending.path) { try FileManager.default.removeItem(at: pending) }
        try FileManager.default.moveItem(at: restored, to: pending)
    }

    /// Vérifie qu'une sauvegarde ouverte contient une vraie base d'Engram (elle s'ouvre, les migrations passent) et
    /// renvoie son nombre de notes (corbeille exclue).
    public static func noteCount(inRestored folder: URL) throws -> Int {
        let path = folder.appendingPathComponent(DatabaseRecovery.databaseFileName).path
        let database = try AppDatabase(DatabaseQueue(path: path, configuration: AppDatabase.makeConfiguration()))
        let count = try database.writer.read { db in
            try Memory.filter(Column("status") != MemoryStatus.trashed).fetchCount(db)
        }
        try database.writer.close()
        return count
    }

    public static func hasPending(in storage: URL) -> Bool {
        FileManager.default.fileExists(atPath: storage.appendingPathComponent(pendingFolder)
            .appendingPathComponent(DatabaseRecovery.databaseFileName).path)
    }

    /// Applique la restauration en attente ; renvoie le dossier où les anciennes données ont été rangées.
    public static func applyPending(in storage: URL, at date: Date) throws -> URL? {
        guard hasPending(in: storage) else { return nil }
        let fileManager = FileManager.default
        let pending = storage.appendingPathComponent(pendingFolder, isDirectory: true)
        let aside = storage.appendingPathComponent("Avant-restauration-\(Exporter.stamp(date))", isDirectory: true)
        try fileManager.createDirectory(at: aside, withIntermediateDirectories: true)
        let database = DatabaseRecovery.databaseFileName
        for name in [database, database + "-wal", database + "-shm", "audio"]
        where fileManager.fileExists(atPath: storage.appendingPathComponent(name).path) {
            try fileManager.moveItem(at: storage.appendingPathComponent(name), to: aside.appendingPathComponent(name))
        }
        for name in [database, "audio"] where fileManager.fileExists(atPath: pending.appendingPathComponent(name).path) {
            try fileManager.moveItem(at: pending.appendingPathComponent(name), to: storage.appendingPathComponent(name))
        }
        try fileManager.removeItem(at: pending)
        return aside
    }
}
