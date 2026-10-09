import EngramCore
import SwiftUI

/// Une note dans une liste, comme dans Notes : le titre, puis la date et le début du texte.
struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(memory.title)
                .lineLimit(2)
            HStack(spacing: 6) {
                if memory.status == .unsorted {
                    Label("À classer", systemImage: "tray")
                }
                Text(memory.capturedAt, format: .relative(presentation: .named))
                if let preview = Self.preview(of: memory) {
                    Text(preview).lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
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
