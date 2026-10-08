import SwiftUI

@main
@MainActor
struct EngramApp: App {
    @State private var launch = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .success(let model):
                RootView()
                    .environment(model)
                    .tint(.primary)
                    .preferredColorScheme(Self.forcedColorScheme)
            case .failure(let error):
                RecoveryView(error: error)
                    .tint(.primary)
            }
        }
    }

    /// Mode sombre imposé pour les captures des tests d'interface (développement seulement) ; sinon, celui de l'iPhone.
    static var forcedColorScheme: ColorScheme? {
        #if DEBUG
        if UITestSeed.wantsDarkMode { return .dark }
        #endif
        return nil
    }
}
