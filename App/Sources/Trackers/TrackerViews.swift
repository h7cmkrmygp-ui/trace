import Charts
import EngramCore
import EngramStore
import SwiftUI

/// Apparence de chaque suivi : nom, symbole et couleur (comme dans l'app Santé).
extension Metric {
    var title: String {
        switch self {
        case .weight: "Poids"
        case .sleep: "Sommeil"
        case .bloodPressure: "Tension"
        case .heartRate: "Pouls"
        case .steps: "Pas"
        case .glucose: "Glycémie"
        }
    }

    var symbol: String {
        switch self {
        case .weight: "scalemass.fill"
        case .sleep: "bed.double.fill"
        case .bloodPressure: "waveform.path.ecg"
        case .heartRate: "heart.fill"
        case .steps: "figure.walk"
        case .glucose: "drop.fill"
        }
    }

    var tint: Color {
        switch self {
        case .weight: .purple
        case .sleep: .teal
        case .bloodPressure: .red
        case .heartRate: .pink
        case .steps: .orange
        case .glucose: .blue
        }
    }

    /// « −2,5 lb en 30 jours », « stable depuis 30 jours ».
    func changeText(_ change: Double?, unit: String) -> String? {
        guard let change else { return nil }
        let rounded = (change * 10).rounded() / 10
        if rounded == 0 { return "stable depuis 30 jours" }
        let sign = rounded > 0 ? "+" : "−"
        let amount: String
        switch self {
        case .sleep: amount = MetricUnits.decimal(abs(rounded)) + " h"
        case .steps: amount = MetricUnits.format(abs(rounded), second: nil, metric: .steps, unit: unit)
        case .heartRate: amount = "\(Int(abs(rounded).rounded())) bpm"
        case .bloodPressure: amount = "\(Int(abs(rounded).rounded()))"
        case .weight, .glucose: amount = MetricUnits.decimal(abs(rounded)) + " " + unit
        }
        return "\(sign)\(amount) en 30 jours"
    }

    /// La valeur d'un objectif dans l'unité affichée (un objectif de poids en kilos s'affiche en livres au besoin).
    func goalValue(_ goal: TrackerGoal, weightUnit: String) -> Double {
        guard self == .weight, goal.unit != weightUnit else { return goal.target }
        return weightUnit == "kg" ? MetricUnits.kilograms(fromPounds: goal.target) : MetricUnits.pounds(fromKilograms: goal.target)
    }

    /// Unité affichée : le poids dans l'unité choisie, le reste tel quel.
    func unit(weightUnit: String) -> String {
        switch self {
        case .weight: weightUnit
        case .sleep: "h"
        case .bloodPressure: "mmHg"
        case .heartRate: "bpm"
        case .steps: "pas"
        case .glucose: "mmol/L"
        }
    }
}

/// « Suivis » : une carte par suivi, avec sa dernière valeur, une petite courbe et l'évolution sur 30 jours.
struct TrackersView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("engram.weightUnit") private var weightUnit = "lb"
    @State private var metrics: [Metric] = []
    @State private var points: [Metric: [MetricPoint]] = [:]
    @State private var goals: [Metric: TrackerGoal] = [:]
    /// P17 : les habitudes.
    @State private var habits: [HabitSummary] = []
    /// P21 : les objectifs par semaine.
    @State private var habitGoals: [Habit: Int] = [:]

    var body: some View {
        ScrollView {
            if !metrics.isEmpty && !habits.isEmpty { sectionTitle("Mesures") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(metrics) { metric in
                    NavigationLink(value: NotesRoute.metric(metric)) {
                        TrackerCard(metric: metric, points: points[metric] ?? [], unit: metric.unit(weightUnit: weightUnit),
                                    goal: goals[metric].map { metric.goalValue($0, weightUnit: weightUnit) })
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            if !habits.isEmpty {
                sectionTitle("Habitudes")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(habits) { summary in
                        NavigationLink(value: NotesRoute.habit(summary.habit)) {
                            HabitCard(summary: summary, goal: habitGoals[summary.habit])
                        }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            Text("Dis une mesure ou une habitude dans une note (« je pèse 162 livres », « j'ai dormi 7 h 30 », « j'ai médité 10 minutes », « j'ai fait mon workout ») : elle s'ajoute ici toute seule, sans rien envoyer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .task {
            do {
                for try await list in model.measurements.habitSummariesStream(today: Date()) { habits = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
        .task {
            do {
                for try await goals in model.measurements.habitGoalsStream() { habitGoals = goals }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
        .overlay {
            if metrics.isEmpty && habits.isEmpty {
                ContentUnavailableView("Aucun suivi pour l'instant", systemImage: "chart.xyaxis.line",
                                       description: Text("Dis « je pèse 162 livres » ou « j'ai dormi 7 h » dans une note."))
            }
        }
        .navigationTitle("Suivis")
        .task(id: weightUnit) {
            do {
                for try await list in model.measurements.metricsStream() {
                    metrics = list
                    var loaded: [Metric: [MetricPoint]] = [:]
                    var loadedGoals: [Metric: TrackerGoal] = [:]
                    for metric in list {
                        loaded[metric] = (try? model.measurements.points(metric: metric, weightUnit: weightUnit)) ?? []
                        if let goal = try? model.measurements.goal(metric: metric) { loadedGoals[metric] = goal }
                    }
                    points = loaded
                    goals = loadedGoals
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}

extension TrackersView {
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Une carte de suivi.
struct TrackerCard: View {
    let metric: Metric
    let points: [MetricPoint]
    let unit: String
    /// Objectif dans l'unité affichée (P11).
    var goal: Double?

    private var summary: MetricSummary? { MetricStats.summary(of: points) }

    /// « Objectif 155 lb · encore 9,8 lb », « Objectif atteint ».
    private var goalText: String? {
        guard let goal, let summary, let first = points.first else { return nil }
        let status = GoalProgress.evaluate(start: first.value, current: summary.latest, target: goal)
        if status.reached { return "Objectif atteint" }
        let format = { (value: Double) in MetricUnits.format(value, second: nil, metric: metric, unit: unit) }
        return "Objectif \(format(goal)) · encore \(format(status.remaining))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.tint)
            if let summary {
                Text(MetricUnits.format(summary.latest, second: summary.latestSecond, metric: metric, unit: unit))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Chart(points.suffix(30), id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(metric.tint)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 44)
                .accessibilityHidden(true)
                Text(goalText ?? metric.changeText(summary.change30, unit: unit)
                     ?? summary.latestDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(goalText == "Objectif atteint" ? Color.green : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Un suivi : son graphique (mois, 3 mois, année, tout), le minimum, le maximum et la moyenne, puis chaque mesure.
struct MetricDetailView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("engram.weightUnit") private var weightUnit = "lb"
    let metric: Metric
    @State private var points: [MetricPoint] = []
    @State private var entries: [MeasurementStore.Entry] = []
    @State private var range: ChartRange = .threeMonths
    /// Objectif du suivi (P11).
    @State private var goal: TrackerGoal?
    @State private var isSettingGoal = false
    @State private var goalText = ""

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "Mois", threeMonths = "3 mois", year = "Année", all = "Tout"
        var id: String { rawValue }
        var days: Double? {
            switch self {
            case .month: 30
            case .threeMonths: 91
            case .year: 365
            case .all: nil
            }
        }
    }

    private var unit: String { metric.unit(weightUnit: weightUnit) }

    private var shown: [MetricPoint] {
        guard let days = range.days, let last = points.last?.date else { return points }
        let start = last.addingTimeInterval(-days * 86_400)
        return points.filter { $0.date >= start }
    }

    var body: some View {
        List {
            Section {
                if let summary = MetricStats.summary(of: shown) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MetricUnits.format(summary.latest, second: summary.latestSecond, metric: metric, unit: unit))
                            .font(.largeTitle.weight(.bold))
                        Text(metric.changeText(MetricStats.summary(of: points)?.change30, unit: unit)
                             ?? "Dernière mesure \(summary.latestDate.formatted(.relative(presentation: .named)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                    Picker("Période", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    chart
                        .frame(height: 220)
                        .listRowSeparator(.hidden)
                    HStack {
                        stat("Minimum", summary.minimum)
                        Spacer()
                        stat("Moyenne", summary.average)
                        Spacer()
                        stat("Maximum", summary.maximum)
                    }
                }
            }
            if metric != .bloodPressure { goalSection }
            Section("Mesures") {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.memoryID) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MetricUnits.format(entry.value, second: entry.secondValue, metric: metric, unit: entry.unit))
                                    .font(.body.weight(.semibold))
                                Text(entry.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(entry.date, format: .dateTime.day().month(.abbreviated))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(metric.title)
        .toolbar {
            if metric == .weight {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Unité", selection: $weightUnit) {
                        Text("Livres").tag("lb")
                        Text("Kilos").tag("kg")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .task(id: weightUnit) {
            do {
                for try await list in model.measurements.pointsStream(metric: metric, weightUnit: weightUnit) {
                    points = list
                    entries = (try? model.measurements.entries(metric: metric, weightUnit: weightUnit)) ?? []
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
        .task {
            do {
                for try await value in model.measurements.goalStream(metric: metric) { goal = value }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
        .alert("Objectif", isPresented: $isSettingGoal) {
            TextField(unit, text: $goalText)
                .keyboardType(.decimalPad)
            Button("Annuler", role: .cancel) {}
            Button("OK") { saveGoal() }
        } message: {
            Text("La valeur à atteindre, en \(unit). Tu peux aussi le dire dans une note : « mon objectif : 155 livres ».")
        }
    }

    /// L'objectif dans l'unité affichée.
    private var goalTarget: Double? { goal.map { metric.goalValue($0, weightUnit: weightUnit) } }

    /// « Objectif » : la valeur à atteindre, la progression depuis le moment où il a été fixé, et ce qu'il reste.
    @ViewBuilder private var goalSection: some View {
        Section("Objectif") {
            if let goal, let target = goalTarget, let last = points.last {
                // Départ : la dernière mesure avant que l'objectif soit fixé (sinon la première).
                let start = points.last { $0.date <= goal.setAt }?.value ?? points.first?.value ?? last.value
                let status = GoalProgress.evaluate(start: start, current: last.value, target: target)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Objectif \(MetricUnits.format(target, second: nil, metric: metric, unit: unit))")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(status.reached ? "Atteint" : "Encore \(MetricUnits.format(status.remaining, second: nil, metric: metric, unit: unit))")
                            .font(.subheadline)
                            .foregroundStyle(status.reached ? Color.green : Color.secondary)
                    }
                    ProgressView(value: status.fraction)
                        .tint(status.reached ? .green : metric.tint)
                        .accessibilityLabel("Progression : \(Int((status.fraction * 100).rounded())) %")
                }
                .padding(.vertical, 4)
            }
            Button(goal == nil ? "Fixer un objectif" : "Changer l'objectif", systemImage: "target") {
                goalText = goalTarget.map { MetricUnits.decimal($0) } ?? ""
                isSettingGoal = true
            }
            if goal != nil {
                Button("Retirer l'objectif", systemImage: "xmark.circle", role: .destructive) {
                    model.perform { try model.measurements.removeGoal(metric: metric) }
                }
            }
        }
    }

    private func saveGoal() {
        guard let value = Double(goalText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
              value > 0 else { return }
        model.perform { try model.measurements.setGoal(metric: metric, target: value, unit: unit) }
    }

    @ViewBuilder private var chart: some View {
        Chart {
            if let target = goalTarget {
                RuleMark(y: .value("Objectif", target))
                    .foregroundStyle(metric.tint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Objectif").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value),
                         series: .value("Mesure", metric == .bloodPressure ? "Haute" : metric.title))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metric.tint)
                PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                    .foregroundStyle(metric.tint)
                    .symbolSize(24)
                if metric == .bloodPressure, let low = point.secondValue {
                    LineMark(x: .value("Date", point.date), y: .value("Basse", low), series: .value("Mesure", "Basse"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(metric.tint.opacity(0.5))
                    PointMark(x: .value("Date", point.date), y: .value("Basse", low))
                        .foregroundStyle(metric.tint.opacity(0.5))
                        .symbolSize(24)
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Graphique \(metric.title.lowercased()), \(NotesView.count(shown.count, "mesure", nil))")
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MetricUnits.format(value, second: nil, metric: metric == .bloodPressure ? .heartRate : metric, unit: unit)
                .replacingOccurrences(of: " bpm", with: metric == .bloodPressure ? "" : " bpm"))
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
