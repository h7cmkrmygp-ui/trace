import EngramCore
import Foundation
import GRDB

extension MemoryStore {
    /// F29 — les tentatives de classement d'une dictée, dans l'ordre.
    public func analysisRuns(sourceID: UUID) throws -> [AnalysisRun] { [] }

    /// F29 — le parcours d'une dictée, pour un diagnostic ; expurgé par défaut (ni la note, ni ses dossiers).
    public func diagnosticReport(sourceID: UUID, redacted: Bool = true) throws -> String { "" }
}
