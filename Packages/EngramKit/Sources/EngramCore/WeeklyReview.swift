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
    /// « Semaine du 10 au 16 janvier », « Semaine du 28 février au 6 mars », l'année si elle change.
    public static func title(start: Date, calendar: Calendar) -> String { "" }

    /// « 3 notes de plus que la semaine d'avant » ; nil s'il n'y avait rien la semaine d'avant.
    public static func comparison(notes: Int, lastWeek: Int) -> String? { nil }

    /// Le jour où il y a eu le plus de notes (« mercredi ») ; nil si la semaine est vide.
    public static func busiestDay(perDay: [Int], start: Date, calendar: Calendar) -> String? { nil }
}
