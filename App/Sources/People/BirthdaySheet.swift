import EngramCore
import EngramStore
import SwiftUI

/// P20 — poser ou changer la fête d'une personne : le jour, le mois, et l'année si on la connaît.
struct BirthdaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entityID: UUID
    let name: String
    let current: PersonBirthday?

    @State private var month = 1
    @State private var day = 1
    @State private var knowsYear = false
    @State private var year = 1990

    static let longest = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    static let monthNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        return formatter.monthSymbols
    }()

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mois", selection: $month) {
                        ForEach(1...12, id: \.self) { Text(Self.monthNames[$0 - 1]).tag($0) }
                    }
                    Picker("Jour", selection: $day) {
                        ForEach(1...Self.longest[month - 1], id: \.self) { Text($0 == 1 ? "1er" : "\($0)").tag($0) }
                    }
                } footer: {
                    Text("Engram te le rappelle la veille à 19 h et le jour même à 9 h.")
                }
                Section {
                    Toggle("Je connais l'année", isOn: $knowsYear)
                    if knowsYear {
                        Picker("Année", selection: $year) {
                            ForEach((1900...thisYear).reversed(), id: \.self) { Text(String($0)).tag($0) }
                        }
                        .pickerStyle(.wheel)
                    }
                } footer: {
                    if knowsYear { Text("Engram dira son âge.") }
                }
            }
            .navigationTitle("Fête de \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        model.perform {
                            try model.entities.setBirthday(entityID, month: month, day: day, year: knowsYear ? year : nil)
                        }
                        dismiss()
                    }
                }
            }
            .onChange(of: month) { _, value in day = min(day, Self.longest[value - 1]) }
            .onAppear {
                guard let current else { return }
                month = current.month
                day = current.day
                if let known = current.year {
                    knowsYear = true
                    year = known
                }
            }
        }
    }
}
