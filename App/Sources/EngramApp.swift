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
                    .tint(.indigo)
            case .failure(let error):
                RecoveryView(error: error)
                    .tint(.indigo)
            }
        }
    }
}
