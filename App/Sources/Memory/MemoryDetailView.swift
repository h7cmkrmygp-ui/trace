import EngramCore
import SwiftUI

struct MemoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID

    @State private var memory: Memory?
    @State private var source: Source?
    @State private var versions: [MemoryVersion] = []
    @State private var assigned: [EngramCategory] = []
    @State private var isEditing = false
    @State private var isPickingCategories = false
    @State private var isConfirmingDeletion = false
    @State private var isRetranscribing = false

    var body: some View {
        Group {
            if let memory {
                content(memory)
            } else {
                ContentUnavailableView("Souvenir introuvable", systemImage: "questionmark.folder")
            }
        }
        .task { reload() }
    }

    private func content(_ memory: Memory) -> some View {
        List {
            Section {
                Text(memory.content)
                    .textSelection(.enabled)
            } header: {
                Text(memory.capturedAt, format: .dateTime.day().month(.wide).year().hour().minute())
            }
            Section("Catégories") {
                if assigned.isEmpty {
                    Text("À classer").foregroundStyle(.secondary)
                }
                ForEach(assigned) { Label($0.name, systemImage: "folder") }
                Button("Choisir les catégories…", systemImage: "folder.badge.plus") { isPickingCategories = true }
            }
            if let source, let provider = source.analysisProvider {
                Section("Classement") {
                    Label(Self.providerLabel(provider), systemImage: provider == "apple" ? "iphone" : "cloud")
                    if let level = source.privacyLevel {
                        LabeledContent("Confidentialité", value: Self.levelLabel(level))
                    }
                    if let reason = source.routeReason, !reason.isEmpty {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let original = source?.originalText {
                Section("Source") {
                    Text(original)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section("Historique") {
                ForEach(versions) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(version.version)")
                            Text("\(version.changeReason ?? "") · \(version.createdAt.formatted(.relative(presentation: .named)))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if version.version != memory.version {
                            Button("Restaurer") {
                                model.perform { _ = try model.memories.restoreVersion(version.version, of: memoryID) }
                                reload()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle(memory.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { isEditing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                actionsMenu(memory)
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: reload) { MemoryEditor(memory: memory) }
        .sheet(isPresented: $isPickingCategories, onDismiss: reload) { CategoryPicker(memoryID: memoryID) }
        .confirmationDialog("Supprimer définitivement ce souvenir ?", isPresented: $isConfirmingDeletion,
                            titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                model.perform {
                    try model.deletePermanently(memoryID)
                    dismiss()
                }
            }
        } message: {
            Text("Cette action est irréversible.")
        }
    }

    private func actionsMenu(_ memory: Memory) -> some View {
        Menu("Actions", systemImage: "ellipsis.circle") {
            switch memory.status {
            case .trashed:
                Button("Restaurer", systemImage: "arrow.uturn.backward") { run { _ = try model.memories.restore(memoryID) } }
                Button("Supprimer définitivement", systemImage: "trash.slash", role: .destructive) { isConfirmingDeletion = true }
            case .archived:
                Button("Désarchiver", systemImage: "arrow.uturn.backward") { run { _ = try model.memories.restore(memoryID) } }
                Button("Mettre à la corbeille", systemImage: "trash", role: .destructive) {
                    run { _ = try model.memories.setStatus(.trashed, for: memoryID, actor: .user) }
                }
            case .active, .unsorted:
                if let source, source.kind == .voice, source.audioPath != nil, !source.correctedByOwner {
                    Button("Retranscrire avec Whisper", systemImage: "waveform") {
                        isRetranscribing = true
                        Task {
                            await model.retranscribe(sourceID: source.id)
                            isRetranscribing = false
                            reload()
                            // La note a pu être remplacée par sa nouvelle version : revenir à la liste.
                            if self.memory == nil { dismiss() }
                        }
                    }
                    .disabled(isRetranscribing)
                }
                Button("Archiver", systemImage: "archivebox") {
                    run { _ = try model.memories.setStatus(.archived, for: memoryID, actor: .user) }
                }
                Button("Mettre à la corbeille", systemImage: "trash", role: .destructive) {
                    run { _ = try model.memories.setStatus(.trashed, for: memoryID, actor: .user) }
                }
            }
        }
    }

    static func providerLabel(_ provider: String) -> String {
        switch provider {
        case "gemini": "Classée par Gemini"
        case "groq": "Classée par Groq"
        default: "Classée sur l'iPhone (IA d'Apple)"
        }
    }

    static func levelLabel(_ level: PrivacyLevel) -> String {
        switch level {
        case .neutral: "Neutre"
        case .personal: "Personnelle"
        case .secret: "Gardée sur l'iPhone"
        }
    }

    private func run(_ action: () throws -> Void) {
        model.perform(action)
        reload()
    }

    private func reload() {
        model.perform {
            memory = try model.memories.memory(id: memoryID)
            guard let memory else { return }
            source = try model.memories.source(id: memory.sourceID)
            versions = try model.memories.versions(of: memoryID)
            assigned = try model.categories.categories(for: memoryID)
        }
    }
}
