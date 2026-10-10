import SwiftUI

extension View {
    /// Affiche `message` dans une alerte tant qu'il n'est pas `nil`.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Une erreur est survenue",
            isPresented: Binding(get: { message.wrappedValue != nil },
                                 set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
