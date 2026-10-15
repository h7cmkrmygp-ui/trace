import EngramCore
import EngramStore
import SwiftUI

/// P24 — « Ce jour-là » : ce que tu notais le même jour, il y a un mois, six mois, un an… (jamais une note privée).
struct OnThisDayView: View {
    @Environment(AppModel.self) private var model
    @State private var groups: [OnThisDay.Group] = []

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.label) {
                    ForEach(group.notes) { note in
                        NavigationLink(value: note.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).foregroundStyle(.primary)
                                Text(note.capturedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ce jour-là")
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Rien ce jour-là", systemImage: "clock.arrow.circlepath",
                                       description: Text("Les notes prises le même jour, il y a un mois ou un an, reviendront ici."))
            }
        }
        .onAppear { groups = model.onThisDay() }
    }
}
