import EngramIntelligence
import EngramStore
import SwiftUI

/// Réglages (ouverts depuis Notes) : état de l'IA, évaluation, export.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var isExporting = false
    private let intelligence = AppleThoughtAnalyzer.availabilityDescription()

    var body: some View {
        Form {
            Section {
                LabeledContent("IA sur l'iPhone", value: intelligence.text)
                NavigationLink(value: NotesRoute.evaluation) {
                    Label("Évaluer le classement", systemImage: "checklist")
                }
            } header: {
                Text("Intelligence")
            } footer: {
                Text("Le classement se fait sur ton iPhone, sans rien envoyer sur Internet.")
            }
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
            }
        }
        .navigationTitle("Réglages")
    }

    private func export() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        let exporter = Exporter(database: model.database, audioDirectory: model.storageDirectory)
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
