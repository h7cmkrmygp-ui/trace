import EngramCore
import EngramStore
import SwiftUI

/// P40 — le ménage automatique des dossiers : ce qu'Engram a changé, et « Annuler » pour chaque changement.
struct TidyView: View {
    @Environment(AppModel.self) private var model
    @State private var records: [TidyRecord] = []
    @State private var isTidying = false
    @State private var notice: String?
    @State private var proposals: [TidyProposal] = []

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        isTidying = true
                        let count = await model.tidyFoldersNow()
                        proposals = await model.proposedMoves()
                        isTidying = false
                        notice = count == 0 ? (proposals.isEmpty ? "Tout est déjà en ordre." : "Des déplacements te sont proposés.")
                            : "\(count) changement\(count > 1 ? "s" : "")."
                        load()
                    }
                } label: {
                    HStack {
                        Label("Faire le ménage maintenant", systemImage: "sparkles")
                        if isTidying {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isTidying)
                if let notice {
                    Text(notice).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Chaque semaine, Engram fusionne les dossiers en double, met les noms anglais en français et replie les sous-dossiers de moins de 3 notes. Il propose de déplacer les notes clairement mal placées, sans les déplacer seul. Il ne touche jamais à un dossier ni à une note que tu as choisis toi-même, et aucune note n'est supprimée.")
            }
            if !proposals.isEmpty {
                Section {
                    ForEach(proposals) { proposal in
                        HStack {
                            Text(proposal.summary)
                            Spacer()
                            Button("Déplacer") {
                                model.acceptProposal(proposal)
                                proposals.removeAll { $0.id == proposal.id }
                                load()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Propositions")
                } footer: {
                    Text("Ces notes, rangées par l'IA, ressemblent à des notes que tu as rangées ailleurs.")
                }
            }
            Section("Ce qu'Engram a changé") {
                if records.isEmpty {
                    Text("Aucun changement pour l'instant.").foregroundStyle(.secondary)
                }
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.summary)
                            .strikethrough(record.undone)
                            .foregroundStyle(record.undone ? .secondary : .primary)
                        HStack {
                            Text(record.runAt.formatted(.relative(presentation: .named)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if record.undone {
                                Text("Annulé").font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Button("Annuler") {
                                    model.perform { try model.categories.undoTidy(record.id) }
                                    load()
                                }
                                .font(.footnote)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ménage des dossiers")
        .onAppear(perform: load)
        .task { proposals = await model.proposedMoves() }
    }

    private func load() {
        model.perform { records = try model.categories.tidyHistory() }
    }
}
