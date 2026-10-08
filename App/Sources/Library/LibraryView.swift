import EngramCore
import EngramStore
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CategoryStore.LibrarySummary?

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    Section {
                        NavigationLink {
                            MemoryListView(title: "À classer", statuses: [.unsorted])
                        } label: {
                            LabeledContent { Text("\(summary.unsortedCount)") } label: { Label("À classer", systemImage: "tray") }
                        }
                        NavigationLink {
                            MemoryListView(title: "Toutes les pensées", statuses: [.active, .unsorted])
                        } label: {
                            Label("Toutes les pensées", systemImage: "square.stack")
                        }
                    }
                    Section("Catégories") {
                        ForEach(summary.categories) { item in
                            NavigationLink {
                                CategoryMemoriesView(category: item.category)
                            } label: {
                                LabeledContent { Text("\(item.memoryCount)") } label: {
                                    Label(item.category.name, systemImage: "folder")
                                }
                            }
                            .padding(.leading, CGFloat(item.depth) * 16)
                        }
                    }
                    Section {
                        NavigationLink {
                            MemoryListView(title: "Archives", statuses: [.archived])
                        } label: {
                            LabeledContent { Text("\(summary.archivedCount)") } label: { Label("Archives", systemImage: "archivebox") }
                        }
                        NavigationLink {
                            MemoryListView(title: "Corbeille", statuses: [.trashed])
                        } label: {
                            LabeledContent { Text("\(summary.trashedCount)") } label: { Label("Corbeille", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Bibliothèque")
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
