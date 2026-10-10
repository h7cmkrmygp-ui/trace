import EngramCore
import EngramStore
import SwiftUI

/// Une catégorie : ses pensées en petit réseau, ses notes, puis une section par sous-catégorie qui contient quelque chose.
struct CategoryMemoriesView: View {
    @Environment(AppModel.self) private var model
    let category: EngramCategory
    @State private var sections: [CategoryStore.CategorySection] = []
    /// Nom de la grande catégorie (pour un sous-dossier), lu une fois.
    @State private var rootName: String?

    /// La couleur du dossier (celle de sa grande catégorie) : la même que son neurone dans le Cerveau.
    private var tint: Color { Color.category(rootName ?? category.name) }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let description = category.descriptionText, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                if !sections.isEmpty {
                    CategoryConstellationView(root: category, sections: sections, tint: tint,
                                              onOpenMemory: { model.push($0) },
                                              onSelectSection: { id in withAnimation { proxy.scrollTo(id, anchor: .top) } })
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.memories) { memory in
                            NavigationLink(value: memory.id) { MemoryRow(memory: memory, tint: tint) }
                                .swipeActions { MemorySwipeActions(memory: memory) }
                        }
                    } header: {
                        if section.category.id != category.id { Text(section.category.name) }
                    }
                    .id(section.category.id)
                }
            }
            .listStyle(.plain)
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView("Aucune pensée dans « \(category.name) »", systemImage: "folder")
            }
        }
        .navigationTitle(category.name)
        .task {
            if let parentID = category.parentID {
                rootName = (try? model.categories.activeCategories())?.first { $0.id == parentID }?.name
            }
            do {
                for try await value in model.categories.sectionsStream(rootID: category.id) { sections = value }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
