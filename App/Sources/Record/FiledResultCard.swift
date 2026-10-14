import SwiftUI

/// Une pensée classée après une capture : son titre, ce qui a été ajouté à une liste, et sa catégorie. Toucher ouvre le souvenir.
struct FiledResultCard: View {
    let item: RecordModel.FiledItem

    var body: some View {
        NavigationLink(value: item.id) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                // Une liste complétée dit ce qui y a été ajouté (P41) ; toucher l'ouvre pour corriger.
                if !item.added.isEmpty {
                    Label("Ajouté : \(item.added.joined(separator: ", "))", systemImage: "checklist")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Label(item.path ?? "À classer", systemImage: item.path == nil ? "tray" : "folder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if item.addedToCalendar {
                    Label("Ajouté au calendrier", systemImage: "calendar.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
