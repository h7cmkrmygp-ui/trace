import Charts
import EngramCore
import EngramStore
import SwiftUI

/// P18 — « Ta semaine » : les notes, ce qui a été fait, le jour le plus actif, les dossiers, les personnes, les
/// habitudes et les suivis. Tout est lu sur l'iPhone ; on remonte les semaines avec les flèches.
struct WeeklyReviewView: View {
    @Environment(AppModel.self) private var model
    /// 0 : cette semaine (ou ce mois) ; -1 : celle d'avant…
    @State private var offset = 0
    /// P28 : la semaine ou le mois.
    @State private var period: ReviewPeriod = .week
    @State private var review: WeeklyReview?
    @State private var highlights: [String] = []

    private var calendar: Calendar { AppModel.recallCalendar }

    var body: some View {
        List {
            Section {
                Picker("Période", selection: $period) {
                    Text("Semaine").tag(ReviewPeriod.week)
                    Text("Mois").tag(ReviewPeriod.month)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let review {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(WeeklyReviewText.title(start: review.start, period: period, calendar: calendar))
                            .font(.title3.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: 0) {
                            stat(review.notes, review.notes == 1 ? "note" : "notes", .indigo)
                            stat(review.done, review.done == 1 ? "faite" : "faites", .green)
                            stat(review.open, "à faire", .orange)
                        }
                        if let comparison = WeeklyReviewText.comparison(notes: review.notes, lastWeek: review.notesLastWeek,
                                                                        period: period) {
                            Label(comparison, systemImage: review.notes >= review.notesLastWeek ? "arrow.up.right" : "arrow.down.right")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                if review.notes > 0 {
                    Section {
                        Chart(Array(review.perDay.enumerated()), id: \.offset) { index, count in
                            BarMark(x: .value("Jour", period == .week ? dayLetter(index, start: review.start) : "\(index + 1)"),
                                    y: .value("Notes", count))
                                .foregroundStyle(Color.indigo.gradient)
                                .cornerRadius(4)
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 120)
                        .accessibilityLabel("Notes par jour")
                    } header: {
                        Text("Chaque jour")
                    } footer: {
                        if let busiest = WeeklyReviewText.busiestDay(perDay: review.perDay, start: review.start, period: period,
                                                                     calendar: calendar) {
                            Text("Ton jour le plus actif : \(busiest).")
                        }
                    }
                }
                if !review.categories.isEmpty {
                    Section("Dossiers") {
                        ForEach(review.categories) { item in
                            HStack {
                                Label(item.name, systemImage: "folder.fill")
                                    .foregroundStyle(Color.category(item.name))
                                Spacer()
                                Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                if !review.people.isEmpty || !review.places.isEmpty {
                    Section("Avec") {
                        ForEach(review.people + review.places) { item in
                            if let id = item.entityID {
                                NavigationLink(value: NotesRoute.entity(id)) {
                                    LabeledContent(item.name, value: item.count == 1 ? "1 note" : "\(item.count) notes")
                                }
                            }
                        }
                    }
                }
                if !review.habits.isEmpty {
                    Section("Habitudes") {
                        ForEach(review.habits) { item in
                            NavigationLink(value: NotesRoute.habit(item.habit)) {
                                HStack {
                                    Label(item.habit.title, systemImage: item.habit.symbol)
                                        .foregroundStyle(item.habit.tint)
                                    Spacer()
                                    Text("\(item.days)/7 jours").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                if !highlights.isEmpty {
                    Section("Suivis") {
                        ForEach(highlights, id: \.self) { Label($0, systemImage: "chart.xyaxis.line") }
                    }
                }
                if review.notes == 0 {
                    Section {
                        ContentUnavailableView(period == .week ? "Rien noté cette semaine" : "Rien noté ce mois-ci",
                                               systemImage: "calendar",
                                               description: Text("Parle à Engram : ta page se remplira toute seule."))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(period == .week ? "Ta semaine" : "Ton mois")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(period == .week ? "Semaine d'avant" : "Mois d'avant", systemImage: "chevron.left") { offset -= 1 }
                Button(period == .week ? "Semaine d'après" : "Mois d'après", systemImage: "chevron.right") { offset += 1 }
                    .disabled(offset >= 0)
            }
        }
        // Changer de période revient à la semaine (ou au mois) en cours.
        .onChange(of: period) { _, _ in offset = 0 }
        .task(id: "\(period.rawValue)\(offset)") { load() }
    }

    private func load() {
        let day = calendar.date(byAdding: period == .week ? .weekOfYear : .month, value: offset, to: Date()) ?? Date()
        model.perform {
            let loaded = try model.memories.review(period, containing: day)
            review = loaded
            highlights = model.weekDetails(from: loaded.start, to: loaded.end).highlights
        }
    }

    private func stat(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.largeTitle.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// « D », « L », « M »… pour la colonne `index` de la semaine (un caractère invisible garde les deux « M » distincts).
    private func dayLetter(_ index: Int, start: Date) -> String {
        let weekday = calendar.date(byAdding: .day, value: index, to: start).map { calendar.component(.weekday, from: $0) } ?? 1
        let letters = [1: "D", 2: "L", 3: "M", 4: "M\u{200B}", 5: "J", 6: "V", 7: "S"]
        return letters[weekday] ?? ""
    }
}
