import EngramCore
import SwiftUI

struct MemoryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memory: Memory
    @State private var title: String
    @State private var content: String
    @State private var errorText: String?

    init(memory: Memory) {
        self.memory = memory
        _title = State(initialValue: memory.title)
        _content = State(initialValue: memory.content)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") { TextField("Titre", text: $title) }
                Section("Contenu") {
                    TextEditor(text: $content).frame(minHeight: 220)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", action: save)
                }
            }
        }
    }

    private func save() {
        do {
            _ = try model.memories.updateMemory(memory.id, with: MemoryEdit(title: title, content: content), actor: .user)
            dismiss()
        } catch {
            errorText = AppModel.describe(error)
        }
    }
}
