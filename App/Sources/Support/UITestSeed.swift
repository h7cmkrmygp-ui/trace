#if DEBUG
import EngramCore
import EngramStore
import Foundation

/// **Développement seulement** (absent de l'IPA installée) : les tests d'interface lancent l'app avec une base en
/// mémoire remplie de notes **inventées**, pour prendre des captures d'écran sans aucune donnée réelle.
enum UITestSeed {
    static let argument = "-engramUITestSeed"
    static let darkArgument = "-engramUITestDark"
    /// Base vide (écrans « rien pour l'instant », Cerveau vide).
    static let emptyArgument = "-engramUITestEmpty"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(argument) }
    static var wantsDarkMode: Bool { ProcessInfo.processInfo.arguments.contains(darkArgument) }
    static var wantsEmptyMemory: Bool { ProcessInfo.processInfo.arguments.contains(emptyArgument) }
    /// L'écran Enregistrer s'ouvre sur « Vérifie ta note » (dictée inventée), comme après un enregistrement.
    static let recordReviewArgument = "-engramUITestRecordReview"
    static var wantsRecordReview: Bool { ProcessInfo.processInfo.arguments.contains(recordReviewArgument) }

    @MainActor
    static func makeModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("engram-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(database: try AppDatabase.inMemory(), storageDirectory: directory)
        if !wantsEmptyMemory { try seed(model) }
        return model
    }

    @MainActor
    static func seed(_ model: AppModel) throws {
        let memories = model.memories
        let filer = ThoughtFiler(database: model.database)

        @discardableResult
        func file(_ text: String, kind: MemoryKind, path: [String], description: String? = nil, dates: [String] = [],
                  summary: String? = nil, provider: String = "gemini", level: PrivacyLevel = .neutral) throws -> Memory? {
            guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { return nil }
            let thought = ValidThought(title: text, summary: summary, excerpt: text, spanStart: 0, spanEnd: text.utf16.count,
                                       kind: kind, tags: [], categoryPath: path, mentionedDates: dates,
                                       categoryDescription: description)
            let filed = try filer.file([thought], sourceID: interim.sourceID)
            try memories.recordRoute(sourceID: interim.sourceID,
                                     route: AnalysisRoute(level: level, provider: provider,
                                                          reason: "Note inventée pour les captures d'écran.", needsCloudRetry: false))
            return filed.memories.first
        }

        try file("Tailler la haie samedi", kind: .task, path: ["Maison"], description: "Entretien et projets de la maison",
                 dates: ["samedi"],
                 summary: "Tailler la haie du devant samedi matin.\n☐ Sortir le taille-haie\n☐ Ramasser les branches\n☑ Acheter des sacs")
        try file("Réparer la poignée de la porte", kind: .task, path: ["Maison", "Réparations"])
        try file("Acheter du lait et du pain", kind: .task, path: ["Achats"], description: "Courses et achats du quotidien")
        try file("Dentiste vendredi à 14 h", kind: .appointment, path: ["Santé"],
                 description: "Rendez-vous, forme et bien-être", dates: ["vendredi à 14 h"], provider: "groq", level: .personal)
        try file("Faire mon workout jeudi", kind: .task, path: ["Santé"], dates: ["jeudi"], provider: "groq", level: .personal)
        try file("Préparer la présentation du projet Atlas", kind: .task, path: ["Travail"],
                 description: "Projets, réunions et tâches du travail", provider: "groq", level: .personal)
        try file("Idée : une app de recettes", kind: .idea, path: ["Projets"], provider: "apple", level: .secret)

        if case .saved(let unsorted) = try memories.saveTextNoteWithoutAnalysis("Pensée en vrac à classer plus tard") {
            try filer.markFallback(sourceID: unsorted.sourceID)
        }
        if case .saved(let old) = try memories.saveTextNoteWithoutAnalysis("Ancienne tâche terminée") {
            _ = try memories.setStatus(.archived, for: old.id, actor: .user)
        }
        if case .saved(let thrown) = try memories.saveTextNoteWithoutAnalysis("Vieille idée à jeter") {
            _ = try memories.setStatus(.trashed, for: thrown.id, actor: .user)
        }
        let recording = try memories.saveVoiceRecording(audioPath: "audio/capture-demo.caf", duration: 4)
        _ = try memories.attachTranscript(sourceID: recording.sourceID, transcript: "Faut que je call le garage demain",
                                          languages: ["fr"], engine: "whisperkit-large-v3-turbo", needsReview: true)
    }
}
#endif
