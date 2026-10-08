import EngramCore
import Foundation
import UserNotifications

/// Rappels sur l'iPhone : notifications locales, recalculées à chaque changement de la base (jamais envoyées
/// ailleurs). Toucher un rappel ouvre la note.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Note à ouvrir après un toucher sur un rappel.
    var onOpen: ((UUID) -> Void)?

    override init() {
        super.init()
        center.delegate = self
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

    /// Remplace les rappels d'Engram en attente par ceux du plan.
    func apply(_ plan: [PlannedReminder], calendar: Calendar) async {
        await removeAll()
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "engram.reminders"
            content.userInfo = ["memoryID": reminder.memoryID.uuidString]
            let moment = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: moment, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
        }
    }

    func removeAll() async {
        let ours = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["memoryID"] as? String,
              let id = UUID(uuidString: text) else { return }
        await MainActor.run { self.onOpen?(id) }
    }
}
