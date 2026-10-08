import EngramCore
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [Memory] = []

    var body: some View {
        NavigationStack {
            List(results) { memory in
                NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Cherche dans ta mémoire", systemImage: "magnifyingglass",
                                           description: Text("Par mots, sans te soucier des accents."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Recherche")
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .searchable(text: $query, prompt: "Mots, idées, décisions…")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                model.perform {
                    let hits = try model.memories.searchText(query)
                    results = try model.memories.memories(ids: hits.map(\.memoryID))
                }
            }
        }
    }
}
