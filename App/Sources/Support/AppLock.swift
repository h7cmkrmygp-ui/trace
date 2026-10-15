import EngramStore
import LocalAuthentication
import SwiftUI

/// Verrouillage d'Engram par Face ID (ou le code de l'iPhone), en option. Verrouillé dès que l'app passe en
/// arrière-plan ; le contenu est masqué dans le sélecteur d'apps.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isEnabled: Bool
    @ObservationIgnored private let settings: SettingStore
    @ObservationIgnored private var isAuthenticating = false

    init(settings: SettingStore) {
        self.settings = settings
        let enabled = (try? settings.bool(.appLock, default: false)) ?? false
        isEnabled = enabled
        isLocked = enabled
    }

    func lock() {
        if isEnabled { isLocked = true }
    }

    /// Face ID, ou le code de l'iPhone si Face ID n'est pas disponible.
    @discardableResult
    func unlock() async -> Bool {
        guard isLocked, !isAuthenticating else { return !isLocked }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await Self.authenticate(reason: "Ouvrir ta mémoire") { isLocked = false }
        return !isLocked
    }

    /// Activer demande d'abord une authentification réussie (personne ne se verrouille dehors par erreur).
    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled { guard await Self.authenticate(reason: "Verrouiller Engram avec Face ID") else { return false } }
        isEnabled = enabled
        try? settings.set(enabled, for: .appLock)
        if !enabled { isLocked = false }
        return true
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Écran verrouillé : rien de la mémoire n'est visible.
struct LockScreen: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "brain")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Engram est verrouillé")
                    .font(.title3.weight(.semibold))
                Button("Déverrouiller", systemImage: "faceid", action: onUnlock)
                    .buttonStyle(.prominent)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
