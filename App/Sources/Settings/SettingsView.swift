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
            } header: {
                Text("Rappels")
            } footer: {
                Text("Une notification à l'heure dite (1 h avant un rendez-vous), ou à 9 h le jour même sans heure. Une note gardée sur l'iPhone n'affiche que « Rappel Engram ». « Fait » ou corbeille : le rappel disparaît.")
            }
            TranscriptionSettingsSection()
            IntelligenceSettingsSection()
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
