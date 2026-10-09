import EngramCore
import EngramStore
import SwiftUI

/// Pastille d'une personne (ses initiales, dans sa couleur) ou d'un lieu (une épingle).
struct EntityAvatar: View {
    let entity: EngramEntity
    var size: CGFloat = 40

    private var color: Color { Color.category(entity.name) }

    /// « Julie » → « J », « Marc Tremblay » → « MT », « Mon manager » → « M ».
    static func initials(of name: String) -> String {
        let possessives: Set<String> = ["mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos"]
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { !possessives.contains($0.lowercased()) }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? String(name.prefix(1)).uppercased() : letters.joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18))
            if entity.kind == .place {
                Image(systemName: "mappin")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Text(Self.initials(of: entity.name))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Une ligne de « Personnes » ou « Lieux » : pastille, nom, nombre de notes, dernière mention, choses à faire.
struct EntityRow: View {
    let summary: EntityStore.Summary

    var body: some View {
        HStack(spacing: 12) {
            EntityAvatar(entity: summary.entity)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.entity.name)
                HStack(spacing: 4) {
                    Text(NotesView.count(summary.noteCount, "note", nil))
                    if let last = summary.lastMentionedAt {
                        Text("·")
                        Text(last, format: .relative(presentation: .named))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if summary.openTaskCount > 0 {
                Label("\(summary.openTaskCount)", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel(NotesView.count(summary.openTaskCount, "chose", "à faire"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// « Personnes » ou « Lieux » : tous ceux dont parlent tes notes, le plus récemment nommé d'abord.
struct EntityListView: View {
    @Environment(AppModel.self) private var model
    let kind: EntityKind
    @State private var summaries: [EntityStore.Summary] = []
    @State private var query = ""

    private var shown: [EntityStore.Summary] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? summaries : summaries.filter { $0.entity.name.localizedStandardContains(needle) }
    }

    var body: some View {
        List(shown) { summary in
            NavigationLink(value: NotesRoute.entity(summary.entity.id)) { EntityRow(summary: summary) }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: kind == .person ? "Chercher une personne" : "Chercher un lieu")
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView(kind == .person ? "Personne pour l'instant" : "Aucun lieu pour l'instant",
                                       systemImage: kind == .person ? "person.2" : "mappin.and.ellipse",
                                       description: Text(kind == .person
                                                         ? "Nomme quelqu'un dans une note : sa page apparaîtra ici."
                                                         : "Parle d'un endroit dans une note : il apparaîtra ici."))
            }
        }
        .navigationTitle(kind == .person ? "Personnes" : "Lieux")
        .task {
            do {
                for try await list in model.entities.summariesStream(kind: kind) { summaries = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}

/// La page d'une personne ou d'un lieu : ce qu'il reste à faire avec elle, puis toutes ses notes, mois par mois.
struct EntityDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entityID: UUID
    @State private var entity: EngramEntity?
    @State private var memories: [Memory] = []
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isMerging = false
    @State private var isConfirmingHide = false

    private var openTasks: [Memory] {
        memories.filter { ($0.kind == .task || $0.kind == .appointment) && ($0.status == .active || $0.status == .unsorted) }
    }

    /// Les autres notes, regroupées par mois (« octobre 2026 »).
    private var months: [(title: String, memories: [Memory])] {
        let open = Set(openTasks.map(\.id))
        var groups: [(title: String, memories: [Memory])] = []
        for memory in memories where !open.contains(memory.id) {
            let title = memory.capturedAt.formatted(.dateTime.month(.wide).year())
            if groups.last?.title == title { groups[groups.count - 1].memories.append(memory) } else { groups.append((title: title, memories: [memory])) }
        }
        return groups
    }

    var body: some View {
        List {
            if let entity {
                Section {
                    HStack(spacing: 16) {
                        EntityAvatar(entity: entity, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entity.name)
                                .font(.title2.weight(.bold))
                                .accessibilityAddTraits(.isHeader)
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                }
                if !openTasks.isEmpty {
                    Section(entity.kind == .person ? "À faire avec \(entity.name)" : "À faire : \(entity.name)") {
                        ForEach(openTasks) { memory in
                            NavigationLink(value: memory.id) { MemoryRow(memory: memory, tint: Color.category(entity.name)) }
                        }
                    }
                }
                ForEach(months, id: \.title) { month in
                    Section(month.title) {
                        ForEach(month.memories) { memory in
                            NavigationLink(value: memory.id) { MemoryRow(memory: memory) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entity?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entity {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Renommer", systemImage: "pencil") {
                            newName = entity.name
                            isRenaming = true
                        }
                        Button("Fusionner avec…", systemImage: "arrow.triangle.merge") { isMerging = true }
                        Divider()
                        Button(entity.kind == .person ? "Ce n'est pas une personne" : "Ce n'est pas un lieu",
                               systemImage: "eye.slash", role: .destructive) { isConfirmingHide = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Actions")
                }
            }
        }
        .alert("Renommer", isPresented: $isRenaming) {
            TextField("Nom", text: $newName)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { rename() }
        } message: {
            Text("Un nom qui existe déjà les réunit en une seule page.")
        }
        .sheet(isPresented: $isMerging) {
            if let entity {
                MergeEntitySheet(entity: entity) { target in
                    model.perform { try model.entities.merge(entity.id, into: target.id) }
                    dismiss()
                }
            }
        }
        .confirmationDialog(entity?.kind == .place ? "Ce n'est pas un lieu ?" : "Ce n'est pas une personne ?",
                            isPresented: $isConfirmingHide, titleVisibility: .visible) {
            Button("Masquer cette page", role: .destructive) {
                model.perform { try model.entities.hide(entityID) }
                dismiss()
            }
        } message: {
            Text("Sa page disparaît et Engram ne la recréera plus. Tes notes restent intactes.")
        }
        .task {
            entity = try? model.entities.entity(id: entityID)
            do {
                for try await list in model.entities.memoriesStream(for: entityID) {
                    memories = list
                    entity = try? model.entities.entity(id: entityID)
                }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }

    private var subtitle: String {
        var parts = [NotesView.count(memories.count, "note", nil)]
        if !openTasks.isEmpty { parts.append(NotesView.count(openTasks.count, "chose", "à faire")) }
        if let last = memories.first?.capturedAt {
            parts.append("dernière fois \(last.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != entity?.name else { return }
        model.perform {
            let kept = try model.entities.rename(entityID, to: name)
            // Le nom existait déjà : les deux pages n'en font plus qu'une, on revient à la liste.
            if kept.id != entityID { dismiss() } else { entity = kept }
        }
    }
}

/// Choisir la personne (ou le lieu) avec qui fusionner : les notes de la page actuelle la rejoignent.
struct MergeEntitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entity: EngramEntity
    let onChoose: (EngramEntity) -> Void
    @State private var others: [EngramEntity] = []
    @State private var query = ""

    private var shown: [EngramEntity] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? others : others.filter { $0.name.localizedStandardContains(needle) }
    }

    var body: some View {
        NavigationStack {
            List(shown) { other in
                Button {
                    onChoose(other)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        EntityAvatar(entity: other, size: 32)
                        Text(other.name).foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Chercher")
            .overlay {
                if others.isEmpty { ContentUnavailableView("Rien avec qui fusionner", systemImage: "arrow.triangle.merge") }
            }
            .navigationTitle("Fusionner « \(entity.name) »")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
            }
            .task {
                others = ((try? model.entities.allEntities(kind: entity.kind)) ?? []).filter { $0.id != entity.id }
            }
        }
    }
}

/// Ajouter une personne ou un lieu à une note (un nom déjà connu se choisit d'un toucher).
struct AddEntitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    @State private var name = ""
    @State private var kind: EntityKind = .person
    @State private var known: [EngramEntity] = []

    private var suggestions: [EngramEntity] {
        let needle = name.trimmingCharacters(in: .whitespaces)
        return Array((needle.isEmpty ? known : known.filter { $0.name.localizedStandardContains(needle) }).prefix(8))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Personne").tag(EntityKind.person)
                        Text("Lieu").tag(EntityKind.place)
                    }
                    .pickerStyle(.segmented)
                    TextField(kind == .person ? "Nom (Julie, maman…)" : "Lieu (Costco, le gym…)", text: $name)
                        .submitLabel(.done)
                        .onSubmit { add(name) }
                }
                if !suggestions.isEmpty {
                    Section("Déjà dans ta mémoire") {
                        ForEach(suggestions) { entity in
                            Button {
                                add(entity.name)
                            } label: {
                                HStack(spacing: 12) {
                                    EntityAvatar(entity: entity, size: 28)
                                    Text(entity.name).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ajouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { add(name) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task(id: kind) { known = (try? model.entities.allEntities(kind: kind)) ?? [] }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.perform { try model.entities.addEntity(named: trimmed, kind: kind, to: memoryID) }
        dismiss()
    }
}
