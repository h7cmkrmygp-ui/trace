import EngramCore
import SwiftUI

/// Choix manuel des catégories d'un souvenir (en P1, l'IA ne classe pas encore).
struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    @State private var all: [EngramCategory] = []
    @State private var selected: Set<UUID> = []
    @State private var newName = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(all) { category in
                        Button { toggle(category) } label: {
                            HStack {
                                Label(category.name, systemImage: "folder")
                                Spacer()
                                if selected.contains(category.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Nouvelle catégorie") {
                    TextField("Nom", text: $newName)
                        .onSubmit(create)
                    Button("Créer et ajouter", systemImage: "plus", action: create)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Catégories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } }
            }
            .task { load() }
        }
    }

    private func load() {
        do {
            all = try model.categories.activeCategories()
            selected = Set(try model.categories.categories(for: memoryID).map(\.id))
        } catch {
            errorText = AppModel.describe(error)
        }
    }

    private func toggle(_ category: EngramCategory) {
        do {
            if selected.contains(category.id) {
                try model.categories.removeAssignment(memoryID: memoryID, categoryID: category.id, by: .user)
            } else {
                _ = try model.categories.assign(memoryID: memoryID, categoryID: category.id, origin: .user)
            }
            load()
        } catch {
            errorText = AppModel.describe(error)
        }
    }

    private func create() {
        do {
            let category = try model.categories.createCategory(name: newName, parentID: nil, origin: .user).category
            _ = try model.categories.assign(memoryID: memoryID, categoryID: category.id, origin: .user)
            newName = ""
            load()
        } catch {
            errorText = AppModel.describe(error)
        }
    }
}
