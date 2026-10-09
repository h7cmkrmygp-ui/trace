import Foundation

/// P13 — « Te souviens-tu ? » : chaque soir à 19 h, une vieille idée (plus de 30 jours) revient, une différente chaque
/// soir jusqu'à ce que toutes soient revenues. Jamais une tâche, jamais une note privée.
public enum Resurfacing {
    public static let identifier = "engram.resurface"

    public struct Candidate: Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let kind: MemoryKind?
        public let capturedAt: Date
        public let isPrivate: Bool

        public init(id: UUID, title: String, kind: MemoryKind?, capturedAt: Date, isPrivate: Bool) {
            self.id = id
            self.title = title
            self.kind = kind
            self.capturedAt = capturedAt
            self.isPrivate = isPrivate
        }
    }

    public static func pick(_ candidates: [Candidate], on day: Date, calendar: Calendar, minimumAge: Int = 30) -> Candidate? {
        nil
    }

    public static func reminder(from candidates: [Candidate], now: Date, calendar: Calendar, hour: Int = 19,
                                hideTitle: Bool) -> PlannedReminder? {
        nil
    }
}
