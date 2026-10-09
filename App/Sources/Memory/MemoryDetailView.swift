import EngramCore
import SwiftUI

/// Une note, comme dans Notes d'Apple : le titre et le texte se modifient sur place (cases à cocher comprises).
/// En dessous : tes mots exacts, les catégories et les notes liées. Le classement, le texte d'origine et les versions
/// sont rangés dans « Détails ».
struct MemoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID

    @State private var memory: Memory?
    @State private var source: Source?
    @State private var assigned: [EngramCategory] = []
    /// Notes sur le même sujet (au plus 3, seulement si elles ressemblent vraiment).
    @State private var related: [RecallHit] = []
    /// Toutes les catégories, pour retrouver la grande catégorie (et sa couleur) d'une sous-catégorie.
    @State private var allCategories: [UUID: EngramCategory] = [:]
    @State private var title = ""
    @State private var blocks: [NoteBlock] = []
    @FocusState private var focus: NoteField?
    @State private var showsSpokenWords = false
    @State private var isEditingWords = false
    @State private var isPickingCategories = false
    @State private var isShowingInfo = false
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
        .task {
            reload()
            related = await model.relatedNotes(to: memoryID)
        }
        .onDisappear(perform: save)
    }

    private var tint: Color {
        assigned.first.map { Color.category(rootName(of: $0)) } ?? .accentColor
    }

    private func content(_ memory: Memory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(memory)
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Titre", text: $title, axis: .vertical)
                        .font(.title2.weight(.bold))
                        .focused($focus, equals: .title)
                        .accessibilityAddTraits(.isHeader)
                        // Retour dans le titre passe au texte, comme dans Notes.
                        .onChange(of: title) { _, value in
                            guard value.contains("\n") else { return }
                            title = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                            if let first = blocks.first { focus = .block(first.id) }
                        }
                    NoteBodyEditor(blocks: $blocks, focus: $focus, tint: tint, onToggle: save)
                }
                spokenWords(memory)
                categoriesSection
                if !related.isEmpty { relatedSection }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { actionsMenu(memory) }
            ToolbarItemGroup(placement: .keyboard) {
                Button("Liste à cocher", systemImage: "checklist") {
                    let id = NoteBodyEditor.addCheck(to: &blocks, after: focus)
                    focus = .block(id)
                }
                Spacer()
                Button("OK") { focus = nil }
            }
        }
        // Chaque fois qu'on quitte un champ, la note est enregistrée (comme dans Notes, sans bouton).
        .onChange(of: focus) { _, _ in save() }
        .sheet(isPresented: $isEditingWords, onDismiss: reload) { MemoryEditor(memory: memory) }
        .sheet(isPresented: $isPickingCategories, onDismiss: reload) { CategoryPicker(memoryID: memoryID) }
        .sheet(isPresented: $isShowingInfo, onDismiss: reload) { MemoryInfoSheet(memory: memory, source: source) }
        .confirmationDialog("Supprimer définitivement ce souvenir ?", isPresented: $isConfirmingDeletion,
                            titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                model.perform {
                    try model.deletePermanently(memoryID)
                    // Plus rien à enregistrer en quittant l'écran.
                    self.memory = nil
                    dismiss()
                }
            }
        } message: {
            Text("Cette action est irréversible.")
        }
    }

    // MARK: - En-tête : date, type, échéance

    private func header(_ memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memory.capturedAt, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                if let kind = memory.kind, kind != .other {
                    chip(Self.kindLabel(kind), systemImage: RecallHitRow.symbol(for: kind), color: tint)
                }
                if let due = Self.dueText(memory) {
                    chip(due, systemImage: "calendar", color: .orange)
                }
                if memory.status == .archived, memory.kind == .task || memory.kind == .appointment {
                    chip("Fait", systemImage: "checkmark", color: .green)
                }
                if memory.status == .trashed {
                    chip("Corbeille", systemImage: "trash", color: .red)
                }
            }
        }
    }

    private func chip(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: - Tes mots

    private func spokenWords(_ memory: Memory) -> some View {
        DisclosureGroup(isExpanded: $showsSpokenWords) {
            Text(memory.content)
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Label(source?.kind == .voice ? "Ce que tu as dit" : "Ce que tu as écrit", systemImage: "quote.opening")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Catégories et notes liées

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Rangée dans")
            FlowLayout(spacing: 8) {
                if assigned.isEmpty {
                    chip("À classer", systemImage: "tray", color: .secondary)
                }
                ForEach(assigned) { category in
                    let color = Color.category(rootName(of: category))
                    Label(path(of: category), systemImage: "folder.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .labelStyle(TintedIconLabelStyle(color: color))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(color.opacity(0.14), in: Capsule())
                }
                Button {
                    isPickingCategories = true
                } label: {
                    Label("Changer", systemImage: "folder.badge.plus")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choisir les catégories")
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Notes liées")
            VStack(spacing: 8) {
                ForEach(related, id: \.document.id) { hit in
                    NavigationLink(value: hit.document.id) {
                        HStack(spacing: 12) {
                            Image(systemName: RecallHitRow.symbol(for: hit.document.kind))
                                .foregroundStyle(tint)
                                .frame(width: 28)
                            Text(hit.document.title)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Actions

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
                Button("Modifier tes mots…", systemImage: "quote.opening") { isEditingWords = true }
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
                Button("Mettre à la corbeille", systemImage: "trash", role: .destructive) {
                    run { _ = try model.memories.setStatus(.trashed, for: memoryID, actor: .user) }
                }
            }
            Divider()
            Button("Détails", systemImage: "info.circle") { isShowingInfo = true }
        }
    }

    // MARK: - Textes

    /// « pour jeudi 9 octobre à 14 h », « pour samedi 10 octobre ».
    static func dueText(_ memory: Memory) -> String? {
        guard let due = memory.dueAt else { return nil }
        let date = due.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return memory.dueHasTime ? "\(date) à \(due.formatted(.dateTime.hour().minute()))" : date
    }

    /// « Tâche · pour samedi 10 octobre à 14 h », « Idée », « Rendez-vous · fait ».
    static func details(_ memory: Memory) -> String? {
        var parts: [String] = []
        if let kind = memory.kind, kind != .other { parts.append(kindLabel(kind)) }
        if let due = dueText(memory) { parts.append("pour \(due)") }
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

    // MARK: - Lecture et enregistrement

    private func run(_ action: () throws -> Void) {
        save()
        model.perform(action)
        reload()
    }

    private func reload() {
        model.perform {
            memory = try model.memories.memory(id: memoryID)
            guard let memory else { return }
            source = try model.memories.source(id: memory.sourceID)
            assigned = try model.categories.categories(for: memoryID)
            allCategories = Dictionary(uniqueKeysWithValues: try model.categories.activeCategories().map { ($0.id, $0) })
            title = memory.title
            blocks = NoteBody.blocks(from: memory.summary ?? "")
            if blocks.isEmpty { blocks = [NoteBlock(kind: .text, text: "")] }
            showsSpokenWords = (memory.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Enregistre le titre et le texte s'ils ont changé (une version de plus, comme toute modification).
    private func save() {
        guard let memory else { return }
        // Une case vide qu'on vient de quitter disparaît.
        blocks.removeAll { block in
            if case .check = block.kind, block.text.trimmingCharacters(in: .whitespaces).isEmpty,
               focus != .block(block.id) { return true }
            return false
        }
        let body = NoteBody.text(from: blocks.filter {
            if case .check = $0.kind { return !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            return true
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let titleChanged = !newTitle.isEmpty && newTitle != memory.title
        let bodyChanged = body != (memory.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard titleChanged || bodyChanged else { return }
        let edit = MemoryEdit(title: titleChanged ? String(newTitle.prefix(TitleMaker.maxLength)) : nil,
                              summary: bodyChanged ? body : nil)
        model.perform {
            self.memory = try model.memories.updateMemory(memoryID, with: edit, actor: .user)
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

    /// « Finance › Assurances » pour une sous-catégorie.
    private func path(of category: EngramCategory) -> String {
        guard let parentID = category.parentID, let parent = allCategories[parentID] else { return category.name }
        return "\(parent.name) › \(category.name)"
    }
}

/// Étiquette dont seule l'icône prend la couleur de la catégorie.
private struct TintedIconLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
