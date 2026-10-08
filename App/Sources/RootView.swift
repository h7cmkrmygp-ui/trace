import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab("Accueil", systemImage: "house") { HomeView() }
            Tab("Bibliothèque", systemImage: "books.vertical") { LibraryView() }
            Tab("Recherche", systemImage: "magnifyingglass", role: .search) { SearchView() }
            Tab("Réglages", systemImage: "gearshape") { SettingsView() }
        }
        .errorAlert($model.errorMessage)
    }
}
