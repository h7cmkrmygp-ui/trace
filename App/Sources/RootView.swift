import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("Enregistrer", systemImage: "waveform") { RecordView() }
            Tab("Notes", systemImage: "square.stack") { NotesView() }
        }
        .errorAlert($model.errorMessage)
        .task { await model.resumePendingWork() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resumePendingWork() } }
        }
    }
}
