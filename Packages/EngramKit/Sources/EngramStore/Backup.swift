import EngramCore
import Foundation
import GRDB

extension AppDatabase {
    public func backup(to url: URL) throws {}
}

public enum BackupRestore {
    public static func stage(_ restored: URL, in storage: URL) throws {}
    public static func hasPending(in storage: URL) -> Bool { false }
    public static func applyPending(in storage: URL, at date: Date) throws -> URL? { nil }
}
