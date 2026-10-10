import SwiftUI

/// Une pensée classée après une capture : son titre et sa catégorie. Toucher ouvre le souvenir.
struct FiledResultCard: View {
    let item: RecordModel.FiledItem

    var body: some View {
        NavigationLink(value: item.id) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
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
