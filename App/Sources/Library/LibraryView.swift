import EngramCore
import EngramStore
import SwiftUI

/// Destinations de la bibliothèque. Toute la navigation de cet onglet passe par des valeurs : mélanger
/// `NavigationLink(destination:)` et `NavigationLink(value:)` dans une même pile empile les écrans
/// dans le mauvais ordre (le souvenir ouvert se retrouve sous la liste).
enum LibraryRoute: Hashable {
    case list(title: String, statuses: Set<MemoryStatus>)
    case category(EngramCategory)
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CategoryStore.LibrarySummary?

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    Section {
                        NavigationLink(value: LibraryRoute.list(title: "À classer", statuses: [.unsorted])) {
                            LabeledContent { Text("\(summary.unsortedCount)") } label: { Label("À classer", systemImage: "tray") }
                        }
                        NavigationLink(value: LibraryRoute.list(title: "Toutes les pensées", statuses: [.active, .unsorted])) {
                            Label("Toutes les pensées", systemImage: "square.stack")
                        }
                    }
                    Section("Catégories") {
                        ForEach(summary.categories) { item in
                            NavigationLink(value: LibraryRoute.category(item.category)) {
                                LabeledContent { Text("\(item.memoryCount)") } label: {
                                    Label(item.category.name, systemImage: "folder")
                                }
                            }
                            .padding(.leading, CGFloat(item.depth) * 16)
                        }
                    }
                    Section {
                        NavigationLink(value: LibraryRoute.list(title: "Archives", statuses: [.archived])) {
                            LabeledContent { Text("\(summary.archivedCount)") } label: { Label("Archives", systemImage: "archivebox") }
                        }
                        NavigationLink(value: LibraryRoute.list(title: "Corbeille", statuses: [.trashed])) {
                            LabeledContent { Text("\(summary.trashedCount)") } label: { Label("Corbeille", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Bibliothèque")
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .list(let title, let statuses): MemoryListView(title: title, statuses: statuses)
                case .category(let category): CategoryMemoriesView(category: category)
                }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .task {
                do {
                    for try await value in model.categories.librarySummaryStream() { summary = value }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
        }
    }
}
