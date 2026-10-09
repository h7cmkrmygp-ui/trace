import EngramCore
import CoreLocation
import Foundation
import UserNotifications

/// Rappels sur l'iPhone : notifications locales, recalculées à chaque changement de la base (jamais envoyées
/// ailleurs). Un rappel se règle depuis la notification : « Fait », « Dans 1 h », « Demain ». Le résumé du matin
/// ouvre « À faire » ; celui de la semaine ouvre Retrouver.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    enum Kind: String {
        case reminder, digest, weekly
        /// « Te souviens-tu ? » (P13) : toucher ouvre la vieille idée.
        case resurface
        /// Rappel de lieu (P14) : en arrivant à un lieu, ou en le quittant.
        case place
        /// Une fête (P20) : la veille et le jour même ; toucher ouvre la page de la personne.
        case birthday
        /// « Garde ta série » (P21) : toucher ouvre les Suivis.
        case habit

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
    /// Toucher une fête : la page de la personne.
    var onOpenEntity: ((UUID) -> Void)?
    /// Toucher « Garde ta série » : les Suivis.
    var onOpenTrackers: (() -> Void)?

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
            UNNotificationCategory(identifier: Kind.resurface.category, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.place.category, actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.birthday.category, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Kind.habit.category, actions: [], intentIdentifiers: []),
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
        let prefixes = [ReminderPlanner.identifierPrefix, DigestPlanner.morningPrefix, DigestPlanner.weeklyIdentifier,
                        Resurfacing.identifier, BirthdayPlanner.identifierPrefix,
                        HabitNudgePlanner.identifier]
        let ours = await center.pendingNotificationRequests().map(\.identifier)
            .filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Rappels de lieu (P14) : c'est iOS qui surveille les adresses et présente la notification en arrivant (ou en
    /// partant), même Engram fermé ; l'autorisation « Lorsque l'app est active » suffit. Le rappel revient à chaque
    /// arrivée tant que la note n'est pas faite. Seuls les rappels qui changent sont remplacés.
    func applyPlaces(_ planned: [PlaceReminderPlanner.Planned]) async {
        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(PlaceReminderPlanner.identifierPrefix) }
        var kept: Set<String> = []
        for request in pending {
            if let wanted = planned.first(where: { $0.identifier == request.identifier }), Self.matches(request, wanted) {
                kept.insert(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !kept.contains($0) })
        // Une note faite (ou sans rappel) : sa notification déjà reçue disparaît aussi.
        let wanted = Set(planned.map(\.identifier))
        center.removeDeliveredNotifications(withIdentifiers: pending.map(\.identifier).filter { !wanted.contains($0) })
        for place in planned where !kept.contains(place.identifier) {
            let content = UNMutableNotificationContent()
            content.title = place.title
            content.body = place.body
            content.sound = .default
            content.categoryIdentifier = Kind.place.category
            content.threadIdentifier = "engram.places"
            content.userInfo = ["memoryID": place.memoryID.uuidString, "kind": Kind.place.rawValue]
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                                          radius: place.radius, identifier: place.identifier)
            region.notifyOnEntry = place.event == .arrive
            region.notifyOnExit = place.event == .leave
            let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: place.identifier, content: content, trigger: trigger))
        }
    }

    private static func matches(_ request: UNNotificationRequest, _ wanted: PlaceReminderPlanner.Planned) -> Bool {
        guard let trigger = request.trigger as? UNLocationNotificationTrigger,
              let region = trigger.region as? CLCircularRegion else { return false }
        return request.content.title == wanted.title && request.content.body == wanted.body
            && region.center.latitude == wanted.latitude && region.center.longitude == wanted.longitude
            && region.radius == wanted.radius && region.notifyOnEntry == (wanted.event == .arrive)
            && region.notifyOnExit == (wanted.event == .leave)
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
        case .resurface:
            if let memoryID, action != UNNotificationDismissActionIdentifier { onOpen?(memoryID) }
        case .birthday:
            if let memoryID, action != UNNotificationDismissActionIdentifier { onOpenEntity?(memoryID) }
        case .habit:
            if action != UNNotificationDismissActionIdentifier { onOpenTrackers?() }
        case .reminder, .place:
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
