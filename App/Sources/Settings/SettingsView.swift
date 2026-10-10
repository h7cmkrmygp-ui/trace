import EngramCalendar
import EngramIntelligence
import EngramStore
import SwiftUI
import UIKit

/// Réglages (ouverts depuis Notes) : calendrier, transcription, intelligence, export.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var autoAdd = true
    @State private var targetCalendar: String?
    @State private var calendars: [CalendarInfo] = []
    @State private var calendarAccess: CalendarAccess = .notDetermined
    @State private var remindersOn = true
    @State private var remindersAllowed = true
    @State private var morningOn = true
    @State private var weeklyOn = true
    @State private var resurfacingOn = true
    @State private var habitNudgesOn = true
    @State private var autoLocateOn = true

    var body: some View {
        Form {
            Section {
                Toggle("Ajouter mes rendez-vous au calendrier", isOn: $autoAdd)
                    .tint(.green)
                    .onChange(of: autoAdd) { _, value in model.perform { try model.settings.set(value, for: .calendarAutoAdd) } }
                if calendarAccess == .granted {
                    Picker("Calendrier", selection: $targetCalendar) {
                        Text("Calendrier par défaut").tag(String?.none)
                        ForEach(calendars) { calendar in
                            Text(calendar.accountTitle.isEmpty ? calendar.title : "\(calendar.title) · \(calendar.accountTitle)")
                                .tag(Optional(calendar.id))
                        }
                    }
                    .onChange(of: targetCalendar) { _, value in model.perform { try model.settings.set(value, for: .calendarTarget) } }
                } else {
                    Button("Autoriser l'accès au calendrier", systemImage: "calendar.badge.plus") {
                        Task {
                            _ = await model.calendarService.requestAccess()
                            loadCalendarSettings()
                            await model.syncAppointments(askPermission: false)
                        }
                    }
                }
            } header: {
                Text("Calendrier")
            } footer: {
                Text("Les rendez-vous datés que tu dictes y sont ajoutés (1 h si l'heure est connue, durée estimée). Un compte Google ajouté dans Réglages › Calendrier › Comptes apparaît dans la liste.")
            }
            Section {
                Toggle("Me rappeler mes tâches", isOn: $remindersOn)
                    .tint(.green)
                    .onChange(of: remindersOn) { _, value in
                        model.perform { try model.settings.set(value, for: .remindersEnabled) }
                        Task {
                            if value, await model.reminders.isUndecided() { _ = await model.reminders.requestPermission() }
                            await model.syncReminders()
                            remindersAllowed = await model.reminders.isAllowed()
                        }
                    }
                if remindersOn && !remindersAllowed, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settings) {
                        Label("Autoriser les notifications", systemImage: "bell.badge")
                    }
                }
                if remindersOn {
                    Toggle("Résumé du matin (8 h)", isOn: $morningOn)
                        .tint(.green)
                        .onChange(of: morningOn) { _, value in
                            model.perform { try model.settings.set(value, for: .digestMorning) }
                            Task { await model.syncReminders() }
                        }
                    Toggle("Résumé de la semaine (dimanche)", isOn: $weeklyOn)
                        .tint(.green)
                        .onChange(of: weeklyOn) { _, value in
                            model.perform { try model.settings.set(value, for: .digestWeekly) }
                            Task { await model.syncReminders() }
                        }
                    Toggle("Te souviens-tu ? (une vieille idée à 19 h)", isOn: $resurfacingOn)
                        .tint(.green)
                        .onChange(of: resurfacingOn) { _, value in
                            model.perform { try model.settings.set(value, for: .resurfacing) }
                            Task { await model.syncReminders() }
                        }
                    Toggle("Garde ta série (habitudes, 20 h)", isOn: $habitNudgesOn)
                        .tint(.green)
                        .onChange(of: habitNudgesOn) { _, value in
                            model.perform { try model.settings.set(value, for: .habitNudges) }
                            Task { await model.syncReminders() }
                        }
                    Toggle("Trouver l'adresse des lieux tout seul", isOn: $autoLocateOn)
                        .tint(.green)
                        .onChange(of: autoLocateOn) { _, value in
                            model.perform { try model.settings.set(value, for: .autoLocatePlaces) }
                            if value { Task { await model.locateMissingPlaces(askPermission: true) } }
                        }
                }
            } header: {
                Text("Rappels")
            } footer: {
                Text("Une notification à l'heure dite (1 h avant un rendez-vous), ou à 9 h le jour même sans heure, avec « Fait », « Dans 1 h » et « Demain ». Le matin : ce qui est prévu et ce qui est en retard ; le dimanche : ta semaine. Une note gardée sur l'iPhone n'affiche que « Rappel Engram ». « Quand j'arrive au Costco » : Engram cherche les Costco les plus proches de toi avec Plans d'Apple (seulement le nom du lieu et ta zone, jamais ta note).")
            }
            TranscriptionSettingsSection()
            IntelligenceSettingsSection()
            SecuritySettingsSection()
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
        .onAppear(perform: loadCalendarSettings)
        .task {
            remindersOn = model.remindersEnabled
            morningOn = model.morningDigestEnabled
            weeklyOn = model.weeklyDigestEnabled
            resurfacingOn = model.resurfacingEnabled
            habitNudgesOn = model.habitNudgesEnabled
            autoLocateOn = model.autoLocatePlacesEnabled
            let allowed = await model.reminders.isAllowed()
            let undecided = await model.reminders.isUndecided()
            remindersAllowed = allowed || undecided
        }
    }

    private func loadCalendarSettings() {
        calendarAccess = model.calendarService.access
        calendars = model.calendarService.writableCalendars()
        autoAdd = (try? model.settings.bool(.calendarAutoAdd, default: true)) ?? true
        targetCalendar = (try? model.settings.string(.calendarTarget)) ?? nil
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
