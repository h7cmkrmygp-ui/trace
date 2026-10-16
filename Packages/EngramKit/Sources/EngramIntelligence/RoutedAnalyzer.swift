import EngramCore
import Foundation

/// Un service en ligne capable de classer une note.
public protocol CloudThoughtAnalyzing: Sendable {
    func analyze(text: String, existingCategories: [String], context: CloudContext) async throws -> ThoughtAnalysis
}

extension GeminiThoughtAnalyzer: CloudThoughtAnalyzing {}
extension GroqThoughtAnalyzer: CloudThoughtAnalyzing {}

public struct CloudProvider: Sendable {
    /// « gemini » ou « groq » (enregistré sur la note).
    public let name: String
    public let analyzer: any CloudThoughtAnalyzing

    public init(name: String, analyzer: any CloudThoughtAnalyzing) {
        self.name = name
        self.analyzer = analyzer
    }
}

/// Quotas des services gratuits : pause après un « quota atteint », et nombre d'analyses du jour
/// (le jour se compte à l'heure du Pacifique, comme chez Google). Rien de personnel n'y est rangé.
public final class CloudQuota: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults?
    private var pausedUntil: [String: Date] = [:]
    private var counts: [String: Int] = [:]
    static let storageKey = "engram.cloudQuota"

    /// `defaults` nil : en mémoire seulement (tests).
    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let stored = defaults?.dictionary(forKey: Self.storageKey) {
            pausedUntil = (stored["paused"] as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
            counts = stored["counts"] as? [String: Int] ?? [:]
        }
    }

    public func isPaused(_ provider: String, now: Date = Date()) -> Bool {
        lock.withLock { (pausedUntil[provider] ?? .distantPast) > now }
    }

    public func pausedUntil(_ provider: String, now: Date = Date()) -> Date? {
        lock.withLock { pausedUntil[provider].flatMap { $0 > now ? $0 : nil } }
    }

    public func pause(_ provider: String, until date: Date) {
        lock.withLock {
            pausedUntil[provider] = date
            save()
        }
    }

    public func recordUse(_ provider: String, now: Date = Date()) {
        lock.withLock {
            let key = "\(provider)|\(Self.dayKey(now))"
            counts[key, default: 0] += 1
            // On ne garde que le jour en cours.
            counts = counts.filter { $0.key.hasSuffix(Self.dayKey(now)) }
            save()
        }
    }

    public func usage(_ provider: String, now: Date = Date()) -> Int {
        lock.withLock { counts["\(provider)|\(Self.dayKey(now))"] ?? 0 }
    }

    /// À appeler sous verrou.
    private func save() {
        guard let defaults else { return }
        defaults.set(["paused": pausedUntil.mapValues(\.timeIntervalSince1970), "counts": counts], forKey: Self.storageKey)
    }

    static func dayKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Le classement complet : le contrôleur de confidentialité décide du niveau, puis
/// neutre → Gemini (puis Groq), personnel → Groq, secret → l'iPhone. Si aucun service ne répond
/// (pas de clé, réseau, quota), la note est classée sur l'iPhone ; elle sera reclassée plus tard si
/// le service manquait de façon passagère. **Une note personnelle ne va jamais chez Gemini.**
public struct RoutedAnalyzer: MemoryAnalyzer {
    public static let localProvider = "apple"

    public typealias Providers = (neutral: CloudProvider?, personal: CloudProvider?)

    let local: any MemoryAnalyzer
    let judge: (any PrivacyJudge)?
    /// Relu à chaque note : une clé collée dans les Réglages sert tout de suite.
    let providers: @Sendable () -> Providers
    let healthStaysLocal: @Sendable () -> Bool
    /// Réglage « Tout garder sur l'iPhone » : aucune note n'est envoyée.
    let keepEverythingLocal: @Sendable () -> Bool
    let quota: CloudQuota
    /// F10 — revérifie, juste avant chaque envoi, que la source peut encore partir (nil : pas de revérification).
    let sourceAllowsCloud: (@Sendable (UUID) -> Bool)?
    /// F13 — reçus d'envoi : appelé avant l'envoi, puis avec son résultat.
    let onTransmission: (@Sendable (TransmissionEvent) throws -> Void)?
    let timeZone: TimeZone

    public init(local: any MemoryAnalyzer, judge: (any PrivacyJudge)?, neutral: CloudProvider?, personal: CloudProvider?,
                healthStaysLocal: @escaping @Sendable () -> Bool = { false },
                keepEverythingLocal: @escaping @Sendable () -> Bool = { false }, quota: CloudQuota = CloudQuota(),
                sourceAllowsCloud: (@Sendable (UUID) -> Bool)? = nil,
                onTransmission: (@Sendable (TransmissionEvent) throws -> Void)? = nil,
                timeZone: TimeZone = .current) {
        self.init(local: local, judge: judge, providers: { (neutral, personal) }, healthStaysLocal: healthStaysLocal,
                  keepEverythingLocal: keepEverythingLocal, quota: quota, sourceAllowsCloud: sourceAllowsCloud,
                  onTransmission: onTransmission, timeZone: timeZone)
    }

    public init(local: any MemoryAnalyzer, judge: (any PrivacyJudge)?, providers: @escaping @Sendable () -> Providers,
                healthStaysLocal: @escaping @Sendable () -> Bool = { false },
                keepEverythingLocal: @escaping @Sendable () -> Bool = { false }, quota: CloudQuota = CloudQuota(),
                sourceAllowsCloud: (@Sendable (UUID) -> Bool)? = nil,
                onTransmission: (@Sendable (TransmissionEvent) throws -> Void)? = nil,
                timeZone: TimeZone = .current) {
        self.local = local
        self.judge = judge
        self.providers = providers
        self.healthStaysLocal = healthStaysLocal
        self.keepEverythingLocal = keepEverythingLocal
        self.quota = quota
        self.sourceAllowsCloud = sourceAllowsCloud
        self.onTransmission = onTransmission
        self.timeZone = timeZone
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories, context: AnalysisContext())
    }

    public func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        let (neutral, personal) = providers()
        let decision: PrivacyDecision
        // F13 — sur quoi repose le niveau, enregistré avec la route.
        let basis: PrivacyBasis
        if keepEverythingLocal() {
            decision = PrivacyDecision(level: .secret, reasons: [RouteReasons.keepEverythingLocal])
            basis = .everythingLocal
        } else if neutral == nil && personal == nil {
            // Aucun service en ligne : la note reste sur l'iPhone, inutile de faire juger sa confidentialité.
            decision = PrivacyDecision(level: .secret, reasons: [RouteReasons.noCloudService])
            basis = .noCloudService
        } else {
            decision = await PrivacyGate.evaluate(text, keepLocal: context.keepLocal, healthStaysLocal: healthStaysLocal(),
                                                  judge: judge)
            basis = context.keepLocal ? .ownerKeepLocal : .judged
        }
        let candidates: [CloudProvider] = switch decision.level {
        case .neutral: [neutral, personal].compactMap { $0 }
        case .personal: [personal].compactMap { $0 }
        case .secret: []
        }
        // F02 — l'enveloppe de chaque destination : chaque métadonnée n'y entre que si sa provenance l'autorise (une note
        // locale ne produit jamais de dérivé partageable ; sans provenance connue, rien de dérivé ne sort), puis les
        // filtres de mots s'ajoutent comme défense supplémentaire.
        let neutralEnvelope = envelope(for: .cloudNeutral, existingCategories: existingCategories, context: context)
        let personalEnvelope = envelope(for: .cloudPersonal, existingCategories: existingCategories, context: context)
        var temporarilyMissing = false
        var notes: [String] = []
        var stoppedBasis: PrivacyBasis?
        for provider in candidates {
            let label = Self.label(provider.name)
            guard !quota.isPaused(provider.name) else {
                temporarilyMissing = true
                notes.append("\(label) : quota gratuit atteint pour l'instant.")
                continue
            }
            // F10 — juste avant l'envoi : le réglage global et la note elle-même sont relus.
            if keepEverythingLocal() {
                stoppedBasis = .everythingLocal
                notes.append(RouteReasons.keepEverythingLocal)
                break
            }
            if let id = context.sourceID, let allows = sourceAllowsCloud, !allows(id) {
                stoppedBasis = .ownerKeepLocal
                notes.append("La note doit maintenant rester sur l'iPhone : rien n'a été envoyé.")
                break
            }
            let isNeutral = provider.name == neutral?.name
            let sent = isNeutral ? neutralEnvelope : personalEnvelope
            // F13 — le reçu est écrit avant l'envoi ; sans reçu possible, rien ne part.
            let receipt = UUID()
            do {
                try onTransmission?(TransmissionEvent(id: receipt, sourceID: context.sourceID, provider: provider.name,
                                                      status: .sending))
            } catch {
                notes.append("\(label) : envoi annulé (reçu impossible à écrire).")
                continue
            }
            do {
                var analysis = try await provider.analyzer.analyze(text: text, existingCategories: sent.categories,
                                                                   context: sent.context)
                try? onTransmission?(TransmissionEvent(id: receipt, sourceID: context.sourceID, provider: provider.name,
                                                       status: .succeeded))
                quota.recordUse(provider.name)
                analysis.route = AnalysisRoute(level: decision.level, provider: provider.name,
                                               reason: decision.reasons.joined(separator: " "), needsCloudRetry: false,
                                               basis: basis)
                return analysis
            } catch let error as CloudError {
                try? onTransmission?(TransmissionEvent(id: receipt, sourceID: context.sourceID, provider: provider.name,
                                                       status: .failed, detail: String(describing: error)))
                switch error {
                case .quotaExceeded(let retryAfter):
                    quota.pause(provider.name, until: Date().addingTimeInterval(retryAfter ?? 60))
                    temporarilyMissing = true
                    notes.append("\(label) : quota gratuit atteint.")
                case .network, .service, .invalidOutput:
                    temporarilyMissing = true
                    notes.append("\(label) injoignable.")
                case .missingKey:
                    notes.append("\(label) : aucune clé.")
                case .invalidKey:
                    notes.append("\(label) : clé refusée.")
                case .refused:
                    notes.append("\(label) a refusé cette note.")
                }
            } catch {
                try? onTransmission?(TransmissionEvent(id: receipt, sourceID: context.sourceID, provider: provider.name,
                                                       status: .failed, detail: String(describing: error)))
                temporarilyMissing = true
                notes.append("\(label) injoignable.")
            }
        }
        var analysis = try await local.analyze(text: text, existingCategories: existingCategories, context: context)
        let fallback = candidates.isEmpty ? [] : ["Classée sur l'iPhone."]
        // Arrêté juste avant l'envoi : la note est désormais locale (aucun nouvel essai en ligne).
        analysis.route = AnalysisRoute(level: stoppedBasis == nil ? decision.level : .secret, provider: Self.localProvider,
                                       reason: (decision.reasons + notes + fallback).joined(separator: " "),
                                       needsCloudRetry: stoppedBasis == nil && temporarilyMissing,
                                       basis: stoppedBasis ?? basis)
        return analysis
    }

    /// F02 — ce qui peut partir vers une destination : les catégories et le contexte dont la provenance l'autorise.
    func envelope(for destination: PrivacyDestination, existingCategories: [String],
                  context: AnalysisContext) -> (categories: [String], context: CloudContext) {
        let provenance = context.provenance
        func category(_ path: String) -> Bool { provenance?.allowsCategory(path, destination) ?? false }
        func list(_ name: String) -> Bool { provenance?.allowsList(name, destination) ?? false }
        let isNeutral = destination == .cloudNeutral
        // Gemini (palier gratuit) ne voit que les grandes catégories, sans nom de personne ; Groq peut voir les chemins.
        let categories = (isNeutral ? PrivacyGate.neutralCategoryNames(existingCategories)
                                    : PrivacyGate.shareableCategoryNames(existingCategories)).filter(category)
        let allowed = Set(categories)
        // Ce que contient chaque catégorie (P32) : seulement vers Groq, et seulement des descriptions sans coordonnées,
        // numéros ni montants.
        let descriptions = isNeutral ? [:] : PrivacyGate.shareableDescriptions(context.categoryDescriptions, for: categories)
        // Où sont rangées les notes semblables et la taille des dossiers (P34) : des noms de dossiers seulement.
        let evidence = isNeutral
            ? SimilarFolders.roots(context.folderEvidence).filter { !PrivacyGate.neutralCategoryNames([$0.path]).isEmpty }
            : context.folderEvidence.filter { !PrivacyGate.shareableCategoryNames([$0.path]).isEmpty }
        // Les noms des listes (P41) : Gemini ne voit que ceux sans nom de personne.
        let lists = (isNeutral ? PrivacyGate.neutralListNames(context.lists)
                               : PrivacyGate.shareableCategoryNames(context.lists)).filter(list)
        var recent: RecentContext?
        if let previous = context.recent, provenance?.allowsRecent(destination) == true,
           var filtered = isNeutral ? PrivacyGate.neutralRecent(previous) : PrivacyGate.shareableRecent(previous) {
            filtered.lists = filtered.lists.filter(list)
            filtered.folders = filtered.folders.filter(category)
            recent = filtered.isEmpty ? nil : filtered
        }
        let cloud = CloudContext(now: context.capturedAt, timeZone: timeZone, facts: context.facts,
                                 categoryDescriptions: descriptions, folderEvidence: evidence.filter { category($0.path) },
                                 categoryCounts: context.categoryCounts.filter { allowed.contains($0.key) },
                                 lists: lists, recent: recent, repairNotes: context.repairNotes)
        return (categories, cloud)
    }

    static func label(_ provider: String) -> String {
        switch provider {
        case "gemini": "Gemini"
        case "groq": "Groq"
        default: provider
        }
    }
}
