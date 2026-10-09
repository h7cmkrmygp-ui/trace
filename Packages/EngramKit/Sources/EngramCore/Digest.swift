import Foundation

/// Chiffres d'une semaine, pour son résumé.
public struct WeekStats: Sendable, Equatable {
    public let notes: Int
    public let done: Int
    public let open: Int

    public init(notes: Int, done: Int, open: Int) {
        self.notes = notes
        self.done = done
        self.open = open
    }
}

/// Résumés qui font avancer les tâches : le matin (aujourd'hui et retards), la pastille de l'icône, le dimanche soir.
/// Une note privée n'y apparaît jamais par son titre.
public enum DigestPlanner {
    public static let morningPrefix = "engram.digest."
    public static let weeklyIdentifier = "engram.weekly"

    /// Les prochains résumés du matin (8 h), seulement les jours où il y a quelque chose à faire ou en retard.
    public static func mornings(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar, days: Int = 3,
                                hour: Int = 8) -> [PlannedReminder] {
        let open = items.filter(isOpen)
        var digests: [PlannedReminder] = []
        for offset in 0...days {
            guard digests.count < days,
                  let dayStart = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart),
                  moment > now else { continue }
            let today = open.filter { ($0.dueAt ?? .distantPast) >= dayStart && ($0.dueAt ?? .distantPast) < dayEnd }
                .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
            let late = open.filter { $0.kind == .task && ($0.dueAt ?? .distantFuture) < dayStart }
            guard !today.isEmpty || !late.isEmpty else { continue }
            var parts: [String] = []
            if !today.isEmpty {
                let count = today.count == 1 ? "1 chose à faire" : "\(today.count) choses à faire"
                parts.append("\(count) : \(names(today, max: 3)).")
            }
            if !late.isEmpty { parts.append("En retard : \(names(late, max: 2)).") }
            let parts3 = calendar.dateComponents([.year, .month, .day], from: dayStart)
            let key = String(format: "%04d-%02d-%02d", parts3.year ?? 0, parts3.month ?? 0, parts3.day ?? 0)
            digests.append(PlannedReminder(identifier: morningPrefix + key, memoryID: today.first?.id ?? late[0].id,
                                           date: moment, title: "Aujourd'hui", body: parts.joined(separator: " ")))
        }
        return digests
    }

    /// Pastille de l'icône : les tâches du jour ou en retard, et les rendez-vous du jour.
    public static func badgeCount(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return items.filter(isOpen).filter { item in
            guard let due = item.dueAt, due < end else { return false }
            return item.kind == .task || due >= start
        }.count
    }

    /// Le dimanche à 18 h : notes de la semaine, choses faites, choses à faire. Rien si la semaine est vide.
    public static func weekly(_ stats: WeekStats, now: Date, calendar: Calendar) -> PlannedReminder? {
        guard stats.notes > 0,
              let moment = calendar.nextDate(after: now, matching: DateComponents(hour: 18, minute: 0, weekday: 1),
                                             matchingPolicy: .nextTime) else { return nil }
        let notes = stats.notes == 1 ? "1 note" : "\(stats.notes) notes"
        let done = stats.done == 1 ? "1 chose faite" : "\(stats.done) choses faites"
        return PlannedReminder(identifier: weeklyIdentifier, memoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                               date: moment, title: "Ta semaine", body: "\(notes) · \(done) · \(stats.open) à faire")
    }

    static func isOpen(_ item: ReminderPlanner.Item) -> Bool {
        (item.status == .active || item.status == .unsorted) && (item.kind == .task || item.kind == .appointment)
            && item.dueAt != nil
    }

    /// « A, B et C », « A, B et 3 autres » ; une note privée s'appelle « une note privée ».
    static func names(_ items: [ReminderPlanner.Item], max: Int) -> String {
        let titles = items.prefix(max).map { $0.isPrivate ? "une note privée" : $0.title }
        let rest = items.count - titles.count
        if rest > 0 { return titles.joined(separator: ", ") + " et \(rest) autre\(rest > 1 ? "s" : "")" }
        guard titles.count > 1 else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " et " + titles[titles.count - 1]
    }
}

/// Ce que les widgets affichent, écrit par l'app dans le dossier partagé (jamais de note secrète en clair).
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let title: String
        /// « 14 h » si une heure a été dite.
        public let time: String?
        public let isAppointment: Bool

        public init(title: String, time: String?, isAppointment: Bool) {
            self.title = title
            self.time = time
            self.isAppointment = isAppointment
        }
    }

    /// Une chose à faire datée, titre déjà masqué si la note est privée.
    public struct Upcoming: Codable, Sendable, Equatable {
        public let title: String
        public let due: Date
        public let hasTime: Bool
        public let isAppointment: Bool
    }

    public var generatedAt: Date = .distantPast
    /// Les retards et les 8 prochains jours : le widget recalcule « aujourd'hui » lui-même les jours suivants.
    public var upcoming: [Upcoming] = []
    public var today: [Entry] = []
    public var lateCount = 0

    public init() {}

    /// La journée vue à une date donnée : d'abord ce qui est pour la journée (sans heure), puis par heure.
    public func day(at date: Date, calendar: Calendar) -> (today: [Entry], lateCount: Int) {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return ([], 0) }
        let today = upcoming.filter { $0.due >= start && $0.due < end }
            .sorted { ($0.hasTime ? 1 : 0, $0.due) < ($1.hasTime ? 1 : 0, $1.due) }
            .map { Entry(title: $0.title, time: $0.hasTime ? ReminderPlanner.clock($0.due, calendar: calendar) : nil,
                         isAppointment: $0.isAppointment) }
        return (today, upcoming.filter { !$0.isAppointment && $0.due < start }.count)
    }

    public static func make(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar) -> WidgetSnapshot {
        let horizon = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) ?? now
        var snapshot = WidgetSnapshot()
        snapshot.generatedAt = now
        snapshot.upcoming = items.filter(DigestPlanner.isOpen).compactMap { item in
            guard let due = item.dueAt, due < horizon else { return nil }
            return Upcoming(title: item.isPrivate ? "Rappel privé" : item.title, due: due, hasTime: item.dueHasTime,
                            isAppointment: item.kind == .appointment)
        }
        let day = snapshot.day(at: now, calendar: calendar)
        snapshot.today = day.today
        snapshot.lateCount = day.lateCount
        return snapshot
    }
}
