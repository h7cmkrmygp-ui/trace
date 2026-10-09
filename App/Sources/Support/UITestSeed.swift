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
                  summary: String? = nil, people: [String] = [], places: [String] = [],
                  provider: String = "gemini", level: PrivacyLevel = .neutral) throws -> Memory? {
            guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(text) else { return nil }
            let thought = ValidThought(title: text, summary: summary, excerpt: text, spanStart: 0, spanEnd: text.utf16.count,
                                       kind: kind, tags: [], categoryPath: path, mentionedDates: dates,
                                       categoryDescription: description, people: people, places: places)
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
        // P9 : des personnes et des lieux inventés.
        try file("Souper chez Julie et Marc samedi", kind: .appointment, path: ["Famille"],
                 description: "Proches, soupers et anniversaires", dates: ["samedi"], people: ["Julie", "Marc"],
                 provider: "groq", level: .personal)
        try file("Rapporter le livre de Julie", kind: .task, path: ["Famille"], people: ["Julie"],
                 provider: "groq", level: .personal)
        try file("Rapporter les bouteilles au Costco", kind: .task, path: ["Achats"], places: ["au Costco"])
        // P10 : des mesures inventées, sur trois jours, pour les suivis.
        try file("Je pèse 166 livres avant-hier", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        try file("Je pèse 165,4 livres hier", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        try file("Je pèse 164,8 livres ce matin", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        try file("J'ai dormi 7 h 30 cette nuit", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        try file("Tension 118 sur 76", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        // P11 : un objectif de poids et une note épinglée (inventés).
        try file("Mon objectif : 160 livres", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        if let haie = try memories.recallDocuments().first(where: { $0.title.hasPrefix("Tailler la haie") }) {
            try memories.setPinned(true, for: haie.id)
        }
        // P17 : une habitude inventée, deux jours d'affilée.
        try file("Hier j'ai médité 15 minutes", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        try file("J'ai médité 10 minutes ce matin", kind: .info, path: ["Santé"], provider: "apple", level: .personal)
        // P16 : une tâche qui revient (inventée).
        try file("Sortir les poubelles tous les lundis", kind: .task, path: ["Maison"])
        // P15 : une liste d'épicerie inventée, complétée par une deuxième dictée.
        try file("Ajoute du lait et des œufs à ma liste d'épicerie", kind: .task, path: ["Achats"])
        try file("Mets du pain sur la liste d'épicerie", kind: .task, path: ["Achats"])
        // P14 : un rappel de lieu, et une adresse inventée (un point quelconque du centre-ville de Montréal).
        if let piles = try file("Acheter des piles quand j'arrive chez Costco", kind: .task, path: ["Achats"],
                                places: ["Costco"]),
           let costco = try model.entities.placeTrigger(for: piles.id)?.place {
            try model.entities.setLocation(costco.id, latitude: 45.5017, longitude: -73.5673, radius: 200,
                                           label: "Adresse inventée")
        }

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
