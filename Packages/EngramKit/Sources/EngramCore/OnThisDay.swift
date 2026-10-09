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
        /// « Il y a un mois », « Il y a un an », « Il y a 2 ans ».
        public let label: String
        public let notes: [Note]
        public var id: String { label }
    }

    static let steps: [(months: Int, label: String)] =
        [(1, "Il y a un mois"), (6, "Il y a six mois"), (12, "Il y a un an")] + (2...10).map { (months: $0 * 12, label: "Il y a \($0) ans") }

    /// Les notes du même jour du mois (un mois plus court n'en a pas : le 31 mars ne rappelle pas le 28 février), au plus
    /// `perDay` par jour, la plus ancienne d'abord. Les notes privées n'y sont jamais.
    public static func groups(_ notes: [Note], today: Date, calendar: Calendar, perDay: Int = 3) -> [Group] {
        let day = calendar.component(.day, from: today)
        var groups: [Group] = []
        for step in steps {
            guard let target = calendar.date(byAdding: .month, value: -step.months, to: today),
                  calendar.component(.day, from: target) == day else { continue }
            let matching = notes
                .filter { !$0.isPrivate && calendar.isDate($0.capturedAt, inSameDayAs: target) }
                .sorted { $0.capturedAt < $1.capturedAt }
            if !matching.isEmpty { groups.append(Group(label: step.label, notes: Array(matching.prefix(perDay)))) }
        }
        return groups
    }
}
