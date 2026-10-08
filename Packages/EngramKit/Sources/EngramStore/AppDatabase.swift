import EngramCore
import Foundation
import GRDB

/// Accès à la base SQLite d'Engram.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    /// Ouvre la base et applique les migrations manquantes. Ne supprime jamais de données.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Schema.migrator.migrate(writer)
    }

    public static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "Engram"
        return configuration
    }

    /// Base de l'app, dans Application Support/Engram, protégée par la Data Protection d'iOS.
    public static func openOnDisk(fileManager: FileManager = .default) throws -> AppDatabase {
        let directory = try StorageLocation.engramDirectory(fileManager: fileManager)
        let url = directory.appendingPathComponent("engram.sqlite")
        return try AppDatabase(DatabasePool(path: url.path, configuration: makeConfiguration()))
    }

    /// Base en mémoire, pour les tests.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    /// Flux de valeurs recalculées à chaque modification des tables lues par `fetch`.
    public func stream<Value: Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, any Error> {
        let writer = self.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in ValueObservation.tracking(fetch).values(in: writer) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum StorageLocation {
    /// Dossier Application Support/Engram. Sur iOS, les fichiers créés dedans héritent de la protection
    /// « jusqu'à la première authentification » (lisibles en arrière-plan une fois l'iPhone déverrouillé).
    static func engramDirectory(fileManager: FileManager) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Engram", isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        if fileManager.fileExists(atPath: directory.path) {
            if !attributes.isEmpty { try fileManager.setAttributes(attributes, ofItemAtPath: directory.path) }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        }
        return directory
    }
}
