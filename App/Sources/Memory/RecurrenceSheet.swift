import EngramCore
import EngramStore
import SwiftUI

/// P16 — répéter une tâche : chaque jour, certains jours de la semaine, aux deux semaines, chaque mois, chaque année.
struct RecurrenceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    let current: RecurrenceRule?

    enum Choice: String, CaseIterable, Identifiable {
        case never, daily, weekly, biweekly, monthly, yearly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .never: "Jamais"
            case .daily: "Chaque jour"
            case .weekly: "Chaque semaine"
            case .biweekly: "Aux deux semaines"
            case .monthly: "Chaque mois"
            case .yearly: "Chaque année"
            }
        }
    }

    /// Du lundi au dimanche (1 = dimanche, comme `Calendar`).
    static let week = [2, 3, 4, 5, 6, 7, 1]

    @State private var choice: Choice = .never
    @State private var weekdays: Set<Int> = []
    @State private var usesDayOfMonth = false
    @State private var dayOfMonth = 1

    private var rule: RecurrenceRule? {
        let hour = current?.hour
        let minute = current?.minute
        let days = Self.week.filter { weekdays.contains($0) }
        switch choice {
        case .never: return nil
        case .daily: return RecurrenceRule(frequency: .daily, hour: hour, minute: minute)
        case .weekly: return RecurrenceRule(frequency: .weekly, weekdays: days, hour: hour, minute: minute)
        case .biweekly: return RecurrenceRule(frequency: .weekly, interval: 2, weekdays: days, hour: hour, minute: minute)
        case .monthly:
            return RecurrenceRule(frequency: .monthly, dayOfMonth: usesDayOfMonth ? dayOfMonth : nil, hour: hour, minute: minute)
        case .yearly: return RecurrenceRule(frequency: .yearly, hour: hour, minute: minute)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Répéter", selection: $choice) {
                        ForEach(Choice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if choice == .weekly || choice == .biweekly {
                    Section {
                        ForEach(Self.week, id: \.self) { day in
                            Button {
                                if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                HStack {
                                    Text(Recurrence.dayName(day).capitalized).foregroundStyle(.primary)
                                    Spacer()
                                    if weekdays.contains(day) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityAddTraits(weekdays.contains(day) ? .isSelected : [])
                        }
                    } header: {
                        Text("Les jours")
                    } footer: {
                        Text("Aucun jour choisi : le même jour que la prochaine fois prévue.")
                    }
                }
                if choice == .monthly {
                    Section {
                        Toggle("Un jour précis du mois", isOn: $usesDayOfMonth)
                        if usesDayOfMonth {
                            Stepper(dayOfMonth == 1 ? "Le 1er" : "Le \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                        }
                    } footer: {
                        Text("Un mois plus court (le 31 en février) : le dernier jour du mois.")
                    }
                }
                if let rule {
                    Section {
                        Label(Recurrence.describe(rule), systemImage: "repeat")
                    } footer: {
                        Text("« Fait » passe la tâche à la prochaine fois, et ses rappels suivent.")
                    }
                }
            }
            .navigationTitle("Répétition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        model.perform { try model.memories.setRecurrence(rule, for: memoryID) }
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let current else { return }
        weekdays = Set(current.weekdays)
        switch current.frequency {
        case .daily: choice = .daily
        case .weekly: choice = current.interval >= 2 ? .biweekly : .weekly
        case .monthly:
            choice = .monthly
            usesDayOfMonth = current.dayOfMonth != nil
            dayOfMonth = current.dayOfMonth ?? 1
        case .yearly: choice = .yearly
        }
    }
}
