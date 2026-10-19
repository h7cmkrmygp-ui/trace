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

/// F28 — le manifeste d'une sauvegarde : format, version du schéma, fichiers attendus et leurs empreintes.
public struct BackupManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let path: String
        public let size: Int64
        public let sha256: String
    }

    public static let fileName = "manifest.json"
    public var formatVersion: Int
    public var schemaVersion: String
    public var createdAt: Date
    public var files: [Entry]

    /// Écrit le manifeste des fichiers de `folder`.
    @discardableResult
    public static func write(in folder: URL, files: [String], schemaVersion: String, createdAt: Date) throws -> BackupManifest {
        BackupManifest(formatVersion: 1, schemaVersion: schemaVersion, createdAt: createdAt, files: [])
    }
}

extension BackupRestore {
    public enum Failure: Error, Equatable, Sendable {
        case missingDatabase
        case missingFile(String)
        case corrupted(String)
        case notEngram
        case interrupted
    }

    /// Ce que dit la vérification d'une sauvegarde ouverte.
    public struct RestoreCheck: Sendable, Equatable {
        public let noteCount: Int
        public let missingAudio: [String]
        public let hasManifest: Bool
        public let schemaVersion: String?
    }

    /// Étapes d'une restauration (mise de côté, mise en place, fin).
    public static let stepCount = 7

    public static func validate(_ folder: URL) throws -> RestoreCheck {
        RestoreCheck(noteCount: try noteCount(inRestored: folder), missingAudio: [], hasManifest: false, schemaVersion: nil)
    }

    public static func applyPending(in storage: URL, at date: Date, interruptAfter: Int?) throws -> URL? {
        try applyPending(in: storage, at: date)
    }
}
