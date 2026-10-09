import EngramCore
import Foundation
import GRDB

/// P15 — les listes (épicerie, cadeaux…) : une note par liste, complétée à chaque « ajoute … à ma liste ».
public struct ListStore: Sendable {
    /// Une liste, pour la carte « Listes » des Notes.
    public struct Summary: Sendable, Equatable, Identifiable {
        public let memoryID: UUID
        /// « Épicerie ».
        public let name: String
        /// « Liste d'épicerie » (le titre de la note, qui peut avoir été renommée).
        public let title: String
        public let open: Int
        public let done: Int
        public let updatedAt: Date
        public var id: UUID { memoryID }
    }

    public let database: AppDatabase
    public let dates: any DateProvider

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    public func lists() throws -> [Summary] { [] }
}
