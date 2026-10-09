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

    /// L'idée du soir : les idées éligibles, de la plus ancienne à la plus récente, reviennent tour à tour (le numéro du
    /// jour choisit la suivante), sans hasard ni état à garder.
    public static func pick(_ candidates: [Candidate], on day: Date, calendar: Calendar, minimumAge: Int = 30) -> Candidate? {
        guard let limit = calendar.date(byAdding: .day, value: -minimumAge, to: day) else { return nil }
        let eligible = candidates
            .filter { !$0.isPrivate && $0.kind != .task && $0.kind != .appointment && $0.capturedAt <= limit }
            .sorted { ($0.capturedAt, $0.id.uuidString) < ($1.capturedAt, $1.id.uuidString) }
        guard !eligible.isEmpty else { return nil }
        let dayNumber = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0),
                                                to: calendar.startOfDay(for: day)).day ?? 0
        return eligible[((dayNumber % eligible.count) + eligible.count) % eligible.count]
    }

    /// La notification du prochain soir (aujourd'hui avant 19 h, sinon demain). `hideTitle` : Engram est verrouillé.
    public static func reminder(from candidates: [Candidate], now: Date, calendar: Calendar, hour: Int = 19,
                                hideTitle: Bool) -> PlannedReminder? {
        guard let moment = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0),
                                             matchingPolicy: .nextTime),
              let chosen = pick(candidates, on: moment, calendar: calendar) else { return nil }
        return PlannedReminder(identifier: identifier, memoryID: chosen.id, date: moment, title: "Te souviens-tu ?",
                               body: hideTitle ? "Une ancienne idée t'attend" : chosen.title)
    }
}
