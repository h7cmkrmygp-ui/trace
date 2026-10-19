import EngramCore
import SwiftUI

/// P36 — un résultat de la barre de recherche : le titre, le passage où sont les mots cherchés (en gras), et le dossier
/// (ou « Fait », « À classer »).
struct SearchResultRow: View {
    let document: RecallDocument
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: RecallHitRow.symbol(for: document.kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.bold(document.title, query: query))
                    .lineLimit(2)
                if let snippet = SearchSnippet.make(document.text, query: query), snippet != document.title {
                    Text(Self.bold(snippet, query: query))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if document.status == .archived {
                        Label("Fait", systemImage: "checkmark.circle")
                    } else if document.status == .unsorted {
                        Label("À classer", systemImage: "tray")
                    } else if let folder = document.categories.first {
                        Label(folder, systemImage: "folder")
                    }
                    Text(document.capturedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
    }

    /// Le texte, avec les mots qui répondent à la recherche en gras.
    static func bold(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in SearchSnippet.highlights(in: text, query: query) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            attributed[lower..<upper].foregroundColor = .primary
        }
        return attributed
    }
}
