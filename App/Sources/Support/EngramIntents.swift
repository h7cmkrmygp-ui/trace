import AppIntents
import Foundation

// Siri, raccourcis et bouton Action : capturer une pensée ou interroger sa mémoire sans chercher l'app.

/// Ouvre Engram et commence tout de suite à enregistrer (à mettre sur le bouton Action de l'iPhone).
struct RecordThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Enregistrer une pensée"
    static let description = IntentDescription("Ouvre Engram et commence à enregistrer : tu parles, tu te tais, c'est classé.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if case .success(let model) = AppModel.shared { model.requestRecording() }
        return .result()
    }
}

/// Une pensée dite à Siri : enregistrée tout de suite, puis classée par Engram.
struct NoteThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Noter dans Engram"
    static let description = IntentDescription("Enregistre une pensée dite à Siri ; Engram la classe toute seule.")

    @Parameter(title: "Pensée", requestValueDialog: "Qu'est-ce que je note ?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let model) = AppModel.shared else {
            return .result(dialog: "Engram ne peut pas ouvrir ta mémoire pour l'instant.")
        }
        return .result(dialog: "\(model.saveThought(text))")
    }
}

/// Une question à sa mémoire, posée à Siri. iPhone déverrouillé exigé : personne d'autre n'entend tes notes.
struct AskEngramIntent: AppIntent {
    static let title: LocalizedStringResource = "Demander à Engram"
    static let description = IntentDescription("Retrouve une pensée enregistrée, même sans les mots exacts. Tout reste sur l'iPhone.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question", requestValueDialog: "Qu'est-ce que tu cherches ?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let model) = AppModel.shared else {
            return .result(dialog: "Engram ne peut pas ouvrir ta mémoire pour l'instant.")
        }
        let reply = await model.recall(question)
        return .result(dialog: "\(reply.answer)")
    }
}

/// Phrases reconnues par Siri sans rien configurer (elles doivent contenir le nom de l'app).
struct EngramShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordThoughtIntent(),
                    phrases: ["Enregistre une pensée dans \(.applicationName)", "Nouvelle pensée dans \(.applicationName)"],
                    shortTitle: "Enregistrer une pensée", systemImageName: "waveform")
        AppShortcut(intent: NoteThoughtIntent(),
                    phrases: ["Note dans \(.applicationName)", "Ajoute une note dans \(.applicationName)"],
                    shortTitle: "Noter", systemImageName: "square.and.pencil")
        AppShortcut(intent: AskEngramIntent(),
                    phrases: ["Demande à \(.applicationName)", "Cherche dans \(.applicationName)"],
                    shortTitle: "Demander à Engram", systemImageName: "magnifyingglass")
    }
}
