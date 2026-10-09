import EngramCore
import EngramStore
import SwiftUI

// P17 — les habitudes : « j'ai médité 10 minutes », « j'ai fait mon workout »… relevées dans les notes, sur l'iPhone.

extension Habit {
    var title: String {
        switch self {
        case .meditation: "Méditation"
        case .exercise: "Sport"
        case .running: "Course"
        case .walking: "Marche"
        case .reading: "Lecture"
        case .water: "Eau"
        case .vitamins: "Vitamines"
        }
    }

    var symbol: String {
        switch self {
        case .meditation: "brain.head.profile"
        case .exercise: "figure.strengthtraining.traditional"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .reading: "book.fill"
        case .water: "drop.fill"
        case .vitamins: "pills.fill"
        }
    }

    var tint: Color {
        switch self {
        case .meditation: .mint
        case .exercise: .orange
        case .running: .pink
        case .walking: .green
        case .reading: .brown
        case .water: .cyan
        case .vitamins: .purple
        }
    }

    /// « 5 jours d'affilée », « Fait hier », « Fait le 3 janvier ».
    static func streakText(_ summary: HabitSummary) -> String {
        if summary.streak >= 2 { return "\(summary.streak) jours d'affilée" }
        guard let last = summary.lastDoneAt else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(last) { return "Fait aujourd'hui" }
        if calendar.isDateInYesterday(last) { return "Fait hier" }
        return "Fait le \(last.formatted(.dateTime.day().month(.wide)))"
    }

    /// « 10 min », « 5,5 km », « 2 L ».
    static func quantityText(_ entry: HabitEntry) -> String? {
        guard let quantity = entry.quantity, let unit = entry.unit else { return nil }
        return "\(MetricUnits.decimal(quantity)) \(unit)"
    }
}

/// Une carte d'habitude : la série en cours et les 7 derniers jours.
struct HabitCard: View {
    let summary: HabitSummary
    /// Objectif par semaine (P21).
    var goal: Int?

    private var lastWeek: [Bool] {
        let calendar = Calendar.current
        let done = Set(summary.days.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { done.contains($0) } ?? false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary.habit.title, systemImage: summary.habit.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summary.habit.tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if summary.streak >= 2 {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                }
                Text(Habit.streakText(summary))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 4) {
                ForEach(Array(lastWeek.enumerated()), id: \.offset) { _, done in
                    Circle()
                        .fill(done ? summary.habit.tint : Color(.tertiarySystemFill))
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityHidden(true)
            if let goal {
                ProgressView(value: Double(min(summary.thisWeek, goal)), total: Double(goal))
                    .tint(summary.habit.tint)
                Text(summary.thisWeek >= goal ? "Objectif de la semaine atteint" : "\(summary.thisWeek)/\(goal) cette semaine")
                    .font(.caption)
                    .foregroundStyle(summary.thisWeek >= goal ? Color.green : Color.secondary)
            } else {
                Text(summary.thisWeek == 1 ? "1 fois cette semaine" : "\(summary.thisWeek) fois cette semaine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Une habitude : la série, la meilleure série, une grille des 16 dernières semaines, et chaque fois (toucher ouvre
/// la note).
struct HabitDetailView: View {
    @Environment(AppModel.self) private var model
    let habit: Habit
    @State private var summary: HabitSummary?
    @State private var entries: [HabitEntry] = []
    /// P21 : l'objectif par semaine.
    @State private var goal: Int?

    static let weeks = 16

    var body: some View {
        List {
            if let summary {
                Section {
                    HStack(spacing: 0) {
                        stat("\(summary.streak)", "série")
                        stat("\(summary.bestStreak)", "meilleure")
                        stat("\(summary.thisWeek)", "cette semaine")
                        stat("\(summary.total)", "jours en tout")
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    if let goal {
                        Stepper(goal == 7 ? "Tous les jours" : "\(goal) fois par semaine", value: Binding(
                            get: { goal },
                            set: { value in model.perform { try model.measurements.setHabitGoal(habit, perWeek: value) } }
                        ), in: 1...7)
                        Button("Retirer l'objectif", systemImage: "trash", role: .destructive) {
                            model.perform { try model.measurements.removeHabitGoal(habit) }
                        }
                    } else {
                        Button("Fixer un objectif", systemImage: "target") {
                            model.perform { try model.measurements.setHabitGoal(habit, perWeek: 3) }
                        }
                    }
                } header: {
                    Text("Objectif")
                } footer: {
                    Text(goal == nil ? "Ou dis-le : « mon objectif : méditer 5 fois par semaine »."
                         : "\(summary.thisWeek) cette semaine. À 20 h, « Garde ta série » te rappelle une série pas encore faite.")
                }
                Section {
                    HabitGrid(days: summary.days, tint: habit.tint, weeks: Self.weeks)
                        .padding(.vertical, 6)
                } header: {
                    Text("Les \(Self.weeks) dernières semaines")
                }
            }
            Section("Chaque fois") {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.memoryID) {
                        LabeledContent {
                            if let quantity = Habit.quantityText(entry) { Text(quantity) }
                        } label: {
                            Text(entry.doneAt.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(habit.title)
        .task {
            do {
                for try await goals in model.measurements.habitGoalsStream() { goal = goals[habit] }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
        .task {
            do {
                for try await list in model.measurements.habitEntriesStream(for: habit) {
                    entries = list
                    summary = (try? model.measurements.habitSummaries(today: Date()))?.first { $0.habit == habit }
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(habit.tint)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Une case par jour, une colonne par semaine (la plus récente à droite), comme un calendrier de constance.
struct HabitGrid: View {
    let days: [Date]
    let tint: Color
    let weeks: Int

    var body: some View {
        let calendar = Calendar.current
        let grid = HabitStats.grid(days, today: Date(), weeks: weeks, calendar: calendar)
        let letters = Self.weekdayLetters(calendar)
        HStack(alignment: .top, spacing: 3) {
            VStack(spacing: 3) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 14)
                }
            }
            ForEach(Array(grid.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 3) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, cell in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(cell == true ? tint : (cell == nil ? Color.clear : Color(.tertiarySystemFill)))
                            .frame(height: 14)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("\(Set(days.map { calendar.startOfDay(for: $0) }).count) jours sur les \(weeks) dernières semaines")
    }

    /// « D L M M J V S » dans l'ordre du calendrier.
    static func weekdayLetters(_ calendar: Calendar) -> [String] {
        let symbols = ["D", "L", "M", "M", "J", "V", "S"]
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
