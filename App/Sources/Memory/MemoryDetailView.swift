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
    /// Notes sur le même sujet (au plus 3, seulement si elles ressemblent vraiment).
    @State private var related: [RecallHit] = []
    /// Toutes les catégories, pour retrouver la grande catégorie (et sa couleur) d'une sous-catégorie.
    @State private var allCategories: [UUID: EngramCategory] = [:]

    var body: some View {
        Group {
            if let memory {
                content(memory)
            } else {
                ContentUnavailableView("Souvenir introuvable", systemImage: "questionmark.folder")
            }
        }
        .task {
            reload()
            related = await model.relatedNotes(to: memoryID)
        }
    }

    private func content(_ memory: Memory) -> some View {
        List {
            Section {
                Text(memory.content)
                    .textSelection(.enabled)
            } header: {
                Text(memory.capturedAt, format: .dateTime.day().month(.wide).year().hour().minute())
            } footer: {
                if let details = Self.details(memory) { Text(details) }
            }
            Section("Catégories") {
                if assigned.isEmpty {
                    Text("À classer").foregroundStyle(.secondary)
                }
                ForEach(assigned) { category in
                    Label {
                        Text(category.name)
                    } icon: {
                        Image(systemName: "folder.fill").foregroundStyle(Color.category(rootName(of: category)))
                    }
                }
                Button("Choisir les catégories…", systemImage: "folder.badge.plus") { isPickingCategories = true }
            }
            if !related.isEmpty {
                Section("Notes liées") {
                    ForEach(related, id: \.document.id) { hit in
                        NavigationLink(value: hit.document.id) {
                            Label(hit.document.title, systemImage: RecallHitRow.symbol(for: hit.document.kind))
                        }
                    }
                }
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
                // Une tâche ou un rendez-vous terminés sont « faits » (rangés dans les Archives, comme le geste « Fait »).
                if memory.kind == .task || memory.kind == .appointment {
                    Button("Marquer comme fait", systemImage: "checkmark.circle") {
                        run { _ = try model.memories.setStatus(.archived, for: memoryID, actor: .user) }
                    }
                } else {
                    Button("Archiver", systemImage: "archivebox") {
                        run { _ = try model.memories.setStatus(.archived, for: memoryID, actor: .user) }
                    }
                }
                Button("Mettre à la corbeille", systemImage: "trash", role: .destructive) {
                    run { _ = try model.memories.setStatus(.trashed, for: memoryID, actor: .user) }
                }
            }
        }
    }

    /// « Tâche · pour samedi 10 octobre à 14 h », « Idée », « Rendez-vous · fait ».
    static func details(_ memory: Memory) -> String? {
        var parts: [String] = []
        if let kind = memory.kind, kind != .other { parts.append(kindLabel(kind)) }
        if let due = memory.dueAt {
            let date = due.formatted(.dateTime.weekday(.wide).day().month(.wide))
            parts.append(memory.dueHasTime ? "pour \(date) à \(due.formatted(.dateTime.hour().minute()))" : "pour \(date)")
        }
        if memory.status == .archived, memory.kind == .task || memory.kind == .appointment { parts.append("fait") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func kindLabel(_ kind: MemoryKind) -> String {
        switch kind {
        case .task: "Tâche"
        case .appointment: "Rendez-vous"
        case .idea: "Idée"
        case .decision: "Décision"
        case .preference: "Préférence"
        case .info: "Info"
        case .other: "Note"
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
            allCategories = Dictionary(uniqueKeysWithValues: try model.categories.activeCategories().map { ($0.id, $0) })
        }
    }

    /// Nom de la grande catégorie d'une catégorie (elle-même si elle n'a pas de parent).
    private func rootName(of category: EngramCategory) -> String {
        var current = category
        var depth = 0
        while let parentID = current.parentID, let parent = allCategories[parentID], depth < 16 {
            current = parent
            depth += 1
        }
        return current.name
    }
}
