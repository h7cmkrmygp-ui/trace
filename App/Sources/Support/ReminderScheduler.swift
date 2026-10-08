import EngramCore
import Foundation
import UserNotifications

/// Rappels sur l'iPhone : notifications locales, recalculées à chaque changement de la base (jamais envoyées
/// ailleurs). Un rappel se règle depuis la notification : « Fait », « Dans 1 h », « Demain ». Le résumé du matin
/// ouvre « À faire » ; celui de la semaine ouvre Retrouver.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    enum Kind: String {
        case reminder, digest, weekly

        var category: String { "engram.\(rawValue)" }
    }

    static let doneAction = "engram.done"
    static let laterAction = "engram.later"
    static let tomorrowAction = "engram.tomorrow"

    private let center = UNUserNotificationCenter.current()
    /// Toucher un rappel : ouvrir la note.
    var onOpen: ((UUID) -> Void)?
    /// « Fait », « Dans 1 h », « Demain » sur un rappel.
    var onAction: ((String, UUID) -> Void)?
    /// Toucher le résumé du matin.
    var onOpenTodo: (() -> Void)?
    /// Toucher le résumé de la semaine.
    var onOpenWeekly: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Fait", options: [],
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let later = UNNotificationAction(identifier: Self.laterAction, title: "Dans 1 h", options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "clock"))
        let tomorrow = UNNotificationAction(identifier: Self.tomorrowAction, title: "Demain", options: [],
                                            icon: UNNotificationActionIcon(systemImageName: "sunrise"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Kind.reminder.category, actions: [done, later, tomorrow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.digest.category, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.weekly.category, actions: [], intentIdentifiers: []),
        ])
    }

    func isAllowed() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func isUndecided() async -> Bool {
        await center.notificationSettings().authorizationStatus == .notDetermined
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Remplace les notifications d'Engram en attente par celles-ci.
    func apply(_ requests: [(reminder: PlannedReminder, kind: Kind)], calendar: Calendar) async {
        await removeAll()
        for (reminder, kind) in requests {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = kind.category
            content.threadIdentifier = kind == .reminder ? "engram.reminders" : "engram.summaries"
            content.userInfo = ["memoryID": reminder.memoryID.uuidString, "kind": kind.rawValue]
            let moment = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: moment, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }
    }

    func removeAll() async {
        let prefixes = [ReminderPlanner.identifierPrefix, DigestPlanner.morningPrefix, DigestPlanner.weeklyIdentifier]
        let ours = await center.pendingNotificationRequests().map(\.identifier)
            .filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Pastille de l'icône : ce qui est à faire aujourd'hui ou en retard.
    func setBadge(_ count: Int) async {
        try? await center.setBadgeCount(count)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = Kind(rawValue: info["kind"] as? String ?? "") ?? .reminder
        let id = (info["memoryID"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        await MainActor.run { self.handle(kind: kind, action: action, memoryID: id) }
    }

    private func handle(kind: Kind, action: String, memoryID: UUID?) {
        switch kind {
        case .digest: onOpenTodo?()
        case .weekly: onOpenWeekly?()
        case .reminder:
            guard let memoryID else { return }
            if action == UNNotificationDefaultActionIdentifier {
                onOpen?(memoryID)
            } else if action != UNNotificationDismissActionIdentifier {
                onAction?(action, memoryID)
            }
        }
    }
}

/// Rappels reportés (« Dans 1 h », « Demain »), gardés sur l'iPhone ; un report passé est oublié.
@MainActor
final class ReminderSnoozes {
    private let defaults = UserDefaults.standard
    private let key = "engram.reminderSnoozes"

    func active(at now: Date) -> [UUID: Date] {
        let stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        var result: [UUID: Date] = [:]
        for (text, time) in stored where time > now.timeIntervalSince1970 {
            if let id = UUID(uuidString: text) { result[id] = Date(timeIntervalSince1970: time) }
        }
        return result
    }

    func set(_ id: UUID, until date: Date) {
        var stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        stored = stored.filter { $0.value > Date().timeIntervalSince1970 }
        stored[id.uuidString] = date.timeIntervalSince1970
        defaults.set(stored, forKey: key)
    }

    func remove(_ id: UUID) {
        var stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        stored[id.uuidString] = nil
        defaults.set(stored, forKey: key)
    }
}
