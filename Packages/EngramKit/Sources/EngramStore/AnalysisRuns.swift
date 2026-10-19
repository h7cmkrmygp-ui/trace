import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// F29 — garde la trace d'une tentative de classement (sur l'iPhone seulement ; jamais de clé).
    public func recordAnalysisRun(_ run: AnalysisRun) throws {
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO analysis_run (id, source_id, attempt, revision, text_hash, provider, model, prompt_version,
                  contract_version, privacy_level, privacy_basis, proposals, problems, operations, outcome, error_kind,
                  started_at, finished_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [run.id, run.sourceID, run.attempt, run.revision, run.textHash, run.provider, run.model,
                                 run.promptVersion, run.contractVersion, run.privacyLevel, run.privacyBasis,
                                 try json(run.proposals), try json(run.problems), try json(run.operations),
                                 run.outcome.rawValue, run.errorKind, run.startedAt, run.finishedAt])
        }
    }

    /// F29 — les tentatives de classement d'une dictée, dans l'ordre.
    public func analysisRuns(sourceID: UUID) throws -> [AnalysisRun] {
        let decoder = JSONDecoder()
        return try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM analysis_run WHERE source_id = ? ORDER BY started_at, attempt
                """, arguments: [sourceID])
                .map { row in
                    func decode<T: Decodable>(_ type: T.Type, _ column: String) -> T? {
                        (row[column] as String?).flatMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
                    }
                    return AnalysisRun(id: row["id"], sourceID: row["source_id"], attempt: row["attempt"],
                                       revision: row["revision"], textHash: row["text_hash"], provider: row["provider"],
                                       model: row["model"], promptVersion: row["prompt_version"],
                                       contractVersion: row["contract_version"], privacyLevel: row["privacy_level"],
                                       privacyBasis: row["privacy_basis"],
                                       proposals: decode([AnalysisRun.Proposal].self, "proposals") ?? [],
                                       problems: decode([String].self, "problems") ?? [],
                                       operations: decode([String].self, "operations") ?? [],
                                       outcome: AnalysisRun.Outcome(rawValue: row["outcome"]) ?? .failed,
                                       errorKind: row["error_kind"], startedAt: row["started_at"],
                                       finishedAt: row["finished_at"])
                }
        }
    }

    /// F29 — le parcours d'une dictée, pour un diagnostic. Expurgé par défaut : ni le texte de la note, ni les titres,
    /// ni les dossiers ou listes proposés, ni le détail des refus (qui cite la réponse) ; seulement les versions, le
    /// fournisseur et le modèle, la confidentialité, les intentions et types, les opérations et les issues.
    public func diagnosticReport(sourceID: UUID, redacted: Bool = true) throws -> String {
        let runs = try analysisRuns(sourceID: sourceID)
        func hidden(_ text: String) -> String { redacted ? "‹\(text.count) caractères›" : text }
        var lines = ["Diagnostic Engram — dictée \(sourceID.uuidString.prefix(8)) — \(runs.count) tentative(s)"]
        let formatter = ISO8601DateFormatter()
        for run in runs {
            lines.append("")
            lines.append("Tentative \(run.attempt) — \(Self.label(run.outcome)) — \(formatter.string(from: run.startedAt))")
            lines.append("  révision \(run.revision), empreinte \(run.textHash.prefix(12))")
            lines.append("  fournisseur \(run.provider ?? "inconnu"), modèle \(run.model ?? "inconnu")")
            lines.append("  consignes \(run.promptVersion ?? "inconnues"), contrat \(run.contractVersion)")
            lines.append("  confidentialité \(run.privacyLevel ?? "inconnue") (\(run.privacyBasis ?? "base inconnue"))")
            for proposal in run.proposals {
                lines.append("  proposition : intention \(proposal.intent ?? "inconnue"), type \(proposal.kind), titre "
                             + "\(hidden(proposal.title)), dossier \(proposal.folder.isEmpty ? "aucun" : hidden(proposal.folder))"
                             + (proposal.list.map { ", liste \(hidden($0))" } ?? ""))
            }
            if redacted {
                if !run.problems.isEmpty { lines.append("  refus : \(run.problems.count) raison(s) (détail gardé sur l'iPhone)") }
            } else {
                for problem in run.problems { lines.append("  refus : \(problem)") }
            }
            for operation in run.operations { lines.append("  opération : \(operation)") }
            if let kind = run.errorKind { lines.append("  erreur : \(kind)") }
        }
        return lines.joined(separator: "\n")
    }

    static func label(_ outcome: AnalysisRun.Outcome) -> String {
        switch outcome {
        case .filed: "classée"
        case .refused: "refusée (hors contrat)"
        case .waiting: "en attente"
        case .failed: "échec"
        case .stale: "obsolète (la note a changé)"
        }
    }
}
