import EngramCore
import SwiftUI

/// Une note dans une liste : son type en icône (dans la couleur du dossier), le titre, puis la date, l'avancement de
/// ses cases à cocher et le début du texte.
struct MemoryRow: View {
    let memory: Memory
    /// Couleur du dossier ; nil dans les listes mélangées (Archives, Corbeille, recherche).
    var tint: Color?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: RecallHitRow.symbol(for: memory.kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 34, height: 34)
                .background((tint ?? Color.secondary).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if memory.status == .unsorted {
                        Label("À classer", systemImage: "tray")
                    }
                    Text(memory.capturedAt, format: .relative(presentation: .named))
                    if let progress = NoteBody.progress(of: memory.summary) {
                        HStack(spacing: 3) {
                            Image(systemName: progress.done == progress.total ? "checkmark.circle.fill" : "checklist")
                            Text("\(progress.done)/\(progress.total)").monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(progress.done) sur \(progress.total) fait\(progress.done > 1 ? "s" : "")")
                    } else if let preview = Self.preview(of: memory) {
                        Text(preview).lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Première ligne du texte de la note (sans répéter le titre).
    static func preview(of memory: Memory) -> String? {
        let line = (memory.summary ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, line != memory.title else { return nil }
        return line
    }
}
