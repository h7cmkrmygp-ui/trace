import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

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
        .onOpenURL { model.open($0) }
        // Verrou Face ID : écran verrouillé, et contenu masqué dans le sélecteur d'apps.
        .overlay {
            if model.lock.isLocked {
                LockScreen { Task { await model.lock.unlock() } }
            } else if model.lock.isEnabled && scenePhase != .active {
                Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            }
        }
        .task {
            if model.lock.isLocked { await model.lock.unlock() }
            await model.resumePendingWork()
        }
        // Les rappels suivent la base pendant toute la vie de l'app.
        .task { await model.watchReminders() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.lock.lock()
                wasInBackground = true
            case .active:
                // Face ID ne se redemande qu'au vrai retour dans l'app (sa propre fenêtre rend l'app « inactive » un
                // instant : sans ça, un refus la ferait réapparaître en boucle).
                let returning = wasInBackground
                wasInBackground = false
                Task {
                    if returning, model.lock.isLocked { await model.lock.unlock() }
                    await model.resumePendingWork()
                }
            default:
                break
            }
        }
    }
}
