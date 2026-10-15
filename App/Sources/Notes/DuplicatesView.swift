import EngramCore
import EngramStore
import SwiftUI

/// P23 — « Doublons possibles » : la même pensée dite deux fois. « Réunir » garde la plus ancienne et y ajoute ce que
/// l'autre disait de plus (l'autre va à la corbeille, d'où elle se récupère) ; « Ce n'est pas un doublon » l'écarte.
struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @State private var pairs: [DuplicatePair] = []
    @State private var isLoading = true

    var body: some View {
        List {
            ForEach(pairs) { pair in
                Section {
                    row(pair.keep, label: "À garder", symbol: "checkmark.circle.fill", tint: .green)
                    row(pair.duplicate, label: "Doublon", symbol: "doc.on.doc", tint: .orange)
                    Button {
                        model.perform { try model.memories.mergeDuplicate(pair.duplicate.id, into: pair.keep.id) }
                        reload()
                    } label: {
                        Label("Réunir les deux notes", systemImage: "arrow.triangle.merge")
                    }
                    Button(role: .destructive) {
                        model.perform { try model.memories.dismissDuplicate(pair.keep.id, pair.duplicate.id) }
                        reload()
                    } label: {
                        Label("Ce n'est pas un doublon", systemImage: "xmark.circle")
                    }
                } footer: {
                    Text("Réunir garde chaque mot, les dossiers, les personnes et les lieux. Le doublon va à la corbeille.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Doublons possibles")
        .overlay {
            if pairs.isEmpty && !isLoading {
                ContentUnavailableView("Aucun doublon", systemImage: "checkmark.seal",
                                       description: Text("Quand tu dis deux fois la même chose, Engram te le propose ici."))
            }
        }
        .onAppear(perform: reload)
    }

    private func row(_ memory: Memory, label: String, symbol: String, tint: Color) -> some View {
        NavigationLink(value: memory.id) {
            VStack(alignment: .leading, spacing: 4) {
                Label(label, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(memory.title)
                    .foregroundStyle(.primary)
                Text(memory.capturedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func reload() {
        pairs = (try? model.memories.duplicatePairs()) ?? []
        isLoading = false
    }
}
