import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Enregistrer", systemImage: "waveform", value: AppTab.record) { RecordView() }
            Tab("Cerveau", systemImage: "circle.hexagongrid", value: AppTab.brain) { BrainView() }
            Tab("Calendrier", systemImage: "calendar", value: AppTab.calendar) { CalendarView() }
            Tab("Notes", systemImage: "square.stack", value: AppTab.notes) { NotesView() }
            // Retrouver : le bouton loupe à part de la barre d'onglets (rôle « recherche » d'iOS).
            Tab("Retrouver", systemImage: "magnifyingglass", value: AppTab.recall, role: .search) { RecallView() }
        }
        .errorAlert($model.errorMessage)
        .task { await model.resumePendingWork() }
        // Les rappels suivent la base pendant toute la vie de l'app.
        .task { await model.watchReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resumePendingWork() } }
        }
    }
}
