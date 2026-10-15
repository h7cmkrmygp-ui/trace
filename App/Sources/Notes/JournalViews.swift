import EngramCore
import EngramStore
import SwiftUI

/// Le journal : toutes tes notes, jour par jour (« Aujourd'hui », « Hier », « Mercredi 13 janvier »…).
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var memories: [Memory] = []

    var body: some View {
        let groups = DayGrouping.groups(memories, date: \.capturedAt, now: Date(), calendar: .current)
        List {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.items) { memory in
                        NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(NotesView.count(group.items.count, "note", nil)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if memories.isEmpty {
                ContentUnavailableView("Ton journal est vide", systemImage: "book.closed",
                                       description: Text("Chaque pensée que tu dis ou écris s'y range, jour après jour."))
            }
        }
        .navigationTitle("Journal")
        .task {
            do {
                for try await list in model.memories.memoriesStream(statuses: [.active, .unsorted, .archived]) {
                    memories = list
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}

/// En haut des Notes : les notes épinglées (les plus récemment épinglées d'abord).
struct PinnedCard: View {
    let memories: [Memory]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Épinglées", systemImage: "pin.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.bottom, 6)
            ForEach(memories) { memory in
                NavigationLink(value: memory.id) {
                    HStack(spacing: 10) {
                        Image(systemName: RecallHitRow.symbol(for: memory.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(memory.title)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if memory.id != memories.last?.id { Divider() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
