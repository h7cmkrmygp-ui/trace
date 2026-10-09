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

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(metrics) { metric in
                    NavigationLink(value: NotesRoute.metric(metric)) {
                        TrackerCard(metric: metric, points: points[metric] ?? [], unit: metric.unit(weightUnit: weightUnit))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            Text("Dis une mesure dans une note (« je pèse 162 livres », « j'ai dormi 7 h 30 », « tension 120 sur 80 ») : elle s'ajoute ici toute seule, sans rien envoyer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .overlay {
            if metrics.isEmpty {
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
                    for metric in list {
                        loaded[metric] = (try? model.measurements.points(metric: metric, weightUnit: weightUnit)) ?? []
                    }
                    points = loaded
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}

/// Une carte de suivi.
struct TrackerCard: View {
    let metric: Metric
    let points: [MetricPoint]
    let unit: String

    private var summary: MetricSummary? { MetricStats.summary(of: points) }

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
                Text(metric.changeText(summary.change30, unit: unit) ?? summary.latestDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
    }

    @ViewBuilder private var chart: some View {
        Chart {
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
