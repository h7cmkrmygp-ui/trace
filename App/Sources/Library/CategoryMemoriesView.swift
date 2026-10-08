import EngramCore
import EngramStore
import SwiftUI

/// Une catégorie : ses notes, puis une section par sous-catégorie qui contient quelque chose.
struct CategoryMemoriesView: View {
    @Environment(AppModel.self) private var model
    let category: EngramCategory
    @State private var sections: [CategoryStore.CategorySection] = []

    var body: some View {
        List {
            if let description = category.descriptionText, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.memories) { memory in
                        NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                            .swipeActions { MemorySwipeActions(memory: memory) }
                    }
                } header: {
                    if section.category.id != category.id { Text(section.category.name) }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView("Aucune pensée dans « \(category.name) »", systemImage: "folder")
            }
        }
        .navigationTitle(category.name)
        .task {
            do {
                for try await value in model.categories.sectionsStream(rootID: category.id) { sections = value }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
