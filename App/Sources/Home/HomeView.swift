import EngramCore
import EngramStore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var recent: [Memory] = []
    @State private var feedback: String?
    @FocusState private var editorFocused: Bool

    private var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Écrire une pensée…", text: $draft, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($editorFocused)
                    Button("Enregistrer", systemImage: "square.and.arrow.down", action: save)
                        .disabled(!canSave)
                } footer: {
                    if let feedback { Text(feedback) }
                }
                Section("Récents") {
                    if recent.isEmpty {
                        ContentUnavailableView("Aucune pensée pour l'instant", systemImage: "brain",
                                               description: Text("Écris ta première pensée ci-dessus."))
                    }
                    ForEach(recent) { memory in
                        NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                            .swipeActions { MemorySwipeActions(memory: memory) }
                    }
                }
            }
            .navigationTitle("Engram")
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .task {
                do {
                    for try await list in model.memories.memoriesStream(statuses: [.active, .unsorted], limit: 30) {
                        recent = list
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
        }
    }

    private func save() {
        do {
            switch try model.memories.saveTextNoteWithoutAnalysis(draft) {
            case .saved: feedback = "Pensée enregistrée."
            case .duplicate: feedback = "Cette pensée vient déjà d'être enregistrée."
            }
            draft = ""
            editorFocused = false
        } catch {
            feedback = AppModel.describe(error)
        }
    }
}
