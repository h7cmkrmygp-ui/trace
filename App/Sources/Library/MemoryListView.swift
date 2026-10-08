import EngramCore
import SwiftUI

struct MemoryListView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let statuses: Set<MemoryStatus>
    @State private var memories: [Memory] = []

    var body: some View {
        List(memories) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                .swipeActions { MemorySwipeActions(memory: memory) }
        }
        .overlay {
            if memories.isEmpty { ContentUnavailableView("Rien ici", systemImage: "tray") }
        }
        .navigationTitle(title)
        .task {
            do {
                for try await list in model.memories.memoriesStream(statuses: statuses) { memories = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
