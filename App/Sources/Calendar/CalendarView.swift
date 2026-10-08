import EngramCalendar
import EngramCore
import SwiftUI
import UIKit

/// Calendrier : la grille du mois, puis le jour choisi (aujourd'hui par défaut) avec les échéances d'Engram
/// et les événements du calendrier de l'iPhone.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var month = CalendarView.calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay = CalendarView.calendar.startOfDay(for: .now)
    @State private var dueItems: [Memory] = []
    @State private var events: [CalendarEventInfo] = []
    @State private var access: CalendarAccess = .notDetermined

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var calendar: Calendar { Self.calendar }

    private var monthRange: (start: Date, end: Date) {
        let end = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        return (month, end)
    }

    private var markedDays: Set<Date> {
        Set(dueItems.compactMap { $0.dueAt.map { calendar.startOfDay(for: $0) } } + events.flatMap(days(of:)))
    }

    private var dayItems: [Memory] {
        dueItems.filter { $0.dueAt.map { calendar.isDate($0, inSameDayAs: selectedDay) } ?? false }
    }

    /// Événements qui touchent le jour choisi (un événement de plusieurs jours apparaît chaque jour).
    private var dayEvents: [CalendarEventInfo] {
        let start = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return events.filter { $0.start < end && max($0.end, $0.start.addingTimeInterval(1)) > start }
            .sorted { $0.start < $1.start }
    }

    /// Jours couverts par un événement (31 au plus).
    private func days(of event: CalendarEventInfo) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: event.start)
        // La fin d'un événement est exclusive : un événement qui finit à minuit ne touche pas le jour suivant.
        let last = calendar.startOfDay(for: max(event.start, event.end.addingTimeInterval(-1)))
        while day <= last && days.count < 31 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthGrid(month: month, selectedDay: $selectedDay, markedDays: markedDays, calendar: calendar)
                }
                .listRowSeparator(.hidden)
                Section {
                    if dayItems.isEmpty && dayEvents.isEmpty {
                        Text("Rien de prévu.").foregroundStyle(.secondary)
                    }
                    ForEach(dayItems) { memory in
                        NavigationLink(value: memory.id) { DueRow(memory: memory) }
                            .swipeActions {
                                Button("Fait", systemImage: "checkmark") {
                                    model.perform { _ = try model.memories.setStatus(.archived, for: memory.id, actor: .user) }
                                }
                                .tint(.gray)
                            }
                    }
                    ForEach(dayEvents) { EventRow(event: $0) }
                } header: {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                }
                if access != .granted {
                    Section {
                        if access == .notDetermined {
                            Button("Autoriser l'accès au calendrier", systemImage: "calendar.badge.plus") {
                                Task { await requestAccess() }
                            }
                        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
                            // Refusé (ou écriture seulement) : iOS ne redemande pas, seul l'écran Réglages le permet.
                            Link(destination: settings) {
                                Label("Ouvrir les Réglages de l'iPhone", systemImage: "gear")
                            }
                        }
                    } footer: {
                        Text(access == .notDetermined
                             ? "Pour voir tes événements ici et y ajouter tes rendez-vous dictés. Un compte Google ajouté au Calendrier de l'iPhone fonctionne aussi."
                             : "L'accès complet au calendrier n'est pas autorisé. Dans Réglages › Engram › Calendriers, choisis « Accès complet » pour voir tes événements ici.")
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Mois précédent", systemImage: "chevron.left") { move(by: -1) }
                    Button("Aujourd'hui") {
                        month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
                        selectedDay = calendar.startOfDay(for: .now)
                    }
                    Button("Mois suivant", systemImage: "chevron.right") { move(by: 1) }
                }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            // Rendez-vous ajoutés depuis un autre onglet, ou accès changé dans les Réglages : on relit.
            .onChange(of: model.calendarRevision) { _, _ in loadEvents() }
            .onAppear {
                access = model.calendarService.access
                loadEvents()
            }
            .task(id: month) {
                access = model.calendarService.access
                loadEvents()
                do {
                    for try await items in model.memories.memoriesStream(dueFrom: monthRange.start, to: monthRange.end) {
                        dueItems = items
                    }
                } catch {
                    model.errorMessage = AppModel.describe(error)
                }
            }
        }
    }

    private func move(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = next
        selectedDay = next
    }

    /// Événements du mois, sans ceux qu'Engram a créés (ils sont déjà affichés comme échéances).
    private func loadEvents() {
        let own = (try? model.calendarLinks.linkedEventIdentifiers()) ?? []
        events = model.calendarService.events(from: monthRange.start, to: monthRange.end).filter { !own.contains($0.id) }
    }

    private func requestAccess() async {
        _ = await model.calendarService.requestAccess()
        access = model.calendarService.access
        loadEvents()
        await model.syncAppointments(askPermission: false)
    }
}

/// Grille d'un mois, du lundi au dimanche.
struct MonthGrid: View {
    let month: Date
    @Binding var selectedDay: Date
    let markedDays: Set<Date>
    let calendar: Calendar

    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + dates
    }

    private let symbols = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index]).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(day: day, isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                            isToday: calendar.isDateInToday(day), isMarked: markedDays.contains(day)) {
                        selectedDay = day
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }
}

struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isMarked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isSelected ? Color.primary : .clear))
                    .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
                Circle()
                    .fill(isMarked ? Color.primary.opacity(0.6) : .clear)
                    .frame(width: 4, height: 4)
            }
            // Toute la case est touchable (au moins 44 pt, comme le recommande Apple).
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (isMarked ? ", prévu" : ""))
    }
}

struct DueRow: View {
    let memory: Memory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: memory.kind == .appointment ? "calendar" : "circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title)
                if memory.dueHasTime, let due = memory.dueAt {
                    Text(due.formatted(.dateTime.hour().minute())).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarEventInfo

    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(Color.primary.opacity(0.3)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text(event.isAllDay ? "Journée entière · \(event.calendarTitle)"
                     : "\(event.start.formatted(.dateTime.hour().minute()))–\(event.end.formatted(.dateTime.hour().minute())) · \(event.calendarTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
