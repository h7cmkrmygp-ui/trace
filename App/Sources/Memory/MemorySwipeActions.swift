import EngramCore
import SwiftUI

/// Actions de balayage, selon l'état du souvenir.
struct MemorySwipeActions: View {
    @Environment(AppModel.self) private var model
    let memory: Memory

    var body: some View {
        switch memory.status {
        case .trashed:
            Button("Restaurer", systemImage: "arrow.uturn.backward") {
                model.perform { _ = try model.memories.restore(memory.id) }
            }
            .tint(.indigo)
        case .archived:
            Button("Corbeille", systemImage: "trash", role: .destructive) {
                model.perform { _ = try model.memories.setStatus(.trashed, for: memory.id, actor: .user) }
            }
            Button("Désarchiver", systemImage: "arrow.uturn.backward") {
                model.perform { _ = try model.memories.restore(memory.id) }
            }
            .tint(.indigo)
        case .active, .unsorted:
            Button("Corbeille", systemImage: "trash", role: .destructive) {
                model.perform { _ = try model.memories.setStatus(.trashed, for: memory.id, actor: .user) }
            }
            Button("Archiver", systemImage: "archivebox") {
                model.perform { _ = try model.memories.setStatus(.archived, for: memory.id, actor: .user) }
            }
            .tint(.indigo)
        }
    }
}
