import Foundation

public enum BackupArchive {
    public enum Failure: Error, Equatable {
        case notABackup, wrongPasswordOrDamaged, unsafePath
    }

    public static let defaultIterations: UInt32 = 600_000

    public static func write(files: [String], from base: URL, to archive: URL, password: String,
                             iterations: UInt32 = defaultIterations) throws {}

    @discardableResult
    public static func read(_ archive: URL, password: String, into destination: URL) throws -> [String] { [] }

    static func isSafe(_ path: String) -> Bool { true }
}
