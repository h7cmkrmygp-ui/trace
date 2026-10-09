import EngramCore
import Foundation
import GRDB

/// Deux notes qui se ressemblent, pour « Doublons possibles ».
public struct DuplicatePair: Sendable, Equatable, Identifiable {
    public let keep: Memory
    public let duplicate: Memory
    public let score: Double
    public var id: String { DuplicateFinder.key(keep.id, duplicate.id) }
}

/// P23 — les doublons possibles.
extension MemoryStore {
    public func duplicatePairs() throws -> [DuplicatePair] { [] }

    public func mergeDuplicate(_ duplicateID: UUID, into keepID: UUID) throws {}

    public func dismissDuplicate(_ first: UUID, _ second: UUID) throws {}
}
