import EngramCalendar
import EngramCapture
import EngramCore
import EngramIntelligence
import EngramPipeline
import EngramStore
import Foundation
import Observation
import SwiftUI
import UIKit
import WidgetKit

/// Onglets de l'app.
enum AppTab: Hashable {
    case record, brain, calendar, notes, recall
}

/// Services partagés par tous les écrans, et dernière erreur à afficher.
@MainActor
@Observable
final class AppModel {
    /// La même mémoire pour l'app et pour les raccourcis Siri (qui peuvent tourner sans ouvrir l'écran).
    static let shared: Result<AppModel, any Error> = AppModel.launch()

    /// Onglet affiché.
    var selectedTab: AppTab = .record
    /// Écrans ouverts dans chaque onglet. Quitter un onglet vide sa pile : on y revient sur sa page principale.
    var notesPath = NavigationPath()
    var brainPath = NavigationPath()
    var calendarPath = NavigationPath()
    var recordPath = NavigationPath()
    var recallPath = NavigationPath()
    /// Augmente à chaque demande d'enregistrement venue de Siri ou du bouton Action.
    private(set) var recordingRequest = 0
    @ObservationIgnored private var servedRecordingRequest = 0
    /// Note à ouvrir (toucher sur un rappel).
    var openMemoryRequest: UUID?
    /// Augmente quand le résumé du matin est touché : les Notes ouvrent « À faire ».
    private(set) var openTodoRequest = 0
    @ObservationIgnored private var servedTodoRequest = 0
    /// Question à poser dans Retrouver (résumé de la semaine touché).
    var recallQuestionRequest: String?
    /// Rappels de l'iPhone (notifications locales).
    let reminders = ReminderScheduler()
    private let snoozes = ReminderSnoozes()
    /// Sauvegardes chiffrées.
    let backups = BackupService()
    /// Verrouillage Face ID (option).
    let lock: AppLock
    /// Ce que la dernière restauration a mis de côté (affiché une fois dans les Réglages).
    var restoredAside: URL?
    let database: AppDatabase
    /// Dossier Engram (base, enregistrements audio).
    let storageDirectory: URL
    let memories: MemoryStore
    /// Les personnes et les lieux de la mémoire (P9).
    let entities: EntityStore
    /// Les suivis : mesures dites dans les notes (P10).
    let measurements: MeasurementStore
    /// Les listes (P15) : épicerie, cadeaux…
    let lists: ListStore
    let categories: CategoryStore
    let processor: ThoughtProcessor
    let settings: SettingStore
    let calendarLinks: CalendarLinkStore
    /// Modèles Whisper téléchargés (hors du dossier Engram : jamais dans les exports ni dans la sauvegarde iCloud).
    let whisperModels: WhisperModelStore
    let appleTranscriber = FileTranscriber()
    let calendarService = CalendarService()
    var errorMessage: String?
    /// Progression (0 à 1) des modèles Whisper en cours de téléchargement.
    var modelDownloads: [WhisperModel: Double] = [:]
    /// Modèles en cours de préparation (premier chargement, juste après le téléchargement).
    var preparingModels: Set<WhisperModel> = []
    /// Augmente à chaque ajout au calendrier de l'iPhone : le Calendrier d'Engram relit alors ses événements.
    var calendarRevision = 0
    /// Dernier repli vers la reconnaissance d'Apple, expliqué dans les Réglages.
    var transcriptionNotice: String?
    /// Quotas gratuits de Gemini et Groq (pauses après « quota atteint », analyses du jour).
    let quota: CloudQuota
    /// « Retrouver » : recherche par mots, mots proches et sens, entièrement sur l'iPhone.
    let recall = RecallEngine(embedder: AppleSentenceEmbedder(), neighbors: AppleWordNeighbors())
    let recallAnswerer = RecallAnswerer()
    private var whisperTranscribers: [WhisperModel: WhisperTranscriber] = [:]
    private var isResuming = false
    private var isSyncingCalendar = false
    /// Transcriptions en cours : une même note n'est jamais transcrite deux fois en parallèle.
    private var transcribing: Set<UUID> = []

    init(database: AppDatabase, storageDirectory: URL) {
        self.database = database
        self.storageDirectory = storageDirectory
        // Semaine du lundi au dimanche (comme le Calendrier d'Engram) : « Ta semaine », tâches qui reviennent.
        memories = MemoryStore(database: database, calendar: Self.recallCalendar)
        entities = EntityStore(database: database)
        measurements = MeasurementStore(database: database)
        lists = ListStore(database: database)
        categories = CategoryStore(database: database)
        settings = SettingStore(database: database)
        calendarLinks = CalendarLinkStore(database: database)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        whisperModels = WhisperModelStore(directory: support.appendingPathComponent("WhisperModels", isDirectory: true))
        let quota = CloudQuota()
        self.quota = quota
        lock = AppLock(settings: settings)
        let settings = self.settings
        // Neutre → Gemini, personnel → Groq, secret → l'iPhone ; le contrôleur de confidentialité décide sur l'iPhone.
        let router = RoutedAnalyzer(local: AppleThoughtAnalyzer(), judge: ApplePrivacyJudge(),
                                    providers: { AppModel.cloudProviders(settings: settings) },
                                    healthStaysLocal: { (try? settings.bool(.healthStaysLocal, default: false)) ?? false },
                                    keepEverythingLocal: { (try? settings.bool(.keepEverythingLocal, default: false)) ?? false },
                                    quota: quota)
        processor = ThoughtProcessor(memories: memories, categories: categories,
                                     filer: ThoughtFiler(database: database), analyzer: router)
        reminders.onOpen = { [weak self] id in self?.openMemory(id) }
        reminders.onAction = { [weak self] action, id in
            Task { await self?.handleReminderAction(action, memoryID: id) }
        }
        reminders.onOpenTodo = { [weak self] in self?.openTodo() }
        reminders.onOpenWeekly = { [weak self] in self?.openWeeklySummary() }
        reminders.onOpenEntity = { [weak self] id in self?.openEntity(id) }
    }

    func openTodo() {
        selectedTab = .notes
        openTodoRequest += 1
    }

    /// Vrai une seule fois par demande (les Notes ne rouvrent jamais « À faire » pour une vieille demande).
    func consumeTodoRequest() -> Bool {
        guard openTodoRequest > servedTodoRequest else { return false }
        servedTodoRequest = openTodoRequest
        return true
    }

    /// Une fête touchée : la page de la personne s'ouvre dans les Notes (P20).
    func openEntity(_ id: UUID) {
        selectedTab = .notes
        var path = NavigationPath()
        path.append(NotesRoute.entity(id))
        notesPath = path
    }

    /// Une fête posée, changée ou retirée : les rappels sont recalculés (P20).
    func watchBirthdays() async {
        do {
            for try await _ in entities.birthdaysStream() { await syncReminders() }
        } catch {
            // Recalculés au prochain lancement.
        }
    }

    /// Le résumé du dimanche touché : « Ta semaine » s'ouvre dans les Notes, tout lu sur l'iPhone (P18).
    func openWeeklySummary() {
        selectedTab = .notes
        var path = NavigationPath()
        path.append(NotesRoute.weekly)
        notesPath = path
    }

    /// « Fait », « Dans 1 h », « Demain » depuis un rappel (l'app peut être lancée en arrière-plan pour ça).
    func handleReminderAction(_ action: String, memoryID: UUID) async {
        switch action {
        case ReminderScheduler.doneAction:
            perform { _ = try memories.setStatus(.archived, for: memoryID, actor: .user) }
            snoozes.remove(memoryID)
        case ReminderScheduler.laterAction:
            snoozes.set(memoryID, until: Date().addingTimeInterval(3_600))
        case ReminderScheduler.tomorrowAction:
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
            snoozes.set(memoryID, until: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
        default:
            return
        }
        await syncReminders()
    }

    // MARK: - Navigation (Siri, rappels)

    /// Ouvre un écran dans l'onglet affiché, sur la même pile que les liens (un point touché dans un petit réseau).
    func push<Value: Hashable>(_ value: Value) {
        switch selectedTab {
        case .notes: notesPath.append(value)
        case .brain: brainPath.append(value)
        case .calendar: calendarPath.append(value)
        case .record: recordPath.append(value)
        case .recall: recallPath.append(value)
        }
    }

    /// L'onglet quitté revient à sa page principale (Réglages, une note ouverte… sont refermés).
    func leave(_ tab: AppTab) {
        switch tab {
        case .notes: if !notesPath.isEmpty { notesPath = NavigationPath() }
        case .brain: if !brainPath.isEmpty { brainPath = NavigationPath() }
        case .calendar: if !calendarPath.isEmpty { calendarPath = NavigationPath() }
        case .record: if !recordPath.isEmpty { recordPath = NavigationPath() }
        case .recall: if !recallPath.isEmpty { recallPath = NavigationPath() }
        }
    }

    /// Siri ou le bouton Action : l'écran Enregistrer s'ouvre et l'enregistrement commence.
    func requestRecording() {
        selectedTab = .record
        recordingRequest += 1
    }

    /// Vrai une seule fois par demande : l'écran Enregistrer ne relance jamais une vieille demande.
    func consumeRecordingRequest() -> Bool {
        guard recordingRequest > servedRecordingRequest else { return false }
        servedRecordingRequest = recordingRequest
        return true
    }

    func openMemory(_ id: UUID) {
        selectedTab = .notes
        openMemoryRequest = id
    }

    // MARK: - Rappels

    var remindersEnabled: Bool {
        (try? settings.bool(.remindersEnabled, default: true)) ?? true
    }

    /// Suit la base : à chaque changement (note datée, « Fait », corbeille, date modifiée), les rappels sont recalculés.
    func watchReminders() async {
        do {
            for try await items in memories.reminderItemsStream() { await syncReminders(items) }
        } catch {
            // Les rappels ne doivent jamais bloquer l'app : ils seront recalculés au prochain lancement.
        }
    }

    var morningDigestEnabled: Bool { (try? settings.bool(.digestMorning, default: true)) ?? true }
    var weeklyDigestEnabled: Bool { (try? settings.bool(.digestWeekly, default: true)) ?? true }

    /// « Te souviens-tu ? » (P13) : une vieille idée chaque soir à 19 h.
    var resurfacingEnabled: Bool { (try? settings.bool(.resurfacing, default: true)) ?? true }

    /// Les idées qui peuvent revenir le soir : notes vivantes (la règle des 30 jours et des notes privées est dans
    /// `Resurfacing`).
    func resurfacingCandidates() -> [Resurfacing.Candidate] {
        ((try? memories.recallDocuments()) ?? [])
            .filter { $0.status == .active || $0.status == .unsorted }
            .map { Resurfacing.Candidate(id: $0.id, title: $0.title, kind: $0.kind, capturedAt: $0.capturedAt, isPrivate: $0.isPrivate) }
    }

    /// Le résumé du dimanche (P13) : les personnes nommées cette semaine (jamais si Engram est verrouillé) et
    /// l'évolution du poids et du sommeil.
    func weekDetails(from start: Date, to end: Date) -> (people: [String], highlights: [String]) {
        let people = lock.isEnabled ? [] : ((try? entities.summaries(kind: .person)) ?? [])
            .filter { ($0.lastMentionedAt ?? .distantPast) >= start }
            .prefix(3)
            .map(\.entity.name)
        var highlights: [String] = []
        let weightUnit = UserDefaults.standard.string(forKey: "engram.weightUnit") ?? "lb"
        let week = { (points: [MetricPoint]) in points.filter { $0.date >= start && $0.date < end } }
        if let weights = try? week(measurements.points(metric: .weight, weightUnit: weightUnit)), weights.count >= 2,
           let first = weights.first, let last = weights.last {
            let change = ((last.value - first.value) * 10).rounded() / 10
            let sign = change > 0 ? "+" : (change < 0 ? "−" : "±")
            highlights.append("Poids \(sign)\(MetricUnits.decimal(abs(change))) \(weightUnit)")
        }
        if let nights = try? week(measurements.points(metric: .sleep, weightUnit: weightUnit)), !nights.isEmpty {
            let average = nights.map(\.value).reduce(0, +) / Double(nights.count)
            highlights.append("Sommeil \(MetricUnits.format(average, second: nil, metric: .sleep, unit: "h")) en moyenne")
        }
        return (Array(people), highlights)
    }

    /// Rappels, résumés du matin et de la semaine, pastille de l'icône et widgets : tout est recalculé ensemble.
    func syncReminders(_ items: [ReminderPlanner.Item]? = nil) async {
        var current = items ?? ((try? memories.reminderItems()) ?? [])
        // Engram verrouillé : aucun titre dans les widgets ni les notifications.
        if lock.isEnabled {
            current = current.map {
                ReminderPlanner.Item(id: $0.id, title: $0.title, kind: $0.kind, status: $0.status, dueAt: $0.dueAt,
                                     dueHasTime: $0.dueHasTime, isPrivate: true)
            }
        }
        let now = Date()
        let calendar = Self.recallCalendar
        writeWidgetSnapshot(current, now: now, calendar: calendar)
        guard remindersEnabled else {
            await reminders.removeAll()
            await reminders.setBadge(0)
            await reminders.applyPlaces([])
            return
        }
        guard await reminders.isAllowed() else { return }
        var requests = ReminderPlanner.plan(current, snoozes: snoozes.active(at: now), now: now, calendar: calendar, limit: 55)
            .map { (reminder: $0, kind: ReminderScheduler.Kind.reminder) }
        if morningDigestEnabled {
            requests += DigestPlanner.mornings(current, now: now, calendar: calendar).map { (reminder: $0, kind: .digest) }
        }
        if weeklyDigestEnabled, let week = calendar.dateInterval(of: .weekOfYear, for: now),
           let counts = try? memories.weekStats(from: week.start, to: week.end) {
            let details = weekDetails(from: week.start, to: week.end)
            let stats = WeekStats(notes: counts.notes, done: counts.done, open: counts.open, people: details.people,
                                  highlights: details.highlights)
            if let weekly = DigestPlanner.weekly(stats, now: now, calendar: calendar) {
                requests.append((reminder: weekly, kind: .weekly))
            }
        }
        // Les fêtes (P20) : la veille à 19 h et le jour même à 9 h ; sans nom si Engram est verrouillé. Seulement les
        // 60 prochains jours : iOS garde au plus 64 notifications en attente (recalculées à chaque ouverture).
        requests += BirthdayPlanner.plan((try? entities.birthdays()) ?? [], now: now, calendar: calendar,
                                         hideNames: lock.isEnabled)
            .filter { $0.date < now.addingTimeInterval(60 * 86_400) }
            .map { (reminder: $0, kind: .birthday) }
        // « Te souviens-tu ? » : sans titre si Engram est verrouillé.
        if resurfacingEnabled,
           let evening = Resurfacing.reminder(from: resurfacingCandidates(), now: now, calendar: calendar,
                                              hideTitle: lock.isEnabled) {
            requests.append((reminder: evening, kind: .resurface))
        }
        await reminders.apply(requests, calendar: calendar)
        await reminders.setBadge(DigestPlanner.badgeCount(current, now: now, calendar: calendar))
        await syncPlaceReminders()
    }

    /// Rappels de lieu (P14) : iOS surveille lui-même les adresses ; sans titre si Engram est verrouillé.
    func syncPlaceReminders(_ items: [PlaceReminderPlanner.Item]? = nil) async {
        guard remindersEnabled else {
            await reminders.applyPlaces([])
            return
        }
        var current = items ?? ((try? entities.placeReminderItems()) ?? [])
        if lock.isEnabled {
            current = current.map {
                PlaceReminderPlanner.Item(memoryID: $0.memoryID, title: $0.title, status: $0.status, isPrivate: true,
                                          placeID: $0.placeID, placeName: $0.placeName, event: $0.event,
                                          location: $0.location, createdAt: $0.createdAt)
            }
        }
        await reminders.applyPlaces(PlaceReminderPlanner.plan(current))
    }

    /// Suit la base : une note qui attend un lieu, une adresse posée, une note faite… et iOS surveille les bons lieux.
    func watchPlaceReminders() async {
        do {
            for try await items in entities.placeReminderItemsStream() { await syncPlaceReminders(items) }
        } catch {
            // Recalculés au prochain lancement.
        }
    }

    /// Après un rappel de lieu ou une adresse : l'autorisation des notifications est demandée une seule fois.
    func askForPlaceRemindersIfNeeded() async {
        guard remindersEnabled else { return }
        if await reminders.isUndecided(), await reminders.requestPermission() {
            await syncReminders()
        }
        await syncPlaceReminders()
    }

    /// Résumé du jour pour les widgets, dans le dossier partagé (rien de secret en clair). Sans dossier partagé, rien.
    func writeWidgetSnapshot(_ items: [ReminderPlanner.Item], now: Date, calendar: Calendar) {
        if SharedContainer.writeSnapshot(WidgetSnapshot.make(items, now: now, calendar: calendar)) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Éléments partagés vers Engram depuis d'autres apps : enregistrés puis classés comme une note écrite.
    func importSharedItems() async {
        guard let inbox = SharedContainer.inbox else { return }
        for item in inbox.drain() where !item.noteText.isEmpty {
            await captureText(item.noteText, keepLocal: false)
        }
    }

    /// engram://record (widget, Centre de contrôle) et engram://today (widget Aujourd'hui).
    func open(_ url: URL) {
        guard url.scheme == "engram" else { return }
        switch url.host {
        case "record": requestRecording()
        case "today": openTodo()
        default: break
        }
    }

    /// Après une note datée : l'autorisation des rappels est demandée une seule fois, au moment où elle sert.
    func askForRemindersIfNeeded() async {
        guard remindersEnabled, await reminders.isUndecided(),
              let items = try? memories.reminderItems(),
              !ReminderPlanner.plan(items, now: Date(), calendar: .current).isEmpty else { return }
        if await reminders.requestPermission() { await syncReminders(items) }
    }

    /// Pensée dite à Siri : enregistrée tout de suite (rien n'est perdu), classée ensuite. Renvoie la réponse de Siri.
    func saveThought(_ text: String) -> String {
        do {
            switch try memories.saveTextNoteWithoutAnalysis(text) {
            case .duplicate:
                return "Cette pensée vient déjà d'être enregistrée."
            case .saved(let memory):
                Task {
                    if case .filed = await processor.process(sourceID: memory.sourceID) {
                        await syncAppointments(askPermission: false)
                    }
                }
                return "C'est noté."
            }
        } catch {
            return "Je n'ai pas pu l'enregistrer : \(Self.describe(error))"
        }
    }

    // MARK: - Services en ligne

    /// Modèles Gemini utilisés tant que la clé n'a pas été testée (alias de Google vers les derniers Flash).
    nonisolated static let defaultGeminiModels = ["gemini-flash-latest", "gemini-flash-lite-latest"]

    /// Services disponibles, relus à chaque note : seulement ceux dont la clé est dans le trousseau.
    nonisolated static func cloudProviders(settings: SettingStore) -> RoutedAnalyzer.Providers {
        let gemini = SecretStore.read(.gemini).map { key -> CloudProvider in
            let saved = ((try? settings.string(.geminiModels)) ?? nil)?
                .split(separator: ",").map(String.init).filter { !$0.isEmpty } ?? []
            return CloudProvider(name: GeminiThoughtAnalyzer.providerName,
                                 analyzer: GeminiThoughtAnalyzer(client: GeminiClient(apiKey: key),
                                                                 models: saved.isEmpty ? defaultGeminiModels : saved))
        }
        let groq = SecretStore.read(.groq).map { key in
            CloudProvider(name: GroqThoughtAnalyzer.providerName, analyzer: GroqThoughtAnalyzer(client: GroqClient(apiKey: key)))
        }
        return (gemini, groq)
    }

    /// Enregistre la clé collée par le propriétaire (vide = supprimer), puis la teste. Le message ne contient jamais la clé.
    func saveCloudKey(_ value: String, for account: SecretStore.Account) async -> String {
        guard SecretStore.save(value, for: account) else { return "Impossible d'enregistrer la clé dans le trousseau de l'iPhone." }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if account == .gemini { try? settings.set(nil, for: .geminiModels) }
            return "Clé supprimée de l'iPhone."
        }
        return await testCloudKey(account)
    }

    func testCloudKey(_ account: SecretStore.Account) async -> String {
        guard let key = SecretStore.read(account) else { return "Aucune clé enregistrée." }
        do {
            switch account {
            case .gemini:
                let picked = GeminiModelPicker.pick(from: try await GeminiClient(apiKey: key).listModels())
                let models = [picked.primary, picked.lite].compactMap { $0 }
                guard !models.isEmpty else { return "Clé valide, mais aucun modèle Flash n'est disponible avec elle." }
                try? settings.set(models.joined(separator: ","), for: .geminiModels)
                return "Clé valide. Modèles : \(models.joined(separator: ", "))."
            case .groq:
                try await GroqClient(apiKey: key).checkKey()
                return "Clé valide. Modèle : \(GroqClient.model)."
            case .backupPassword:
                return "Mot de passe de sauvegarde enregistré."
            }
        } catch let error as CloudError {
            switch error {
            case .invalidKey: return "Clé refusée : vérifie que tu l'as copiée en entier."
            case .network: return "Pas de connexion : réessaie plus tard."
            case .quotaExceeded: return "Clé valide, mais le quota gratuit est atteint pour l'instant."
            default: return "Le service ne répond pas correctement pour l'instant."
            }
        } catch {
            return "Le test a échoué."
        }
    }

    /// Notes classées sur l'iPhone faute de service : reclassées par le bon service dès qu'il répond,
    /// seulement si le propriétaire n'y a pas touché (10 au plus à chaque retour dans l'app).
    func retryCloudClassifications() async {
        let (neutral, personal) = Self.cloudProviders(settings: settings)
        guard neutral != nil || personal != nil else { return }
        for source in (try? memories.sourcesNeedingCloudRetry(limit: 10)) ?? [] {
            let provider = source.privacyLevel == .neutral ? (neutral ?? personal) : personal
            guard let provider, !quota.isPaused(provider.name) else { continue }
            guard (try? memories.reopenForCloudRetry(sourceID: source.id)) == true else { continue }
            _ = await processor.process(sourceID: source.id)
        }
    }

    // MARK: - Réglages de transcription

    var transcriptionEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: ((try? settings.string(.transcriptionEngine)) ?? nil) ?? "") ?? .default
    }

    var whisperModel: WhisperModel {
        WhisperModel(rawValue: ((try? settings.string(.whisperModel)) ?? nil) ?? "") ?? .default
    }

    /// « Vérifie ta note » avant de classer : désactivé par défaut (je parle, je termine, c'est enregistré).
    var reviewsBeforeFiling: Bool {
        (try? settings.bool(.reviewBeforeFiling, default: false)) ?? false
    }

    /// L'enregistrement s'arrête tout seul quand on se tait (activé par défaut).
    var stopsOnSilence: Bool {
        (try? settings.bool(.autoStopOnSilence, default: true)) ?? true
    }

    var whisperStrategy: TranscriptionStrategy {
        TranscriptionStrategy(rawValue: ((try? settings.string(.whisperStrategy)) ?? nil) ?? "") ?? .default
    }

    /// Dossier du banc d'essai (enregistrements des phrases lues, résultats) : hors du dossier Engram,
    /// donc jamais pris pour des notes, jamais exporté.
    var benchmarkDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Benchmark", isDirectory: true)
    }

    func whisperTranscriber(for model: WhisperModel) -> WhisperTranscriber {
        if let existing = whisperTranscribers[model] { return existing }
        let created = WhisperTranscriber(model: model, store: whisperModels)
        whisperTranscribers[model] = created
        return created
    }

    /// Télécharge un modèle Whisper (en Wi-Fi de préférence ; l'écran reste allumé pendant le téléchargement).
    func downloadWhisperModel(_ model: WhisperModel) async {
        guard modelDownloads[model] == nil, !whisperModels.isDownloaded(model) else { return }
        modelDownloads[model] = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            modelDownloads[model] = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        do {
            try await whisperModels.download(model) { [weak self] value in
                guard let self else { return }
                Task { @MainActor in
                    guard self.modelDownloads[model] != nil else { return }
                    self.modelDownloads[model] = value
                }
            }
            // Premier chargement tout de suite (optimisation pour l'iPhone, dictionnaire en ligne), pas pendant une dictée.
            preparingModels.insert(model)
            try? await whisperTranscriber(for: model).prepare()
            preparingModels.remove(model)
            if model != whisperModel { await whisperTranscriber(for: model).unload() }
        } catch {
            errorMessage = "Le téléchargement du modèle a échoué. Vérifie ta connexion (Wi-Fi conseillé) et réessaie."
        }
    }

    func deleteWhisperModel(_ model: WhisperModel) async {
        if let loaded = whisperTranscribers.removeValue(forKey: model) { await loaded.unload() }
        perform { try whisperModels.delete(model) }
    }

    /// Ouvre la base sur l'appareil. Plus de catégories de départ : celles de P1 restées vides sont archivées.
    static func launch() -> Result<AppModel, any Error> {
        #if DEBUG
        // Tests d'interface : base en mémoire avec des notes inventées (jamais dans l'IPA installée).
        if UITestSeed.isActive { return Result { try UITestSeed.makeModel() } }
        #endif
        return Result {
            // Une restauration préparée s'applique avant d'ouvrir la base (les données actuelles sont mises de côté).
            let storage = try DatabaseRecovery.storageDirectory()
            let aside = try? BackupRestore.applyPending(in: storage, at: Date())
            let model = AppModel(database: try AppDatabase.openOnDisk(), storageDirectory: storage)
            model.restoredAside = aside ?? nil
            // Un échec du nettoyage ne doit pas empêcher l'app de s'ouvrir.
            _ = try? model.categories.archiveUnusedSeeds()
            return model
        }
    }

    // MARK: - Traitement des pensées

    /// Transcrit une note vocale. Renvoie `false` si ce n'est pas possible pour l'instant (la note reste en attente).
    func transcribe(sourceID: UUID, audioPath: String) async -> Bool {
        guard !transcribing.contains(sourceID) else { return false }
        transcribing.insert(sourceID)
        defer { transcribing.remove(sourceID) }
        let url = AudioFiles.url(forRelativePath: audioPath, in: storageDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Fichier introuvable : on clôt la transcription pour ne pas réessayer indéfiniment (la note reste « À classer »).
            _ = try? memories.attachTranscript(sourceID: sourceID, transcript: "", languages: [], engine: nil)
            return true
        }
        do {
            let (transcript, engine) = try await runTranscription(url: url)
            try memories.attachTranscript(sourceID: sourceID, transcript: transcript.text,
                                          languages: Self.languages(of: transcript), engine: engine,
                                          needsReview: reviewsBeforeFiling)
            return true
        } catch {
            return false
        }
    }

    /// Whisper si c'est le moteur choisi et que son modèle est sur l'iPhone, sinon la reconnaissance d'Apple.
    private func runTranscription(url: URL) async throws -> (Transcript, String) {
        if transcriptionEngine == .whisper {
            let model = whisperModel
            if whisperModels.isDownloaded(model) {
                let whisper = whisperTranscriber(for: model)
                do {
                    let transcript = try await whisper.transcribe(url: url, strategy: whisperStrategy)
                    transcriptionNotice = nil
                    return (transcript, whisper.engineName)
                } catch {
                    transcriptionNotice = "Whisper n'a pas pu transcrire la dernière note : la reconnaissance d'Apple a pris le relais."
                }
            } else {
                transcriptionNotice = "Le modèle Whisper n'est pas encore téléchargé : la reconnaissance d'Apple a pris le relais."
            }
        }
        let transcript = try await appleTranscriber.transcribe(url: url)
        return (transcript, appleTranscriber.engineName)
    }

    // MARK: - Retrouver

    /// Semaine du lundi au dimanche, comme le Calendrier d'Engram.
    static var recallCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Les notes qui répondent à une question. Rien ne quitte l'iPhone : ni la question ni les notes.
    /// - Parameter previous: la question d'avant, pour affiner (« Et la semaine passée ? »).
    func recallSearch(_ question: String, after previous: RecallQuery? = nil) async -> RecallResult {
        guard let documents = try? memories.recallDocuments() else { return RecallResult(query: RecallQuery(), hits: []) }
        let engine = recall
        let now = Date()
        let calendar = Self.recallCalendar
        // Le calcul du sens peut prendre un moment avec beaucoup de notes : hors du fil de l'interface.
        return await Task.detached(priority: .userInitiated) {
            engine.search(question, in: documents, now: now, calendar: calendar, after: previous)
        }.value
    }

    /// La phrase de réponse, rédigée sur l'iPhone à partir des seules notes trouvées.
    func recallAnswer(_ question: String, result: RecallResult) async -> String {
        await recallAnswerer.answer(question: question, result: result, now: Date(), calendar: Self.recallCalendar)
    }

    /// Question et réponse en une fois (Siri).
    func recall(_ question: String) async -> (answer: String, hits: [RecallHit]) {
        let result = await recallSearch(question)
        return (await recallAnswer(question, result: result), result.hits)
    }

    /// Relit les anciennes notes, sur l'iPhone, pour y trouver les personnes et les lieux. Renvoie le nombre de liens posés.
    func recognizeNamesInOldNotes() async -> Int {
        let store = entities
        return await Task.detached(priority: .utility) {
            (try? store.backfill(using: AppleEntityRecognizer())) ?? 0
        }.value
    }

    /// Notes sur le même sujet qu'une note (au plus 3, jamais devinées).
    func relatedNotes(to memoryID: UUID) async -> [RecallHit] {
        guard let documents = try? memories.recallDocuments(),
              let document = documents.first(where: { $0.id == memoryID }) else { return [] }
        let engine = recall
        let now = Date()
        return await Task.detached(priority: .utility) { engine.related(to: document, in: documents, now: now) }.value
    }

    /// Transcrit une question dictée (même moteur que les notes : Whisper s'il est là, sinon Apple).
    func transcribeQuestion(url: URL) async throws -> String {
        try await runTranscription(url: url).0.text
    }

    static func languages(of transcript: Transcript) -> [String] {
        transcript.localeIdentifier.split(separator: "+").map(String.init).filter { !$0.isEmpty }
    }

    /// Note écrite depuis l'onglet Notes : enregistrée tout de suite (rien n'est perdu), puis classée.
    func captureText(_ text: String, keepLocal: Bool) async {
        do {
            switch try memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) {
            case .duplicate:
                errorMessage = "Cette pensée vient déjà d'être enregistrée."
            case .saved(let memory):
                if case .filed = await processor.process(sourceID: memory.sourceID) {
                    await syncAppointments(askPermission: true)
                    await askForRemindersIfNeeded()
                }
            }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// « Vérifie ta note » confirmé : la correction est enregistrée, puis la note est classée.
    func confirmReview(sourceID: UUID, text: String, keepLocal: Bool) async -> ProcessingOutcome? {
        do {
            try memories.confirmReview(sourceID: sourceID, text: text, keepLocal: keepLocal)
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
        let outcome = await processor.process(sourceID: sourceID)
        if case .filed = outcome {
            await syncAppointments(askPermission: true)
            await askForRemindersIfNeeded()
        }
        return outcome
    }

    /// Relit l'audio d'une note vocale avec Whisper, puis la reclasse. Les notes modifiées à la main sont gardées.
    @discardableResult
    func retranscribe(sourceID: UUID) async -> Bool {
        guard let source = try? memories.source(id: sourceID), let path = source.audioPath else { return false }
        guard !source.correctedByOwner else {
            errorMessage = "Tu as corrigé cette transcription à la main : elle n'est pas remplacée."
            return false
        }
        let url = AudioFiles.url(forRelativePath: path, in: storageDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "L'enregistrement de cette note n'existe plus."
            return false
        }
        let model = whisperModel
        guard whisperModels.isDownloaded(model) else {
            errorMessage = "Télécharge d'abord le modèle Whisper dans Réglages › Transcription."
            return false
        }
        guard !transcribing.contains(sourceID) else { return false }
        transcribing.insert(sourceID)
        defer { transcribing.remove(sourceID) }
        do {
            let whisper = whisperTranscriber(for: model)
            let transcript = try await whisper.transcribe(url: url, strategy: whisperStrategy)
            guard !transcript.text.isEmpty else {
                errorMessage = "Whisper n'a reconnu aucune parole dans cet enregistrement."
                return false
            }
            try memories.retranscribe(sourceID: sourceID, transcript: transcript.text,
                                      languages: Self.languages(of: transcript), engine: whisper.engineName)
            _ = await processor.process(sourceID: sourceID)
            await syncAppointments(askPermission: false)
            return true
        } catch {
            errorMessage = Self.describe(error)
            return false
        }
    }

    /// Retranscrit avec Whisper toutes les notes vocales qui ne l'ont pas encore été. Renvoie le nombre de notes refaites.
    func retranscribeAll(progress: (Int, Int) -> Void) async -> Int {
        // Les notes déjà passées par Whisper et celles que le propriétaire a corrigées à la main sont laissées telles quelles.
        let pending = ((try? memories.voiceSources()) ?? [])
            .filter { !($0.transcriptionEngine ?? "").hasPrefix("whisperkit") && !$0.correctedByOwner }
        var done = 0
        for (index, source) in pending.enumerated() {
            progress(index, pending.count)
            if await retranscribe(sourceID: source.id) { done += 1 }
        }
        progress(pending.count, pending.count)
        return done
    }

    func process(sourceID: UUID) async -> ProcessingOutcome {
        await processor.process(sourceID: sourceID)
    }

    /// Reprend le travail interrompu : transcriptions puis analyses en attente.
    func resumePendingWork() async {
        guard !isResuming else { return }
        isResuming = true
        defer { isResuming = false }
        adoptOrphanedRecordings()
        await importSharedItems()
        if let pending = try? memories.sourcesAwaitingTranscription() {
            for source in pending {
                if let path = source.audioPath { _ = await transcribe(sourceID: source.id, audioPath: path) }
            }
        }
        _ = await processor.processPending()
        await retryCloudClassifications()
        await syncAppointments(askPermission: false)
        await describeCategoriesIfNeeded()
        await backups.backupIfDue(model: self)
        // Suivis : les notes jamais relues, et celles modifiées, sur l'iPhone (P10).
        // Seules les notes nouvelles ou modifiées depuis la dernière relecture sont relues.
        let measurementStore = measurements
        let iso = ISO8601DateFormatter()
        let lastScan = ((try? settings.string(.measurementsScannedAt)) ?? nil).flatMap { iso.date(from: $0) }
        let scanStart = Date()
        let scanned = await Task.detached(priority: .utility) {
            (try? measurementStore.backfill(since: lastScan.map { $0.addingTimeInterval(-1) })) != nil
        }.value
        if scanned { perform { try settings.set(iso.string(from: scanStart), for: .measurementsScannedAt) } }
        // Habitudes (P17) : une seule relecture complète des anciennes notes ; ensuite, la relecture des mesures suffit.
        if ((try? settings.string(.habitsScannedAt)) ?? nil) == nil {
            let habitsStart = Date()
            let done = await Task.detached(priority: .utility) {
                (try? measurementStore.backfillHabits(since: nil)) != nil
            }.value
            if done { perform { try settings.set(iso.string(from: habitsStart), for: .habitsScannedAt) } }
        }
    }

    /// Catégories créées avant les descriptions : l'IA d'Apple leur en écrit une, sur l'iPhone (3 au plus par retour).
    func describeCategoriesIfNeeded() async {
        guard let missing = try? categories.categoriesMissingDescription(limit: 3, sampleTitles: 5), !missing.isEmpty else { return }
        let describer = AppleCategoryDescriber()
        for item in missing {
            guard let text = try? await describer.describe(name: item.category.name, titles: item.titles), !text.isEmpty else { continue }
            try? categories.describeIfMissing(categoryID: item.category.id, description: text)
        }
    }

    /// Ajoute au calendrier de l'iPhone les rendez-vous datés pas encore ajoutés, si l'option est active.
    /// `askPermission` : demander l'accès au calendrier s'il n'a jamais été demandé (juste après une dictée).
    func syncAppointments(askPermission: Bool) async {
        guard !isSyncingCalendar else { return }
        isSyncingCalendar = true
        defer { isSyncingCalendar = false }
        guard (try? settings.bool(.calendarAutoAdd, default: true)) ?? true else { return }
        guard let waiting = try? calendarLinks.unlinkedAppointments(), !waiting.isEmpty else { return }
        if calendarService.access == .notDetermined {
            guard askPermission, await calendarService.requestAccess() else { return }
        }
        guard calendarService.access == .granted || calendarService.access == .writeOnly else { return }
        let target = (try? settings.string(.calendarTarget)) ?? nil
        // Relire la liste après l'attente de l'autorisation, et revérifier chaque lien juste avant d'ajouter.
        guard let pending = try? calendarLinks.unlinkedAppointments() else { return }
        for memory in pending {
            guard let start = memory.dueAt, (try? calendarLinks.link(for: memory.id)) == nil else { continue }
            guard let added = try? calendarService.addAppointment(title: memory.title, start: start,
                                                                  hasTime: memory.dueHasTime, notes: memory.summary,
                                                                  calendarIdentifier: target) else { continue }
            try? calendarLinks.link(memoryID: memory.id, eventIdentifier: added.eventID, calendarIdentifier: added.calendarID)
            calendarRevision += 1
        }
    }

    /// Enregistrements restés sur le disque sans note (app fermée pendant l'enregistrement) : ils deviennent
    /// des notes vocales à transcrire. Seuls les fichiers de plus de 6 minutes sont pris (jamais celui en cours).
    func adoptOrphanedRecordings() {
        guard let referenced = try? memories.referencedAudioPaths(),
              let orphans = try? AudioFiles.orphanedRecordings(in: storageDirectory, referenced: referenced,
                                                               olderThan: Date().addingTimeInterval(-6 * 60))
        else { return }
        for path in orphans { _ = try? memories.saveVoiceRecording(audioPath: path, duration: nil) }
    }

    /// Suppression définitive, y compris le fichier audio s'il n'est plus utilisé.
    func deletePermanently(_ id: UUID) throws {
        let deletion = try memories.deletePermanently(id)
        if let path = deletion.audioPathToRemove {
            try? FileManager.default.removeItem(at: AudioFiles.url(forRelativePath: path, in: storageDirectory))
        }
    }

    /// Vide la corbeille, avec les fichiers audio qui ne servent plus.
    func emptyTrash() throws {
        for deletion in try memories.emptyTrash() {
            if let path = deletion.audioPathToRemove {
                try? FileManager.default.removeItem(at: AudioFiles.url(forRelativePath: path, in: storageDirectory))
            }
        }
    }

    // MARK: - Erreurs

    /// Exécute une action ; en cas d'erreur, l'affiche dans une alerte.
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = Self.describe(error) }
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? StoreError {
            switch error {
            case .emptyContent: return "Le contenu est vide."
            case .notFound: return "Cet élément n'existe plus."
            case .protectedByUser: return "Ce souvenir a été modifié à la main : il est protégé."
            case .nameConflict: return "Une catégorie porte déjà ce nom à cet endroit."
            case .invalidName: return "Ce nom n'est pas valide (vide ou trop long)."
            case .invalidOperation(let reason): return "Opération impossible : \(reason)."
            }
        }
        if let error = error as? TranscriptionError {
            switch error {
            case .unsupportedLanguage: return "La reconnaissance vocale ne prend pas en charge cette langue sur cet iPhone."
            case .modelUnavailable(let reason): return reason
            case .unreadableAudio: return "L'enregistrement ne peut pas être lu."
            }
        }
        if let error = error as? MemoryValidationError {
            switch error {
            case .emptyTitle: return "Le titre ne peut pas être vide."
            case .titleTooLong: return "Le titre dépasse 80 caractères."
            case .emptyContent: return "Le contenu ne peut pas être vide."
            case .emptyExcerpt, .invalidStatus, .invalidConfidence: return "Données de souvenir invalides."
            }
        }
        return error.localizedDescription
    }
}
