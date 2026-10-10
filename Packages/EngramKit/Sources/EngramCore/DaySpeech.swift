import Foundation

/// P27 — « Ma journée » dite par Siri : ce qui est prévu aujourd'hui (les heures d'abord), ce qui est en retard, les
/// fêtes et les séries à garder. Une note privée s'appelle « une note privée ».
public enum DaySpeech {
    public static let maximumNamed = 4

    public static func summary(_ items: [ReminderPlanner.Item], birthdays: [String], streaks: [String], now: Date,
                               calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let open = items.filter { DigestPlanner.isOpen($0) }
        let today = open.enumerated()
            .filter { ($0.element.dueAt ?? .distantPast) >= start && ($0.element.dueAt ?? .distantFuture) < end }
            .sorted { first, second in
                let a = first.element.dueHasTime
                let b = second.element.dueHasTime
                if a != b { return a }
                if a, let x = first.element.dueAt, let y = second.element.dueAt, x != y { return x < y }
                return first.offset < second.offset
            }
            .map { $0.element }
        let late = open.filter { $0.kind == .task && ($0.dueAt ?? .distantFuture) < start }

        var sentences: [String] = []
        let named = today.map { item -> String in
            let title = item.isPrivate ? "une note privée" : ListSpeech.lowerFirst(item.title)
            guard item.dueHasTime, let due = item.dueAt else { return title }
            return "\(title) à \(ReminderPlanner.clock(due, calendar: calendar))"
        }
        if named.count > maximumNamed {
            let rest = named.count - maximumNamed
            sentences.append("Aujourd'hui, \(named.count) choses : " + named.prefix(maximumNamed).joined(separator: ", ")
                             + " et \(rest) autre\(rest > 1 ? "s" : "").")
        } else if !named.isEmpty {
            sentences.append("Aujourd'hui : \(joined(named)).")
        }
        if late.count == 1 {
            let title = late[0].isPrivate ? "une note privée" : ListSpeech.lowerFirst(late[0].title)
            sentences.append("1 chose en retard : \(title).")
        } else if late.count > 1 {
            sentences.append("\(late.count) choses en retard.")
        }
        if sentences.isEmpty { sentences.append("Rien de prévu aujourd'hui.") }
        if !birthdays.isEmpty {
            sentences.append("C'est la fête de " + joined(birthdays.map(BirthdayPlanner.inSentence), linker: " et de ") + ".")
        }
        if !streaks.isEmpty {
            sentences.append("Garde ta série : \(joined(streaks.map(ListSpeech.lowerFirst))).")
        }
        return sentences.joined(separator: " ")
    }

    /// « a », « a et b », « a, b et c ».
    static func joined(_ parts: [String], linker: String = " et ") -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + linker + parts[parts.count - 1]
    }
}
