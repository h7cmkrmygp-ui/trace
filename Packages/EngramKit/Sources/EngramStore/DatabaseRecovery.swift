import Foundation

/// Copie de secours des fichiers bruts de la base (implémentation à venir).
public enum DatabaseRecovery {
    public struct Archive: Sendable, Equatable {
        public let archiveURL: URL
        public let fileNames: [String]
    }

    public static func archiveRawFiles(from directory: URL, into destination: URL, at date: Date = Date()) throws -> Archive {
        throw StoreError.invalidOperation("pas encore implémenté")
    }
}
