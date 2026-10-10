import EngramCore
import SwiftUI

/// Actions de balayage, selon l'état du souvenir. Les couleurs sont explicites : avec la teinte blanche de l'app,
/// un bouton sans couleur propre devenait blanc et son icône disparaissait.
struct MemorySwipeActions: View {
    @Environment(AppModel.self) private var model
    let memory: Memory
    /// Demande de suppression définitive (l'écran parent affiche la confirmation).
    var onDeletePermanently: ((Memory) -> Void)?

    var body: some View {
        switch memory.status {
        case .trashed:
            if let onDeletePermanently {
                // Pas de rôle « destructif » ici : la ligne ne doit pas disparaître avant la confirmation.
                Button("Supprimer", systemImage: "trash.slash") { onDeletePermanently(memory) }
                    .tint(.red)
            }
            Button("Restaurer", systemImage: "arrow.uturn.backward") {
                model.perform { _ = try model.memories.restore(memory.id) }
            }
            .tint(.blue)
        case .archived:
            Button("Corbeille", systemImage: "trash", role: .destructive) {
                model.perform { _ = try model.memories.setStatus(.trashed, for: memory.id, actor: .user) }
            }
            .tint(.red)
            Button("Désarchiver", systemImage: "arrow.uturn.backward") {
                model.perform { _ = try model.memories.restore(memory.id) }
            }
            .tint(.gray)
        case .active, .unsorted:
            Button("Corbeille", systemImage: "trash", role: .destructive) {
                model.perform { _ = try model.memories.setStatus(.trashed, for: memory.id, actor: .user) }
            }
            .tint(.red)
            Button("Archiver", systemImage: "archivebox") {
                model.perform { _ = try model.memories.setStatus(.archived, for: memory.id, actor: .user) }
            }
            .tint(.gray)
        }
    }
}
