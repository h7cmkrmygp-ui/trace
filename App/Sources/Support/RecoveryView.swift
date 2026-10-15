import EngramStore
import SwiftUI

/// Écran affiché si la base ne s'ouvre pas : rien n'est effacé, et une copie de secours des fichiers bruts peut être enregistrée.
struct RecoveryView: View {
    let error: any Error
    @State private var archiveURL: URL?
    @State private var problem: String?

    var body: some View {
        ContentUnavailableView {
            Label("Impossible d'ouvrir ta mémoire", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Tes données n'ont pas été modifiées.\n\(AppModel.describe(error))")
        } actions: {
            if let archiveURL {
                ShareLink(item: archiveURL) {
                    Label("Enregistrer la copie de secours", systemImage: "doc.zipper")
                }
            } else {
                Button("Préparer une copie de secours", systemImage: "lifepreserver", action: prepare)
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prepare() {
        do {
            let archive = try DatabaseRecovery.archiveRawFiles(
                from: try DatabaseRecovery.storageDirectory(),
                into: FileManager.default.temporaryDirectory)
            archiveURL = archive.archiveURL
        } catch {
            problem = AppModel.describe(error)
        }
    }
}
