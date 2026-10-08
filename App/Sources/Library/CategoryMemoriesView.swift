import EngramCore
import SwiftUI

struct CategoryMemoriesView: View {
    @Environment(AppModel.self) private var model
    let category: EngramCategory
    @State private var memories: [Memory] = []

    var body: some View {
        List(memories) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                .swipeActions { MemorySwipeActions(memory: memory) }
        }
        .overlay {
            if memories.isEmpty {
                ContentUnavailableView("Aucune pensée dans « \(category.name) »", systemImage: "folder")
            }
        }
        .navigationTitle(category.name)
        .task {
            do {
                for try await list in model.categories.memoriesStream(inCategory: category.id) { memories = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
