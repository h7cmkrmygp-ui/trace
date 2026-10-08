import EngramCore
import EngramStore
import SwiftUI

/// Destinations de l'onglet Notes. Toute la navigation passe par des valeurs : mélanger
/// `NavigationLink(destination:)` et `NavigationLink(value:)` empilerait les écrans dans le mauvais ordre.
enum NotesRoute: Hashable {
    case list(title: String, statuses: Set<MemoryStatus>)
    case category(EngramCategory)
    case todo
    case reviewQueue
    case review(UUID)
    case settings
    case evaluation

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .list(let title, let statuses): MemoryListView(title: title, statuses: statuses)
        case .category(let category): CategoryMemoriesView(category: category)
        case .todo: TodoListView()
        case .reviewQueue: ReviewQueueView()
        case .review(let sourceID): ReviewScreen(sourceID: sourceID)
        case .settings: SettingsView()
        case .evaluation: EvaluationView()
        }
    }
}

/// Notes : une recherche, puis des dossiers — seulement ceux qui contiennent quelque chose.
/// Archives, Corbeille et Réglages sont rangés dans le menu en haut.
struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var summary: CategoryStore.LibrarySummary?
    @State private var todo: [Memory] = []
    @State private var reviewCount = 0
    @State private var query = ""
    @State private var results: [Memory] = []

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var roots: [CategoryStore.CategorySummary] { summary?.categories.filter { $0.depth == 0 } ?? [] }
    private var unsortedCount: Int { summary?.unsortedCount ?? 0 }
    private var isEmpty: Bool { summary != nil && roots.isEmpty && todo.isEmpty && unsortedCount == 0 && reviewCount == 0 }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSearching { searchResults } else { folders }
            }
            .navigationTitle("Notes")
            .searchable(text: $query, prompt: "Chercher dans ta mémoire")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .navigationDestination(for: NotesRoute.self) { $0.destination }
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
            .task {
                do {
                    for try await list in model.memories.sourcesAwaitingReviewStream() { reviewCount = list.count }
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

    private var menu: some View {
        Menu {
            Button {
                path.append(NotesRoute.list(title: "Archives", statuses: [.archived]))
            } label: {
                Label("Archives (\(summary?.archivedCount ?? 0))", systemImage: "archivebox")
            }
            Button {
                path.append(NotesRoute.list(title: "Corbeille", statuses: [.trashed]))
            } label: {
                Label("Corbeille (\(summary?.trashedCount ?? 0))", systemImage: "trash")
            }
            Divider()
            Button {
                path.append(NotesRoute.settings)
            } label: {
                Label("Réglages", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Plus")
    }

    private var folders: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if reviewCount > 0 {
                    NavigationLink(value: NotesRoute.reviewQueue) {
                        FolderCard(systemImage: "text.badge.checkmark", title: "À vérifier",
                                   subtitle: Self.count(reviewCount, "dictée", "à vérifier"))
                    }
                }
                if !todo.isEmpty {
                    NavigationLink(value: NotesRoute.todo) {
                        FolderCard(systemImage: "checklist", title: "À faire", subtitle: Self.count(todo.count, "chose", "à faire"))
                    }
                }
                if unsortedCount > 0 {
                    NavigationLink(value: NotesRoute.list(title: "À classer", statuses: [.unsorted])) {
                        FolderCard(systemImage: "tray", title: "À classer", subtitle: Self.count(unsortedCount, "note", "à classer"))
                    }
                }
                ForEach(roots) { item in
                    NavigationLink(value: NotesRoute.category(item.category)) {
                        FolderCard(systemImage: "folder", title: item.category.name,
                                   subtitle: item.category.descriptionText.flatMap { $0.isEmpty ? nil : $0 }
                                       ?? Self.count(item.totalCount, "note", nil))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView("Aucune note pour l'instant", systemImage: "folder",
                                       description: Text("Parle à Engram : tes dossiers apparaîtront ici tout seuls."))
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        List(results) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    /// « 1 note », « 3 notes à classer »…
    static func count(_ n: Int, _ noun: String, _ suffix: String?) -> String {
        let word = n > 1 ? noun + "s" : noun
        return [String(n), word, suffix].compactMap { $0 }.joined(separator: " ")
    }
}

/// Carte-dossier, dans le style de la capture : icône, nom, une ligne de description, chevron.
struct FolderCard: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Tâches et rendez-vous en cours ; balayer pour marquer « Fait » (archivé).
struct TodoListView: View {
    @Environment(AppModel.self) private var model
    @State private var todo: [Memory] = []

    var body: some View {
        List(todo) { memory in
            NavigationLink(value: memory.id) {
                Label(memory.title, systemImage: memory.kind == .appointment ? "calendar" : "circle")
            }
            .swipeActions {
                Button("Fait", systemImage: "checkmark") {
                    model.perform { _ = try model.memories.setStatus(.archived, for: memory.id, actor: .user) }
                }
                .tint(.green)
            }
        }
        .overlay {
            if todo.isEmpty { ContentUnavailableView("Rien à faire", systemImage: "checkmark.circle") }
        }
        .navigationTitle("À faire")
        .task {
            do {
                for try await list in model.memories.memoriesStream(kinds: [.task, .appointment], statuses: [.active, .unsorted]) {
                    todo = list
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
