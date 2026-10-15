import EngramCore
import EngramStore
import SwiftUI

/// P15 — les listes : une note par liste (épicerie, cadeaux…), complétée à la voix. Toucher une liste l'ouvre comme
/// une note, avec ses cases à cocher.
struct ListsView: View {
    @Environment(AppModel.self) private var model
    @State private var lists: [ListStore.Summary] = []

    var body: some View {
        List {
            Section {
                ForEach(lists) { list in
                    NavigationLink(value: list.memoryID) {
                        HStack(spacing: 12) {
                            Image(systemName: list.open == 0 && list.done > 0 ? "checkmark.circle.fill" : "checklist")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(Self.counts(list))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                if !lists.isEmpty {
                    Text("Dis « Ajoute du lait et des œufs à ma liste d'épicerie » : tout va dans la même liste. Une case cochée revient si tu la redemandes.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Listes")
        .overlay {
            if lists.isEmpty {
                ContentUnavailableView("Aucune liste", systemImage: "checklist",
                                       description: Text("Dis « Ajoute du lait à ma liste d'épicerie »."))
            }
        }
        .task {
            do {
                for try await value in model.lists.listsStream() { lists = value }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }

    /// « 3 choses · 2 cochées », « Tout est coché ».
    static func counts(_ list: ListStore.Summary) -> String {
        if list.open == 0 { return list.done == 0 ? "Vide" : "Tout est coché" }
        let open = list.open == 1 ? "1 chose" : "\(list.open) choses"
        guard list.done > 0 else { return open }
        return "\(open) · \(list.done) cochée\(list.done > 1 ? "s" : "")"
    }

    /// « Épicerie (3) · Cadeaux (1) », pour la carte des Notes.
    static func summary(_ lists: [ListStore.Summary]) -> String {
        lists.prefix(3).map { $0.open > 0 ? "\($0.name) (\($0.open))" : $0.name }.joined(separator: " · ")
    }
}
