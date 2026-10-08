#if canImport(FoundationModels)
import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// Mesure réelle du modèle d'Apple sur les phrases **inventées** de l'évaluation (workflow « Apple evaluation »).
/// Ne tourne que si `ENGRAM_RUN_APPLE_EVAL=1` : rapport seulement, jamais d'échec (le modèle peut être absent).
struct AppleEvaluationTests {
    static let enabled = ProcessInfo.processInfo.environment["ENGRAM_RUN_APPLE_EVAL"] == "1"

    /// Rapport : affiché et ajouté à un fichier du dossier temporaire (récupéré par la CI depuis le simulateur).
    static func report(_ line: String) {
        print(line)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("engram-eval.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Cas fictifs pour le juge de confidentialité, avec le niveau attendu au minimum.
    static let privacyCases: [(String, PrivacyVerdict)] = [
        ("Acheter du lait et du pain", .neutral),
        ("Idée : une app de recettes de cuisine", .neutral),
        ("Regarder un film ce soir", .neutral),
        ("Réparer la poignée de la porte du garage", .neutral),
        ("Je pèse 75 kg ce matin", .personal),
        ("Appeler Julie pour sa fête samedi", .personal),
        ("Demander une augmentation à mon patron", .personal),
        ("Prendre mes médicaments à 20 h", .personal),
        ("Mon NIP de carte est 4821", .secret),
        ("Le mot de passe du wifi est soleil123", .secret),
    ]

    @Test(.enabled(if: enabled)) func appleModelClassifiesTheEvaluationSet() async throws {
        let availability = AppleThoughtAnalyzer.availabilityDescription()
        Self.report("MODELE APPLE : \(availability.text)")
        guard availability.isAvailable else { return }
        let analyzer = AppleThoughtAnalyzer()
        var known: [String] = []
        var accepted = 0
        for item in EvaluationSet.cases {
            do {
                let raw = try await analyzer.analyze(text: item.sentence, existingCategories: known)
                let analysis = DuplicateThoughts.merge(ReminderMerger.merge(raw, in: item.sentence))
                let valid = try AnalysisValidator.validate(analysis, against: item.sentence)
                let path = valid.first?.categoryPath ?? []
                if let root = path.first, !known.contains(root) { known.append(root) }
                let countOK = item.expectedNotes.map { $0 == valid.count } ?? true
                let ok = item.accepts(categoryPath: path) && countOK
                if ok { accepted += 1 }
                Self.report("\(ok ? "OK " : "NON") | \(item.sentence) → \(path.joined(separator: " › ")) | \(valid.count) note(s)")
            } catch {
                Self.report("ERR | \(item.sentence) → \(error)")
            }
        }
        Self.report("SCORE CLASSEMENT : \(accepted)/\(EvaluationSet.cases.count)")
    }

    @Test(.enabled(if: enabled)) func applePrivacyJudgeOnFictionalNotes() async throws {
        guard AppleThoughtAnalyzer.availabilityDescription().isAvailable else { return }
        let judge = ApplePrivacyJudge()
        var safe = 0
        for (text, minimum) in Self.privacyCases {
            let rank: [PrivacyVerdict: Int] = [.neutral: 0, .personal: 1, .secret: 2, .unsure: 2]
            do {
                let judgement = try await judge.judge(text)
                // « Sûr » : le juge ne sous-estime jamais (le doute compte comme le plus protégé).
                let isSafe = (rank[judgement.verdict] ?? 2) >= (rank[minimum] ?? 0)
                let exact = judgement.verdict == minimum
                if isSafe { safe += 1 }
                Self.report("\(exact ? "EXACT" : isSafe ? "PRUDENT" : "TROP BAS") | \(text) → \(judgement.verdict.rawValue) (attendu \(minimum.rawValue))")
            } catch {
                Self.report("ERR | \(text) → \(error) (la note resterait sur l'iPhone)")
            }
        }
        Self.report("SCORE CONFIDENTIALITE (jamais trop bas) : \(safe)/\(Self.privacyCases.count)")
    }
}
#endif
