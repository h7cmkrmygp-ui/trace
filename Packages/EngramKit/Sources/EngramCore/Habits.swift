import Foundation

/// P17 — une habitude qu'on dit avoir faite (« j'ai médité », « j'ai fait mon workout »).
public enum Habit: String, Codable, Sendable, CaseIterable {
    case meditation, exercise, running, walking, reading, water, vitamins
}

/// Une habitude dite dans une note, avec sa quantité si elle est dite (« 10 minutes », « 5 km »).
public struct ParsedHabit: Sendable, Equatable {
    public let habit: Habit
    public let quantity: Double?
    /// « min », « km », « pages », « L », « verres ».
    public let unit: String?
    /// « hier » : 1 ; « avant-hier » : 2.
    public let daysBefore: Int

    public init(habit: Habit, quantity: Double? = nil, unit: String? = nil, daysBefore: Int = 0) {
        self.habit = habit
        self.quantity = quantity
        self.unit = unit
        self.daysBefore = daysBefore
    }
}

/// Reconnaît, sur l'iPhone et sans IA, les habitudes faites. Un projet (« il faut que je médite »), un refus
/// (« j'ai pas médité ») ou un faux ami (« je suis allé au marché ») n'en sont pas.
public enum HabitParser {
    public static func parse(_ text: String) -> [ParsedHabit] { [] }
}

/// Séries, semaine et grille d'une habitude, à partir des jours où elle a été faite.
public enum HabitStats {
    /// Jours d'affilée jusqu'à aujourd'hui ; une série encore vivante si hier compte et aujourd'hui pas encore.
    public static func streak(_ days: [Date], today: Date, calendar: Calendar) -> Int { 0 }

    public static func bestStreak(_ days: [Date], calendar: Calendar) -> Int { 0 }

    /// Jours faits cette semaine (la semaine du calendrier).
    public static func thisWeek(_ days: [Date], today: Date, calendar: Calendar) -> Int { 0 }

    /// Les `weeks` dernières semaines, une colonne par semaine (la plus ancienne d'abord), un jour par case dans l'ordre
    /// du calendrier ; nil pour les jours à venir.
    public static func grid(_ days: [Date], today: Date, weeks: Int, calendar: Calendar) -> [[Bool?]] { [] }
}
