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
    let timeZone: TimeZone

    public init(local: any MemoryAnalyzer, judge: (any PrivacyJudge)?, neutral: CloudProvider?, personal: CloudProvider?,
                healthStaysLocal: @escaping @Sendable () -> Bool = { false },
                keepEverythingLocal: @escaping @Sendable () -> Bool = { false }, quota: CloudQuota = CloudQuota(),
                timeZone: TimeZone = .current) {
        self.init(local: local, judge: judge, providers: { (neutral, personal) }, healthStaysLocal: healthStaysLocal,
                  keepEverythingLocal: keepEverythingLocal, quota: quota, timeZone: timeZone)
    }

    public init(local: any MemoryAnalyzer, judge: (any PrivacyJudge)?, providers: @escaping @Sendable () -> Providers,
                healthStaysLocal: @escaping @Sendable () -> Bool = { false },
                keepEverythingLocal: @escaping @Sendable () -> Bool = { false }, quota: CloudQuota = CloudQuota(),
                timeZone: TimeZone = .current) {
        self.local = local
        self.judge = judge
        self.providers = providers
        self.healthStaysLocal = healthStaysLocal
        self.keepEverythingLocal = keepEverythingLocal
        self.quota = quota
        self.timeZone = timeZone
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories, context: AnalysisContext())
    }

    public func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        let (neutral, personal) = providers()
        let decision: PrivacyDecision
        if keepEverythingLocal() {
            decision = PrivacyDecision(level: .secret, reasons: ["Réglage « Tout garder sur l'iPhone » activé."])
        } else if neutral == nil && personal == nil {
            // Aucun service en ligne : la note reste sur l'iPhone, inutile de faire juger sa confidentialité.
            decision = PrivacyDecision(level: .secret, reasons: ["Aucun service en ligne configuré."])
        } else {
            decision = await PrivacyGate.evaluate(text, keepLocal: context.keepLocal, healthStaysLocal: healthStaysLocal(),
                                                  judge: judge)
        }
        let candidates: [CloudProvider] = switch decision.level {
        case .neutral: [neutral, personal].compactMap { $0 }
        case .personal: [personal].compactMap { $0 }
        case .secret: []
        }
        let shareable = PrivacyGate.shareableCategoryNames(existingCategories)
        let cloudContext = CloudContext(now: context.capturedAt, timeZone: timeZone)
        var temporarilyMissing = false
        var notes: [String] = []
        for provider in candidates {
            let label = Self.label(provider.name)
            guard !quota.isPaused(provider.name) else {
                temporarilyMissing = true
                notes.append("\(label) : quota gratuit atteint pour l'instant.")
                continue
            }
            // Gemini (palier gratuit) ne voit que les grandes catégories ; Groq peut voir les chemins complets.
            let categories = provider.name == neutral?.name ? PrivacyGate.neutralCategoryNames(existingCategories) : shareable
            do {
                var analysis = try await provider.analyzer.analyze(text: text, existingCategories: categories, context: cloudContext)
                quota.recordUse(provider.name)
                analysis.route = AnalysisRoute(level: decision.level, provider: provider.name,
                                               reason: decision.reasons.joined(separator: " "), needsCloudRetry: false)
                return analysis
            } catch let error as CloudError {
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
                temporarilyMissing = true
                notes.append("\(label) injoignable.")
            }
        }
        var analysis = try await local.analyze(text: text, existingCategories: existingCategories, context: context)
        let fallback = candidates.isEmpty ? [] : ["Classée sur l'iPhone."]
        analysis.route = AnalysisRoute(level: decision.level, provider: Self.localProvider,
                                       reason: (decision.reasons + notes + fallback).joined(separator: " "),
                                       needsCloudRetry: temporarilyMissing)
        return analysis
    }

    static func label(_ provider: String) -> String {
        switch provider {
        case "gemini": "Gemini"
        case "groq": "Groq"
        default: provider
        }
    }
}
