import EngramCore
import Foundation
import GRDB

extension CategoryStore {
    /// F02 — pour chaque dossier actif (chemin complet), les destinations interdites par les notes qui y sont rangées
    /// (sous-dossiers compris). Un dossier créé par l'IA sans aucune note a une provenance inconnue : rien ne sort.
    public func provenanceMasks() throws -> [String: Int] { [:] }
}

extension ListStore {
    /// F02 — pour chaque liste (son nom), les destinations interdites par toutes ses contributions.
    public func provenanceMasks() throws -> [String: Int] { [:] }
}

extension MemoryStore {
    /// F02 — les destinations interdites par une source (inconnue : toutes).
    public func forbiddenMask(sourceID: UUID) throws -> Int { 0 }

    /// F13 — écrit ou complète un reçu d'envoi.
    public func recordTransmission(_ event: TransmissionEvent) throws {}

    /// Les reçus d'envoi d'une source, du plus ancien au plus récent.
    public func transmissions(sourceID: UUID) throws -> [TransmissionEvent] { [] }
}
