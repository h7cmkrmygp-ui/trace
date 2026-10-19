import CryptoKit
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

    /// F28 — la dernière migration appliquée (la version du schéma, écrite dans le manifeste d'une sauvegarde).
    public func schemaVersion() throws -> String {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1") ?? "inconnue"
        }
    }
}

/// F28 — le manifeste d'une sauvegarde : format, version du schéma, fichiers attendus et leurs empreintes (SHA-256).
public struct BackupManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let path: String
        public let size: Int64
        public let sha256: String
    }

    public static let fileName = "manifest.json"
    public static let currentFormat = 1
    public var formatVersion: Int
    public var schemaVersion: String
    public var createdAt: Date
    public var files: [Entry]

    /// Écrit le manifeste des fichiers de `folder` (chemins relatifs) et le renvoie.
    @discardableResult
    public static func write(in folder: URL, files: [String], schemaVersion: String, createdAt: Date) throws -> BackupManifest {
        let entries = try files.map { path -> Entry in
            let url = folder.appendingPathComponent(path)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return Entry(path: path, size: size, sha256: try digest(of: url))
        }
        let manifest = BackupManifest(formatVersion: currentFormat, schemaVersion: schemaVersion, createdAt: createdAt,
                                      files: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(fileName), options: .atomic)
        return manifest
    }

    static func read(in folder: URL) throws -> BackupManifest? {
        let url = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BackupManifest.self, from: Data(contentsOf: url)) else {
            throw BackupRestore.Failure.corrupted(fileName)
        }
        return manifest
    }

    /// L'empreinte SHA-256 d'un fichier, lu par morceaux (les enregistrements audio peuvent être longs).
    static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Restauration d'une sauvegarde : vérifiée, préparée tout de suite, appliquée au lancement suivant, avant d'ouvrir la
/// base. Les données actuelles ne sont jamais effacées : elles sont rangées dans « Avant-restauration-… ».
public enum BackupRestore {
    static let pendingFolder = "RestorePending"
    static let journalName = "RestoreJournal.json"

    public enum Failure: Error, Equatable, Sendable {
        /// La sauvegarde ne contient pas de base : rien n'est restauré (et aucune base vide n'est fabriquée).
        case missingDatabase
        /// Un fichier annoncé par le manifeste manque.
        case missingFile(String)
        /// Un fichier ne correspond pas à son empreinte, ou la base ne passe pas le contrôle de SQLite.
        case corrupted(String)
        /// La base ne vient pas d'Engram.
        case notEngram
        /// Arrêt volontaire pendant une restauration (tests) : le journal permet de la reprendre.
        case interrupted
    }

    /// Ce que dit la vérification d'une sauvegarde ouverte.
    public struct RestoreCheck: Sendable, Equatable {
        public let noteCount: Int
        /// Enregistrements audio référencés par la base mais absents de la sauvegarde.
        public let missingAudio: [String]
        /// false : sauvegarde d'une version d'avant le manifeste (restaurable, sans empreintes à vérifier).
        public let hasManifest: Bool
        public let schemaVersion: String?
    }

    /// Range la sauvegarde ouverte (base et audio) en attente de restauration.
    public static func stage(_ restored: URL, in storage: URL) throws {
        let pending = storage.appendingPathComponent(pendingFolder, isDirectory: true)
        if FileManager.default.fileExists(atPath: pending.path) { try FileManager.default.removeItem(at: pending) }
        try FileManager.default.moveItem(at: restored, to: pending)
    }

    /// F28 — vérifie une sauvegarde ouverte sans rien y créer : la base est là, chaque fichier du manifeste correspond à
    /// son empreinte, la base s'ouvre en lecture seule et passe le contrôle d'intégrité de SQLite, et c'est une base
    /// d'Engram. Signale les audios référencés absents.
    public static func validate(_ folder: URL) throws -> RestoreCheck {
        let fileManager = FileManager.default
        let databaseURL = folder.appendingPathComponent(DatabaseRecovery.databaseFileName)
        guard fileManager.fileExists(atPath: databaseURL.path) else { throw Failure.missingDatabase }
        let manifest = try BackupManifest.read(in: folder)
        for entry in manifest?.files ?? [] {
            let url = folder.appendingPathComponent(entry.path)
            guard fileManager.fileExists(atPath: url.path) else { throw Failure.missingFile(entry.path) }
            guard try BackupManifest.digest(of: url) == entry.sha256 else { throw Failure.corrupted(entry.path) }
        }
        var configuration = Configuration()
        configuration.readonly = true
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        } catch {
            throw Failure.corrupted(DatabaseRecovery.databaseFileName)
        }
        defer { try? queue.close() }
        let (count, audio): (Int, [String])
        do {
            (count, audio) = try queue.read { db -> (Int, [String]) in
                guard try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok" else {
                    throw Failure.corrupted(DatabaseRecovery.databaseFileName)
                }
                guard try db.tableExists("memory"), try db.tableExists("source") else { throw Failure.notEngram }
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory WHERE status != 'trashed'") ?? 0
                let audio = try String.fetchAll(db, sql: "SELECT audio_path FROM source WHERE audio_path IS NOT NULL")
                return (count, audio)
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.corrupted(DatabaseRecovery.databaseFileName)
        }
        let missing = audio.filter { !fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }.sorted()
        return RestoreCheck(noteCount: count, missingAudio: missing, hasManifest: manifest != nil,
                            schemaVersion: manifest?.schemaVersion)
    }

    /// Le nombre de notes d'une sauvegarde ouverte (corbeille exclue), après vérification (voir `validate`).
    public static func noteCount(inRestored folder: URL) throws -> Int {
        try validate(folder).noteCount
    }

    public static func hasPending(in storage: URL) -> Bool {
        FileManager.default.fileExists(atPath: storage.appendingPathComponent(journalName).path)
            || FileManager.default.fileExists(atPath: storage.appendingPathComponent(pendingFolder)
                .appendingPathComponent(DatabaseRecovery.databaseFileName).path)
    }

    /// F28 — le journal d'une restauration en cours : le dossier de mise de côté et les étapes faites.
    struct Journal: Codable {
        var aside: String
        var done: Int
    }

    /// Les étapes, dans l'ordre : mettre de côté la base, ses journaux et l'audio actuels, mettre en place la base et
    /// l'audio restaurés, puis terminer. Chacune peut être refaite sans dommage.
    static let steps: [(kind: String, name: String)] = {
        let database = DatabaseRecovery.databaseFileName
        return [("aside", database), ("aside", database + "-wal"), ("aside", database + "-shm"), ("aside", "audio"),
                ("in", database), ("in", "audio"), ("finish", "")]
    }()

    /// Arrêts possibles pendant une restauration (après chaque déplacement, avant la fin).
    public static var stepCount: Int { steps.count - 1 }

    /// Applique la restauration en attente, ou reprend celle qu'un arrêt a interrompue (journal) ; renvoie le dossier où
    /// les anciennes données ont été rangées. Une erreur n'est jamais ignorée : le journal reste pour la reprise.
    /// - Parameter interruptAfter: tests seulement — s'arrête après ce nombre d'étapes.
    public static func applyPending(in storage: URL, at date: Date, interruptAfter: Int? = nil) throws -> URL? {
        guard hasPending(in: storage) else { return nil }
        let fileManager = FileManager.default
        let journalURL = storage.appendingPathComponent(journalName)
        let pending = storage.appendingPathComponent(pendingFolder, isDirectory: true)
        var journal: Journal
        if let data = try? Data(contentsOf: journalURL), let saved = try? JSONDecoder().decode(Journal.self, from: data) {
            journal = saved
        } else {
            journal = Journal(aside: "Avant-restauration-\(Exporter.stamp(date))", done: 0)
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        }
        let aside = storage.appendingPathComponent(journal.aside, isDirectory: true)
        try fileManager.createDirectory(at: aside, withIntermediateDirectories: true)
        var performed = 0
        for index in journal.done..<steps.count {
            let step = steps[index]
            switch step.kind {
            case "aside":
                let current = storage.appendingPathComponent(step.name)
                if fileManager.fileExists(atPath: current.path) {
                    var target = aside.appendingPathComponent(step.name)
                    // Déjà mis de côté avant un arrêt : la copie gardée reste intacte, la nouvelle va à côté.
                    if fileManager.fileExists(atPath: target.path) {
                        target = aside.appendingPathComponent(step.name + "-pendant-la-reprise-\(Exporter.stamp(date))")
                        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
                    }
                    try fileManager.moveItem(at: current, to: target)
                }
            case "in":
                let restored = pending.appendingPathComponent(step.name)
                if fileManager.fileExists(atPath: restored.path) {
                    let target = storage.appendingPathComponent(step.name)
                    // Ce qui a pu être écrit entre un arrêt et la reprise n'est jamais effacé : il est mis de côté aussi.
                    if fileManager.fileExists(atPath: target.path) {
                        let kept = aside.appendingPathComponent(step.name + "-pendant-la-reprise-\(Exporter.stamp(date))")
                        if fileManager.fileExists(atPath: kept.path) { try fileManager.removeItem(at: kept) }
                        try fileManager.moveItem(at: target, to: kept)
                    }
                    try fileManager.moveItem(at: restored, to: target)
                }
            default:
                if fileManager.fileExists(atPath: pending.path) { try fileManager.removeItem(at: pending) }
            }
            journal.done = index + 1
            if index + 1 < steps.count {
                try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            } else {
                try fileManager.removeItem(at: journalURL)
            }
            performed += 1
            if let interruptAfter, performed >= interruptAfter, index + 1 < steps.count { throw Failure.interrupted }
        }
        return aside
    }
}
