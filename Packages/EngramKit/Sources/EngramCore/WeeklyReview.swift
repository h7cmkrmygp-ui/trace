import Foundation

/// P18 — « Ta semaine » : les chiffres d'une semaine du calendrier.
public struct WeeklyReview: Sendable, Equatable {
    /// Un dossier, une personne ou un lieu, et combien de notes de la semaine en parlent.
    public struct Count: Sendable, Equatable, Identifiable {
        public let name: String
        public let count: Int
        /// La personne ou le lieu (pour ouvrir sa page) ; nil pour un dossier.
        public let entityID: UUID?
        public var id: String { (entityID?.uuidString ?? "") + name }

        public init(name: String, count: Int, entityID: UUID? = nil) {
            self.name = name
            self.count = count
            self.entityID = entityID
        }
    }

    /// Une habitude et le nombre de jours où elle a été faite cette semaine.
    public struct HabitCount: Sendable, Equatable, Identifiable {
        public let habit: Habit
        public let days: Int
        public var id: Habit { habit }

        public init(habit: Habit, days: Int) {
            self.habit = habit
            self.days = days
        }
    }

    public let start: Date
    public let end: Date
    public let notes: Int
    public let notesLastWeek: Int
    /// Tâches et rendez-vous faits pendant la semaine (une tâche qui revient compte chaque fois).
    public let done: Int
    /// Ce qui reste à faire aujourd'hui.
    public let open: Int
    /// Notes de chaque jour, dans l'ordre du calendrier.
    public let perDay: [Int]
    public let categories: [Count]
    public let people: [Count]
    public let places: [Count]
    public let habits: [HabitCount]

    public init(start: Date, end: Date, notes: Int, notesLastWeek: Int, done: Int, open: Int, perDay: [Int],
                categories: [Count], people: [Count], places: [Count], habits: [HabitCount]) {
        self.start = start
        self.end = end
        self.notes = notes
        self.notesLastWeek = notesLastWeek
        self.done = done
        self.open = open
        self.perDay = perDay
        self.categories = categories
        self.people = people
        self.places = places
        self.habits = habits
    }
}

/// Les mots de « Ta semaine ».
public enum WeeklyReviewText {
    static let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre",
                         "novembre", "décembre"]

    /// « Semaine du 10 au 16 janvier », « Semaine du 28 février au 6 mars », l'année si elle change.
    public static func title(start: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let first = calendar.dateComponents([.year, .month, .day], from: start)
        let last = calendar.dateComponents([.year, .month, .day], from: end)
        func day(_ parts: DateComponents) -> String { parts.day == 1 ? "1er" : "\(parts.day ?? 1)" }
        func month(_ parts: DateComponents) -> String { months[max(0, min(11, (parts.month ?? 1) - 1))] }
        if first.year != last.year {
            return "Semaine du \(day(first)) \(month(first)) \(first.year ?? 0) au \(day(last)) \(month(last)) \(last.year ?? 0)"
        }
        if first.month != last.month {
            return "Semaine du \(day(first)) \(month(first)) au \(day(last)) \(month(last))"
        }
        return "Semaine du \(day(first)) au \(day(last)) \(month(last))"
    }

    /// « 3 notes de plus que la semaine d'avant » ; nil s'il n'y avait rien la semaine d'avant.
    public static func comparison(notes: Int, lastWeek: Int) -> String? {
        guard lastWeek > 0 else { return nil }
        let difference = notes - lastWeek
        if difference == 0 { return "Autant de notes que la semaine d'avant" }
        let count = abs(difference)
        return "\(count) note\(count > 1 ? "s" : "") de \(difference > 0 ? "plus" : "moins") que la semaine d'avant"
    }

    /// Le jour où il y a eu le plus de notes (« mercredi ») ; nil si la semaine est vide. À égalité, le premier.
    public static func busiestDay(perDay: [Int], start: Date, calendar: Calendar) -> String? {
        guard let most = perDay.max(), most > 0, let index = perDay.firstIndex(of: most),
              let day = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
        return Recurrence.dayName(calendar.component(.weekday, from: day))
    }
}

/// P28 — la période d'un bilan : une semaine ou un mois.
public enum ReviewPeriod: String, Sendable, CaseIterable {
    case week, month

    var component: Calendar.Component { self == .week ? .weekOfYear : .month }

    /// La semaine (ou le mois) du calendrier qui contient `date`.
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: component, for: date)
    }

    /// Le début de la période d'avant.
    public func previousStart(of start: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: component, value: -1, to: start)
    }
}

extension WeeklyReviewText {
    /// « Semaine du 10 au 16 janvier » ou « Janvier 2027 ».
    public static func title(start: Date, period: ReviewPeriod, calendar: Calendar) -> String {
        guard period == .month else { return title(start: start, calendar: calendar) }
        let parts = calendar.dateComponents([.year, .month], from: start)
        let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
        return month.prefix(1).uppercased() + month.dropFirst() + " \(parts.year ?? 0)"
    }

    /// « 10 notes de plus que le mois d'avant ».
    public static func comparison(notes: Int, lastWeek: Int, period: ReviewPeriod) -> String? {
        guard let text = comparison(notes: notes, lastWeek: lastWeek) else { return nil }
        return period == .week ? text : text.replacingOccurrences(of: "la semaine d'avant", with: "le mois d'avant")
    }

    /// « mercredi » pour une semaine, « le 14 janvier » pour un mois.
    public static func busiestDay(perDay: [Int], start: Date, period: ReviewPeriod, calendar: Calendar) -> String? {
        guard period == .month else { return busiestDay(perDay: perDay, start: start, calendar: calendar) }
        guard let most = perDay.max(), most > 0, let index = perDay.firstIndex(of: most),
              let day = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: day)
        let number = parts.day == 1 ? "1er" : "\(parts.day ?? 1)"
        return "le \(number) \(months[max(0, min(11, (parts.month ?? 1) - 1))])"
    }
}
