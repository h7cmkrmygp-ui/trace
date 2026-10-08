import EngramStore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task { await export() }
                    } label: {
                        HStack {
                            Label("Exporter toute ma mémoire", systemImage: "square.and.arrow.up")
                            if isExporting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Partager ou enregistrer l'export", systemImage: "doc.zipper")
                        }
                    }
                } header: {
                    Text("Mes données")
                } footer: {
                    Text("L'export (JSON, Markdown et audio, dans un fichier ZIP) n'est pas chiffré. Garde-le en lieu sûr.")
                }
                Section("À propos") {
                    LabeledContent("Version", value: Self.versionString)
                    LabeledContent("Analyse IA", value: "Bientôt")
                }
            }
            .navigationTitle("Réglages")
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        let exporter = Exporter(database: model.database)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let result = try await Task.detached(priority: .userInitiated) {
                try exporter.export(into: destination)
            }.value
            exportURL = result.archiveURL
        } catch {
            model.errorMessage = AppModel.describe(error)
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
