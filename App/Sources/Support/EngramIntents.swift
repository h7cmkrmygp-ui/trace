import AppIntents
import EngramCore
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

/// Pour un assistant (ChatGPT, Claude…) : les notes qui répondent à une question, en texte, à passer à l'étape suivante
/// d'un raccourci. Rien ne part tout seul : c'est le raccourci du propriétaire qui décide où va ce texte. Les notes
/// gardées sur l'iPhone (ou jugées secrètes) n'y sont jamais, et rien n'est donné si « Tout garder sur l'iPhone » est actif.
struct FindForAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Trouver dans Engram pour un assistant"
    static let description = IntentDescription("Renvoie en texte les notes qui répondent à ta question, pour les donner à ChatGPT ou à Claude dans un raccourci. Les notes gardées sur l'iPhone ne sont jamais incluses.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question", requestValueDialog: "Qu'est-ce que tu cherches ?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard case .success(let model) = AppModel.shared else {
            return .result(value: "", dialog: "Engram ne peut pas ouvrir ta mémoire pour l'instant.")
        }
        guard !((try? model.settings.bool(.keepEverythingLocal, default: false)) ?? false) else {
            return .result(value: "", dialog: "« Tout garder sur l'iPhone » est activé : Engram ne donne rien aux assistants.")
        }
        let result = await model.recallSearch(question)
        let text = AssistantExport.text(question: question, hits: result.hits, calendar: AppModel.recallCalendar, now: Date())
        let count = min(5, result.hits.filter { !$0.document.isPrivate }.count)
        let summary = count == 0 ? "Aucune note partageable trouvée." : "\(count) note\(count > 1 ? "s" : "") trouvée\(count > 1 ? "s" : "")."
        return .result(value: text, dialog: "\(summary)")
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
        // P27 : la journée avec Siri.
        AppShortcut(intent: TodayIntent(),
                    phrases: ["Ma journée dans \(.applicationName)", "Qu'est-ce que j'ai aujourd'hui dans \(.applicationName)"],
                    shortTitle: "Ma journée", systemImageName: "sun.max")
        // P26 : les listes avec Siri.
        AppShortcut(intent: ReadListIntent(),
                    phrases: ["Lis ma liste dans \(.applicationName)", "Qu'est-ce qu'il y a sur ma liste dans \(.applicationName)"],
                    shortTitle: "Lire ma liste", systemImageName: "checklist")
        AppShortcut(intent: AddToListIntent(),
                    phrases: ["Ajoute à ma liste dans \(.applicationName)", "Ajoute à ma liste d'épicerie dans \(.applicationName)"],
                    shortTitle: "Ajouter à ma liste", systemImageName: "text.badge.plus")
    }
}

/// P26 — « Qu'est-ce qu'il y a sur ma liste ? » : Siri lit ce qui reste (l'épicerie d'abord, ou la liste nommée). iPhone
/// déverrouillé exigé ; une liste privée ne dit que le nombre.
struct ReadListIntent: AppIntent {
    static let title: LocalizedStringResource = "Lire une liste Engram"
    static let description = IntentDescription("Siri lit ce qui reste sur ta liste d'épicerie, ou sur la liste que tu nommes.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Liste", requestValueDialog: "Quelle liste ?")
    var list: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let model) = AppModel.shared else {
            return .result(dialog: "Engram ne peut pas ouvrir ta mémoire pour l'instant.")
        }
        return .result(dialog: "\(model.readList(named: list))")
    }
}

/// P26 — « Ajoute du lait à ma liste » : Engram classe la demande comme une dictée (la liste est complétée).
struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter à une liste Engram"
    static let description = IntentDescription("Ajoute des choses à ta liste d'épicerie, ou à la liste que tu nommes.")

    @Parameter(title: "Quoi", requestValueDialog: "Qu'est-ce que j'ajoute ?")
    var item: String

    @Parameter(title: "Liste")
    var list: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let model) = AppModel.shared else {
            return .result(dialog: "Engram ne peut pas ouvrir ta mémoire pour l'instant.")
        }
        _ = model.saveThought(ListSpeech.addCommand(item: item, list: list))
        let reply = ListSpeech.added(to: list)
        return .result(dialog: "\(reply)")
    }
}

/// P27 — « Ma journée » : Siri dit ce qui est prévu aujourd'hui, ce qui est en retard, les fêtes et les séries à garder.
/// iPhone déverrouillé exigé.
struct TodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Ma journée dans Engram"
    static let description = IntentDescription("Siri te dit ce qui est prévu aujourd'hui, ce qui est en retard et les fêtes.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard case .success(let model) = AppModel.shared else {
            return .result(dialog: "Engram ne peut pas ouvrir ta mémoire pour l'instant.")
        }
        let reply = model.daySummary()
        return .result(dialog: "\(reply)")
    }
}
