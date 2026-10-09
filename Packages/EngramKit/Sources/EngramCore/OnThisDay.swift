import Foundation

/// P24 — « Ce jour-là » : les notes prises le même jour, il y a un mois, six mois, un an, deux ans…
public enum OnThisDay {
    public struct Note: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let capturedAt: Date
        /// Gardée sur l'iPhone ou jugée secrète : jamais montrée ici.
        public let isPrivate: Bool

        public init(id: UUID, title: String, capturedAt: Date, isPrivate: Bool) {
            self.id = id
            self.title = title
            self.capturedAt = capturedAt
            self.isPrivate = isPrivate
        }
    }

    public struct Group: Sendable, Equatable, Identifiable {
        public let label: String
        public let notes: [Note]
        public var id: String { label }
    }

    public static func groups(_ notes: [Note], today: Date, calendar: Calendar, perDay: Int = 3) -> [Group] { [] }
}
