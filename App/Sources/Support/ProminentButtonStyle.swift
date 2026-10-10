import SwiftUI

/// Bouton principal, noir sur blanc ou blanc sur noir selon le mode. La teinte de l'app est `.primary` (blanche en
/// mode sombre) : avec `.borderedProminent`, le texte blanc pourrait se retrouver sur un fond blanc, comme le bouton
/// Corbeille signalé sur l'iPhone. Ici, le contraste est toujours garanti.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(Color(.systemBackground))
            .background(Capsule().fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)))
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}
