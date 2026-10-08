import EngramCore
import SwiftUI

/// Liste de souvenirs par état (À classer, Archives, Corbeille). Dans la corbeille : suppression d'un geste
/// et « Tout supprimer », toujours avec confirmation.
struct MemoryListView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let statuses: Set<MemoryStatus>
    @State private var memories: [Memory] = []
    @State private var pendingDeletion: Memory?
    @State private var isConfirmingEmptyTrash = false

    private var isTrash: Bool { statuses == [.trashed] }

    private func requestDeletion(_ memory: Memory) {
        pendingDeletion = memory
    }

    var body: some View {
        List(memories) { memory in
            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                .swipeActions {
                    MemorySwipeActions(memory: memory, onDeletePermanently: isTrash ? requestDeletion : nil)
                }
        }
        .overlay {
            if memories.isEmpty {
                ContentUnavailableView(isTrash ? "Corbeille vide" : "Rien ici", systemImage: isTrash ? "trash" : "tray")
            }
        }
        .navigationTitle(title)
        .toolbar {
            if isTrash && !memories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tout supprimer", role: .destructive) { isConfirmingEmptyTrash = true }
                        .tint(.red)
                }
            }
        }
        .confirmationDialog("Supprimer définitivement cette note ?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible, presenting: pendingDeletion) { memory in
            Button("Supprimer définitivement", role: .destructive) {
                model.perform { try model.deletePermanently(memory.id) }
            }
        } message: { _ in
            Text("Elle ne pourra plus être restaurée.")
        }
        .confirmationDialog("Vider la corbeille ?", isPresented: $isConfirmingEmptyTrash, titleVisibility: .visible) {
            Button("Supprimer \(memories.count) note\(memories.count > 1 ? "s" : "") définitivement", role: .destructive) {
                model.perform { try model.emptyTrash() }
            }
        } message: {
            Text("Les notes de la corbeille et leurs enregistrements seront effacés pour de bon.")
        }
        .task {
            do {
                for try await list in model.memories.memoriesStream(statuses: statuses) { memories = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
