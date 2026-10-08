import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("Enregistrer", systemImage: "waveform") { RecordView() }
            Tab("Cerveau", systemImage: "circle.hexagongrid") { BrainView() }
            Tab("Calendrier", systemImage: "calendar") { CalendarView() }
            Tab("Notes", systemImage: "square.stack") { NotesView() }
            // Retrouver : le bouton loupe à part de la barre d'onglets (rôle « recherche » d'iOS).
            Tab("Retrouver", systemImage: "magnifyingglass", role: .search) { RecallView() }
        }
        .errorAlert($model.errorMessage)
        .task { await model.resumePendingWork() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resumePendingWork() } }
        }
    }
}
