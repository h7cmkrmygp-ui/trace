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
    case benchmark
    /// P9 : les personnes, les lieux, et la page de l'un d'eux.
    case people
    case places
    case entity(UUID)
    /// P10 : les suivis, et la page de l'un d'eux.
    case trackers
    case metric(Metric)
    /// P11 : le journal, jour par jour.
    case journal

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .list(let title, let statuses): MemoryListView(title: title, statuses: statuses)
        case .category(let category): CategoryMemoriesView(category: category)
        case .todo: TodoListView()
        case .reviewQueue: ReviewQueueView()
        case .review(let sourceID): ReviewScreen(sourceID: sourceID)
        case .settings: SettingsView()
        case .evaluation: EvaluationView()
        case .benchmark: BenchmarkView()
        case .people: EntityListView(kind: .person)
        case .places: EntityListView(kind: .place)
        case .entity(let id): EntityDetailView(entityID: id)
        case .trackers: TrackersView()
        case .metric(let metric): MetricDetailView(metric: metric)
        case .journal: JournalView()
        }
    }
}

/// Notes : une recherche, puis des dossiers — seulement ceux qui contiennent quelque chose.
/// Archives, Corbeille et Réglages sont rangés dans le menu en haut.
struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CategoryStore.LibrarySummary?
    @State private var todo: [Memory] = []
    @State private var reviewCount = 0
    @State private var isWriting = false
    @State private var query = ""
    @State private var results: [Memory] = []
    @State private var people: [EntityStore.Summary] = []
    @State private var places: [EntityStore.Summary] = []
    /// P10 : « Poids 162,5 lb · Sommeil 7 h 30 » (vide sans mesure).
    @State private var trackersSummary = ""
    /// P11 : les notes épinglées.
    @State private var pinned: [Memory] = []
    @AppStorage("engram.weightUnit") private var weightUnit = "lb"

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var roots: [CategoryStore.CategorySummary] { summary?.categories.filter { $0.depth == 0 } ?? [] }
    private var unsortedCount: Int { summary?.unsortedCount ?? 0 }
    private var isEmpty: Bool { summary != nil && roots.isEmpty && todo.isEmpty && unsortedCount == 0 && reviewCount == 0 }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.notesPath) {
            Group {
                if isSearching { searchResults } else { folders }
            }
            .navigationTitle("Notes")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Chercher dans ta mémoire")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Nouvelle note", systemImage: "plus") { isWriting = true }
                    menu
                }
            }
            .sheet(isPresented: $isWriting) {
                TextCaptureSheet { text, keepLocal in Task { await model.captureText(text, keepLocal: keepLocal) } }
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
            .task {
                do {
                    for try await list in model.entities.summariesStream(kind: .person) { people = list }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
            .task {
                do {
                    for try await list in model.entities.summariesStream(kind: .place) { places = list }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
            .task {
                do {
                    for try await list in model.memories.pinnedStream() { pinned = list }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
            .task(id: weightUnit) {
                do {
                    for try await metrics in model.measurements.metricsStream() {
                        trackersSummary = metrics.prefix(2).compactMap { metric -> String? in
                            guard let last = (try? model.measurements.points(metric: metric, weightUnit: weightUnit))?.last
                            else { return nil }
                            return "\(metric.title) " + MetricUnits.format(last.value, second: last.secondValue, metric: metric,
                                                                            unit: metric.unit(weightUnit: weightUnit))
                        }
                        .joined(separator: " · ")
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
            // Résumé du matin ou widget « Aujourd'hui » touché : « À faire » s'ouvre.
            .task(id: model.openTodoRequest) {
                guard model.consumeTodoRequest() else { return }
                var path = NavigationPath()
                path.append(NotesRoute.todo)
                model.notesPath = path
            }
            // Toucher sur un rappel : la note s'ouvre (même si l'onglet n'était pas encore affiché).
            .task(id: model.openMemoryRequest) {
                guard let id = model.openMemoryRequest else { return }
                model.openMemoryRequest = nil
                var path = NavigationPath()
                path.append(id)
                model.notesPath = path
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
                model.notesPath.append(NotesRoute.list(title: "Archives", statuses: [.archived]))
            } label: {
                Label("Archives (\(summary?.archivedCount ?? 0))", systemImage: "archivebox")
            }
            Button {
                model.notesPath.append(NotesRoute.list(title: "Corbeille", statuses: [.trashed]))
            } label: {
                Label("Corbeille (\(summary?.trashedCount ?? 0))", systemImage: "trash")
            }
            Button {
                model.notesPath.append(NotesRoute.journal)
            } label: {
                Label("Journal", systemImage: "book.closed")
            }
            Divider()
            Button {
                model.notesPath.append(NotesRoute.settings)
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
                if !pinned.isEmpty { PinnedCard(memories: Array(pinned.prefix(5))) }
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
                        FolderCard(systemImage: "folder.fill", title: item.category.name,
                                   subtitle: item.category.descriptionText.flatMap { $0.isEmpty ? nil : $0 }
                                       ?? Self.count(item.totalCount, "note", nil),
                                   tint: .category(item.category.name))
                    }
                }
                // Les personnes et les lieux dont parlent tes notes (P9).
                if !people.isEmpty {
                    NavigationLink(value: NotesRoute.people) {
                        FolderCard(systemImage: "person.2.fill", title: "Personnes", subtitle: Self.names(people))
                    }
                }
                if !places.isEmpty {
                    NavigationLink(value: NotesRoute.places) {
                        FolderCard(systemImage: "mappin.and.ellipse", title: "Lieux", subtitle: Self.names(places))
                    }
                }
                // Les suivis (P10) : poids, sommeil, tension… dits dans les notes.
                if !trackersSummary.isEmpty {
                    NavigationLink(value: NotesRoute.trackers) {
                        FolderCard(systemImage: "chart.xyaxis.line", title: "Suivis", subtitle: trackersSummary)
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

    /// « Julie, Marc et 3 autres ».
    static func names(_ summaries: [EntityStore.Summary]) -> String {
        let first = summaries.prefix(2).map(\.entity.name)
        let others = summaries.count - first.count
        guard others > 0 else { return ListFormatter.localizedString(byJoining: first) }
        return first.joined(separator: ", ") + " et \(others) autre\(others > 1 ? "s" : "")"
    }

    /// « 1 note », « 3 notes à classer »…
    static func count(_ n: Int, _ noun: String, _ suffix: String?) -> String {
        let word = n > 1 ? noun + "s" : noun
        return [String(n), word, suffix].compactMap { $0 }.joined(separator: " ")
    }
}

/// Carte-dossier, dans le style de la capture : icône, nom, une ligne de description, chevron.
struct FolderCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let systemImage: String
    let title: String
    let subtitle: String
    /// Couleur de la catégorie (la même que son neurone dans le Cerveau) ; nil pour les dossiers spéciaux.
    var tint: Color?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint ?? .primary)
                .frame(width: 48, height: 48)
                .background(tint.map { $0.opacity(0.16) } ?? Color(.tertiarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // Très grand texte (réglages d'accessibilité) : la description s'étend au lieu d'être coupée.
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
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
