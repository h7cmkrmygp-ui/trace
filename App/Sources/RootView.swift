import SwiftUI

struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Engram",
            systemImage: "brain",
            description: Text("Les fondations sont en construction.")
        )
    }
}
