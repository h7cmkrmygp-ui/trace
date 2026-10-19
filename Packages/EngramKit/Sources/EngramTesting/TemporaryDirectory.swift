import Foundation

/// Dossier temporaire unique, supprimé automatiquement à la fin du test.
public final class TemporaryDirectory: Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engram-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
