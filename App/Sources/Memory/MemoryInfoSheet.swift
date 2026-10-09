import EngramCore
import SwiftUI

/// Détails d'une note, rangés à part pour garder la note légère : où elle a été classée, le texte d'origine avant
/// correction, et les versions précédentes (restaurables).
struct MemoryInfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let memory: Memory
    let source: Source?
    @State private var versions: [MemoryVersion] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Notée le", value: memory.capturedAt.formatted(date: .long, time: .shortened))
                    if let kind = memory.kind { LabeledContent("Type", value: MemoryDetailView.kindLabel(kind)) }
                }
                if let source, let provider = source.analysisProvider {
                    Section("Classement") {
                        Label(MemoryDetailView.providerLabel(provider), systemImage: provider == "apple" ? "iphone" : "cloud")
                        if let level = source.privacyLevel {
                            LabeledContent("Confidentialité", value: MemoryDetailView.levelLabel(level))
                        }
                        if let reason = source.routeReason, !reason.isEmpty {
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let original = source?.originalText, original != memory.content {
                    Section("Texte d'origine") {
                        Text(original)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if versions.count > 1 {
                    Section("Versions") {
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
                                        model.perform { _ = try model.memories.restoreVersion(version.version, of: memory.id) }
                                        dismiss()
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .onAppear {
                model.perform { versions = try model.memories.versions(of: memory.id) }
            }
        }
    }
}
