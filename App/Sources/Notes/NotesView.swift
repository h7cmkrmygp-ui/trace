import EngramCore
import EngramStore
import SwiftUI

/// Destinations de l'onglet Notes. Toute la navigation passe par des valeurs : mélanger
/// `NavigationLink(destination:)` et `NavigationLink(value:)` empilerait les écrans dans le mauvais ordre.
enum NotesRoute: Hashable {
    case list(title: String, statuses: Set<MemoryStatus>)
    case category(EngramCategory)
    case settings
    case evaluation
}

/// Notes : recherche, « À faire », catégories créées par l'IA, puis Archives et Corbeille.
struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CategoryStore.LibrarySummary?
    @State private var todo: [Memory] = []
    @State private var query = ""
    @State private var results: [Memory] = []

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    searchResults
                } else {
                    todoSection
                    if let summary { librarySections(summary) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notes")
            .searchable(text: $query, prompt: "Chercher dans ta mémoire")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: NotesRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .navigationDestination(for: NotesRoute.self) { route in
                switch route {
                case .list(let title, let statuses): MemoryListView(title: title, statuses: statuses)
                case .category(let category): CategoryMemoriesView(category: category)
                case .settings: SettingsView()
                case .evaluation: EvaluationView()
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
            .task {
                do {
                    for try await list in model.memories.memoriesStream(kinds: [.task, .appointment], statuses: [.active, .unsorted]) {
                        todo = list
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, isSearching else { return }
                model.perform {
                    let hits = try model.memories.searchText(query)
                    results = try model.memories.memories(ids: hits.map(\.memoryID))
                }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        ForEach(results) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
        }
    }

    @ViewBuilder private var todoSection: some View {
        if !todo.isEmpty {
            Section("À faire") {
                ForEach(todo) { memory in
                    NavigationLink(value: memory.id) {
                        Label(memory.title, systemImage: memory.kind == .appointment ? "calendar" : "circle")
                    }
                    .swipeActions {
                        Button("Fait", systemImage: "checkmark") {
                            model.perform { _ = try model.memories.setStatus(.archived, for: memory.id, actor: .user) }
                        }
                        .tint(.gray)
                    }
                }
            }
        }
    }

    @ViewBuilder private func librarySections(_ summary: CategoryStore.LibrarySummary) -> some View {
        if summary.unsortedCount > 0 {
            Section {
                NavigationLink(value: NotesRoute.list(title: "À classer", statuses: [.unsorted])) {
                    LabeledContent { Text("\(summary.unsortedCount)") } label: { Label("À classer", systemImage: "tray") }
                }
            }
        }
        Section("Catégories") {
            if summary.categories.isEmpty {
                Text("Parle à Engram : tes catégories apparaîtront ici toutes seules.")
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.categories) { item in
                NavigationLink(value: NotesRoute.category(item.category)) {
                    LabeledContent { Text("\(item.memoryCount)") } label: {
                        Label(item.category.name, systemImage: item.depth == 0 ? "folder" : "arrow.turn.down.right")
                    }
                }
                .padding(.leading, CGFloat(item.depth) * 16)
            }
        }
        Section {
            NavigationLink(value: NotesRoute.list(title: "Archives", statuses: [.archived])) {
                LabeledContent { Text("\(summary.archivedCount)") } label: { Label("Archives", systemImage: "archivebox") }
            }
            NavigationLink(value: NotesRoute.list(title: "Corbeille", statuses: [.trashed])) {
                LabeledContent { Text("\(summary.trashedCount)") } label: { Label("Corbeille", systemImage: "trash") }
            }
        }
    }
}
