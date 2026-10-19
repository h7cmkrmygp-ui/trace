import AppIntents
import EngramCore
import SwiftUI
import WidgetKit

// Widgets d'Engram : « Aujourd'hui » (ce qu'il y a à faire) et un bouton pour enregistrer une pensée, sur l'écran
// d'accueil, l'écran verrouillé et dans le Centre de contrôle.

@main
struct EngramWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ListsWidget()
        RecordWidget()
        RecordControl()
    }
}

// MARK: - Aujourd'hui

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        var sample = WidgetSnapshot()
        sample.today = [.init(title: "Appeler le garage", time: nil, isAppointment: false),
                        .init(title: "Dentiste", time: "14 h", isAppointment: true)]
        return TodayEntry(date: .now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TodayEntry(date: .now, snapshot: SharedContainer.readSnapshot()))
    }

    /// Une entrée maintenant, puis une à chaque minuit des trois prochains jours (le widget recalcule « aujourd'hui »).
    /// L'app rafraîchit aussi les widgets dès que ses rappels changent.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = SharedContainer.readSnapshot()
        let calendar = Calendar.current
        var entries = [TodayEntry(date: .now, snapshot: snapshot)]
        for offset in 1...3 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) {
                entries.append(TodayEntry(date: midnight, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "engram.today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "engram://today"))
        }
        .configurationDisplayName("Aujourd'hui")
        .description("Ce que tu as à faire aujourd'hui, et ce qui est en retard.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var day: (today: [WidgetSnapshot.Entry], lateCount: Int)? {
        entry.snapshot?.day(at: entry.date, calendar: .current)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // Écran verrouillé : seulement un nombre, jamais de titre.
            Label(inlineText, systemImage: "checklist")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Aujourd'hui", systemImage: "checklist").font(.headline)
                Text(inlineText).font(.caption)
            }
        default:
            homeScreen
        }
    }

    private var inlineText: String {
        guard let day else { return "Ouvre Engram" }
        let count = day.today.count
        let base = count == 0 ? "Rien de prévu" : count == 1 ? "1 chose à faire" : "\(count) choses à faire"
        return day.lateCount > 0 ? "\(base) · \(day.lateCount) en retard" : base
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Aujourd'hui").font(.headline)
                Spacer()
                if let day, day.lateCount > 0 {
                    Text("\(day.lateCount) en retard").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            if let day {
                if day.today.isEmpty {
                    Spacer()
                    Text("Rien de prévu.").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(Array(day.today.prefix(family == .systemSmall ? 3 : 4).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Image(systemName: item.isAppointment ? "calendar" : "circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.title).font(.subheadline).lineLimit(1)
                                // Écran verrouillé ou mode En veille : le titre est masqué.
                                .privacySensitive()
                            Spacer(minLength: 0)
                            if let time = item.time { Text(time).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Spacer()
                Text("Ouvre Engram pour voir ta journée.").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - Enregistrer

struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "engram.record", provider: RecordProvider()) { _ in
            RecordWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "engram://record"))
        }
        .configurationDisplayName("Enregistrer une pensée")
        .description("Un toucher : Engram s'ouvre et t'écoute.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct RecordProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct RecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2)
            }
            .accessibilityLabel("Enregistrer une pensée")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 34))
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(LinearGradient(colors: [Color(hue: 0.66, saturation: 0.5, brightness: 0.95),
                                                                       Color(hue: 0.9, saturation: 0.45, brightness: 0.95)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .foregroundStyle(.white)
                Text("Enregistrer").font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// Bouton du Centre de contrôle (et du bouton Action) : ouvre Engram, qui commence à enregistrer.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "engram.record.control") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "engram://record")!)) {
                Label("Enregistrer une pensée", systemImage: "waveform")
            }
        }
        .displayName("Enregistrer une pensée")
        .description("Ouvre Engram et commence à enregistrer.")
    }
}

// MARK: - Liste (P25)

struct ListsEntry: TimelineEntry {
    let date: Date
    let snapshot: ListsSnapshot?
}

struct ListsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListsEntry {
        let sample = ListsSnapshot.make([ListsSnapshot.Source(memoryID: UUID(), name: "Épicerie", title: "Liste d'épicerie",
                                                              body: "☐ Lait\n☐ Pain\n☐ Œufs\n☑ Café", isPrivate: false)],
                                        hideItems: false, now: .now)
        return ListsEntry(date: .now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ListsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ListsEntry(date: .now, snapshot: SharedContainer.readLists()))
    }

    /// L'app réécrit les listes et rafraîchit le widget dès qu'une case change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ListsEntry>) -> Void) {
        completion(Timeline(entries: [ListsEntry(date: .now, snapshot: SharedContainer.readLists())], policy: .never))
    }
}

struct ListsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "engram.lists", provider: ListsProvider()) { entry in
            ListsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.snapshot?.lists.first.map { URL(string: "engram://list/\($0.memoryID.uuidString)")! }
                           ?? URL(string: "engram://lists"))
        }
        .configurationDisplayName("Liste")
        .description("Ce qui reste sur ta liste d'épicerie (ou ta liste la plus récente).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ListsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ListsEntry

    private var shownLists: [ListsSnapshot.List] {
        let lists = entry.snapshot?.lists ?? []
        return Array(lists.prefix(family == .systemLarge ? 2 : 1))
    }

    private var itemsPerList: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 6
        default: 6
        }
    }

    var body: some View {
        if shownLists.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Liste", systemImage: "checklist").font(.headline)
                Spacer()
                Text("Dis « ajoute du lait à ma liste d'épicerie ».").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shownLists) { list in
                    listView(list)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func listView(_ list: ListsSnapshot.List) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(list.title).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(list.openCount)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if list.openCount == 0 {
                Text(list.done > 0 ? "Tout est coché." : "Vide.").font(.subheadline).foregroundStyle(.secondary)
            } else if list.open.isEmpty {
                // Liste privée ou Engram verrouillé : seulement le nombre.
                Text(list.openCount == 1 ? "1 chose à prendre" : "\(list.openCount) choses à prendre")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let columns = family == .systemMedium ? 2 : 1
                let items = Array(list.open.prefix(itemsPerList))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns),
                          alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
                            Text(item).font(.subheadline).lineLimit(1).privacySensitive()
                        }
                    }
                }
                if list.openCount > items.count {
                    Text("et \(list.openCount - items.count) de plus").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
