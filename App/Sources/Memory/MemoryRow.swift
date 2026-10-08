import EngramCore
import SwiftUI

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
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
