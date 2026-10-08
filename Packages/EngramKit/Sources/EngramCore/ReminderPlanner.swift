import Foundation

/// Un rappel à programmer sur l'iPhone (notification locale).
public struct PlannedReminder: Sendable, Equatable {
    public let identifier: String
    public let memoryID: UUID
    public let date: Date
    public let title: String
    public let body: String
}

/// Calcule les rappels des tâches et rendez-vous datés.
public enum ReminderPlanner {
    public struct Item: Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let kind: MemoryKind?
        public let status: MemoryStatus
        public let dueAt: Date?
        public let dueHasTime: Bool
        /// Note gardée sur l'iPhone (secrète) : rien de son contenu sur l'écran verrouillé.
        public let isPrivate: Bool

        public init(id: UUID, title: String, kind: MemoryKind?, status: MemoryStatus, dueAt: Date?, dueHasTime: Bool,
                    isPrivate: Bool) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.dueAt = dueAt
            self.dueHasTime = dueHasTime
            self.isPrivate = isPrivate
        }
    }

    /// Tâches à l'heure dite, rendez-vous 1 h avant ; sans heure, à 9 h le jour même. Seulement les notes encore à
    /// faire et dans le futur ; les plus proches d'abord (iOS garde au plus 64 notifications en attente).
    public static func plan(_ items: [Item], now: Date, calendar: Calendar, limit: Int = 60) -> [PlannedReminder] {
        let planned = items.compactMap { item -> PlannedReminder? in
            guard item.status == .active || item.status == .unsorted, let due = item.dueAt,
                  item.kind == .task || item.kind == .appointment else { return nil }
            let isAppointment = item.kind == .appointment
            let date: Date
            let body: String
            if item.dueHasTime {
                date = isAppointment ? due.addingTimeInterval(-3_600) : due
                body = isAppointment ? "Rendez-vous à \(clock(due, calendar: calendar))" : "À faire maintenant"
            } else {
                date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
                body = isAppointment ? "Rendez-vous aujourd'hui" : "À faire aujourd'hui"
            }
            guard date > now else { return nil }
            return PlannedReminder(identifier: identifierPrefix + item.id.uuidString, memoryID: item.id, date: date,
                                   title: item.isPrivate ? "Rappel Engram" : item.title,
                                   body: item.isPrivate ? "Ouvre Engram pour le voir." : body)
        }
        return Array(planned.sorted { $0.date < $1.date }.prefix(limit))
    }

    public static let identifierPrefix = "engram.reminder."

    /// « 14 h », « 14 h 30 » (comme au Québec).
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(hour) h" : String(format: "%d h %02d", hour, minute)
    }
}

/// Raisons de classement fixes, partagées entre l'IA (qui les écrit) et la base (qui les lit) : une note classée sur
/// l'iPhone pour l'une d'elles n'est pas secrète pour autant (les rappels peuvent montrer son titre).
public enum RouteReasons {
    public static let keepEverythingLocal = "Réglage « Tout garder sur l'iPhone » activé."
    public static let noCloudService = "Aucun service en ligne configuré."
}
